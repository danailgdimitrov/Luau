local Services = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/refs/heads/main/Miscellaneous/Services.luau"))()

local LocalPlayer = Services.Players.LocalPlayer
local Remotes = Services.ReplicatedStorage.remotes
local Configuration = Services.Lighting:WaitForChild("Configuration")

-- Race status cache (safe to read in hooks)
local isRaceActive = false
local cachedFinishTime = nil

local remotes = {
    Spurt = Remotes.Spurt,
    Ultimate = Remotes.Ultimate,
    RequestAbility = Remotes.RequestAbility,
    RequestSprintAction = Remotes.RequestSprintAction,
    Visuals = Services.ReplicatedStorage.Package.Remotes.Visuals
}

-- Track last activation times (bidirectional)
local lastUltimateTime = nil
local lastAbilityTime = nil
local lastSpurtTime = nil  -- For measuring Spurt → Ultimate/Ability
local lastQTETime = nil    -- For measuring QTE → Spurt
local lastSpurtTimeForQTE = nil -- For measuring Spurt → QTE

-- Cooldown tracking (15 seconds each)
local COOLDOWN_DURATION = 15
local spurtCooldownEnd = 0
local slipCooldownEnd = 0

-- SpeedTarget tracking (smart stabilization)
local currentSpeedTarget = nil
local displayedSpeedTarget = nil
local speed_target_history = {}  -- Recent values for pattern detection
local HISTORY_SIZE = 10  -- How many values to track (faster response)
local STABILITY_THRESHOLD = 2  -- Small fluctuation range (more sensitive)
local BIG_JUMP_THRESHOLD = 10  -- Immediate update threshold (lower = more responsive)
local lastSpeedTargetUpdate = 0  -- When display last changed
local STABLE_TIMEOUT = 2  -- Seconds before color returns to white

-- Character transition tracking
local previousCharName = nil
local isCharacterTransitioning = false

-- Label transition tracking (for smooth text/color changes)
local tween_cache = {}  -- Stores active tweens to cancel if needed

-- Speed indicator transition tracking
local indicatorIsTransitioning = false

--------------------------------------------------------------------------------
-- Theme (Centralized Colors, Fonts, Sizes)
--------------------------------------------------------------------------------

local Theme = {
    Colors = {
        -- UI Frame colors
        Background = Color3.fromRGB(20, 20, 25),
        TitleBar = Color3.fromRGB(30, 30, 40),
        Stroke = Color3.fromRGB(80, 80, 100),
        SliderTrack = Color3.fromRGB(50, 50, 60),
        SliderFill = Color3.fromRGB(100, 180, 255),
        
        -- Text colors
        Text = Color3.fromRGB(220, 220, 240),
        TextMuted = Color3.fromRGB(100, 100, 120),
        TextSubtle = Color3.fromRGB(150, 150, 170),
        SectionText = Color3.fromRGB(110, 110, 140),
        TooltipText = Color3.fromRGB(200, 200, 220),
        Tooltip = Color3.fromRGB(40, 40, 50),
        
        -- Status colors
        Success = Color3.fromRGB(100, 255, 150),
        Warning = Color3.fromRGB(255, 220, 100),
        WarningMid = Color3.fromRGB(255, 150, 50),
        Danger = Color3.fromRGB(255, 100, 100),
        Neutral = Color3.fromRGB(200, 200, 220),
        
        -- Row label colors
        Ultimate = Color3.fromRGB(255, 180, 80),
        Ability = Color3.fromRGB(100, 180, 255),
        QTE = Color3.fromRGB(255, 100, 150),
        Character = Color3.fromRGB(255, 150, 255),
        Speed = Color3.fromRGB(180, 100, 255),
        Stamina = Color3.fromRGB(50, 255, 100),
        SpurtCD = Color3.fromRGB(100, 255, 180),
        SlipCD = Color3.fromRGB(128, 220, 255),
        Elapsed = Color3.fromRGB(255, 220, 100),
        Finish = Color3.fromRGB(100, 255, 255),
        
        -- Timing result colors
        UltimateResult = Color3.fromRGB(255, 200, 100),
        AbilityResult = Color3.fromRGB(100, 200, 255),
        QTEResult = Color3.fromRGB(255, 100, 150),
    },
    
    Fonts = {
        Primary = Enum.Font.GothamBold,
        Secondary = Enum.Font.Gotham,
    },
    
    Sizes = {
        Row = 22,
        Section = 14,
        LabelText = 13,
        ValueText = 16,
        TitleText = 13,
        TooltipText = 11,
        SectionText = 9,
    },
}

