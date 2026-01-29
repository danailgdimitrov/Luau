--!native
--!optimize 2
---@diagnostic disable: undefined-global

--[[
	UmaSplits.luau - Uma Racing-specific split tracking with HUD
	
	Integrates with the generic SplitTracker module to provide:
	- Map/weather/race detection for Uma Racing
	- Checkpoint tracking via .Touched
	- Split popup and delta tracker HUD
	- 8 comparison modes (PB/Median/Average/Record × Global/Per-Uma)
	
	Usage:
	------------------------------------------------------------
	loadstring(game:HttpGet("...UmaSplits.luau"))()
	------------------------------------------------------------
]]

-- Load dependencies
local Services = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/refs/heads/main/Miscellaneous/Services.luau"))()
-- DEBUG: Using debug branch for SplitTracker
local SplitTracker = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/refs/heads/fix/split-tracker-save/Miscellaneous/SplitTracker.luau"))()

-- Performance: local references
local Clock = os.clock
local MathFloor = math.floor
local StringFormat = string.format
local TableInsert = table.insert

-- Initialize SplitTracker for Uma Racing
SplitTracker.Initialize({
	BaseFolder = "UmaRacing_Data",
	TrackPlayer = true,
	EntityKey = "uma",
})

--------------------------------------------------------------------------------
-- Game References
--------------------------------------------------------------------------------

local LocalPlayer = Services.Players.LocalPlayer
local Lighting = Services.Lighting
local Configuration = Lighting:WaitForChild("Configuration")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local currentMapName = nil
local currentWeather = nil
local currentUma = nil
local raceStartTime = nil
local currentSplits = {}
local checkpointConnections = {}
local isRaceActive = false
local lastCheckpointIndex = 0

-- Cutscene pause tracking
local cutscenePauseStart = nil
local cumulativePauseTime = 0

-- For accurate total delta display
local cumulativeRefTime = 0
local totalDeltaSum = 0  -- Sum of all segment deltas

-- Extended telemetry tracking (LocalPlayer only)
local localTelemetry = {}  -- Array of {time, stamina, staminaRaw, spurts, slips, usedZone, position}
local slipCount = 0        -- LocalPlayer's slip count (SprintRegenUP additions)
local slipConnection = nil -- Connection for tracking LocalPlayer's slips
local hadZoneCutscene = false  -- Did the zone trigger a cutscene?
local zoneCutsceneTracking = nil  -- Connection for cutscene during zone

-- Version info (cached once)
local placeVersion = game.PlaceVersion
local releaseVersion = nil  -- Parsed from game title (just "1.1", not "UPD 1.1")

-- Parse release version from game title (e.g., "[UPD 1.1] Uma Racing" -> "1.1")
local function GetReleaseVersion()
	if releaseVersion then return releaseVersion end
	
	local success, info = pcall(function()
		return Services.MarketplaceService:GetProductInfo(game.PlaceId)
	end)
	
	if success and info and info.Name then
		-- Match "[UPD X.X]" and extract just the version number
		local match = info.Name:match("%[UPD%s*([%d%.]+)%]")
		releaseVersion = match or "Unknown"
	else
		releaseVersion = "Unknown"
	end
	
	return releaseVersion
end

-- Get character for a player (workspace.Players or Player.Character)
local function GetCharacter(player)
	local playerFolder = workspace:FindFirstChild("Players")
	if playerFolder then
		local char = playerFolder:FindFirstChild(player.Name)
		if char then return char end
	end
	return player.Character
end

-- Get uma name for any player/character
local function GetUma(playerOrCharacter)
	if not playerOrCharacter then return nil end
	
	-- If it's a character, find the player
	local player = playerOrCharacter
	if not playerOrCharacter:IsA("Player") then
		player = Services.Players:GetPlayerFromCharacter(playerOrCharacter)
		if not player then
			player = Services.Players:FindFirstChild(playerOrCharacter.Name)
		end
	end
	
	if player then
		local currentCharacter = player:FindFirstChild("CurrentCharacter")
		if currentCharacter then
			return tostring(currentCharacter.Value)
		end
	end
	
	return nil
end

-- Get stamina info: { percent = 85, current = 100, max = 150 }
local function GetStaminaInfo(character)
	if not character then return nil end
	
	local info = character:FindFirstChild("Info")
	if not info then return nil end
	
	local staminaVal = info:FindFirstChild("Stamina")
	local maxStaminaVal = info:FindFirstChild("MaxStamina")
	
	if not staminaVal then return nil end
	
	local current = staminaVal.Value
	local max = maxStaminaVal and tonumber(maxStaminaVal.Value) or 100
	local percent = max > 0 and (current / max * 100) or 0
	
	return {
		percent = MathFloor(percent + 0.5),
		current = MathFloor(current + 0.5),
		max = MathFloor(max + 0.5)
	}
