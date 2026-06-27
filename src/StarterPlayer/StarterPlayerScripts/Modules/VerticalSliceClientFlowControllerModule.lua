--!strict
-- VerticalSliceClientFlowControllerModule — Client singleton (Sprint 32)
-- Local-only vertical slice flow state.  No networking, no remotes, no UI.
--
-- State sequence:
--   LobbyReady → RoundStarted → HoleReady → ShotInProgress
--               → BallLanded  → HoleComplete → RoundComplete
--
-- Public API
--   StartFlow()           — reset to LobbyReady
--   MarkRoundStarted()    — advance to RoundStarted, started=true
--   MarkHoleReady()       — advance to HoleReady
--   MarkShotInProgress()  — advance to ShotInProgress
--   MarkBallLanded()      — advance to BallLanded
--   MarkHoleComplete()    — advance to HoleComplete
--   MarkRoundComplete()   — advance to RoundComplete, completed=true
--   GetFlowState()        → FlowState (copy)
--   Reset()               — LobbyReady, started=false, completed=false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Shared.Logger)

-- ── Types ─────────────────────────────────────────────────────────────────────

type FlowState = {
	state:     string,
	started:   boolean,
	completed: boolean,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean = false
local _state:       string  = "LobbyReady"
local _started:     boolean = false
local _completed:   boolean = false

-- ── Module ───────────────────────────────────────────────────────────────────

local VerticalSliceClientFlowControllerModule = {}
VerticalSliceClientFlowControllerModule.__index = VerticalSliceClientFlowControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Resets to the initial ready state.
function VerticalSliceClientFlowControllerModule:StartFlow()
	if not _initialized then return end
	_state     = "LobbyReady"
	_started   = false
	_completed = false
	Logger:Debug("VerticalSliceClientFlowControllerModule", "flow started — LobbyReady")
end

function VerticalSliceClientFlowControllerModule:MarkRoundStarted()
	if not _initialized then return end
	_state   = "RoundStarted"
	_started = true
	Logger:Debug("VerticalSliceClientFlowControllerModule", "RoundStarted")
end

function VerticalSliceClientFlowControllerModule:MarkHoleReady()
	if not _initialized then return end
	_state = "HoleReady"
	Logger:Debug("VerticalSliceClientFlowControllerModule", "HoleReady")
end

function VerticalSliceClientFlowControllerModule:MarkShotInProgress()
	if not _initialized then return end
	_state = "ShotInProgress"
	Logger:Debug("VerticalSliceClientFlowControllerModule", "ShotInProgress")
end

function VerticalSliceClientFlowControllerModule:MarkBallLanded()
	if not _initialized then return end
	_state = "BallLanded"
	Logger:Debug("VerticalSliceClientFlowControllerModule", "BallLanded")
end

function VerticalSliceClientFlowControllerModule:MarkHoleComplete()
	if not _initialized then return end
	_state = "HoleComplete"
	Logger:Debug("VerticalSliceClientFlowControllerModule", "HoleComplete")
end

function VerticalSliceClientFlowControllerModule:MarkRoundComplete()
	if not _initialized then return end
	_state     = "RoundComplete"
	_completed = true
	Logger:Debug("VerticalSliceClientFlowControllerModule", "RoundComplete")
end

-- Returns an independent copy of the current flow state.
function VerticalSliceClientFlowControllerModule:GetFlowState(): FlowState
	return { state = _state, started = _started, completed = _completed }
end

-- Resets all state to initial values.
function VerticalSliceClientFlowControllerModule:Reset()
	_state     = "LobbyReady"
	_started   = false
	_completed = false
	Logger:Debug("VerticalSliceClientFlowControllerModule", "reset")
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function VerticalSliceClientFlowControllerModule:Init()
	if _initialized then
		warn("[VerticalSliceClientFlowControllerModule] Init called twice — skipping")
		return
	end
	_initialized = true
	_state       = "LobbyReady"
	_started     = false
	_completed   = false
	Logger:Info("VerticalSliceClientFlowControllerModule", "ready")
end

function VerticalSliceClientFlowControllerModule:Update(_dt: number) end

function VerticalSliceClientFlowControllerModule:Destroy()
	_state       = "LobbyReady"
	_started     = false
	_completed   = false
	_initialized = false
end

return VerticalSliceClientFlowControllerModule
