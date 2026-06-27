--!strict
-- RoundPipelineService — Server-only singleton (Sprint 27)
-- Coordinates GameService + ActionExecutionService for a single-hole round loop.
-- Exposes safe helper methods for starting rounds and queuing gameplay actions;
-- does NOT replace GameService, EventBusHandler, PhysicsService, or ScoringService.
-- Does NOT own state-machine logic — all state lives in GameService.
--
-- AES:Execute is called directly (bypassing RPS+RDS) because the caller is
-- server-side and there is no remote round-trip to acknowledge.
--
-- Counter semantics:
--   startedCount     — BeginRoundForPlayer calls that returned success=true
--   holeReadyCount   — QueueHoleReady calls that returned success=true
--   swingIntentCount — QueueSwingIntent calls that returned success=true
--   rejectedCount    — QueueHoleReady/QueueSwingIntent calls that returned success=false
--
-- Public API
--   BeginRoundForPlayer(player) → { success: boolean, status: string }
--   QueueHoleReady(player)      → ExecutionResult
--   QueueSwingIntent(player, payload) → ExecutionResult
--   GetPlayerPipelineState(player) → PipelineState
--   ResetPlayer(player)         → boolean
--   GetStartedCount()           → number
--   GetHoleReadyCount()         → number
--   GetSwingIntentCount()       → number
--   GetRejectedCount()          → number
--   ResetCounts()

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger      = require(ReplicatedStorage.Shared.Logger)
local GameService = require(ServerScriptService.Modules.GameService)
local AES         = require(ServerScriptService.Services.ActionExecutionService)

-- ── Types ─────────────────────────────────────────────────────────────────────

type RoundResult = {
	success: boolean,
	status:  string,
}

type ExecutionResult = {
	success: boolean,
	status:  string,
	payload: any,
}

type PipelineState = {
	gameState:      string,
	currentHoleId:  string?,
	hasTeePosition: boolean,
	hasPinPosition: boolean,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean = false
local _startedCount:     number  = 0
local _holeReadyCount:   number  = 0
local _swingIntentCount: number  = 0
local _rejectedCount:    number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local RoundPipelineService = {}
RoundPipelineService.__index = RoundPipelineService

-- ── Public API ────────────────────────────────────────────────────────────────

-- Calls GameService:StartRound safely. Returns { success, status }.
-- Increments startedCount only when successful.
function RoundPipelineService:BeginRoundForPlayer(player: Player): RoundResult
	if not _initialized then
		return { success = false, status = "NotInitialized" }
	end
	local ok, errMsg = pcall(function()
		GameService:StartRound(player)
	end)
	if not ok then
		local msg    = tostring(errMsg)
		local status = if msg:find("already has an active session")
			then "AlreadyStarted"
			else "StartError"
		Logger:Warn("RoundPipelineService",
			("BeginRoundForPlayer failed for %s: %s"):format(player.Name, msg))
		return { success = false, status = status }
	end
	_startedCount += 1
	Logger:Info("RoundPipelineService",
		("round started for %s"):format(player.Name))
	return { success = true, status = "Started" }
end

-- Executes the HoleReady action through AES.
-- Increments holeReadyCount on success, rejectedCount on failure.
function RoundPipelineService:QueueHoleReady(player: Player): ExecutionResult
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local result = AES:Execute(player, { eventType = "HoleReady", payload = {} })
	if result.success then
		_holeReadyCount += 1
	else
		_rejectedCount += 1
	end
	return result
end

-- Executes the SwingIntent action through AES with the given payload.
-- Increments swingIntentCount on success, rejectedCount on failure.
function RoundPipelineService:QueueSwingIntent(
	player:  Player,
	payload: any
): ExecutionResult
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local result = AES:Execute(player, { eventType = "SwingIntent", payload = payload })
	if result.success then
		_swingIntentCount += 1
	else
		_rejectedCount += 1
	end
	return result
end

-- Returns a snapshot of the player's pipeline state from GameService.
-- Returns an independent table copy (safe to read; does not mutate session).
function RoundPipelineService:GetPlayerPipelineState(player: Player): PipelineState
	return {
		gameState      = GameService:GetState(player),
		currentHoleId  = GameService:GetCurrentHoleId(player),
		hasTeePosition = GameService:GetTeePosition(player) ~= nil,
		hasPinPosition = GameService:GetPinPosition(player) ~= nil,
	}
end

-- Aborts the player's round via GameService:AbortRound.
-- Returns true on success, false if AbortRound errored.
function RoundPipelineService:ResetPlayer(player: Player): boolean
	if not _initialized then return false end
	local ok = pcall(function()
		GameService:AbortRound(player)
	end)
	return ok
end

function RoundPipelineService:GetStartedCount(): number
	return _startedCount
end

function RoundPipelineService:GetHoleReadyCount(): number
	return _holeReadyCount
end

function RoundPipelineService:GetSwingIntentCount(): number
	return _swingIntentCount
end

function RoundPipelineService:GetRejectedCount(): number
	return _rejectedCount
end

function RoundPipelineService:ResetCounts()
	_startedCount     = 0
	_holeReadyCount   = 0
	_swingIntentCount = 0
	_rejectedCount    = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RoundPipelineService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[RoundPipelineService] Init called twice — skipping")
		return
	end
	_initialized = true
	RoundPipelineService:ResetCounts()

	Logger:Info("RoundPipelineService", "ready")
end

function RoundPipelineService:Update(_dt: number) end

function RoundPipelineService:Destroy()
	RoundPipelineService:ResetCounts()
	_initialized = false
end

return RoundPipelineService
