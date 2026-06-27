--!strict
-- HoleCompletionService — Server-only singleton (Sprint 30)
-- Coordinator for hole-completion state tracking.
--
-- Stores per-player completion state locally; does NOT own physics, scoring,
-- or course advancement.  Reads GameService:GetState for observability (logging)
-- only — it does not call any private GameService internals or ScoringService.
--
-- ProcessLanding validates the landing envelope and delegates to CompleteHole
-- when inCup=true.  CompleteHole always succeeds locally (it stores "HoleComplete"
-- regardless of GameService state), so it is safe to call without an active session.
--
-- Counter semantics:
--   completedCount — CompleteHole calls that stored "HoleComplete" locally
--   rejectedCount  — ProcessLanding calls that failed validation only
--                    (NotInCup is NOT counted as a rejection)
--
-- Public API
--   ProcessLanding(player, landingData) → CompletionResult
--   CompleteHole(player)               → CompletionResult
--   GetHoleStatus(player)              → HoleStatus  (copy)
--   ResetPlayer(player)
--   GetCompletedCount()  → number
--   GetRejectedCount()   → number
--   ResetCounts()

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger      = require(ReplicatedStorage.Shared.Logger)
local GameService = require(ServerScriptService.Modules.GameService)

-- ── Types ─────────────────────────────────────────────────────────────────────

type HoleEntry = {
	status:    string,
	completed: boolean,
}

type HoleStatus = {
	status:    string,
	completed: boolean,
}

type CompletionResult = {
	success: boolean,
	status:  string,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean                    = false
local _holes:          { [number]: HoleEntry? }   = {}
local _completedCount: number                     = 0
local _rejectedCount:  number                     = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local HoleCompletionService = {}
HoleCompletionService.__index = HoleCompletionService

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _getOrCreate(player: Player): HoleEntry
	local entry = _holes[player.UserId]
	if not entry then
		entry = { status = "WaitingForFinish", completed = false }
		_holes[player.UserId] = entry
	end
	return entry
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Validates the landing envelope then routes to CompleteHole (inCup=true) or
-- returns NotInCup (inCup=false/nil).
--
-- Validation rules:
--   landingData must be a table.
--   landingData.position must be a Vector3.
--   landingData.inCup, when provided, must be a boolean.
-- All validation failures increment rejectedCount.  NotInCup is NOT a rejection.
function HoleCompletionService:ProcessLanding(
	player:      Player,
	landingData: any
): CompletionResult
	if not _initialized then
		return { success = false, status = "NotInitialized" }
	end
	if type(landingData) ~= "table" then
		_rejectedCount += 1
		Logger:Warn("HoleCompletionService",
			("ProcessLanding: landingData must be a table for %s"):format(player.Name))
		return { success = false, status = "InvalidData" }
	end
	if typeof(landingData.position) ~= "Vector3" then
		_rejectedCount += 1
		Logger:Warn("HoleCompletionService",
			("ProcessLanding: landingData.position must be Vector3 for %s"):format(player.Name))
		return { success = false, status = "InvalidPosition" }
	end
	if landingData.inCup ~= nil and type(landingData.inCup) ~= "boolean" then
		_rejectedCount += 1
		Logger:Warn("HoleCompletionService",
			("ProcessLanding: landingData.inCup must be boolean if provided for %s"):format(player.Name))
		return { success = false, status = "InvalidInCup" }
	end

	if landingData.inCup == true then
		local entry   = _getOrCreate(player)
		entry.status  = "CheckingCup"
		return HoleCompletionService:CompleteHole(player)
	else
		local entry   = _getOrCreate(player)
		entry.status  = "WaitingForFinish"
		Logger:Debug("HoleCompletionService",
			("ProcessLanding: ball not in cup for %s — WaitingForFinish"):format(player.Name))
		return { success = false, status = "NotInCup" }
	end
end

-- Stores "HoleComplete" locally and increments completedCount.
-- Always succeeds regardless of GameService state — safe to call without a session.
-- Reads GameService:GetState for observability only; does not call private internals.
function HoleCompletionService:CompleteHole(player: Player): CompletionResult
	if not _initialized then
		return { success = false, status = "NotInitialized" }
	end

	local ok, gameState = pcall(function() return GameService:GetState(player) end)
	if ok then
		Logger:Debug("HoleCompletionService",
			("CompleteHole for %s — GameService state=%q"):format(player.Name, tostring(gameState)))
	end

	local entry    = _getOrCreate(player)
	entry.status   = "HoleComplete"
	entry.completed = true
	_completedCount += 1

	Logger:Info("HoleCompletionService",
		("hole completed for %s (completedCount=%d)"):format(player.Name, _completedCount))
	return { success = true, status = "HoleComplete" }
end

-- Returns an independent copy of the player's current hole-completion state.
-- Returns default { status="WaitingForFinish", completed=false } before any ProcessLanding.
function HoleCompletionService:GetHoleStatus(player: Player): HoleStatus
	local entry = _holes[player.UserId]
	if not entry then
		return { status = "WaitingForFinish", completed = false }
	end
	return { status = entry.status, completed = entry.completed }
end

-- Clears the player's local hole-completion state.
function HoleCompletionService:ResetPlayer(player: Player)
	_holes[player.UserId] = nil
end

function HoleCompletionService:GetCompletedCount(): number
	return _completedCount
end

function HoleCompletionService:GetRejectedCount(): number
	return _rejectedCount
end

function HoleCompletionService:ResetCounts()
	_completedCount = 0
	_rejectedCount  = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function HoleCompletionService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[HoleCompletionService] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_holes)
	HoleCompletionService:ResetCounts()

	Logger:Info("HoleCompletionService", "ready")
end

function HoleCompletionService:Update(_dt: number) end

function HoleCompletionService:Destroy()
	table.clear(_holes)
	HoleCompletionService:ResetCounts()
	_initialized = false
end

return HoleCompletionService
