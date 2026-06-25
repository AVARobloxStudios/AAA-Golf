--!strict
-- PlayerDataService — Server-only ModuleScript
-- Sole owner of ProfileService reads/writes. No other service touches ProfileService directly.
-- TDD §4.4, §11, §12.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local DataStoreBridge = require(script.Parent.DataStoreBridge)

local ProfileService = require(ServerScriptService.Packages.ProfileService)
local ReplicaService = require(ReplicatedStorage.Packages.ReplicaService)

-- XP required per level (flat rate — no formula in TDD v1.0; tunable here).
local XP_PER_LEVEL = 500

-- ── ProfileTemplate — TDD §11.2 Complete Schema ────────────────────────────

local ProfileTemplate = {
	-- IDENTITY
	userId          = 0,
	username        = "",
	displayName     = "",
	joinDate        = 0,          -- os.time() on first join
	lastSeen        = 0,          -- os.time() on each session start
	schemaVersion   = 1,          -- increment on breaking schema changes only
	totalSessions   = 0,
	isBanned        = false,
	trustScore      = Constants.TRUST_SCORE_DEFAULT,
	isPremiumMember = false,

	-- PROGRESSION
	xp       = 0,   -- lifetime total; NEVER subtract
	level    = 1,   -- recomputed from xp on every load
	prestige = 0,   -- post-level-100; always 0 in VS
	activeBoosters = {},

	-- ECONOMY — integers ONLY; floats are a bug
	coins         = 0,
	gems          = 0,   -- VS: schema-ready, always 0 at launch
	lifetimeCoins = 0,   -- append-only analytics counter
	lifetimeGems  = 0,
	pendingRewards = {},  -- crash-safe grant queue: {type, amount} entries
	purchaseIds    = {},  -- DevProduct receipt dedup set

	-- UNLOCK
	unlockedCourses  = { "course_1" },  -- default unlock per TDD §11.2
	completedCourses = {},

	-- INVENTORY — items never deleted; set retired=true instead (TDD §11.3)
	clubs        = {},
	clubLoadouts = {},
	cosmetics = {
		ballSkins    = {},
		trailEffects = {},
		emotes       = {},
		avatarItems  = {},
		titles       = {},
	},
	equippedCosmetics = {
		ballSkin    = "default",
		trailEffect = "classic_white",
		emote       = nil,
		title       = nil,
	},

	-- STATISTICS — server-only writes; zero client paths to increment (TDD §11.3)
	totalRounds          = 0,
	totalHolesPlayed     = 0,
	totalStrokes         = 0,
	totalPlaytimeSeconds = 0,
	holesInOne           = 0,
	condors              = 0,
	albatrosses          = 0,
	eagles               = 0,
	birdies              = 0,
	pars                 = 0,
	bogeys               = 0,
	doubleBogeys         = 0,
	worseThanDouble      = 0,
	bestRound            = nil,   -- { score, courseId, date } or nil
	longestDrive         = 0,
	longestPutt          = 0,
	totalWins            = 0,
	totalTop3            = 0,
	totalTournamentWins  = 0,
	currentWinStreak     = 0,
	bestWinStreak        = 0,

	-- DAILY REWARDS
	dailyStreak         = 0,
	lastDailyRewardDate = "",  -- "YYYY-MM-DD"
	lastDailyRewardTime = 0,

	-- ACHIEVEMENTS — schema-ready, no grants in VS
	achievements = {},

	-- BATTLE PASS — schema-ready
	battlePass = {
		season = 0, tier = 0, xp = 0, isPremium = false,
		premiumPurchasedAt  = nil,
		claimedRewards      = {},
		claimedPremiumRewards = {},
	},
	battlePassHistory = {},

	-- TOURNAMENTS — schema-ready
	tournamentEntries = {},
}

-- ── ProfileStore ───────────────────────────────────────────────────────────

local ProfileStore = ProfileService.GetProfileStore("PlayerData", ProfileTemplate)
local PlayerClassToken = ReplicaService.NewClassToken("PlayerProfile")

-- ── Internal State ──────────────────────────────────────────────────────────

local profiles: { [number]: any } = {}  -- userId → Profile
local replicas: { [number]: any } = {}  -- userId → Replica

