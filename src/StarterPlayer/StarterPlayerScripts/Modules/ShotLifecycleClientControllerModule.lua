--!strict
-- ShotLifecycleClientControllerModule — Client singleton (Sprint 28)
-- Tracks local shot lifecycle state for one in-progress shot.
-- Pure state machine: None → Queued → Dispatched → Accepted/Rejected → Landed.
--
-- This module has no network connections.  External callers (RoundPipelineClient,
-- UI, tests) drive it forward by calling the Mark* methods.  It never calls
-- GameBus, RequestController, or any action queue directly.
--
-- Public API
--   BeginLocalShot(payload)        — transition to Queued
--   MarkLocalShotDispatched()      — transition to Dispatched
--   MarkLocalShotAcked(status)     — Accepted → Accepted; anything else → Rejected
--   MarkLocalBallLanded()          — Accepted or InFlight → Landed
--   GetLocalShotState()            → { state, hasPayload, hasLandingData }  (copy)
--   Reset()                        — return to None
--
-- ShotLifecycleClientController.client.lua is the thin runner.

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean = false
local _state:          string  = "None"
local _hasPayload:     boolean = false
local _hasLandingData: boolean = false

-- ── Module ───────────────────────────────────────────────────────────────────

local ShotLifecycleClientControllerModule = {}
ShotLifecycleClientControllerModule.__index = ShotLifecycleClientControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Transitions state to "Queued". payload must be a table; non-tables are rejected.
function ShotLifecycleClientControllerModule:BeginLocalShot(payload: any)
	if not _initialized then return end
	if type(payload) ~= "table" then
		warn("[ShotLifecycleClientController] BeginLocalShot: payload must be a table")
		return
	end
	_state          = "Queued"
	_hasPayload     = true
	_hasLandingData = false
end

function ShotLifecycleClientControllerModule:MarkLocalShotDispatched()
	if not _initialized then return end
	_state = "Dispatched"
end

-- Updates state based on the server acknowledgement status string.
function ShotLifecycleClientControllerModule:MarkLocalShotAcked(status: string)
	if not _initialized then return end
	_state = if status == "Accepted" then "Accepted" else "Rejected"
end

-- Transitions from Accepted or InFlight to Landed.
-- No-ops for any other state so late-arriving landed events are safe.
function ShotLifecycleClientControllerModule:MarkLocalBallLanded()
	if not _initialized then return end
	if _state == "Accepted" or _state == "InFlight" then
		_state          = "Landed"
		_hasLandingData = true
	end
end

-- Returns an independent copy of the current local shot state.
function ShotLifecycleClientControllerModule:GetLocalShotState(): { [string]: any }
	return {
		state          = _state,
		hasPayload     = _hasPayload,
		hasLandingData = _hasLandingData,
	}
end

-- Resets all local state to None.
function ShotLifecycleClientControllerModule:Reset()
	_state          = "None"
	_hasPayload     = false
	_hasLandingData = false
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ShotLifecycleClientControllerModule:Init()
	if _initialized then
		warn("[ShotLifecycleClientController] Init called twice — skipping")
		return
	end
	_initialized    = true
	_state          = "None"
	_hasPayload     = false
	_hasLandingData = false

	print("[ShotLifecycleClientController] ready")
end

function ShotLifecycleClientControllerModule:Update(_dt: number) end

function ShotLifecycleClientControllerModule:Destroy()
	_state          = "None"
	_hasPayload     = false
	_hasLandingData = false
	_initialized    = false
end

return ShotLifecycleClientControllerModule