end

-- Get spurts remaining (2 = full, 1 = one used, 0 = both used)
local function GetSpurtsRemaining(character)
	if not character then return 2 end
	
	local spurtCount = character:FindFirstChild("SpurtCount")
	if not spurtCount then return 2 end  -- Not added yet = hasn't used any
	
	return spurtCount.Value
end

-- Check if zone/ultimate has been used
local function HasUsedZone(character)
	if not character then return false end
	return character:FindFirstChild("UsedUlt") ~= nil
end

-- Get racers in the current race (from Configuration NumberValues)
local function GetRacers()
	local racers = {}
	for _, child in ipairs(Configuration:GetChildren()) do
		if child:IsA("NumberValue") then
			-- The NumberValue name is the player name, value is their position
			TableInsert(racers, child.Name)
		end
	end
	return racers
end

-- Get LocalPlayer's current race position (from Configuration)
local function GetRacePosition()
	local posValue = Configuration:FindFirstChild(LocalPlayer.Name)
	if posValue and posValue:IsA("NumberValue") then
		return posValue.Value
	end
	return nil
end

-- Comparison mode: "PB_Global", "PB_Uma", "Median_Global", "Median_Uma", etc.
local comparisonMode = "PB_Uma"

-- Settings persistence
local SETTINGS_FILE = "UmaSplitsSettings.json"
local settings = {
	comparisonMode = "PB_Uma",
	popupPosX = 0.5,
	popupPosY = 0.05,
	trackerPosX = 0.85,
	trackerPosY = 0.3,
	trackerOpacity = 0,
}

--------------------------------------------------------------------------------
-- Theme (matching UMX.luau)
--------------------------------------------------------------------------------

local Theme = {
	Colors = {
		Background = Color3.fromRGB(20, 20, 25),
		TitleBar = Color3.fromRGB(30, 30, 40),
		Stroke = Color3.fromRGB(80, 80, 100),
		Text = Color3.fromRGB(220, 220, 240),
		TextMuted = Color3.fromRGB(100, 100, 120),
		Success = Color3.fromRGB(100, 255, 150),
		Warning = Color3.fromRGB(255, 220, 100),
		Danger = Color3.fromRGB(255, 100, 100),
		Neutral = Color3.fromRGB(200, 200, 220),
	},
	Fonts = {
		Primary = Enum.Font.GothamBold,
		Secondary = Enum.Font.Gotham,
	},
}

--------------------------------------------------------------------------------
-- Settings Persistence
--------------------------------------------------------------------------------

local function LoadSettings()
	pcall(function()
		if isfile and isfile(SETTINGS_FILE) then
			local data = readfile(SETTINGS_FILE)
			local decoded = Services.HttpService:JSONDecode(data)
			if decoded then
				for key, value in pairs(decoded) do
					settings[key] = value
				end
				comparisonMode = settings.comparisonMode
			end
		end
	end)
end

local function SaveSettings()
	pcall(function()
		if writefile then
			settings.comparisonMode = comparisonMode
			local data = Services.HttpService:JSONEncode(settings)
			writefile(SETTINGS_FILE, data)
		end
	end)
end

LoadSettings()

--------------------------------------------------------------------------------
-- Detection Functions
--------------------------------------------------------------------------------

local function DetectMap()
	local MapFolder = workspace:FindFirstChild("Map")
	if MapFolder then
		local Server = MapFolder:FindFirstChild("Server")
		if Server then
			local MapNameValue = Server:FindFirstChild("MapName")
			if MapNameValue and MapNameValue:IsA("StringValue") then
				return MapNameValue.Value
			end
		end
	end
	return nil
end

local function DetectWeather()
	local isSnowing = Configuration:GetAttribute("IsSnowing")
	local isRaining = Configuration:GetAttribute("IsRaining")
	
	if isSnowing then
		return "Snow"
	elseif isRaining then
		return "Rain"
	else
		return "Clear"
	end
end

local function DetectUma()
	local currentCharacter = LocalPlayer:FindFirstChild("CurrentCharacter")
	if currentCharacter then
		return tostring(currentCharacter.Value)
	end
	return nil
end

local function IsRaceActive()
	local gateStart = Configuration:GetAttribute("GateStart")
	local intermission = Configuration:GetAttribute("Intermission")
	return gateStart == true and intermission == -1
end

--------------------------------------------------------------------------------
-- UI Setup
--------------------------------------------------------------------------------

local HiddenUI = gethui()

-- Clean up existing GUI
local ExistingGui = HiddenUI:FindFirstChild("UmaSplitsGui")
if ExistingGui then ExistingGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UmaSplitsGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = HiddenUI

--------------------------------------------------------------------------------
-- Split Popup (Top Center)
--------------------------------------------------------------------------------