-- Helper: Tween a label's color smoothly
local function TweenLabelColor(label, newColor, duration)
    duration = duration or 0.35
    
    -- Cancel any existing tween for this label
    if tween_cache[label] then
        tween_cache[label]:Cancel()
    end
    
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = Services.TweenService:Create(label, tweenInfo, {TextColor3 = newColor})
    tween_cache[label] = tween
    tween:Play()
end

-- Helper: Smooth text change with a quick fade
local function SmoothTextChange(label, newText, newColor, duration)
    duration = duration or 0.35
    
    -- Only animate if text actually changed
    if label.Text == newText then
        -- Just update color smoothly if text is same
        if newColor and label.TextColor3 ~= newColor then
            TweenLabelColor(label, newColor, duration)
        end
        return
    end
    
    -- Fade out, change, fade in
    local tweenInfo = TweenInfo.new(duration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local fadeOut = Services.TweenService:Create(label, tweenInfo, {TextTransparency = 0.7})
    fadeOut:Play()
    
    fadeOut.Completed:Connect(function()
        label.Text = newText
        if newColor then
            label.TextColor3 = newColor
        end
        
        local fadeIn = Services.TweenService:Create(label, tweenInfo, {TextTransparency = 0})
        fadeIn:Play()
    end)
end

-- Helper: Fade indicator for icon change (for speed arrows)
-- Position animation not used since UIListLayout controls position
local function SlideIndicator(indicator, newIcon, newColor, duration)
    duration = duration or 0.35
    
    -- If same icon, just update color
    if indicator.Text == newIcon then
        if newColor then
            TweenLabelColor(indicator, newColor, duration)
        end
        return
    end
    
    -- Don't stack animations
    if indicatorIsTransitioning then return end
    indicatorIsTransitioning = true
    
    -- Start color tween immediately (syncs with number color)
    if newColor then
        TweenLabelColor(indicator, newColor, duration)
    end
    
    -- Fade out
    local fadeOutInfo = TweenInfo.new(duration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local fadeOut = Services.TweenService:Create(indicator, fadeOutInfo, {
        TextTransparency = 1
    })
    fadeOut:Play()
    
    fadeOut.Completed:Connect(function()
        -- Change icon while hidden
        indicator.Text = newIcon
        
        -- Fade in
        local fadeInInfo = TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local fadeIn = Services.TweenService:Create(indicator, fadeInInfo, {
            TextTransparency = 0
        })
        fadeIn:Play()
        
        fadeIn.Completed:Connect(function()
            indicatorIsTransitioning = false
        end)
    end)
end

--------------------------------------------------------------------------------
-- UI Setup (Protected with gethui)
--------------------------------------------------------------------------------

local SETTINGS_FILE = "SpurtStopwatchSettings.json"
local saved_settings = { posX = 0.5, posY = 0.1, opacity = 0 }

-- Try to load saved settings
pcall(function()
    if isfile and isfile(SETTINGS_FILE) then
        local data = readfile(SETTINGS_FILE)
        local decoded = Services.HttpService:JSONDecode(data)
        if decoded then
            saved_settings = decoded
        end
    end
end)

local function SaveSettings()
    pcall(function()
        if writefile then
            local data = Services.HttpService:JSONEncode(saved_settings)
            writefile(SETTINGS_FILE, data)
        end
    end)
end

local HiddenUI = gethui()

local ExistingGui = HiddenUI:FindFirstChild("SpurtTimerGui")
if ExistingGui then ExistingGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpurtTimerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = HiddenUI

-- Main frame (draggable) - Using CanvasGroup for GroupTransparency
local MainFrame = Instance.new("CanvasGroup")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 220, 0, 380)  -- Compact layout
MainFrame.Position = UDim2.new(saved_settings.posX, 0, saved_settings.posY, 0)
MainFrame.BackgroundColor3 = Theme.Colors.Background
MainFrame.GroupTransparency = saved_settings.opacity or 0
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Theme.Colors.Stroke
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 26)
TitleBar.BackgroundColor3 = Theme.Colors.TitleBar
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local TitleFix = Instance.new("Frame")
TitleFix.Size = UDim2.new(1, 0, 0, 10)
TitleFix.Position = UDim2.new(0, 0, 1, -10)
TitleFix.BackgroundColor3 = Theme.Colors.TitleBar
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(0.7, 0, 1, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "🐴 UMX" -- Uma (Musume) Extended
TitleLabel.TextColor3 = Theme.Colors.Text
TitleLabel.TextSize = 13
TitleLabel.Font = Theme.Fonts.Primary
TitleLabel.Parent = TitleBar

-- Opacity slider at bottom of frame
local OpacityContainer = Instance.new("Frame")
OpacityContainer.Name = "OpacityContainer"
OpacityContainer.Size = UDim2.new(1, -20, 0, 20)
OpacityContainer.Position = UDim2.new(0, 10, 1, -25)
OpacityContainer.BackgroundTransparency = 1
OpacityContainer.Parent = MainFrame

local OpacityLabel = Instance.new("TextLabel")
OpacityLabel.Size = UDim2.new(0, 50, 1, 0)
OpacityLabel.BackgroundTransparency = 1
OpacityLabel.Text = "Opacity:"
OpacityLabel.TextColor3 = Theme.Colors.TextSubtle
OpacityLabel.TextSize = 11
OpacityLabel.Font = Theme.Fonts.Secondary
OpacityLabel.TextXAlignment = Enum.TextXAlignment.Left
OpacityLabel.Parent = OpacityContainer

local OpacitySlider = Instance.new("Frame")
OpacitySlider.Name = "OpacitySlider"
OpacitySlider.Size = UDim2.new(1, -55, 0, 8)
OpacitySlider.Position = UDim2.new(0, 55, 0.5, -4)
OpacitySlider.BackgroundColor3 = Theme.Colors.SliderTrack
OpacitySlider.BorderSizePixel = 0
OpacitySlider.Parent = OpacityContainer

local SliderCorner = Instance.new("UICorner")
SliderCorner.CornerRadius = UDim.new(0, 4)
SliderCorner.Parent = OpacitySlider

local SliderFill = Instance.new("Frame")
SliderFill.Name = "Fill"
SliderFill.Size = UDim2.new(1 - ((saved_settings.opacity or 0) / 0.7), 0, 1, 0)
SliderFill.BackgroundColor3 = Theme.Colors.SliderFill
SliderFill.BorderSizePixel = 0
SliderFill.Parent = OpacitySlider

local FillCorner = Instance.new("UICorner")
FillCorner.CornerRadius = UDim.new(0, 4)
FillCorner.Parent = SliderFill

-- Slider interaction
local slidingOpacity = false

OpacitySlider.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        slidingOpacity = true
    end
end)