-- ── Private Helpers ────────────────────────────────────────────────────────

local function assertInteger(amount: number, method: string)
	if type(amount) ~= "number" or math.floor(amount) ~= amount then
		error(
			("[PlayerDataService] %s: amount must be an integer, got %s"):format(method, tostring(amount)),
			2
		)
	end
end

local function computeLevel(xp: number): number
	return math.floor(xp / XP_PER_LEVEL) + 1
end

-- ── Module ─────────────────────────────────────────────────────────────────

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

function PlayerDataService:_onPlayerAdded(player: Player)
	local sessionRetries = 0

	-- ProfileService LoadProfileAsync handles session locking internally.
	-- notReleasedHandler: defer SESSION_LOCK_DEFER_SECONDS, retry SESSION_LOCK_MAX_RETRIES times.
	local profile = ProfileStore:LoadProfileAsync(
		"Player_" .. tostring(player.UserId),
		function()
			sessionRetries += 1
			if sessionRetries > Constants.SESSION_LOCK_MAX_RETRIES then
				return "Cancel"
			end
			task.wait(Constants.SESSION_LOCK_DEFER_SECONDS)
		end
	)

	-- Guard: player may have left while profile was loading asynchronously.
	if not player.Parent then
		if profile then
			profile:Release()
		end
		return
	end

	if not profile then
		player:Kick("Data load failed — another session may be active. Rejoin in 30 seconds.")
		return
	end

	-- Fill any new fields added since this profile was last saved (TDD §11.3).
	profile:Reconcile()

	-- Refresh identity fields that may have changed since last session.
	local data = profile.Data
	data.userId      = player.UserId
	data.username    = player.Name
	data.displayName = player.DisplayName
	data.lastSeen    = os.time()
	data.totalSessions += 1
	if data.joinDate == 0 then
		data.joinDate = os.time()
	end

	-- Level is always recomputed from XP on load — never trust the stored value.
	data.level = computeLevel(data.xp)

	profiles[player.UserId] = profile
	DataStoreBridge:Register(player.UserId, profile)

	-- Drain any rewards that were queued but not applied before the last crash.
	-- Must happen before replica creation so the replica reflects final values.
	self:DrainRewards(player)

	-- Push the minimal public profile subset to the owning client via ReplicaService.
	-- UIController listens for PlayerProfile replicas and drives the currency display.
	local replica = ReplicaService.NewReplica({
		ClassToken = PlayerClassToken,
		Tags       = { Player = player },
		Data       = {
			coins = data.coins,
			level = data.level,
			xp    = data.xp,
		},
		Replication = player,
	})
	replicas[player.UserId] = replica
end

function PlayerDataService:_onPlayerRemoving(player: Player)
	local profile = profiles[player.UserId]
	if profile then
		DataStoreBridge:FlushNow(player.UserId)
		profile:Release()
		profiles[player.UserId] = nil
	end
	DataStoreBridge:Unregister(player.UserId)

	local replica = replicas[player.UserId]
	if replica then
		replica:Destroy()
		replicas[player.UserId] = nil
	end
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function PlayerDataService:Init()
	DataStoreBridge:Init()  -- idempotent; safe if DataStoreBridge runner already called it

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			self:_onPlayerAdded(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_onPlayerRemoving(player)
	end)

	-- Handle players already present when this script loads (e.g. in Studio play-solo).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:_onPlayerAdded(player)
		end)
	end
end

function PlayerDataService:Update(_dt: number) end

function PlayerDataService:Destroy()
	for userId, profile in pairs(profiles) do
		if profile then
			profile:Release()
		end
		profiles[userId] = nil
	end
end

-- ── Public API — TDD §4.4 ──────────────────────────────────────────────────

-- Returns the live Profile object (contains .Data table).
-- Other services should prefer the specific getter methods below.
function PlayerDataService:GetProfile(player: Player): any?
	return profiles[player.UserId]
end

-- Returns current coin balance as an integer.
function PlayerDataService:GetCoins(player: Player): number
	local profile = profiles[player.UserId]
	assert(profile, "[PlayerDataService] GetCoins: no profile for " .. player.Name)
	return profile.Data.coins :: number
end

