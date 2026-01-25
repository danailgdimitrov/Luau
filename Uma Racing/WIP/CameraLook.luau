-- Camera Look Script (Z = Left, C = Right, X = Back)
-- Disables shift lock while looking, re-enables when centered

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer

-- Configuration
local LOOK_ANGLE_SIDE = 90  -- Degrees for left/right
local LOOK_ANGLE_BACK = 180 -- Degrees for backwards
local LOOK_SPEED = 10       -- How fast to rotate (higher = faster)
local CENTER_THRESHOLD = 1  -- Degrees from center to consider "centered"

-- Cleanup previous instance
if _G.CameraLookCleanup then
    _G.CameraLookCleanup()
end

-- State
local currentOffset = 0
local targetOffset = 0
local connections = {}
local savedMouseBehavior = nil
local isLooking = false

-- Get character's look direction as base
local function getBaseCFrame()
    local character = Player.Character
    if not character then return nil end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    return hrp.CFrame
end

-- Disable shift lock
local function disableShiftLock()
    if not isLooking then
        savedMouseBehavior = UserInputService.MouseBehavior
        isLooking = true
    end
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

-- Restore shift lock
local function restoreShiftLock()
    if savedMouseBehavior then
        UserInputService.MouseBehavior = savedMouseBehavior
        savedMouseBehavior = nil
    end
    isLooking = false
end

-- Input handling
local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.Z then
        targetOffset = LOOK_ANGLE_SIDE -- Look left
        disableShiftLock()
    elseif input.KeyCode == Enum.KeyCode.C then
        targetOffset = -LOOK_ANGLE_SIDE -- Look right
        disableShiftLock()
    elseif input.KeyCode == Enum.KeyCode.X then
        targetOffset = LOOK_ANGLE_BACK -- Look backwards
        disableShiftLock()
    end
end

local function onInputEnded(input)
    if input.KeyCode == Enum.KeyCode.Z or input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.X then
        targetOffset = 0 -- Return to center
    end
end

-- Camera update loop
local function onRenderStep(dt)
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local baseCFrame = getBaseCFrame()
    if not baseCFrame then return end
    
    -- Smoothly interpolate towards target
    local diff = targetOffset - currentOffset
    currentOffset = currentOffset + diff * math.min(1, LOOK_SPEED * dt)
    
    -- Check if we've returned to center
    if isLooking and targetOffset == 0 and math.abs(currentOffset) < CENTER_THRESHOLD then
        currentOffset = 0
        restoreShiftLock()
    end
    
    -- Apply camera rotation if we have an offset
    if math.abs(currentOffset) > 0.1 then
        local pos = camera.CFrame.Position
        
        -- Calculate look direction based on character facing + offset
        local rotatedCFrame = baseCFrame * CFrame.Angles(0, math.rad(currentOffset), 0)
        local lookDirection = rotatedCFrame.LookVector
        
        -- Keep current camera pitch
        local currentLook = camera.CFrame.LookVector
        local pitch = math.asin(currentLook.Y)
        
        -- Apply horizontal rotation while preserving pitch
        local horizontalLook = Vector3.new(lookDirection.X, 0, lookDirection.Z).Unit
        local finalLook = (horizontalLook + Vector3.new(0, math.tan(pitch), 0)).Unit
        
        camera.CFrame = CFrame.new(pos, pos + finalLook)
    end
end

-- Connect events
connections.inputBegan = UserInputService.InputBegan:Connect(onInputBegan)
connections.inputEnded = UserInputService.InputEnded:Connect(onInputEnded)
connections.renderStep = RunService.RenderStepped:Connect(onRenderStep)

-- Cleanup function for re-execution
_G.CameraLookCleanup = function()
    for _, conn in pairs(connections) do
        if conn then
            conn:Disconnect()
        end
    end
    connections = {}
    currentOffset = 0
    targetOffset = 0
    if savedMouseBehavior then
        restoreShiftLock()
    end
    print("🔄 Camera Look cleaned up")
end

print("✅ Camera Look loaded!")
print("   Z = Look Left | C = Look Right | X = Look Back")
