if not game:IsLoaded() then
    game.Loaded:Wait()
end

loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/main/Miscellaneous/Hook%20Console%20Logging.luau"))()

local MVP_VALUE = 380
local MAX_PING = 150 -- Maximum acceptable ping in ms

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local hasMVPs = false

for _, Player in Players:GetPlayers() do
    if Player == LocalPlayer then continue end
    if Player.leaderstats.MVP.Value < MVP_VALUE then continue end

    rconsoleprint(`Found MVP: {Player.Name}\n`)
    hasMVPs = true
    break
end

rconsoleprint(`Has MVPs: {hasMVPs}\n`)

local function FindServer()
    local success, response = pcall(function()
        return HttpService:JSONDecode(game:HttpGetAsync(`https://games.roproxy.com/v1/games/{game.PlaceId}/servers/Public?sortOrder=Asc&limit=100`))
    end)
    
    if not success then
        rconsolewarn("Failed to fetch servers: {response}\n")
        return nil
    end
    
    if not response or not response.data then
        rconsolewarn("No server data in response\n")
        return nil
    end
    
    for _, server in response.data do
        -- Skip current server, full servers, and high ping servers
        local isCurrentServer = server.id == game.JobId
        local isFull = server.playing >= server.maxPlayers
        local hasBadPing = server.ping > MAX_PING
        
        if not isCurrentServer and not isFull and not hasBadPing then
            rconsoleprint(`Found server: {server.id} | Players: {server.playing}/{server.maxPlayers} | Ping: {server.ping or "unknown"}\n`)
            return server.id
        end
    end
    
    return nil
end

if not hasMVPs then
    rconsolewarn("No MVPs found in this server.\n")

    LocalPlayer.OnTeleport:Once(function(teleportState)
        rconsoleprint(`Teleport state: {teleportState}\n`)
        if teleportState ~= Enum.TeleportState.InProgress then return end

        rconsoleprint("Teleport is in progress, queueing script.\n")
        queue_on_teleport(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/main/Uma%20Racing/Server%20Hop.luau"))
    end)
    
    local serverId = FindServer()
    
    if serverId then
        rconsoleprint(`Teleporting to server: {serverId}\n`)
        TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
    else
        rconsolewarn("No suitable servers found, trying random teleport.\n")
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
else
    rconsoleprint("Has MVPs! Staying in server.\n")
end