local SplitPopup = Instance.new("CanvasGroup")
SplitPopup.Name = "SplitPopup"
SplitPopup.Size = UDim2.new(0, 280, 0, 50)
SplitPopup.Position = UDim2.new(settings.popupPosX, -140, settings.popupPosY, 0)
SplitPopup.AnchorPoint = Vector2.new(0, 0)
SplitPopup.BackgroundColor3 = Theme.Colors.Background
SplitPopup.GroupTransparency = 1  -- Start hidden
SplitPopup.Visible = false
SplitPopup.Parent = ScreenGui

local PopupCorner = Instance.new("UICorner")
PopupCorner.CornerRadius = UDim.new(0, 8)
PopupCorner.Parent = SplitPopup

local PopupStroke = Instance.new("UIStroke")
PopupStroke.Color = Theme.Colors.Stroke
PopupStroke.Thickness = 1
PopupStroke.Parent = SplitPopup

local PopupLayout = Instance.new("UIListLayout")
PopupLayout.FillDirection = Enum.FillDirection.Horizontal
PopupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
PopupLayout.VerticalAlignment = Enum.VerticalAlignment.Center
PopupLayout.Padding = UDim.new(0, 15)
PopupLayout.Parent = SplitPopup

local PopupCheckpoint = Instance.new("TextLabel")
PopupCheckpoint.Name = "Checkpoint"
PopupCheckpoint.Size = UDim2.new(0, 50, 0, 40)
PopupCheckpoint.BackgroundTransparency = 1
PopupCheckpoint.Text = "1"
PopupCheckpoint.TextColor3 = Theme.Colors.Text
PopupCheckpoint.TextSize = 18
PopupCheckpoint.Font = Theme.Fonts.Primary
PopupCheckpoint.Parent = SplitPopup

local PopupTime = Instance.new("TextLabel")
PopupTime.Name = "Time"
PopupTime.Size = UDim2.new(0, 80, 0, 40)
PopupTime.BackgroundTransparency = 1
PopupTime.Text = "45.12s"
PopupTime.TextColor3 = Theme.Colors.Text
PopupTime.TextSize = 20
PopupTime.Font = Theme.Fonts.Primary
PopupTime.Parent = SplitPopup

local PopupDelta = Instance.new("TextLabel")
PopupDelta.Name = "Delta"
PopupDelta.Size = UDim2.new(0, 80, 0, 40)
PopupDelta.BackgroundTransparency = 1
PopupDelta.Text = "-0.45s"
PopupDelta.TextColor3 = Theme.Colors.Success
PopupDelta.TextSize = 20
PopupDelta.Font = Theme.Fonts.Primary
PopupDelta.Parent = SplitPopup

--------------------------------------------------------------------------------
-- Delta Tracker Panel (Corner)
--------------------------------------------------------------------------------

local TrackerPanel = Instance.new("CanvasGroup")
TrackerPanel.Name = "TrackerPanel"
TrackerPanel.Size = UDim2.new(0, 160, 0, 230)
TrackerPanel.Position = UDim2.new(settings.trackerPosX, 0, settings.trackerPosY, 0)
TrackerPanel.BackgroundColor3 = Theme.Colors.Background
TrackerPanel.GroupTransparency = settings.trackerOpacity
TrackerPanel.Visible = false
TrackerPanel.Parent = ScreenGui

local TrackerCorner = Instance.new("UICorner")
TrackerCorner.CornerRadius = UDim.new(0, 8)
TrackerCorner.Parent = TrackerPanel

local TrackerStroke = Instance.new("UIStroke")
TrackerStroke.Color = Theme.Colors.Stroke
TrackerStroke.Thickness = 1
TrackerStroke.Parent = TrackerPanel

-- Tracker Title Bar
local TrackerTitle = Instance.new("Frame")
TrackerTitle.Name = "TitleBar"
TrackerTitle.Size = UDim2.new(1, 0, 0, 24)
TrackerTitle.BackgroundColor3 = Theme.Colors.TitleBar
TrackerTitle.BorderSizePixel = 0
TrackerTitle.Parent = TrackerPanel

local TrackerTitleCorner = Instance.new("UICorner")
TrackerTitleCorner.CornerRadius = UDim.new(0, 8)
TrackerTitleCorner.Parent = TrackerTitle

local TrackerTitleFix = Instance.new("Frame")
TrackerTitleFix.Size = UDim2.new(1, 0, 0, 8)
TrackerTitleFix.Position = UDim2.new(0, 0, 1, -8)
TrackerTitleFix.BackgroundColor3 = Theme.Colors.TitleBar
TrackerTitleFix.BorderSizePixel = 0
TrackerTitleFix.Parent = TrackerTitle

