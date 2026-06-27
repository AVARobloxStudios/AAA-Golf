--!strict
-- VerticalSliceFlowService — Server-only singleton (Sprint 32)
-- Coordinator for the playable vertical slice flow.
-- Delegates every gameplay action to existing pipeline services;
-- does NOT own physics, scoring, persistence, or remotes.
--
-- Flow sequence per player:
--   StartVerticalSlice  → RoundStarted
--   MarkHoleReady       → HoleReady
--   SubmitSwing         → ShotInProgress
--   RecordBallLanding   → BallLanded
--   MarkHoleComplete    → HoleComplete
--   FinalizeVerticalSlice → RoundComplete
--
-- Counter semantics:
--   startedCount   — StartVerticalSlice calls that succeeded
--   completedCount — FinalizeVerticalSlice calls where both RCS steps succeeded
--   rejectedCount  — any delegation call that returned success=false
--
-- Public API
--   StartVerticalSlice(player)                → result
--   MarkHoleReady(player)                     → result
--   SubmitSwing(player, payload)              → result
--   RecordBallLanding(player, landingPosition)→ result
--   MarkHoleComplete(player)                  → result
--   FinalizeVerticalSlice(player)             → result
--   GetFlowState(player)                      → FlowState  (copy)
--   ResetPlayer(player)
--   GetStartedCount()   → number
--   GetCompletedCount() → number
--   GetRejectedCount()  → number
--   ResetCounts()

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Logger)
local RPS    = require(ServerScriptService.Services.RoundPipelineService)
local SLS    = require(ServerScriptService.Services.ShotLifecycleService)
local LPS    = require(ServerScriptService.Services.LandingPipelineService)
local HCS    = require(ServerScriptService.Services.HoleCompletionService)
local RCS    = require(ServerScriptService.Services.RoundCompletionService)

-- ── Types ─────────────────────────────────────────────────────────────────────

type FlowEntry = {
	state:     string,
	started:   boolean,
	completed: boolean,
}

type FlowState = {
	state:     string,
	started:   boolean,
	completed: boolean,
}

