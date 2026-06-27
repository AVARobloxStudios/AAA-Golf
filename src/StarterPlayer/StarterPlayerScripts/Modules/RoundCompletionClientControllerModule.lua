--!strict
-- RoundCompletionClientControllerModule — Client singleton (Sprint 31)
-- Tracks local end-of-round flow state.
-- Pure state machine: Idle → ResultsIncoming → RoundFinished → ReadyForLobby.
--
-- This module has no network connections.  External callers drive it forward
-- by calling BeginResults / FinishRound / ReadyForLobby.  It never writes to
-- GameBus, RequestController, or any action queue.
--
-- Public API
--   BeginResults(data)  — validate table, state → "ResultsIncoming", store copy
--   FinishRound(data)   — validate table, state → "RoundFinished", store copy
--   ReadyForLobby()     — only from "RoundFinished" → "ReadyForLobby"; else safe no-op
--   GetState()          → { state, hasData }  (independent copy)
--   Reset()             — state → "Idle", clear data
--
-- RoundCompletionClientController.client.lua is the thin runner.

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean = false
local _state:       string  = "Idle"
local _data:        any     = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local RoundCompletionClientControllerModule = {}
RoundCompletionClientControllerModule.__index = RoundCompletionClientControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _shallowCopy(t: { [string]: any }): { [string]: any }
	local copy: { [string]: any } = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Transitions state to "ResultsIncoming" and stores a shallow copy of data.
-- data must be a table; non-tables are warned and ignored.
function RoundCompletionClientControllerModule:BeginResults(data: any)
	if not _initialized then return end
	if type(data) ~= "table" then
		warn("[RoundCompletionClientController] BeginResults: data must be a table")
		return
	end
	_data  = _shallowCopy(data :: { [string]: any })
	_state = "ResultsIncoming"
end

-- Transitions state to "RoundFinished" and stores a shallow copy of data.
-- data must be a table; non-tables are warned and ignored.
function RoundCompletionClientControllerModule:FinishRound(data: any)
	if not _initialized then return end
	if type(data) ~= "table" then
		warn("[RoundCompletionClientController] FinishRound: data must be a table")
		return
	end
	_data  = _shallowCopy(data :: { [string]: any })
	_state = "RoundFinished"
end

-- Transitions "RoundFinished" → "ReadyForLobby".
-- Any other state is a safe no-op so out-of-order calls do not crash.
function RoundCompletionClientControllerModule:ReadyForLobby()
	if not _initialized then return end
	if _state == "RoundFinished" then
		_state = "ReadyForLobby"
	end
end

-- Returns an independent copy of the current round-completion state.
function RoundCompletionClientControllerModule:GetState(): { [string]: any }
	return {
		state   = _state,
		hasData = _data ~= nil,
	}
end

-- Returns all local state to the initial Idle condition.
function RoundCompletionClientControllerModule:Reset()
	_state = "Idle"
	_data  = nil
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RoundCompletionClientControllerModule:Init()
	if _initialized then
		warn("[RoundCompletionClientController] Init called twice — skipping")
		return
	end
	_initialized = true
	RoundCompletionClientControllerModule:Reset()

	print("[RoundCompletionClientController] ready")
end

function RoundCompletionClientControllerModule:Update(_dt: number) end

function RoundCompletionClientControllerModule:Destroy()
	_state       = "Idle"
	_data        = nil
	_initialized = false
end

return RoundCompletionClientControllerModule
