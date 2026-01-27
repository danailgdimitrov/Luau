--!native
--!optimize 2
---@diagnostic disable: undefined-global

--[[
	SplitTracker.luau - Generic timing framework for racing/speedrun games
	
	A reusable module for recording split times, persisting data via JSON-Lines,
	and calculating statistics (median, average, personal best).
	
	Usage:
	------------------------------------------------------------
	local SplitTracker = loadstring(game:HttpGet("..."))()
	
	SplitTracker.Initialize({
		BaseFolder = "MyGame_Data",
		TrackPlayer = true,        -- Include player name in records
		EntityKey = "uma",         -- Field name for entity/class (nil to omit, if there are no variants of entities)
	})
	
	-- Load history for a map/condition
	local history = SplitTracker.LoadHistory("Kyoto", "Clear")
	
	-- Append a new record
	SplitTracker.AppendRecord("Kyoto", "Clear", {
		player = "PlayerName",
		uma = "Gold Ship",
		totalTime = 127.5,
		splits = {12.5, 28.3, 45.1, 62.8, 80.2, 97.5},
	})
	
	-- Get statistics (optionally filter by entity)
	local stats = SplitTracker.GetStats("Kyoto", "Clear", "Gold Ship")
	-- stats = { medians = {...}, averages = {...}, bests = {...}, recordTotal = 120.5 }
	
	-- Calculate delta string
	local delta = SplitTracker.CalculateDelta(45.5, 44.2)  -- "+1.30s"
	------------------------------------------------------------
]]

-- Performance: local references for global lookups
local TableInsert = table.insert
local TableSort = table.sort
local MathFloor = math.floor
local StringFormat = string.format
local OsTime = os.time

-- Load Services internally
local Services = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/danailgdimitrov/Luau/refs/heads/main/Miscellaneous/Services.luau"))()

local SplitTracker = {}

-- Configuration (set via Initialize)
local Config = {
	BaseFolder = "SplitTracker_Data",
	TrackPlayer = true,
	EntityKey = nil,
}

-- Cache: _G.SplitCache[map][condition] = { history = {...}, stats = {...} }
_G.SplitCache = _G.SplitCache or {}

--------------------------------------------------------------------------------
-- Private: File I/O Helpers
--------------------------------------------------------------------------------

local function _EnsureFolder(path)
	if makefolder and not isfolder(path) then
		pcall(makefolder, path)
	end
end

local function _GetFilePath(mapName, condition)
	local mapFolder = Config.BaseFolder .. "/" .. mapName
	_EnsureFolder(Config.BaseFolder)
	_EnsureFolder(mapFolder)
	return mapFolder .. "/" .. condition .. ".jsonl"
end

local function _ReadFile(path)
	if not isfile or not isfile(path) then
		return nil
	end
	local success, content = pcall(readfile, path)
	return success and content or nil
end

local function _WriteFile(path, content)
	if not writefile then return false end
	local success = pcall(writefile, path, content)
	return success
end

local function _AppendFile(path, content)
	if appendfile then
		local success = pcall(appendfile, path, content)
		return success
	elseif writefile then
		-- Fallback: read + append + write
		local existing = _ReadFile(path) or ""
		return _WriteFile(path, existing .. content)
	end
	return false
end

--------------------------------------------------------------------------------
-- Private: Statistics Helpers
--------------------------------------------------------------------------------

local function _CalculateMedian(values)
	if #values == 0 then return nil end
	
	local sorted = {}
	for i, value in ipairs(values) do
		sorted[i] = value
	end
	TableSort(sorted)
	
	local count = #sorted
	local middle = MathFloor(count / 2)
	
	if count % 2 == 0 then
		return (sorted[middle] + sorted[middle + 1]) / 2
	else
		return sorted[middle + 1]
	end
end

local function _CalculateAverage(values)
	if #values == 0 then return nil end
	
	local sum = 0
	for _, value in ipairs(values) do
		sum = sum + value
	end
	return sum / #values
end

local function _FilterOutliers(history, threshold)
	if #history < 3 then
		-- Not enough data to determine outliers
		return history
	end
	
	-- Calculate median total time
	local totalTimes = {}
	for _, record in ipairs(history) do
		TableInsert(totalTimes, record.totalTime)
	end

	local medianTime = _CalculateMedian(totalTimes)
	if not medianTime then return history end
	
	-- Filter records exceeding threshold
	local cutoff = medianTime * threshold
	local filtered = {}
	for _, record in ipairs(history) do
		if record.totalTime <= cutoff then
			TableInsert(filtered, record)
		end
	end
	
	return filtered
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function SplitTracker.Initialize(userConfig)
	if userConfig.BaseFolder then
		Config.BaseFolder = userConfig.BaseFolder
	end
	if userConfig.TrackPlayer ~= nil then
		Config.TrackPlayer = userConfig.TrackPlayer
	end
	if userConfig.EntityKey then
		Config.EntityKey = userConfig.EntityKey
	end
	
	-- Ensure base folder exists
	_EnsureFolder(Config.BaseFolder)
end