OpacitySlider.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        slidingOpacity = false
        SaveSettings()
    end
end)

Services.UserInputService.InputChanged:Connect(function(input)
    if slidingOpacity and input.UserInputType == Enum.UserInputType.MouseMovement then
        local relX = math.clamp((input.Position.X - OpacitySlider.AbsolutePosition.X) / OpacitySlider.AbsoluteSize.X, 0, 1)
        local opacity = 1 - relX  -- Left = transparent, Right = opaque
        saved_settings.opacity = opacity * 0.7  -- Max 70% transparent
        MainFrame.GroupTransparency = saved_settings.opacity
        SliderFill.Size = UDim2.new(relX, 0, 1, 0)
    end
end)

-- Content area
local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -36)
Content.Position = UDim2.new(0, 10, 0, 30)
Content.BackgroundTransparency = 1
Content.Parent = MainFrame

local ListLayout = Instance.new("UIListLayout")
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0, 4)
ListLayout.Parent = Content

--------------------------------------------------------------------------------
-- UI Module (loaded from external file)
--------------------------------------------------------------------------------

local UI = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/refs/heads/main/Miscellaneous/UIModule.luau"))()({
    Services = Services,
    Theme = Theme,
    Content = Content,
    ScreenGui = ScreenGui,
})

-- Build the UI using declarative config
UI.CreateSection({
    Text = "⚡ SPURT TIMING",
    Rows = {
        {Name = "Ultimate", Label = "Ultimate:", Color = Theme.Colors.Ultimate,
         Tooltip = "Time between Ultimate and Spurt.\n▶ = Ult first, ◀ = Spurt first"},
        {Name = "Ability", Label = "Ability:", Color = Theme.Colors.Ability,
         Tooltip = "Time between Ability and Spurt.\n▶ = Abil first, ◀ = Spurt first"},
        {Name = "QTE", Label = "QTE:", Color = Theme.Colors.QTE,
         Tooltip = "Time between QTE (SkillCheck) and Spurt.\n▶ = QTE first, ◀ = Spurt first"},
    }
})