-- Adds `amount` coins. Rejects floats — currency integrity (TDD §4.4 / §11.3).
function PlayerDataService:AddCoins(player: Player, amount: number)
	assertInteger(amount, "AddCoins")
	local profile = profiles[player.UserId]
	assert(profile, "[PlayerDataService] AddCoins: no profile for " .. player.Name)
	profile.Data.coins += amount
	if amount > 0 then
		profile.Data.lifetimeCoins += amount
	end
	DataStoreBridge:QueueWrite(player.UserId)
	local replica = replicas[player.UserId]
	if replica then
		replica:SetValue({ "coins" }, profile.Data.coins)
	end
end

-- Adds `amount` XP. Rejects floats. Level is recomputed after every grant.
function PlayerDataService:AddXP(player: Player, amount: number)
	assertInteger(amount, "AddXP")
	local profile = profiles[player.UserId]
	assert(profile, "[PlayerDataService] AddXP: no profile for " .. player.Name)
	profile.Data.xp += amount
	local newLevel = computeLevel(profile.Data.xp)
	profile.Data.level = newLevel
	DataStoreBridge:QueueWrite(player.UserId)
	local replica = replicas[player.UserId]
	if replica then
		replica:SetValue({ "xp" },    profile.Data.xp)
		replica:SetValue({ "level" }, newLevel)
	end
end

-- Adds `amount` gems. Rejects floats. Gems are always 0 in VS but schema-ready.
function PlayerDataService:AddGems(player: Player, amount: number)
	assertInteger(amount, "AddGems")
	local profile = profiles[player.UserId]
	assert(profile, "[PlayerDataService] AddGems: no profile for " .. player.Name)
	profile.Data.gems += amount
	if amount > 0 then
		profile.Data.lifetimeGems += amount
	end
	DataStoreBridge:QueueWrite(player.UserId)
end

-- Adds courseId to unlockedCourses if not already present.
function PlayerDataService:UnlockCourse(player: Player, courseId: string)
	local profile = profiles[player.UserId]
	assert(profile, "[PlayerDataService] UnlockCourse: no profile for " .. player.Name)
	for _, id in ipairs(profile.Data.unlockedCourses) do
		if id == courseId then return end
	end
	table.insert(profile.Data.unlockedCourses, courseId)
	DataStoreBridge:QueueWrite(player.UserId)
end

-- Appends a reward to pendingRewards. Reward survives a server crash — drained on next login.
-- reward shape: { type: "coins" | "xp" | "gems", amount: number }
function PlayerDataService:QueueReward(player: Player, reward: { type: string, amount: number })
	local profile = profiles[player.UserId]
	assert(profile, "[PlayerDataService] QueueReward: no profile for " .. player.Name)
	table.insert(profile.Data.pendingRewards, reward)
	DataStoreBridge:QueueWrite(player.UserId)
end

-- Applies all queued rewards atomically and clears the queue.
-- Called on session start (after profile load) and on round end.
-- Returns the list of applied rewards so callers can display notifications.
function PlayerDataService:DrainRewards(player: Player): { { type: string, amount: number } }
	local profile = profiles[player.UserId]
	if not profile then return {} end

	local pending = profile.Data.pendingRewards
	profile.Data.pendingRewards = {}

	for _, reward in ipairs(pending) do
		local rtype = reward.type
		local amt   = reward.amount
		if rtype == "coins" then
			self:AddCoins(player, amt)
		elseif rtype == "xp" then
			self:AddXP(player, amt)
		elseif rtype == "gems" then
			self:AddGems(player, amt)
		else
			warn("[PlayerDataService] DrainRewards: unknown reward type: " .. tostring(rtype))
		end
	end

	DataStoreBridge:QueueWrite(player.UserId)
	return pending
end

-- Marks the profile dirty for the next heartbeat save (async, batched).
-- Use after stat writes or unlock events that are not time-critical.
function PlayerDataService:SaveProfile(player: Player)
	DataStoreBridge:QueueWrite(player.UserId)
end

-- Triggers an immediate ProfileService save (blocking DataStore call).
-- Use at round end and PlayerRemoving — never in hot paths.
function PlayerDataService:FlushNow(player: Player)
	DataStoreBridge:FlushNow(player.UserId)
end

return PlayerDataService
