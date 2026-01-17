loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/main/Miscellaneous/Hook%20Console%20Logging.luau"))()

local MVP_VALUE = 380

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local hasMVPs = false

for _, Player in Players:GetPlayers() do
    if Player == LocalPlayer then continue end
    if Player.leaderstats.MVP.Value < MVP_VALUE then continue end

    hasMVPs = true
    break
end

LocalPlayer.OnTeleport:Connect(function(teleportState)
    if teleportState ~= Enum.TeleportState.InProgress then return end

    print("Teleport is in progress, queueing script.")

    queue_on_teleport(loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/main/Uma%20Racing/Server%20Hop.luau")))
end)

if not hasMVPs then
    warn("No MVPs.")
    return game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
else
    warn("Has MVPs.")
end