local TrackerTitleLabel = Instance.new("TextLabel")
TrackerTitleLabel.Size = UDim2.new(1, -10, 1, 0)
TrackerTitleLabel.Position = UDim2.new(0, 5, 0, 0)
TrackerTitleLabel.BackgroundTransparency = 1
TrackerTitleLabel.Text = "🏁 SPLITS"
TrackerTitleLabel.TextColor3 = Theme.Colors.Text
TrackerTitleLabel.TextSize = 11
TrackerTitleLabel.Font = Theme.Fonts.Primary
TrackerTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TrackerTitleLabel.Parent = TrackerTitle

-- Tracker Content
local TrackerContent = Instance.new("ScrollingFrame")
TrackerContent.Name = "Content"
TrackerContent.Size = UDim2.new(1, -10, 1, -60)
TrackerContent.Position = UDim2.new(0, 5, 0, 28)
TrackerContent.BackgroundTransparency = 1
TrackerContent.ScrollBarThickness = 4
TrackerContent.ScrollBarImageColor3 = Theme.Colors.Stroke
TrackerContent.CanvasSize = UDim2.new(0, 0, 0, 0)
TrackerContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
TrackerContent.Parent = TrackerPanel

local TrackerLayout = Instance.new("UIListLayout")
TrackerLayout.SortOrder = Enum.SortOrder.LayoutOrder
TrackerLayout.Padding = UDim.new(0, 2)
TrackerLayout.Parent = TrackerContent

-- Tracker split row template
local function CreateSplitRow(index, time, delta, deltaColor)
	local Row = Instance.new("Frame")
	Row.Name = "Split" .. index
	Row.Size = UDim2.new(1, 0, 0, 18)
	Row.BackgroundTransparency = 1
	Row.LayoutOrder = index
	Row.Parent = TrackerContent
	
	local IndexLabel = Instance.new("TextLabel")
	IndexLabel.Size = UDim2.new(0, 30, 1, 0)
	IndexLabel.BackgroundTransparency = 1
	IndexLabel.Text = tostring(index)
	IndexLabel.TextColor3 = Theme.Colors.TextMuted
	IndexLabel.TextSize = 11
	IndexLabel.Font = Theme.Fonts.Secondary
	IndexLabel.TextXAlignment = Enum.TextXAlignment.Left
	IndexLabel.Parent = Row
	
	local TimeLabel = Instance.new("TextLabel")
	TimeLabel.Name = "Time"
	TimeLabel.Size = UDim2.new(0, 50, 1, 0)
	TimeLabel.Position = UDim2.new(0, 30, 0, 0)
	TimeLabel.BackgroundTransparency = 1
	TimeLabel.Text = StringFormat("%.2fs", time)
	TimeLabel.TextColor3 = Theme.Colors.Text
	TimeLabel.TextSize = 11
	TimeLabel.Font = Theme.Fonts.Secondary
	TimeLabel.TextXAlignment = Enum.TextXAlignment.Right
	TimeLabel.Parent = Row
	
	local DeltaLabel = Instance.new("TextLabel")
	DeltaLabel.Name = "Delta"
	DeltaLabel.Size = UDim2.new(0, 55, 1, 0)
	DeltaLabel.Position = UDim2.new(0, 85, 0, 0)
	DeltaLabel.BackgroundTransparency = 1
	DeltaLabel.Text = delta or "---"
	DeltaLabel.TextColor3 = deltaColor or Theme.Colors.Neutral
	DeltaLabel.TextSize = 11
	DeltaLabel.Font = Theme.Fonts.Primary
	DeltaLabel.TextXAlignment = Enum.TextXAlignment.Right
	DeltaLabel.Parent = Row
	
	return Row
end

-- Tracker Total Row
local TrackerTotal = Instance.new("Frame")
TrackerTotal.Name = "TotalRow"
TrackerTotal.Size = UDim2.new(1, -10, 0, 24)
TrackerTotal.Position = UDim2.new(0, 5, 1, -30)
TrackerTotal.BackgroundColor3 = Theme.Colors.TitleBar
TrackerTotal.BorderSizePixel = 0
TrackerTotal.Parent = TrackerPanel

local TotalCorner = Instance.new("UICorner")
TotalCorner.CornerRadius = UDim.new(0, 4)
TotalCorner.Parent = TrackerTotal

local TotalLabel = Instance.new("TextLabel")
TotalLabel.Size = UDim2.new(0.4, 0, 1, 0)
TotalLabel.Position = UDim2.new(0, 5, 0, 0)
TotalLabel.BackgroundTransparency = 1
TotalLabel.Text = "Δ Total:"
TotalLabel.TextColor3 = Theme.Colors.Text
TotalLabel.TextSize = 12
TotalLabel.Font = Theme.Fonts.Primary
TotalLabel.TextXAlignment = Enum.TextXAlignment.Left
TotalLabel.Parent = TrackerTotal