UI.CreateSection({
    Text = "📊 STATS",
    Rows = {
        {Name = "Character", Label = "Uma:", Color = Theme.Colors.Character,
         Tooltip = "Your currently selected character."},
        {Name = "SpeedTarget", Label = "Speed:", Color = Theme.Colors.Speed, HasIndicator = true,
         Tooltip = "Your current speed target value."},
        {Name = "Stamina", Label = "Stamina:", Color = Theme.Colors.Stamina,
         Tooltip = "Your current stamina percentage."},
    }
})

UI.CreateSection({
    Text = "⏳ COOLDOWNS",
    Rows = {
        {Name = "SpurtCD", Label = "Spurt:", Color = Theme.Colors.SpurtCD,
         Tooltip = "Cooldown until Spurt is ready (15s)."},
        {Name = "SlipCD", Label = "Slip:", Color = Theme.Colors.SlipCD,
         Tooltip = "Cooldown until Slipstream is ready (15s)."},
    }
})

UI.CreateSection({
    Text = "⏱ LAP TIME",
    Rows = {
        {Name = "ElapsedTime", Label = "Elapsed:", Color = Theme.Colors.Elapsed,
         Tooltip = "Elapsed time in the current race."},
        {Name = "FinishTime", Label = "Finish:", Color = Theme.Colors.Finish,
         Tooltip = "Your finish time when you complete the race."},
    }
})

-- Convenience aliases for accessing labels (maintaining backward compatibility)
local UltimateValue = UI.Labels.Ultimate
local AbilityValue = UI.Labels.Ability
local QTEValue = UI.Labels.QTE
local CharacterValue = UI.Labels.Character
local SpeedTargetNumber = UI.Labels.SpeedTarget.Number
local SpeedTargetIndicator = UI.Labels.SpeedTarget.Indicator
local StaminaValue = UI.Labels.Stamina
local SpurtCDValue = UI.Labels.SpurtCD
local SlipCDValue = UI.Labels.SlipCD
local ElapsedTimeValue = UI.Labels.ElapsedTime
local FinishTimeValue = UI.Labels.FinishTime

--------------------------------------------------------------------------------
-- Dragging Logic
--------------------------------------------------------------------------------

local dragging = false
local dragStart = nil
local startPos = nil

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)

TitleBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        -- Save position when drag ends
        saved_settings.posX = MainFrame.Position.X.Scale + (MainFrame.Position.X.Offset / ScreenGui.AbsoluteSize.X)
        saved_settings.posY = MainFrame.Position.Y.Scale + (MainFrame.Position.Y.Offset / ScreenGui.AbsoluteSize.Y)
        SaveSettings()
    end
end)

Services.UserInputService.InputChanged:Connect(function(input)
    if slidingOpacity then return end  -- Don't move while adjusting opacity
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

--------------------------------------------------------------------------------
-- Cooldown Update Loop
--------------------------------------------------------------------------------

local function FormatCooldown(endTime)
    local remaining = endTime - os.clock()
    if remaining <= 0 then
        return "✅ READY", Theme.Colors.Success
    else
        return string.format("🔴 %.1fs", remaining), Theme.Colors.Danger
    end
end

local RACE_DURATION = 180 -- 3 minutes

local function FormatLapTime(raceTimeRemaining)
    if not raceTimeRemaining or raceTimeRemaining <= 0 or raceTimeRemaining > RACE_DURATION then
        return "--:--", Theme.Colors.TextMuted
    end
    local elapsed = RACE_DURATION - raceTimeRemaining
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)
    return string.format("%d:%02d", mins, secs), Theme.Colors.Success
