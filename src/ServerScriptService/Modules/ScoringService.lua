--!strict
-- ScoringService — Server-only ModuleScript
-- Tracks per-player hole and round scores in-memory, classifies score tiers,
-- queues per-hole and round-completion rewards through PlayerDataService, and
-- returns a RoundSummary on FinalizeRound.
-- TDD §4.3. No dependency on EconomyService — reward amounts come from ScoringRules.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types             = require(ReplicatedStorage.Shared.Modules.Types)
local ScoringRules      = require(ReplicatedStorage.Shared.Modules.ScoringRules)
local Constants         = require(ReplicatedStorage.Shared.Modules.Constants)
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ScoringRules tables use specific string literal keys; cast to generic string
-- dictionaries once here so strict-mode indexing by a variable works cleanly.
local TIER_XP:            { [string]: number } = ScoringRules.TIER_XP            :: any
local TIER_COINS:         { [string]: number } = ScoringRules.TIER_COINS         :: any
local PENALTY_STROKES:    { [string]: number } = ScoringRules.PENALTY_STROKES    :: any
local MAX_STROKES_PER_HOLE: number             = ScoringRules.MAX_STROKES_PER_HOLE :: any

-- ── Types ──────────────────────────────────────────────────────────────────

type HoleScore    = Types.HoleScore
type RoundSummary = Types.RoundSummary

-- Return type of CommitStroke — named locally to keep the signature clean.
type StrokeResult = {
	strokeDelta: number,
	penalty:     number,
}

-- Mutable state for a single hole in progress.
type HoleSession = {
	holeNumber: number,
	par:        number,
	strokes:    number,  -- swing count + accumulated penalty strokes
	penalty:    number,  -- penalty strokes only (for StrokeResult)
}

-- Mutable state for a player's active round.
type PlayerSession = {
	courseId:       string,
	completedHoles: { HoleScore },
	active:         HoleSession?,
}

-- ── Module state ───────────────────────────────────────────────────────────

-- Nullable value type so _sessions[userId] = nil is valid in strict mode.
local _sessions: { [number]: PlayerSession? } = {}

-- ── Module ─────────────────────────────────────────────────────────────────

local ScoringService = {}
ScoringService.__index = ScoringService

-- ── Pure helpers ───────────────────────────────────────────────────────────

-- Delegates to ScoringRules.ClassifyScore. Exposed so GameService and tests
-- can classify scores without requiring ScoringRules separately.
function ScoringService:ClassifyScore(strokes: number, par: number): string
	return ScoringRules.ClassifyScore(strokes, par)
end

-- Returns a round-completion XP bonus in [XP_ROUND_MIN, XP_ROUND_MAX], scaled
-- by average tier quality across all completed holes. Separate from the per-hole
-- XP already granted by HoleComplete. scoreCard is an ordered array of ScoreTier
-- strings (one per completed hole).
function ScoringService:ComputeRoundXP(scoreCard: { string }): number
	if #scoreCard == 0 then
		return Constants.XP_ROUND_MIN
	end
	local total = 0
	for _, tier in ipairs(scoreCard) do
		total += TIER_XP[tier] or Constants.XP_ROUND_MIN
	end
	local avg = total / #scoreCard
	return math.clamp(math.floor(avg), Constants.XP_ROUND_MIN, Constants.XP_ROUND_MAX)
end

