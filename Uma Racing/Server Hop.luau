local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local hasMVPs = false
local mvpValue = 380

for _, Player in Players:GetPlayers() do
    if Player == LocalPlayer then continue end
    if Player.leaderstats.MVP.Value < mvpValue then continue end

    hasMVPs = true
    break
end

LocalPlayer.OnTeleport:Connect(function(teleportState)
    if teleportState ~= Enum.TeleportState.InProgress then return end

    queue_on_teleport(loadfile(placeholder))
end)

if not hasMVPs then
    warn("No MVPs")
    return game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
else
    warn("Has MVPs")
end