end

--------------------------------------------------------------------------------
-- Uma Musume Character Gradients
--------------------------------------------------------------------------------

-- Manual hex parser since Color3.fromHex may not work in all executors
local function HexToColor3(hex)
    hex = hex:gsub("#", "")
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return Color3.fromRGB(r, g, b)
end

local function CreateGradient(c1, c2, c3)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, HexToColor3(c1)),
        ColorSequenceKeypoint.new(0.5, HexToColor3(c2)),
        ColorSequenceKeypoint.new(1, HexToColor3(c3))
    })
end

local CHARACTER_GRADIENTS = {
    ["Gold Ship"]      = CreateGradient("#FFE135", "#FFCC00", "#FFFACD"), -- Bright Gold -> Gold -> Cream
    ["Meisho Doto"]    = CreateGradient("#5B8DEE", "#FFFFFF", "#FFB6C1"), -- Bright Blue -> White -> Light Pink
    ["Tamamo Cross"]   = CreateGradient("#40E0D0", "#FFFFFF", "#98D8C8"), -- Turquoise -> White -> Mint
    ["T.M. Opera O"]   = CreateGradient("#DA70D6", "#FF9933", "#FFD700"), -- Orchid -> Orange -> Gold
    ["Oguri Cap"]      = CreateGradient("#4169E1", "#B0C4DE", "#E6E6FA"), -- Royal Blue -> Light Steel -> Lavender
    ["Silence Suzuka"] = CreateGradient("#32CD32", "#90EE90", "#ADFF2F"), -- Lime Green -> Light Green -> Green Yellow
    ["Daiwa Scarlet"]  = CreateGradient("#FF4444", "#FFFFFF", "#4488FF"), -- Bright Red -> White -> Blue
    ["Nice Nature"]    = CreateGradient("#FF6347", "#DAA520", "#3CB371"), -- Tomato -> Goldenrod -> Green
    ["Air Groove"]     = CreateGradient("#1E90FF", "#4169E1", "#FFD700"), -- Dodger Blue -> Royal Blue -> Gold
    ["Haru Urara"]     = CreateGradient("#FF69B4", "#FFB6C1", "#FFFACD"), -- Hot Pink -> Light Pink -> Lemon
    ["Rice Shower"]    = CreateGradient("#9370DB", "#6B5B7A", "#4A4458"), -- Purple -> Muted Purple -> Dark Plum/Grey
}

-- Default white gradient for unknown characters
local DEFAULT_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 220, 240))
})

-- Helper function to find character gradient (fuzzy match - handles spaces, case, underscores)
local function GetCharacterGradient(charName)
    -- Direct match first
    if CHARACTER_GRADIENTS[charName] then
        return CHARACTER_GRADIENTS[charName]
    end
    
    -- Normalize: lowercase and remove spaces/underscores for comparison
    local normalized = string.lower(charName):gsub("[%s_]", "")
    
    for key, gradient in pairs(CHARACTER_GRADIENTS) do
        local keyNormalized = string.lower(key):gsub("[%s_]", "")
        if normalized == keyNormalized then
            return gradient
        end
    end
    
    return DEFAULT_GRADIENT
end

--------------------------------------------------------------------------------
-- Main Update Loop
--------------------------------------------------------------------------------

local speedTargetIsColored = false

