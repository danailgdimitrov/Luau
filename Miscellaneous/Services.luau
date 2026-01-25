--!native
--!optimize 2
---@diagnostic disable: undefined-global

--[[
	Usage:
	------------------------------------------------------------
	local Services = require(path.to.Services)

	print(Services.RunService) -- RunService (also has auto-complete!)
	------------------------------------------------------------
]]

-- The things I do for auto-complete...
export type Services = {
	-- Visible in the studio explorer
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
	-- Requiring a script permission of at least the level of a plugin
	Selection: Selection,
	ChangeHistoryService: ChangeHistoryService,
	ScriptEditorService: ScriptEditorService,
	VirtualInputManager: VirtualInputManager,
	VirtualUser: VirtualUser,
	-- Studio-only
	StudioService: StudioService, -- Requiring a script permission of at least the level of a plugin
	StudioTestService: StudioTestService,
	-- Others
	RunService: RunService,
	UserInputService: UserInputService,
	HttpService: HttpService,
	TweenService: TweenService,
	DataStoreService: DataStoreService,
	MessagingService: MessagingService,
	MarketplaceService: MarketplaceService,
	TeleportService: TeleportService,
	BadgeService: BadgeService,
	Chat: Chat,
	CollectionService: CollectionService,
	ContextActionService: ContextActionService,
	GuiService: GuiService,
	MemoryStoreService: MemoryStoreService,
	ProximityPromptService: ProximityPromptService,
	PhysicsService: PhysicsService,
	AnalyticsService: AnalyticsService,
	SocialService: SocialService,
	GroupService: GroupService,
	InsertService: InsertService,
	AssetService: AssetService,
	UGCValidationService: UGCValidationService,
	PolicyService: PolicyService,
	ScriptContext: ScriptContext,
	Stats: Stats,
	HapticService: HapticService,
	KeyframeSequenceProvider: KeyframeSequenceProvider,
	AnimationClipProvider: AnimationClipProvider,
	AvatarEditorService: AvatarEditorService,
	SerializationService: SerializationService,
	SharedTableRegistry: SharedTableRegistry,
	PathfindingService: PathfindingService,
	Debris: Debris,
	ContentProvider: ContentProvider,
	UserService: UserService,
	ExperienceNotificationService: ExperienceNotificationService,
	VideoCaptureService: VideoCaptureService,
	CoreGui: CoreGui,
	RobloxReplicatedStorage: RobloxReplicatedStorage,
	LogService: LogService,
	ScriptProfilerService: ScriptProfilerService,
	PublishService: PublishService,
	NetworkServer: NetworkServer,
	AdService: AdService,
	GamePassService: GamePassService,
	GamepadService: GamepadService
}

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

getgenv().Services = setmetatable({}, {
	__index = function(self, key)
		local success, result = pcall(function()			
			return key == "VirtualInputManager" and Instance.new(key) or game:GetService(key)
		end)

		self[key] = success and result or nil -- If it fails, success will be false instead of nil, so I have to explicitly set it.

		return rawget(self, key)
	end,
	__call = function(self, ...)
		-- for k, v in self do...
		-- In ^ case, 'self' is being treated like an iterator function, which is not what I intended. (why doesn't it default to __iter?)
		if select("#", ...) == 2 then -- If I were to make it a table and rawlen, it will not treat it as 2 arguments.
			return next(self, ({...})[2])
		end

		for _, Child in game:GetChildren() do
			Child = self[Child.ClassName] -- Trigger the metamethod for an attempt to append the service to the table.
		end

		return self
	end
}) :: Services

return getgenv().Services