-- Returns a round-completion coin bonus scaled by average tier quality.
-- Separate from the per-hole coins already granted by HoleComplete.
function ScoringService:ComputeRoundCoins(scoreCard: { string }): number
	if #scoreCard == 0 then
		return 0
	end
	local total = 0
	for _, tier in ipairs(scoreCard) do
		total += TIER_COINS[tier] or 0
	end
	return math.floor(total / #scoreCard)
end

-- ── Session management ─────────────────────────────────────────────────────

-- Initialises a fresh round session. Called by GameService on LOADING state
-- entry. Overwrites any leftover state from a prior disconnected session.
function ScoringService:StartRound(player: Player, courseId: string)
	if _sessions[player.UserId] then
		warn("[ScoringService] StartRound: overwriting existing session for " .. player.Name)
	end
	_sessions[player.UserId] = {
		courseId       = courseId,
		completedHoles = {},
		active         = nil,
	}
end

-- Initialises hole tracking. Called by GameService when transitioning to
-- PRE_SHOT. par is read from CourseService hole metadata.
function ScoringService:StartHole(player: Player, holeNumber: number, par: number)
	local session = _sessions[player.UserId]
	assert(session, "[ScoringService] StartHole: no active session for " .. player.Name)
	if session.active then
		warn("[ScoringService] StartHole: hole " .. tostring(session.active.holeNumber)
			.. " was still active when hole " .. tostring(holeNumber) .. " was started")
	end
	session.active = {
		holeNumber = holeNumber,
		par        = par,
		strokes    = 0,
		penalty    = 0,
	}
end

-- ── TDD §4.3 — CommitStroke ────────────────────────────────────────────────

-- Called by GameService/PhysicsService after each BallResolved event. Counts
-- the swing as one stroke, adds any hazard penalty strokes, fires a
-- StrokeCommitted envelope on GameBus, and returns the current stroke delta
-- and penalty count.
-- surface must be a value from Enums.SurfaceType (FAIRWAY, GREEN, SAND,
-- WATER, OOB, ROUGH). SAND carries 0 penalty (lie penalty only — TDD §4.3).
function ScoringService:CommitStroke(player: Player, surface: string): StrokeResult
	local session = _sessions[player.UserId]
	assert(session, "[ScoringService] CommitStroke: no active session for " .. player.Name)
	local hole = session.active
	assert(hole, "[ScoringService] CommitStroke: no active hole for " .. player.Name)

	hole.strokes += 1

	local penaltyStrokes: number = PENALTY_STROKES[surface] or 0
	hole.strokes += penaltyStrokes
	hole.penalty += penaltyStrokes

	local strokeDelta: number = hole.strokes - hole.par

	-- Preview the current tier and associated rewards so the client HUD can
	-- show the "scoring indicator" before the hole is finished.
	local scoreTier  = ScoringRules.ClassifyScore(hole.strokes, hole.par)
	local xpPreview:   number = TIER_XP[scoreTier]    or 0
	local coinPreview: number = TIER_COINS[scoreTier]  or 0

	GameBus:FireAllClients({
		eventType = "StrokeCommitted",
		payload   = {
			strokes   = hole.strokes,
			par       = hole.par,
			scoreTier = scoreTier,
			coinDelta = coinPreview,
			xpDelta   = xpPreview,
		} :: any,
		timestamp = os.time(),
	})

	return { strokeDelta = strokeDelta, penalty = penaltyStrokes }
end

-- ── HoleComplete ───────────────────────────────────────────────────────────

-- Finalises the active hole when GameService detects BallState → HOLED.
-- Caps strokes at MAX_STROKES_PER_HOLE, classifies the tier, queues per-hole
-- coin + XP rewards through PlayerDataService (crash-safe pendingRewards),
-- appends the result to completedHoles, and returns the HoleScore for the
-- GameBus HoleComplete event fired by GameService.
function ScoringService:HoleComplete(player: Player): HoleScore
	local session = _sessions[player.UserId]
	assert(session, "[ScoringService] HoleComplete: no active session for " .. player.Name)
	local hole = session.active
	assert(hole, "[ScoringService] HoleComplete: no active hole for " .. player.Name)

	local finalStrokes = math.min(hole.strokes, MAX_STROKES_PER_HOLE)
	local scoreTier    = ScoringRules.ClassifyScore(finalStrokes, hole.par)
	local coins: number = TIER_COINS[scoreTier] or 0
	local xp: number    = TIER_XP[scoreTier]    or 0

	-- Queue rewards before clearing session state — if an error occurs below
	-- the rewards are still persisted on the next reward drain.
	PlayerDataService:QueueReward(player, { type = "coins", amount = coins })
	PlayerDataService:QueueReward(player, { type = "xp",    amount = xp    })

	local holeScore: HoleScore = {
		holeNumber = hole.holeNumber,
		par        = hole.par,
		strokes    = finalStrokes,
		scoreTier  = scoreTier,
		coins      = coins,
		xp         = xp,
	}

	table.insert(session.completedHoles, holeScore)
	session.active = nil

	return holeScore
end

-- ── TDD §4.3 — FinalizeRound ───────────────────────────────────────────────

-- Called by GameService when transitioning to ROUND_END.
-- 1. Force-completes any hole that was not HoleComplete'd (edge case: crash
--    recovery / max-strokes timeout).
-- 2. Computes a round-completion bonus via ComputeRoundXP / ComputeRoundCoins.
-- 3. Queues the bonus rewards and drains ALL pending rewards atomically.
-- 4. Flushes immediately to DataStore (round-end always warrants a flush).
-- 5. Returns a RoundSummary for the UI layer (RoundSummary screen).
-- totalCoins / totalXP include both per-hole and round-bonus amounts.
function ScoringService:FinalizeRound(player: Player): RoundSummary
	local session = _sessions[player.UserId]
	assert(session, "[ScoringService] FinalizeRound: no active session for " .. player.Name)

	-- Guard: force-complete an open hole so completedHoles is always full.
	if session.active then
		warn("[ScoringService] FinalizeRound: hole "
			.. tostring(session.active.holeNumber)
			.. " was not completed — forcing HoleComplete")
		self:HoleComplete(player)
	end

	local scoreCard: { string } = {}
	local totalStrokes = 0
	local totalPar     = 0
	local totalCoins   = 0
	local totalXP      = 0

	for _, holeScore in ipairs(session.completedHoles) do
		table.insert(scoreCard, holeScore.scoreTier)
		totalStrokes += holeScore.strokes
		totalPar     += holeScore.par
		totalCoins   += holeScore.coins
		totalXP      += holeScore.xp
	end

	local bonusCoins = self:ComputeRoundCoins(scoreCard)
	local bonusXP    = self:ComputeRoundXP(scoreCard)

	PlayerDataService:QueueReward(player, { type = "coins", amount = bonusCoins })
	PlayerDataService:QueueReward(player, { type = "xp",    amount = bonusXP    })

	-- Drain applies per-hole + round-bonus rewards atomically in one pass.
	PlayerDataService:DrainRewards(player)

	-- Immediate flush — round end warrants durable persistence.
	PlayerDataService:FlushNow(player)

	local summary: RoundSummary = {
		courseId     = session.courseId,
		holes        = session.completedHoles,
		totalStrokes = totalStrokes,
		totalPar     = totalPar,
		totalCoins   = totalCoins + bonusCoins,
		totalXP      = totalXP + bonusXP,
	}

	_sessions[player.UserId] = nil

	return summary
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function ScoringService:Init(_dependencies: { [string]: any })
	-- Clean up sessions if a player disconnects mid-round.
	Players.PlayerRemoving:Connect(function(player: Player)
		_sessions[player.UserId] = nil
	end)
end

function ScoringService:Update(_dt: number) end

function ScoringService:Destroy()
	table.clear(_sessions)
end

return ScoringService