Services.RunService.Heartbeat:Connect(function()
    -- Check if SpeedTarget should return to neutral (stable)
    if speedTargetIsColored and (os.clock() - lastSpeedTargetUpdate) >= STABLE_TIMEOUT then
        speedTargetIsColored = false
        if displayedSpeedTarget then
            -- Tween number color to white, slide indicator to en dash
            local neutralColor = Theme.Colors.Neutral
            TweenLabelColor(SpeedTargetNumber, neutralColor, 0.4)
            SlideIndicator(SpeedTargetIndicator, "–", neutralColor, 0.4)
        end
    end

    -- Update Cooldowns (no animation - changes every frame)
    local spurtText, spurtColor = FormatCooldown(spurtCooldownEnd)
    SpurtCDValue.Text = spurtText
    SpurtCDValue.TextColor3 = spurtColor

    local slipText, slipColor = FormatCooldown(slipCooldownEnd)
    SlipCDValue.Text = slipText
    SlipCDValue.TextColor3 = slipColor

    -- Update Stamina
    local staminaPct = nil
    local playerFolder = workspace:FindFirstChild("Players")
    if playerFolder and LocalPlayer then
        local charModel = playerFolder:FindFirstChild(LocalPlayer.Name)
        if charModel then
            local hrp = charModel:FindFirstChild("HumanoidRootPart")
            if hrp then
                local runningUI = hrp:FindFirstChild("RunningUI")
                if runningUI then
                    local bars = runningUI:FindFirstChild("Bars")
                    if bars then
                        local staminaBar = bars:FindFirstChild("StaminaBar")
                        if staminaBar then
                            local fill = staminaBar:FindFirstChild("Fill")
                            if fill then
                                local gradient = fill:FindFirstChild("UIGradient")
                                if gradient then
                                    staminaPct = gradient.Offset.Y * 100
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if staminaPct then
        local staminaText = string.format("%.0f%%", staminaPct)
        local staminaColor
        if staminaPct >= 75 then
            staminaColor = Theme.Colors.Success  -- Green
        elseif staminaPct >= 50 then
            staminaColor = Theme.Colors.Warning  -- Yellow
        elseif staminaPct >= 25 then
            staminaColor = Theme.Colors.WarningMid  -- Orange
        else
            staminaColor = Theme.Colors.Danger  -- Red
        end
        
        StaminaValue.Text = staminaText
        TweenLabelColor(StaminaValue, staminaColor, 0.3)
    else
        StaminaValue.Text = "---"
        TweenLabelColor(StaminaValue, Theme.Colors.TextMuted, 0.3)
    end

    -- Update Elapsed Time
    local raceTime = Configuration:GetAttribute("RaceTime")
    local raceText, raceColor = FormatLapTime(raceTime)
    ElapsedTimeValue.Text = raceText
    ElapsedTimeValue.TextColor3 = raceColor

    -- Update cached race status safely
    isRaceActive = Configuration:GetAttribute("GateStart") and Configuration:GetAttribute("Intermission") == -1
    if not isRaceActive then
        cachedFinishTime = nil
    end

    -- Update Character (with gradient colors and transition animation)
    if LocalPlayer then
        local currChar = LocalPlayer:FindFirstChild("CurrentCharacter")
        if currChar then
            local charName = tostring(currChar.Value)
            
            -- Check if character changed
            if charName ~= previousCharName and not isCharacterTransitioning then
                isCharacterTransitioning = true
                
                -- Get or create UIGradient
                local gradient = CharacterValue:FindFirstChild("CharGradient")
                if not gradient then
                    gradient = Instance.new("UIGradient")
                    gradient.Name = "CharGradient"
                    gradient.Parent = CharacterValue
                end
                
                local newGradient = GetCharacterGradient(charName)
                
                -- Animation settings
                local transitionDuration = 0.5
                local slideDistance = 20  -- pixels to slide
                
                -- Store original position
                local originalPos = CharacterValue.Position
                
                -- Phase 1: Slide out to left
                local slideOutInfo = TweenInfo.new(transitionDuration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                local slideOut = Services.TweenService:Create(CharacterValue, slideOutInfo, {
                    Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset - slideDistance, originalPos.Y.Scale, originalPos.Y.Offset),
                    TextTransparency = 0.8
                })
                slideOut:Play()
                
                slideOut.Completed:Connect(function()
                    -- Change text and gradient while mostly invisible
                    CharacterValue.Text = charName
                    CharacterValue.TextColor3 = Color3.fromRGB(255, 255, 255)
                    gradient.Color = newGradient
                    
                    -- Position on right side for slide in
                    CharacterValue.Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset + slideDistance, originalPos.Y.Scale, originalPos.Y.Offset)
                    
                    -- Phase 2: Slide in from right
                    local slideInInfo = TweenInfo.new(transitionDuration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                    local slideIn = Services.TweenService:Create(CharacterValue, slideInInfo, {
                        Position = originalPos,
                        TextTransparency = 0
                    })
                    slideIn:Play()
                    
                    slideIn.Completed:Connect(function()
                        previousCharName = charName
                        isCharacterTransitioning = false
                    end)
                end)
            elseif charName == previousCharName or previousCharName == nil then
                -- Same character or first load - just set directly
                if previousCharName == nil then
                    previousCharName = charName
                end
                
                CharacterValue.Text = charName
                
                local gradient = CharacterValue:FindFirstChild("CharGradient")
                if not gradient then
                    gradient = Instance.new("UIGradient")
                    gradient.Name = "CharGradient"
                    gradient.Parent = CharacterValue
                end
                
                CharacterValue.TextColor3 = Color3.fromRGB(255, 255, 255)
                gradient.Color = GetCharacterGradient(charName)
            end
        else
            CharacterValue.Text = "-"
            local gradient = CharacterValue:FindFirstChild("CharGradient")
            if gradient then
                gradient.Color = DEFAULT_GRADIENT
            end
            previousCharName = nil
        end
    end

    -- Update Finish Time
    local isFinished = false
    local pFolder = workspace:FindFirstChild("Players")
    if pFolder then
        local charModel = pFolder:FindFirstChild(LocalPlayer.Name)
        if charModel and charModel:FindFirstChild("FinishedRace") then
            isFinished = true
        end
    end

    if isFinished then
        if not cachedFinishTime then
            local rTime = Configuration:GetAttribute("RaceTime") or RACE_DURATION
            cachedFinishTime = math.max(0, RACE_DURATION - rTime)
        end
        
        local fMins = math.floor(cachedFinishTime / 60)
        local fSecs = math.floor(cachedFinishTime % 60)
        FinishTimeValue.Text = string.format("%d:%02d", fMins, fSecs)
    else
        FinishTimeValue.Text = "--:--"
    end
end)

