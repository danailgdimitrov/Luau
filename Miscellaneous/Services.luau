--!native
--!optimize 2
---@diagnostic disable: undefined-global

--[[
	A wrapper for services so that you don't pollute your script with 'local X = game:GetService("ServiceName")'.

	Features:
	1. Auto-complete: Exported type ensures Studio knows what services exist, providing IntelliSense.
	2. Lazy loading: Services are only fetched (game:GetService) the first time you use them.

	Usage:
	------------------------------------------------------------
	-- Setup
	local Services = require(path.to.Services)
	-- or: local Services = loadstring(game:HttpGet("..."))()

	-- Accessing a service (fetch + cache)
	Services.RunService.Heartbeat:Connect(function() end)

	-- Preload everything in the game hierarchy
	Services()

	-- Iterating all loaded services (debug/dumping)
	for name, service in Services do 
		print(name, service) 
	end
	------------------------------------------------------------
]]

export type Services = {
	-- [Standard]
	Workspace: Workspace,
	Players: Players,
	Lighting: Lighting,
	MaterialService: MaterialService,
	NetworkClient: NetworkClient,
	ReplicatedFirst: ReplicatedFirst,
	ReplicatedStorage: ReplicatedStorage,
	ServerScriptService: ServerScriptService,
	ServerStorage: ServerStorage,
	StarterGui: StarterGui,
	StarterPack: StarterPack,
	StarterPlayer: StarterPlayer,
	Teams: Teams,
	SoundService: SoundService,
	TextChatService: TextChatService,
	VoiceChatService: VoiceChatService,
	LocalizationService: LocalizationService,
	TestService: TestService,
	VRService: VRService,

	-- [Scripting & Simulation]
	RunService: RunService,
	UserInputService: UserInputService,
	HttpService: HttpService,
	TweenService: TweenService,
	DataStoreService: DataStoreService,
	MessagingService: MessagingService,
	MarketplaceService: MarketplaceService,
	TeleportService: TeleportService,
	BadgeService: BadgeService,
	CollectionService: CollectionService,
	ContextActionService: ContextActionService,
	GuiService: GuiService,
	MemoryStoreService: MemoryStoreService,
	ProximityPromptService: ProximityPromptService,
	PhysicsService: PhysicsService,
	PathfindingService: PathfindingService,
	Debris: Debris,
	ContentProvider: ContentProvider,
	InsertService: InsertService,
	AssetService: AssetService,
	UGCValidationService: UGCValidationService,
	GamepadService: GamepadService,
	SerializationService: SerializationService,
	SharedTableRegistry: SharedTableRegistry,

	-- [User, Social & Policies]
	UserService: UserService,
	GroupService: GroupService,
	SocialService: SocialService,
	AvatarEditorService: AvatarEditorService,
	ExperienceNotificationService: ExperienceNotificationService,
	PolicyService: PolicyService,
	AdService: AdService,
	NotificationService: NotificationService,

	-- [Engine & Debugging]
	LogService: LogService,
	Stats: Stats,
	AnalyticsService: AnalyticsService,
	ScriptContext: ScriptContext,
	ScriptProfilerService: ScriptProfilerService,
	HapticService: HapticService,
	VideoCaptureService: VideoCaptureService,
	VideoService: VideoService,
	VRStatusService: VRStatusService,
	UserGameSettings: UserGameSettings,
	LanguageService: LanguageService,
	TextService: TextService,
	ReflectionService: ReflectionService,

	-- [Animation]
	KeyframeSequenceProvider: KeyframeSequenceProvider,
	AnimationClipProvider: AnimationClipProvider,

	-- [Studio & Plugin API]
	Selection: Selection,
	ChangeHistoryService: ChangeHistoryService,
	ScriptEditorService: ScriptEditorService,
	StudioService: StudioService,
	StudioTestService: StudioTestService,
	PublishService: PublishService,

	-- [Internal]
	CoreGui: CoreGui,
	RobloxReplicatedStorage: RobloxReplicatedStorage,
	NetworkServer: NetworkServer,
	VirtualInputManager: VirtualInputManager,
	VirtualUser: VirtualUser,
	CorePackages: CorePackages,
	MemStorageService: MemStorageService,
	PermissionsService: PermissionsService,
	
	-- [Legacy]
	Chat: Chat,
	GamePassService: GamePassService
}

--[[
	getgenv is a function that returns the global environment in executors, but doesn't exist in Studio.

	We polyfill it here to ensure this module behaves as a singleton across `loadstring` (common in exploits),
	mirroring the caching behavior of `require()` in Studio.
]]
local getgenv = getgenv or (function() 
	local proxy = setmetatable({}, {
		__newindex = function(_, key, value)
			_G[key], shared[key] = value, value
		end,
		__index = function(_, key)
			return _G[key]
		end
	})

	return function() return proxy end
end)()

--[[
	cloneref is a function used in exploits to create a "clone" of an instance reference.

	This cloned reference is distinct from the original in the VM's eyes, allowing scripts to
	hold references to sensitive services (like CoreGui) without being detected by LocalScripts
	that might do weak table reference checks.
]]
local cloneref = cloneref or function(instance) return instance end

local ServicesProxy = getgenv().Services

if not ServicesProxy then
	ServicesProxy = setmetatable({}, {
		-- __index fires when you try to access a service missing from the table;
		-- since it's missing, the function is called with the goal of adding it into the table.
		__index = function(self, key)
			local success, result = pcall(function()			
				return key == "VirtualInputManager" and Instance.new(key) or cloneref(game:GetService(key))
			end)

			if success and result then
				self[key] = result

				return result
			end
			
			return nil
		end,

		-- Allow generalized iteration (if missing, the VM decides to use __call as an iterator function)
		__iter = function(self)
			return next, self
		end,

		-- Make the table callable, with the function looping through the game hierarchy
		-- and populating the table with everything currently existing.
		__call = function(self)
			for _, Child in game:GetChildren() do
				local _ = self[Child.ClassName] -- Accessing the key triggers __index to cache it, so long it's a valid service
			end

			return self
		end
	}) :: Services

	getgenv().Services = ServicesProxy
end

return ServicesProxy
