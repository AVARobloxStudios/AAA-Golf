--!strict
-- ScoreRevealClientControllerModule — Client singleton (Sprint 29)
-- Tracks local score-reveal lifecycle state.
-- Pure state machine: Hidden → Revealing → Complete.
--
-- This module has no network connections.  External callers drive it forward
-- by calling BeginReveal / CompleteReveal.  It never writes to GameBus,
-- RequestController, or any action queue.
--
-- Public API
--   BeginReveal(data)    — validate table, store copy, state → "Revealing", revealCount++
--   CompleteReveal()     — "Revealing" → "Complete"; any other state is a safe no-op
--   GetRevealState()     → { state, hasData, revealCount }  (independent copy)
--   Reset()              — state → "Hidden", clear data, revealCount = 0
--
-- ScoreRevealClientController.client.lua is the thin runner.

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean = false
local _state:       string  = "Hidden"
local _revealData:  any     = nil
local _revealCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ScoreRevealClientControllerModule = {}
ScoreRevealClientControllerModule.__index = ScoreRevealClientControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Stores a shallow copy of data, transitions to "Revealing", and increments revealCount.
-- data must be a table; non-tables are warned and ignored.
function ScoreRevealClientControllerModule:BeginReveal(data: any)
	if not _initialized then return end
	if type(data) ~= "table" then
		warn("[ScoreRevealClientController] BeginReveal: data must be a table")
		return
	end
	local copy: { [string]: any } = {}
	for k, v in pairs(data :: { [string]: any }) do
		copy[k] = v
	end
	_revealData  = copy
	_state       = "Revealing"
	_revealCount += 1
end

-- Transitions "Revealing" → "Complete". Safe no-op for any other state.
function ScoreRevealClientControllerModule:CompleteReveal()
	if not _initialized then return end
	if _state == "Revealing" then
		_state = "Complete"
	end
end

-- Returns an independent copy of the current reveal state.
function ScoreRevealClientControllerModule:GetRevealState(): { [string]: any }
	return {
		state       = _state,
		hasData     = _revealData ~= nil,
		revealCount = _revealCount,
	}
end

-- Returns all local state to the initial Hidden condition.
function ScoreRevealClientControllerModule:Reset()
	_state       = "Hidden"
	_revealData  = nil
	_revealCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ScoreRevealClientControllerModule:Init()
	if _initialized then
		warn("[ScoreRevealClientController] Init called twice — skipping")
		return
	end
	_initialized = true
	ScoreRevealClientControllerModule:Reset()

	print("[ScoreRevealClientController] ready")
end

function ScoreRevealClientControllerModule:Update(_dt: number) end

function ScoreRevealClientControllerModule:Destroy()
	_state       = "Hidden"
	_revealData  = nil
	_revealCount = 0
	_initialized = false
end

return ScoreRevealClientControllerModule