--------------------------------------------------------------------------------
-- Slipstream Detection (OnClientEvent)
--------------------------------------------------------------------------------

remotes.Visuals.OnClientEvent:Connect(function(effectType, effectName, ...)
    if not effectName then return end
    if typeof(effectName) ~= "string" or effectName:lower() ~= "slipstream +" then return end

    slipCooldownEnd = os.clock() + COOLDOWN_DURATION
end)

--------------------------------------------------------------------------------
-- Namecall Hook
--------------------------------------------------------------------------------

-- Helper: Display timing measurement on a label
local function DisplayTiming(label, ms, direction, color)
    local arrow = direction == "before" and "◀" or "▶"
    local text = string.format("%s %dms", arrow, ms)
    return task.defer(function()
        setthreadidentity(8)
        SmoothTextChange(label, text, color, 0.35)
    end)
end

-- Helper: Update speed display with trend indicator
local function UpdateSpeedDisplay(newValue, textColor, icon)
    return task.defer(function()
        setthreadidentity(8)
        SpeedTargetNumber.Text = string.format("%.0f", newValue)
        TweenLabelColor(SpeedTargetNumber, textColor, 0.35)
        SlideIndicator(SpeedTargetIndicator, icon, textColor, 0.35)
    end)
end

local VanillaNamecall; VanillaNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() ~= "FireServer" then return VanillaNamecall(self, ...) end

    local now = os.clock()

    -- Handle Ultimate (only in race)
    if rawequal(self, remotes.Ultimate) and isRaceActive then
        if lastSpurtTime then
            DisplayTiming(UltimateValue, (now - lastSpurtTime) * 1000, "before", Theme.Colors.UltimateResult)
            lastSpurtTime = nil
        else
            lastUltimateTime = now
        end
    end

    -- Handle Ability (only in race)
    if rawequal(self, remotes.RequestAbility) and isRaceActive then
        if lastSpurtTime then
            DisplayTiming(AbilityValue, (now - lastSpurtTime) * 1000, "before", Theme.Colors.AbilityResult)
            lastSpurtTime = nil
        else
            lastAbilityTime = now
        end
    end

    -- Handle Spurt (timing + cooldown, only in race)
    if rawequal(self, remotes.Spurt) and isRaceActive then
        spurtCooldownEnd = now + COOLDOWN_DURATION

        -- Check Ultimate/Ability timing (one or the other)
        if lastUltimateTime then
            DisplayTiming(UltimateValue, (now - lastUltimateTime) * 1000, "after", Theme.Colors.UltimateResult)
            lastUltimateTime = nil
        elseif lastAbilityTime then
            DisplayTiming(AbilityValue, (now - lastAbilityTime) * 1000, "after", Theme.Colors.AbilityResult)
            lastAbilityTime = nil
        else
            lastSpurtTime = now
        end

        -- Check QTE timing (independent)
        if lastQTETime then
            DisplayTiming(QTEValue, (now - lastQTETime) * 1000, "after", Theme.Colors.QTEResult)
            lastQTETime = nil
        else
            lastSpurtTimeForQTE = now
        end
    end

    -- Handle SpeedTarget (always tracks, not just in race)
    if rawequal(self, remotes.RequestSprintAction) then
        local args = {...}
        if args[1] ~= "SpeedTarget" then return VanillaNamecall(self, ...) end
        
        local newValue = args[2]
        
        -- Track history
        table.insert(speed_target_history, newValue)
        if #speed_target_history > HISTORY_SIZE then
            table.remove(speed_target_history, 1)
        end
        
        -- Calculate average
        local sum = 0
        for _, v in speed_target_history do sum = sum + v end
        local avgValue = sum / #speed_target_history
        
        currentSpeedTarget = newValue
        
        -- Determine if display should update
        local shouldUpdate, newDisplayValue = false, nil
        
        if not displayedSpeedTarget then
            shouldUpdate, newDisplayValue = true, math.floor(newValue + 0.5)
        elseif math.abs(newValue - displayedSpeedTarget) >= BIG_JUMP_THRESHOLD then
            shouldUpdate, newDisplayValue = true, math.floor(newValue + 0.5)
        elseif #speed_target_history >= HISTORY_SIZE then
            local allOutsideRange = true
            for _, v in speed_target_history do
                if math.abs(v - displayedSpeedTarget) < STABILITY_THRESHOLD then
                    allOutsideRange = false
                    break
                end
            end
            if allOutsideRange then
                shouldUpdate, newDisplayValue = true, math.floor(avgValue + 0.5)
            end
        end
        
        if shouldUpdate and newDisplayValue then
            -- Determine trend
            local icon, textColor, isColored = "–", Theme.Colors.Neutral, false
            
            if displayedSpeedTarget then
                if newDisplayValue > displayedSpeedTarget then
                    icon, textColor, isColored = "↑", Theme.Colors.Success, true
                elseif newDisplayValue < displayedSpeedTarget then
                    icon, textColor, isColored = "↓", Theme.Colors.Danger, true
                end
            end
            
            displayedSpeedTarget = newDisplayValue
            lastSpeedTargetUpdate = os.clock()
            speedTargetIsColored = isColored
            
            UpdateSpeedDisplay(newDisplayValue, textColor, icon)
        end
    end

    return VanillaNamecall(self, ...)
