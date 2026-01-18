repeat task.wait() until game:IsLoaded()

loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/main/Miscellaneous/Hook%20Console%20Logging.luau"))()

rconsoleprint("Game loaded\n")

-- Configuration
local MVP_VALUE = 380
local MAX_PING = 150 -- Need to make this check client ping, not server ping
local MAX_API_PAGES = 3 -- Maximum API pages to fetch

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Parse visited servers from teleport data (passed from previous hop)
local visited_servers = {}
local teleport_data = TeleportService:GetLocalPlayerJoinData()

-- Debug: print what we received
if teleport_data then
	rconsoleprint(`Received teleport data: {typeof(teleport_data)}\n`)
	for key, value in pairs(teleport_data) do
		rconsoleprint(`  [{key}] = {typeof(value)}\n`)
	end
else
	rconsoleprint("No teleport data received\n")
end

if teleport_data and teleport_data.VisitedServers then
	for _, serverJobId in teleport_data.VisitedServers do
		visited_servers[serverJobId] = true
	end

	rconsoleprint(`Loaded {#teleport_data.VisitedServers} previously visited servers\n`)
end

-- Always mark current server as visited
visited_servers[game.JobId] = true

local function CheckForMVPs(): boolean
	for _, Player in Players:GetPlayers() do
		if Player == LocalPlayer then continue end
		if Player.leaderstats.MVP.Value < MVP_VALUE then continue end

		rconsoleprint(`Found MVP: {Player.Name} (MVPs: {Player.leaderstats.MVP.Value})\n`)
		return true
	end
    
	return false
end

local function FetchServersPage(cursor: string?): ({any}?, string?)
	local url = `https://games.roblox.com/v1/games/{game.PlaceId}/servers/Public?limit=100` -- Has quite the strict ratelimit
	if cursor then
		url ..= `&cursor={cursor}`
	end

	local success, response = pcall(function()
		return HttpService:JSONDecode(game:HttpGetAsync(url))
	end)

	if not success then
		rconsolewarn(`Failed to fetch servers: {response}\n`)
		return nil, nil
	end

	if not response or not response.data then
		rconsolewarn("No server data in response\n")
		return nil, nil
	end

	return response.data, response.nextPageCursor
end

local function FindServer(): string?
	local cursor = nil
	local pagesChecked = 0

	repeat
		pagesChecked += 1
		local servers, nextCursor = FetchServersPage(cursor)
		cursor = nextCursor

		if not servers then break end

		for _, server in servers do
			local isCurrentServer = server.id == game.JobId
			local isVisited = visited_servers[server.id] == true
			local isFull = server.playing >= server.maxPlayers

			if not isCurrentServer and not isVisited and not isFull then
				rconsoleprint(`Found server: {server.id} | Players: {server.playing}/{server.maxPlayers}\n`)
				return server.id
			end
		end

		rconsoleprint(`Page {pagesChecked}: No valid server found, checking next page...\n`)
	until not cursor or pagesChecked >= MAX_API_PAGES

	return nil
end

local function GetVisitedServersList(): {string}
	local list = {}

	for serverJobId in visited_servers do
		table.insert(list, serverJobId)
	end

	return list
end

local function TeleportToServer(serverJobId: string?)
	local teleportData = {
		VisitedServers = GetVisitedServersList()
	}

	if serverJobId then
		rconsoleprint(`Teleporting to server: {serverJobId}\n`)

		-- Mark this server as visited before teleporting
		visited_servers[serverJobId] = true

		TeleportService:TeleportToPlaceInstance(game.PlaceId, serverJobId, LocalPlayer, nil, teleportData)
	else
		rconsolewarn("No suitable servers found, trying random teleport.\n")

		TeleportService:Teleport(game.PlaceId, LocalPlayer, teleportData)
	end
end

-- Main logic
local hasMVPs = CheckForMVPs()

if hasMVPs then
	rconsoleprint("Has MVPs! Staying in server.\n")
else
	rconsolewarn("No MVPs found in this server. Searching for a new server...\n")

	-- Set up teleport state listener for queueing script on next server
	LocalPlayer.OnTeleport:Connect(function(teleportState)
		rconsoleprint(`Teleport state: {teleportState.Name} ({teleportState.Value})\n`)

		if teleportState == Enum.TeleportState.InProgress then
			rconsoleprint("Teleport is in progress, queueing script.\n")
			queue_on_teleport(`loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/main/Uma%20Racing/Server%20Hop.luau"))()`)

		elseif teleportState == Enum.TeleportState.Failed then
			rconsolewarn("Teleport failed! Retrying with a different server...\n")
			task.wait(1)

			local serverJobId = FindServer()
			TeleportToServer(serverJobId)
		end
	end)

	-- Find and teleport to a suitable server
	local serverJobId = FindServer()
	TeleportToServer(serverJobId)
end