function SplitTracker.LoadHistory(mapName, condition)
	-- Guard against nil parameters
	if not mapName or not condition then
		warn("[SplitTracker] LoadHistory called with nil:", mapName, condition)
		return {}
	end
	
	-- Check cache first
	_G.SplitCache[mapName] = _G.SplitCache[mapName] or {}
	local mapCache = _G.SplitCache[mapName]
	
	if mapCache[condition] then
		return mapCache[condition].history
	end
	
	-- Load from file
	local path = _GetFilePath(mapName, condition)
	local content = _ReadFile(path)
	local history = {}
	
	if content and content ~= "" then
		-- Parse JSONL: each line is a JSON object
		for line in content:gmatch("[^\n]+") do
			local success, record = pcall(function()
				return Services.HttpService:JSONDecode(line)
			end)
			if success and record then
				TableInsert(history, record)
			end
		end
		print("[SplitTracker] Loaded", #history, "records from", path)
	end
	
	-- Store in cache
	mapCache[condition] = {
		history = history,
		stats = nil,  -- Calculate lazily
	}
	
	return history
end

function SplitTracker.AppendRecord(mapName, condition, record)
	-- Guard against nil parameters
	if not mapName or not condition then
		warn("[SplitTracker] AppendRecord called with nil:", mapName, condition)
		return false
	end
	
	-- Add timestamp if not present
	record.timestamp = record.timestamp or OsTime()
	
	-- Ensure history is loaded
	local history = SplitTracker.LoadHistory(mapName, condition)
	
	-- Add to cache
	TableInsert(history, record)
	
	-- Invalidate cached stats (will recalculate on next GetStats)
	local mapCache = _G.SplitCache[mapName]
	if mapCache and mapCache[condition] then
		mapCache[condition].stats = nil
	end
	
	-- Append to file
	local path = _GetFilePath(mapName, condition)
	local jsonLine = Services.HttpService:JSONEncode(record) .. "\n"
	local success = _AppendFile(path, jsonLine)
	
	if success then
		print("[SplitTracker] Saved to", path)
	else
		warn("[SplitTracker] Failed to save to", path)
	end
	
	return success
end

function SplitTracker.GetStats(mapName, condition, entityFilter)
	-- Ensure history is loaded
	local history = SplitTracker.LoadHistory(mapName, condition)
	local mapCache = _G.SplitCache[mapName]
	local cacheEntry = mapCache and mapCache[condition]
	
	-- Check if we have cached stats for this filter
	local cacheKey = entityFilter or "__global__"
	if cacheEntry and cacheEntry.stats and cacheEntry.stats[cacheKey] then
		return cacheEntry.stats[cacheKey]
	end
	
	-- Filter by entity if specified
	local filtered = history
	if entityFilter and Config.EntityKey then
		filtered = {}
		for _, record in ipairs(history) do
			if record[Config.EntityKey] == entityFilter then
				TableInsert(filtered, record)
			end
		end
	end
	
	-- Apply outlier filter (>150% of median)
	filtered = _FilterOutliers(filtered, 1.5)
	
	if #filtered == 0 then
		return {
			medians = {},
			averages = {},
			bests = {},
			recordTotal = nil,
			personalBest = nil,
		}
	end
	
	-- Calculate stats for each split
	local splitCount = #filtered[1].splits
	local medians = {}
	local averages = {}
	local bests = {}
	
	for splitIndex = 1, splitCount do
		local splitTimes = {}
		for _, record in ipairs(filtered) do
			if record.splits and record.splits[splitIndex] then
				TableInsert(splitTimes, record.splits[splitIndex])
			end
		end
		
		medians[splitIndex] = _CalculateMedian(splitTimes)
		averages[splitIndex] = _CalculateAverage(splitTimes)
		bests[splitIndex] = splitTimes[1]
		for _, time in ipairs(splitTimes) do
			if time < bests[splitIndex] then
				bests[splitIndex] = time
			end
		end
	end
	
	-- Calculate total time stats
	local totalTimes = {}
	for _, record in ipairs(filtered) do
		TableInsert(totalTimes, record.totalTime)
	end
	
	local recordTotal = totalTimes[1]
	for _, time in ipairs(totalTimes) do
		if time < recordTotal then
			recordTotal = time
		end
	end
	
	local stats = {
		medians = medians,
		averages = averages,
		bests = bests,
		recordTotal = recordTotal,
		medianTotal = _CalculateMedian(totalTimes),
		averageTotal = _CalculateAverage(totalTimes),
		count = #filtered,
	}
	
	-- Cache stats
	if cacheEntry then
		cacheEntry.stats = cacheEntry.stats or {}
		cacheEntry.stats[cacheKey] = stats
	end
	
	return stats
end

function SplitTracker.GetPersonalBest(mapName, condition, playerName, entityFilter)
	local history = SplitTracker.LoadHistory(mapName, condition)
	
	local bestRecord = nil
	for _, record in ipairs(history) do
		local matchesPlayer = not Config.TrackPlayer or record.player == playerName
		local matchesEntity = not entityFilter or not Config.EntityKey or record[Config.EntityKey] == entityFilter
		
		if matchesPlayer and matchesEntity then
			if not bestRecord or record.totalTime < bestRecord.totalTime then
				bestRecord = record
			end
		end
	end
	
	return bestRecord
end

function SplitTracker.CalculateDelta(currentTime, referenceTime)
	if not referenceTime then
		return nil
	end
	
	local delta = currentTime - referenceTime
	local sign = delta >= 0 and "+" or ""
	
	return StringFormat("%s%.2fs", sign, delta)
end

function SplitTracker.CalculateDeltaColor(currentTime, referenceTime)
	if not referenceTime then
		return nil, Color3.fromRGB(200, 200, 220)  -- Neutral
	end
	
	local delta = currentTime - referenceTime
	local deltaString = SplitTracker.CalculateDelta(currentTime, referenceTime)
	
	if delta < -0.5 then
		return deltaString, Color3.fromRGB(100, 255, 150)  -- Green (ahead)
	elseif delta > 0.5 then
		return deltaString, Color3.fromRGB(255, 100, 100)  -- Red (behind)
	else
		return deltaString, Color3.fromRGB(255, 220, 100)  -- Yellow (close)
	end
end

function SplitTracker.InvalidateCache(mapName)
	if mapName then
		_G.SplitCache[mapName] = nil
	else
		_G.SplitCache = {}
	end
end

function SplitTracker.GetConfig()
	return Config
end

return SplitTracker