end)

--------------------------------------------------------------------------------
-- QTE Detection (SkillCheck appearing in PlayerGui)
--------------------------------------------------------------------------------

local function SetupQTEWatcher()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    
    local function OnSkillCheckAppeared()
        if isRaceActive then
            local now = os.clock()
            
            -- Check if Spurt came first (Spurt → QTE)
            if lastSpurtTimeForQTE then
                local ms = (now - lastSpurtTimeForQTE) * 1000
                local text = string.format("◀ %dms", ms)
                task.defer(function()
                    setthreadidentity(8)
                    SmoothTextChange(QTEValue, text, Theme.Colors.QTEResult, 0.35)
                end)
                lastSpurtTimeForQTE = nil
            else
                -- QTE came first, wait for Spurt
                lastQTETime = now
            end
        end
    end
    
    -- Watch for QTEGui appearing (handles respawn)
    PlayerGui.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "SkillCheck" then
            OnSkillCheckAppeared()
        end
    end)
    
    -- Also check if it already exists
    local existingQTE = PlayerGui:FindFirstChild("QTEGui")
    if existingQTE then
        local skillCheck = existingQTE:FindFirstChild("SkillCheck")
        if skillCheck then
            skillCheck:GetPropertyChangedSignal("Visible"):Connect(function()
                if skillCheck.Visible then
                    OnSkillCheckAppeared()
                end
            end)
        end
    end
end

task.spawn(SetupQTEWatcher)