local TotalDelta = Instance.new("TextLabel")
TotalDelta.Name = "Delta"
TotalDelta.Size = UDim2.new(0.6, -5, 1, 0)
TotalDelta.Position = UDim2.new(0.4, 0, 0, 0)
TotalDelta.BackgroundTransparency = 1
TotalDelta.Text = "---"
TotalDelta.TextColor3 = Theme.Colors.Neutral
TotalDelta.TextSize = 14
TotalDelta.Font = Theme.Fonts.Primary
TotalDelta.TextXAlignment = Enum.TextXAlignment.Right
TotalDelta.Parent = TrackerTotal

-- Lap Time Row
local LapTimeRow = Instance.new("Frame")
LapTimeRow.Name = "LapTimeRow"
LapTimeRow.Size = UDim2.new(1, -10, 0, 20)
LapTimeRow.Position = UDim2.new(0, 5, 1, -52)
LapTimeRow.BackgroundTransparency = 1
LapTimeRow.Parent = TrackerPanel

local LapTimeLabel = Instance.new("TextLabel")
LapTimeLabel.Size = UDim2.new(0.4, 0, 1, 0)
LapTimeLabel.BackgroundTransparency = 1
LapTimeLabel.Text = "Time:"
LapTimeLabel.TextColor3 = Theme.Colors.TextMuted
LapTimeLabel.TextSize = 11
LapTimeLabel.Font = Theme.Fonts.Secondary
LapTimeLabel.TextXAlignment = Enum.TextXAlignment.Left
LapTimeLabel.Parent = LapTimeRow

local LapTimeValue = Instance.new("TextLabel")
LapTimeValue.Name = "Value"
LapTimeValue.Size = UDim2.new(0.6, 0, 1, 0)
LapTimeValue.Position = UDim2.new(0.4, 0, 0, 0)
LapTimeValue.BackgroundTransparency = 1
LapTimeValue.Text = "---"
LapTimeValue.TextColor3 = Theme.Colors.Text
LapTimeValue.TextSize = 11
LapTimeValue.Font = Theme.Fonts.Secondary
LapTimeValue.TextXAlignment = Enum.TextXAlignment.Right
LapTimeValue.Parent = LapTimeRow

--------------------------------------------------------------------------------
-- Mode Selector (Cycles through 8 modes on click)
--------------------------------------------------------------------------------

local COMPARISON_MODES = {
	"PB_Uma",
	"PB_Global",
	"Median_Uma",
	"Median_Global",
	"Average_Uma",
	"Average_Global",
	"Record_Uma",
	"Record_Global",
}

local MODE_LABELS = {
	PB_Uma = "PB (Uma)",
	PB_Global = "PB (All)",
	Median_Uma = "Median (Uma)",
	Median_Global = "Median (All)",
	Average_Uma = "Avg (Uma)",
	Average_Global = "Avg (All)",
	Record_Uma = "Record (Uma)",
	Record_Global = "Record (All)",
}

local ModeButton = Instance.new("TextButton")
ModeButton.Name = "ModeButton"
ModeButton.Size = UDim2.new(1, -10, 0, 20)
ModeButton.Position = UDim2.new(0, 5, 1, -52)
ModeButton.BackgroundColor3 = Theme.Colors.TitleBar
ModeButton.BorderSizePixel = 0
ModeButton.Text = "⚙ " .. (MODE_LABELS[comparisonMode] or comparisonMode)
ModeButton.TextColor3 = Theme.Colors.TextMuted
ModeButton.TextSize = 10
ModeButton.Font = Theme.Fonts.Secondary
ModeButton.AutoButtonColor = true
ModeButton.Parent = TrackerPanel

local ModeButtonCorner = Instance.new("UICorner")
ModeButtonCorner.CornerRadius = UDim.new(0, 4)
ModeButtonCorner.Parent = ModeButton

local function CycleMode()
	-- Find current index
	local currentIndex = 1
	for i, mode in ipairs(COMPARISON_MODES) do
		if mode == comparisonMode then
			currentIndex = i
			break
		end
	end
	
	-- Cycle to next
	local nextIndex = (currentIndex % #COMPARISON_MODES) + 1
	comparisonMode = COMPARISON_MODES[nextIndex]
	
	-- Update button text
	ModeButton.Text = "⚙ " .. (MODE_LABELS[comparisonMode] or comparisonMode)
	
	-- Save settings
	SaveSettings()
end

ModeButton.MouseButton1Click:Connect(CycleMode)

--------------------------------------------------------------------------------
-- Dragging Logic
--------------------------------------------------------------------------------

local function MakeDraggable(handleFrame, saveKey, targetFrame)
	-- handleFrame: what you click to drag
	-- targetFrame: what actually moves (defaults to handleFrame)
	targetFrame = targetFrame or handleFrame
	
	local dragging = false
	local dragStart = nil
	local startPos = nil
	
	handleFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = targetFrame.Position
		end
	end)
	
	handleFrame.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			-- Save position
			local screenSize = ScreenGui.AbsoluteSize
			settings[saveKey .. "X"] = targetFrame.Position.X.Scale + (targetFrame.Position.X.Offset / screenSize.X)
			settings[saveKey .. "Y"] = targetFrame.Position.Y.Scale + (targetFrame.Position.Y.Offset / screenSize.Y)
			SaveSettings()
		end
	end)
	
	Services.UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			targetFrame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

