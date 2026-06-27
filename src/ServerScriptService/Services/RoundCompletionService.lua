--!strict
-- RoundCompletionService — Server-only singleton (Sprint 31)
-- Coordinates local round-completion state per player.
-- Does NOT own scoring, persistence, matchmaking, or rewards.
--
-- Two-step lifecycle per player:
--   NotifyHoleCompleted → state="PendingFinalize"
--   FinalizeRound       → state="Completed", completedRounds++
--
-- Counter semantics:
--   completedRounds — FinalizeRound calls that succeeded (state was PendingFinalize)
--   rejectedCount   — NotifyHoleCompleted duplicates + FinalizeRound on invalid state
--
-- Public API
--   NotifyHoleCompleted(player)      → CompletionResult
--   FinalizeRound(player)            → CompletionResult
--   GetRoundCompletionState(player)  → RoundState  (copy)
--   ResetPlayer(player)
--   GetCompletedRounds()  → number
--   GetRejectedCount()    → number
--   ResetCounts()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

-- ── Types ─────────────────────────────────────────────────────────────────────

type RoundEntry = {
	state:     string,
	completed: boolean,
}

type RoundState = {
	state:     string,
	completed: boolean,
}

type CompletionResult = {
	success: boolean,
	status:  string,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:     boolean                    = false
local _rounds:          { [number]: RoundEntry? }  = {}
local _completedRounds: number                     = 0
local _rejectedCount:   number                     = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local RoundCompletionService = {}
RoundCompletionService.__index = RoundCompletionService

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _getEntry(player: Player): RoundEntry?
	return _rounds[player.UserId]
end

local function _getOrCreate(player: Player): RoundEntry
	local entry = _rounds[player.UserId]
	if not entry then
		entry = { state = "Idle", completed = false }
		_rounds[player.UserId] = entry
	end
	return entry
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Marks the player's round as pending finalization.
-- Returns AlreadyCompleted if the round is already in PendingFinalize or Completed state.
function RoundCompletionService:NotifyHoleCompleted(player: Player): CompletionResult
	if not _initialized then
		return { success = false, status = "NotInitialized" }
	end
	local entry = _getEntry(player)
	if entry and (entry.state == "PendingFinalize" or entry.state == "Completed") then
		_rejectedCount += 1
		Logger:Warn("RoundCompletionService",
			("NotifyHoleCompleted: %s already in %q — rejecting"):format(
				player.Name, entry.state))
		return { success = false, status = "AlreadyCompleted" }
	end
	local e = _getOrCreate(player)
	e.state = "PendingFinalize"
	Logger:Info("RoundCompletionService",
		("round PendingFinalize for %s"):format(player.Name))
	return { success = true, status = "PendingFinalize" }
end

-- Finalizes the round for the player.
-- Only valid when state is "PendingFinalize"; any other state returns InvalidState.
function RoundCompletionService:FinalizeRound(player: Player): CompletionResult
	if not _initialized then
		return { success = false, status = "NotInitialized" }
	end
	local entry = _getEntry(player)
	if not entry or entry.state ~= "PendingFinalize" then
		_rejectedCount += 1
		local cur = entry and entry.state or "Idle"
		Logger:Warn("RoundCompletionService",
			("FinalizeRound: %s not in PendingFinalize (got %q) — rejecting"):format(
				player.Name, cur))
		return { success = false, status = "InvalidState" }
	end
	entry.state     = "Completed"
	entry.completed = true
	_completedRounds += 1
	Logger:Info("RoundCompletionService",
		("round completed for %s (completedRounds=%d)"):format(player.Name, _completedRounds))
	return { success = true, status = "RoundCompleted" }
end

-- Returns an independent copy of the player's round-completion state.
-- Returns { state="Idle", completed=false } before any NotifyHoleCompleted.
function RoundCompletionService:GetRoundCompletionState(player: Player): RoundState
	local entry = _getEntry(player)
	if not entry then
		return { state = "Idle", completed = false }
	end
	return { state = entry.state, completed = entry.completed }
end

-- Clears the player's local round-completion state.
function RoundCompletionService:ResetPlayer(player: Player)
	_rounds[player.UserId] = nil
end

function RoundCompletionService:GetCompletedRounds(): number
	return _completedRounds
end

function RoundCompletionService:GetRejectedCount(): number
	return _rejectedCount
end

function RoundCompletionService:ResetCounts()
	_completedRounds = 0
	_rejectedCount   = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RoundCompletionService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[RoundCompletionService] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_rounds)
	RoundCompletionService:ResetCounts()

	Logger:Info("RoundCompletionService", "ready")
end

function RoundCompletionService:Update(_dt: number) end

function RoundCompletionService:Destroy()
	table.clear(_rounds)
	RoundCompletionService:ResetCounts()
	_initialized = false
end

return RoundCompletionService
