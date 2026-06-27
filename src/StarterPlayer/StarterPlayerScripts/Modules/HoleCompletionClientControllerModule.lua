--!strict
-- HoleCompletionClientControllerModule — Client singleton (Sprint 30)
-- Tracks local hole-completion lifecycle state.
-- Pure state machine: WaitingForFinish → CheckingCup → HoleComplete → Transitioning.
--
-- This module has no network connections.  External callers drive it forward
-- by calling BeginCupCheck / MarkHoleComplete / BeginTransition.  It never
-- writes to GameBus, RequestController, or any action queue.
--
-- Public API
--   BeginCupCheck(data)      — validate table, state → "CheckingCup", store copy
--   MarkHoleComplete(data)   — validate table, state → "HoleComplete", completed=true, count++
--   BeginTransition(data)    — validate table, only from HoleComplete → "Transitioning"
--   GetCompletionState()     → { state, completed, completedCount, hasData }  (copy)
--   Reset()                  — state → "WaitingForFinish", clear all
--
-- HoleCompletionClientController.client.lua is the thin runner.

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean = false
local _state:          string  = "WaitingForFinish"
local _completed:      boolean = false
local _completedCount: number  = 0
local _data:           any     = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local HoleCompletionClientControllerModule = {}
HoleCompletionClientControllerModule.__index = HoleCompletionClientControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _shallowCopy(t: { [string]: any }): { [string]: any }
	local copy: { [string]: any } = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Transitions state to "CheckingCup" and stores a shallow copy of data.
-- data must be a table; non-tables are warned and ignored.
function HoleCompletionClientControllerModule:BeginCupCheck(data: any)
	if not _initialized then return end
	if type(data) ~= "table" then
		warn("[HoleCompletionClientController] BeginCupCheck: data must be a table")
		return
	end
	_data  = _shallowCopy(data :: { [string]: any })
	_state = "CheckingCup"
end

-- Transitions state to "HoleComplete", sets completed=true, increments completedCount.
-- data must be a table; non-tables are warned and ignored.
function HoleCompletionClientControllerModule:MarkHoleComplete(data: any)
	if not _initialized then return end
	if type(data) ~= "table" then
		warn("[HoleCompletionClientController] MarkHoleComplete: data must be a table")
		return
	end
	_data           = _shallowCopy(data :: { [string]: any })
	_state          = "HoleComplete"
	_completed      = true
	_completedCount += 1
end

-- Transitions "HoleComplete" → "Transitioning".
-- Only valid after MarkHoleComplete; any other state is a safe no-op.
-- data must be a table; non-tables are warned and ignored.
function HoleCompletionClientControllerModule:BeginTransition(data: any)
	if not _initialized then return end
	if type(data) ~= "table" then
		warn("[HoleCompletionClientController] BeginTransition: data must be a table")
		return
	end
	if _state ~= "HoleComplete" then
		warn(("[HoleCompletionClientController] BeginTransition: expected HoleComplete, got %q — ignoring"):format(_state))
		return
	end
	_data  = _shallowCopy(data :: { [string]: any })
	_state = "Transitioning"
end

-- Returns an independent copy of the current completion state.
function HoleCompletionClientControllerModule:GetCompletionState(): { [string]: any }
	return {
		state          = _state,
		completed      = _completed,
		completedCount = _completedCount,
		hasData        = _data ~= nil,
	}
end

-- Returns all local state to the initial WaitingForFinish condition.
function HoleCompletionClientControllerModule:Reset()
	_state          = "WaitingForFinish"
	_completed      = false
	_completedCount = 0
	_data           = nil
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function HoleCompletionClientControllerModule:Init()
	if _initialized then
		warn("[HoleCompletionClientController] Init called twice — skipping")
		return
	end
	_initialized = true
	HoleCompletionClientControllerModule:Reset()

	print("[HoleCompletionClientController] ready")
end

function HoleCompletionClientControllerModule:Update(_dt: number) end

function HoleCompletionClientControllerModule:Destroy()
	_state          = "WaitingForFinish"
	_completed      = false
	_completedCount = 0
	_data           = nil
	_initialized    = false
end

return HoleCompletionClientControllerModule