MakeDraggable(SplitPopup, "popupPos")
MakeDraggable(TrackerTitle, "trackerPos", TrackerPanel)  -- Drag title bar to move panel

--------------------------------------------------------------------------------
-- Popup Animation
--------------------------------------------------------------------------------

local popupTween = nil
local popupFadeToken = 0  -- Token to prevent stale fade callbacks

local function ShowSplitPopup(checkpointIndex, time, delta, deltaColor)
	-- Update content
	PopupCheckpoint.Text = tostring(checkpointIndex)
	PopupTime.Text = StringFormat("%.2fs", time)
	PopupDelta.Text = delta or "---"
	PopupDelta.TextColor3 = deltaColor or Theme.Colors.Neutral
	
	-- Cancel existing tween
	if popupTween then 
		popupTween:Cancel() 
		popupTween = nil
	end
	
	-- Increment token to invalidate any pending fade callbacks
	popupFadeToken = popupFadeToken + 1
	local myToken = popupFadeToken
	
	-- Show popup immediately
	SplitPopup.Visible = true
	SplitPopup.GroupTransparency = 0
	
	-- Wait then fade out (only if token still matches)
	task.delay(2.5, function()
		if popupFadeToken ~= myToken then return end  -- Another popup was shown, skip fade
		
		local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		popupTween = Services.TweenService:Create(SplitPopup, tweenInfo, {GroupTransparency = 1})
		popupTween:Play()
		popupTween.Completed:Once(function()
			if popupFadeToken == myToken then
				SplitPopup.Visible = false
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Comparison Logic
--------------------------------------------------------------------------------

local function GetReferenceTime(splitIndex)
	if not currentMapName or not currentWeather then return nil end
	
	local isUmaMode = comparisonMode:find("_Uma") ~= nil
	local modeType = comparisonMode:gsub("_Global", ""):gsub("_Uma", "")
	
	local variantFilter = isUmaMode and currentUma or nil
	local stats = SplitTracker.GetStats(currentMapName, currentWeather, variantFilter)
	
	if modeType == "PB" then
		local pbRecord = SplitTracker.GetPersonalBest(
			currentMapName, 
			currentWeather, 
			LocalPlayer.Name, 
			variantFilter
		)
		if pbRecord and pbRecord.splits and pbRecord.splits[splitIndex] then
			return pbRecord.splits[splitIndex]
		end
	elseif modeType == "Median" then
		if stats.medians and stats.medians[splitIndex] then
			return stats.medians[splitIndex]
		end
	elseif modeType == "Average" then
		if stats.averages and stats.averages[splitIndex] then
			return stats.averages[splitIndex]
		end
	elseif modeType == "Record" then
		if stats.bests and stats.bests[splitIndex] then
			return stats.bests[splitIndex]
		end
	end
	
	return nil
end

--------------------------------------------------------------------------------
-- Checkpoint Tracking
--------------------------------------------------------------------------------

local CHECKPOINT_DEBOUNCE = 0.5  -- Seconds

local function SetupCheckpoints()
	-- Clear existing connections
	for _, connection in ipairs(checkpointConnections) do
		connection:Disconnect()
	end
	checkpointConnections = {}
	
	local MapFolder = workspace:FindFirstChild("Map")
	if not MapFolder then return end
	
	local Server = MapFolder:FindFirstChild("Server")
	if not Server then return end
	
	local CheckpointFolder = Server:FindFirstChild("Checkpoint")
	if not CheckpointFolder then return end
	
	local checkpoints = CheckpointFolder:GetChildren()
	local lastTouchTime = {}
	
	for _, checkpoint in ipairs(checkpoints) do
		if checkpoint:IsA("BasePart") then
			-- Extract index from name (e.g., "Checkpoint1" -> 1)
			local indexString = checkpoint.Name:match("%d+")
			local index = tonumber(indexString)
			
			if index then
				lastTouchTime[index] = 0
				
				local connection = checkpoint.Touched:Connect(function(hit)
					-- Check if it's the local player
					local character = LocalPlayer.Character
					if not character then return end
					if not hit:IsDescendantOf(character) then return end
					
					-- Debounce
					local now = Clock()
					if now - lastTouchTime[index] < CHECKPOINT_DEBOUNCE then return end
					lastTouchTime[index] = now
					
					-- Check race is active
					if not isRaceActive or not raceStartTime then return end
					
					-- Check sequential (must hit checkpoints in order, with 6→1 wrap)
					local expectedIndex = lastCheckpointIndex + 1
					if expectedIndex > 6 then expectedIndex = 1 end
					if index ~= expectedIndex then return end
					
					-- Record split (subtract cutscene pause time)
					local rawTime = now - raceStartTime
					local cumulativeTime = rawTime - cumulativePauseTime
					TableInsert(currentSplits, cumulativeTime)
					lastCheckpointIndex = index
					
					-- Get reference and calculate delta (use array index, not checkpoint index)
					local splitIndex = #currentSplits
					local referenceTime = GetReferenceTime(splitIndex)
					local deltaString, deltaColor = SplitTracker.CalculateDeltaColor(cumulativeTime, referenceTime)
					
					-- Calculate segment delta for total sum
					if referenceTime then
						local segmentDelta = cumulativeTime - referenceTime
						-- For first split, just use the delta directly
						-- For subsequent splits, we need segment time comparison
						if splitIndex == 1 then
							totalDeltaSum = segmentDelta
						else
							-- Get previous cumulative reference
							local prevRefTime = GetReferenceTime(splitIndex - 1)
							local prevCumulativeTime = currentSplits[splitIndex - 1]
							if prevRefTime then
								-- Segment delta = (current segment time) - (reference segment time)
								local currentSegment = cumulativeTime - prevCumulativeTime
								local refSegment = referenceTime - prevRefTime
								totalDeltaSum = totalDeltaSum + (currentSegment - refSegment)
							end
						end
					end
					
					-- Show popup
					ShowSplitPopup(splitIndex, cumulativeTime, deltaString, deltaColor)
					
					-- Add to tracker
					CreateSplitRow(splitIndex, cumulativeTime, deltaString, deltaColor)
					
					-- Update total delta (sum of segment deltas)
					local totalDeltaString = StringFormat("%s%.2fs", totalDeltaSum >= 0 and "+" or "", totalDeltaSum)
					TotalDelta.Text = totalDeltaString
					TotalDelta.TextColor3 = totalDeltaSum >= 0 and Theme.Colors.Danger or Theme.Colors.Success
					
					-- Update lap time display
					LapTimeValue.Text = StringFormat("%.2fs", cumulativeTime)
					
					-- Capture telemetry for LocalPlayer
					local playerChar = GetCharacter(LocalPlayer)
					if playerChar then
						local staminaInfo = GetStaminaInfo(playerChar)
						local splitTelemetry = {
							time = cumulativeTime,
							stamina = staminaInfo and staminaInfo.percent or nil,
							staminaRaw = staminaInfo and StringFormat("%d/%d", staminaInfo.current, staminaInfo.max) or nil,
							spurts = GetSpurtsRemaining(playerChar),
							slips = slipCount,
							usedZone = HasUsedZone(playerChar),
							position = GetRacePosition()
						}
						
						TableInsert(localTelemetry, splitTelemetry)
					end
				end)
				
				TableInsert(checkpointConnections, connection)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Race Lifecycle
--------------------------------------------------------------------------------

local function OnRaceStart()
	isRaceActive = true
	raceStartTime = Clock()
	currentSplits = {}
	lastCheckpointIndex = 1  -- First checkpoint touched will be 2
	cumulativePauseTime = 0
	cutscenePauseStart = nil
	cumulativeRefTime = 0
	totalDeltaSum = 0
	
	-- Reset telemetry for new race
	localTelemetry = {}
	slipCount = 0
	hadZoneCutscene = false
	
	-- Clean up old connections
	if slipConnection then
		slipConnection:Disconnect()
		slipConnection = nil
	end
	if zoneCutsceneTracking then
		zoneCutsceneTracking:Disconnect()
		zoneCutsceneTracking = nil
	end
	
	-- Set up tracking for LocalPlayer
	local character = GetCharacter(LocalPlayer)
	if character then
		-- 1. Slip tracking (SprintRegenUP)
		slipConnection = character.ChildAdded:Connect(function(child)
			if child.Name == "SprintRegenUP" then
				slipCount = slipCount + 1
			end
		end)
		
		-- 2. Zone cutscene tracking (if CutsceneOn added while UsedUlt exists)
		zoneCutsceneTracking = Lighting.ChildAdded:Connect(function(child)
			if child.Name == "CutsceneOn" and HasUsedZone(character) then
				hadZoneCutscene = true
			end
		end)
	end
	
	-- Update current uma
	currentUma = GetUma(LocalPlayer)
	
	-- Re-detect weather in case it changed
	currentWeather = DetectWeather()
	
	-- Update tracker title with current weather
	if currentMapName then
		local weatherIcon = currentWeather == "Snow" and "❄️" or (currentWeather == "Rain" and "🌧️" or "☀️")
		TrackerTitleLabel.Text = "🏁 " .. currentMapName .. " " .. weatherIcon
	end
	
	-- Clear tracker content
	for _, child in ipairs(TrackerContent:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	-- Reset total
	TotalDelta.Text = "---"
	TotalDelta.TextColor3 = Theme.Colors.Neutral
	
	-- Show tracker
	TrackerPanel.Visible = true
	
	-- Preload history for this map/weather (only if both are valid)
	if currentMapName and currentWeather then
		SplitTracker.LoadHistory(currentMapName, currentWeather)
	end
	
	-- Cache version info (do this once)
	GetReleaseVersion()
end

local function OnRaceEnd()
	if not isRaceActive or not raceStartTime then return end
	
	local rawTime = Clock() - raceStartTime
	local totalTime = rawTime - cumulativePauseTime
	
	-- Only save if we have valid data
	if #currentSplits > 0 and currentMapName and currentWeather then
		local record = {
			player = LocalPlayer.Name,
			uma = currentUma,
			totalTime = totalTime,
			splits = currentSplits,
			-- Extended data
			placeVersion = placeVersion,
			releaseVersion = GetReleaseVersion(),
			racers = GetRacers(),
			hadZoneCutscene = hadZoneCutscene,
			telemetry = localTelemetry,
		}
		
		local success = SplitTracker.AppendRecord(currentMapName, currentWeather, record)
		print("[UmaSplits] Saved record:", success and "OK" or "FAILED", currentMapName, currentWeather, totalTime)
	end
	
	-- Clean up connections
	if slipConnection then
		slipConnection:Disconnect()
		slipConnection = nil
	end
	if zoneCutsceneTracking then
		zoneCutsceneTracking:Disconnect()
		zoneCutsceneTracking = nil
	end
	
	isRaceActive = false
	raceStartTime = nil
end

local function OnMapLoad()
	currentMapName = DetectMap()
	currentWeather = DetectWeather()
	currentUma = DetectUma()
	
	if currentMapName then
		-- Update tracker title
		local weatherIcon = currentWeather == "Snow" and "❄️" or (currentWeather == "Rain" and "🌧️" or "☀️")
		TrackerTitleLabel.Text = "🏁 " .. currentMapName .. " " .. weatherIcon
		
		-- Setup checkpoints
		SetupCheckpoints()
	end
end

local function OnMapUnload()
	OnRaceEnd()
	
	-- Hide UI
	TrackerPanel.Visible = false
	SplitPopup.Visible = false
	
	-- Clear connections
	for _, connection in ipairs(checkpointConnections) do
		connection:Disconnect()
	end
	checkpointConnections = {}
	
	currentMapName = nil
	currentWeather = nil
end

--------------------------------------------------------------------------------
-- Event Listeners
--------------------------------------------------------------------------------

-- Map attribute detection
Configuration:GetAttributeChangedSignal("Map"):Connect(function()
	local mapValue = Configuration:GetAttribute("Map")
	
	if mapValue and mapValue ~= "" then
		task.wait(0.3)
		OnMapLoad()
	else
		OnMapUnload()
	end
end)

-- Race start detection (GateStart attribute)
Configuration:GetAttributeChangedSignal("GateStart"):Connect(function()
	local gateStart = Configuration:GetAttribute("GateStart")
	
	if gateStart == true then
		OnRaceStart()
	end
end)

-- Race end detection (FinishedRace flag on character)
local function WatchForFinishedRace(character)
	if not character then return end
	
	character.ChildAdded:Connect(function(child)
		if child.Name == "FinishedRace" and isRaceActive then
			OnRaceEnd()
		end
	end)
end

if LocalPlayer.Character then
	WatchForFinishedRace(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(WatchForFinishedRace)

-- Cutscene pause detection
Lighting.ChildAdded:Connect(function(child)
	if child.Name == "CutsceneOn" and isRaceActive then
		cutscenePauseStart = Clock()
	end
end)

Lighting.ChildRemoved:Connect(function(child)
	if child.Name == "CutsceneOn" and cutscenePauseStart then
		local pauseDuration = Clock() - cutscenePauseStart
		cumulativePauseTime = cumulativePauseTime + pauseDuration
		cutscenePauseStart = nil
	end
end)

-- Initial check if map already loaded
local initialMap = Configuration:GetAttribute("Map")
if initialMap and initialMap ~= "" then
	OnMapLoad()
end

print("[UmaSplits] Loaded - Mode:", comparisonMode)