type Result = {
	success: boolean,
	status:  string,
	payload: any,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean                    = false
local _flows:          { [number]: FlowEntry? }   = {}
local _startedCount:   number                     = 0
local _completedCount: number                     = 0
local _rejectedCount:  number                     = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local VerticalSliceFlowService = {}
VerticalSliceFlowService.__index = VerticalSliceFlowService

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _getOrCreate(player: Player): FlowEntry
	local entry = _flows[player.UserId]
	if not entry then
		entry = { state = "LobbyReady", started = false, completed = false }
		_flows[player.UserId] = entry
	end
	return entry
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Starts a round via RoundPipelineService.  On success, state → "RoundStarted".
function VerticalSliceFlowService:StartVerticalSlice(player: Player): Result
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local result = RPS:BeginRoundForPlayer(player)
	if result.success then
		local entry   = _getOrCreate(player)
		entry.state   = "RoundStarted"
		entry.started = true
		_startedCount += 1
		Logger:Info("VerticalSliceFlowService",
			("vertical slice started for %s"):format(player.Name))
	else
		_rejectedCount += 1
		Logger:Warn("VerticalSliceFlowService",
			("StartVerticalSlice failed for %s — %q"):format(player.Name, result.status))
	end
	return { success = result.success, status = result.status, payload = nil }
end

-- Queues a HoleReady action via RoundPipelineService.  On success, state → "HoleReady".
function VerticalSliceFlowService:MarkHoleReady(player: Player): Result
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local result = RPS:QueueHoleReady(player)
	if result.success then
		local entry = _getOrCreate(player)
		entry.state = "HoleReady"
		Logger:Info("VerticalSliceFlowService",
			("hole ready for %s"):format(player.Name))
	else
		_rejectedCount += 1
		Logger:Warn("VerticalSliceFlowService",
			("MarkHoleReady failed for %s — %q"):format(player.Name, result.status))
	end
	return { success = result.success, status = result.status, payload = result.payload }
end

-- Submits a swing via ShotLifecycleService.  On success, state → "ShotInProgress".
function VerticalSliceFlowService:SubmitSwing(player: Player, payload: any): Result
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local result = SLS:StartShot(player, payload)
	if result.success then
		local entry = _getOrCreate(player)
		entry.state = "ShotInProgress"
		Logger:Info("VerticalSliceFlowService",
			("shot in progress for %s"):format(player.Name))
	else
		_rejectedCount += 1
		Logger:Warn("VerticalSliceFlowService",
			("SubmitSwing failed for %s — %q"):format(player.Name, result.status))
	end
	return { success = result.success, status = result.status, payload = result.payload }
end

-- Records the ball landing via LandingPipelineService.  On success, state → "BallLanded".
function VerticalSliceFlowService:RecordBallLanding(
	player:          Player,
	landingPosition: any
): Result
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local result = LPS:RecordLanding(player, landingPosition)
	if result.success then
		local entry = _getOrCreate(player)
		entry.state = "BallLanded"
		Logger:Info("VerticalSliceFlowService",
			("ball landed for %s"):format(player.Name))
	else
		_rejectedCount += 1
		Logger:Warn("VerticalSliceFlowService",
			("RecordBallLanding failed for %s — %q"):format(player.Name, result.status))
	end
	return { success = result.success, status = result.status, payload = nil }
end

-- Marks the hole as complete via HoleCompletionService.  On success, state → "HoleComplete".
function VerticalSliceFlowService:MarkHoleComplete(player: Player): Result
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local result = HCS:CompleteHole(player)
	if result.success then
		local entry = _getOrCreate(player)
		entry.state = "HoleComplete"
		Logger:Info("VerticalSliceFlowService",
			("hole complete for %s"):format(player.Name))
	else
		_rejectedCount += 1
		Logger:Warn("VerticalSliceFlowService",
			("MarkHoleComplete failed for %s — %q"):format(player.Name, result.status))
	end
	return { success = result.success, status = result.status, payload = nil }
end

-- Finalizes the round via RoundCompletionService (two-step: Notify then Finalize).
-- Both steps must succeed for state → "RoundComplete" and completedCount to increment.
function VerticalSliceFlowService:FinalizeVerticalSlice(player: Player): Result
	if not _initialized then
		return { success = false, status = "NotInitialized", payload = nil }
	end
	local notifyResult = RCS:NotifyHoleCompleted(player)
	if not notifyResult.success then
		_rejectedCount += 1
		Logger:Warn("VerticalSliceFlowService",
			("FinalizeVerticalSlice: NotifyHoleCompleted failed for %s — %q"):format(
				player.Name, notifyResult.status))
		return { success = false, status = notifyResult.status, payload = nil }
	end
	local finalizeResult = RCS:FinalizeRound(player)
	if not finalizeResult.success then
		_rejectedCount += 1
		Logger:Warn("VerticalSliceFlowService",
			("FinalizeVerticalSlice: FinalizeRound failed for %s — %q"):format(
				player.Name, finalizeResult.status))
		return { success = false, status = finalizeResult.status, payload = nil }
	end
	local entry       = _getOrCreate(player)
	entry.state       = "RoundComplete"
	entry.completed   = true
	_completedCount  += 1
	Logger:Info("VerticalSliceFlowService",
		("vertical slice completed for %s (completedCount=%d)"):format(
			player.Name, _completedCount))
	return { success = true, status = "RoundCompleted", payload = nil }
end

-- Returns an independent copy of the player's current flow state.
function VerticalSliceFlowService:GetFlowState(player: Player): FlowState
	local entry = _flows[player.UserId]
	if not entry then
		return { state = "LobbyReady", started = false, completed = false }
	end
	return { state = entry.state, started = entry.started, completed = entry.completed }
end

-- Clears local flow state and resets all sub-services for this player.
-- Uses pcall so a failing sub-service reset does not propagate.
function VerticalSliceFlowService:ResetPlayer(player: Player)
	_flows[player.UserId] = nil
	pcall(function() RPS:ResetPlayer(player) end)   -- aborts GameService session
	pcall(function() SLS:ResetShot(player) end)
	pcall(function() LPS:ResetLanding(player) end)
	pcall(function() HCS:ResetPlayer(player) end)
	pcall(function() RCS:ResetPlayer(player) end)
	Logger:Debug("VerticalSliceFlowService",
		("player %s reset"):format(player.Name))
end

function VerticalSliceFlowService:GetStartedCount(): number
	return _startedCount
end

function VerticalSliceFlowService:GetCompletedCount(): number
	return _completedCount
end

function VerticalSliceFlowService:GetRejectedCount(): number
	return _rejectedCount
end

function VerticalSliceFlowService:ResetCounts()
	_startedCount   = 0
	_completedCount = 0
	_rejectedCount  = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function VerticalSliceFlowService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[VerticalSliceFlowService] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_flows)
	VerticalSliceFlowService:ResetCounts()

	Logger:Info("VerticalSliceFlowService", "ready")
end

function VerticalSliceFlowService:Update(_dt: number) end

function VerticalSliceFlowService:Destroy()
	table.clear(_flows)
	VerticalSliceFlowService:ResetCounts()
	_initialized = false
end

return VerticalSliceFlowService
