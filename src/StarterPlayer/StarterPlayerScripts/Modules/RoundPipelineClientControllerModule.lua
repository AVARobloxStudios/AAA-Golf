--!strict
-- RoundPipelineClientControllerModule — Client singleton (Sprint 27)
-- Coordinates a single local round pipeline attempt through existing controllers.
-- Delegates queuing to GameplayPipelineIntegrationController and dispatch tracking
-- to ClientAckIntegrationController.
--
-- Never fires GameBus directly.  Never calls RequestController.
-- Action flow: PrepareHole/SubmitSwing → GPIC → GABC → CAC;
--              DispatchQueuedActions  → CAIC → ADC → RC → GameBus.
--
-- Public API
--   PrepareHole()
--   SubmitSwing(payload)
--   DispatchQueuedActions()
--   GetLastQueuedCount()    → number
--   GetLastDispatchCount()  → number
--   Reset()
--
-- RoundPipelineClientController.client.lua is the thin runner.

local GPIC = require(script.Parent.GameplayPipelineIntegrationControllerModule)
local CAIC = require(script.Parent.ClientAckIntegrationControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:       boolean = false
local _lastQueuedCount:   number  = 0
local _lastDispatchCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local RoundPipelineClientControllerModule = {}
RoundPipelineClientControllerModule.__index = RoundPipelineClientControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Queues a HoleReady action via GPIC (duplicate-guarded per cycle).
-- Updates lastQueuedCount from GPIC's current queued count.
function RoundPipelineClientControllerModule:PrepareHole()
	if not _initialized then return end
	GPIC:QueueHoleReady()
	_lastQueuedCount = GPIC:GetQueuedCount()
end

-- Queues a SwingIntent action via GPIC (duplicate-guarded per cycle).
-- Updates lastQueuedCount from GPIC's current queued count.
function RoundPipelineClientControllerModule:SubmitSwing(payload: any)
	if not _initialized then return end
	GPIC:QueueSwingIntent(payload)
	_lastQueuedCount = GPIC:GetQueuedCount()
end

-- Dispatches all pending client actions via CAIC and records the dispatch count.
function RoundPipelineClientControllerModule:DispatchQueuedActions()
	if not _initialized then return end
	CAIC:DispatchAllAndTrack()
	_lastDispatchCount = CAIC:GetLastDispatchCount()
end

function RoundPipelineClientControllerModule:GetLastQueuedCount(): number
	return _lastQueuedCount
end

function RoundPipelineClientControllerModule:GetLastDispatchCount(): number
	return _lastDispatchCount
end

-- Resets local counters and clears GPIC's per-cycle duplicate guards.
-- Does NOT clear the CAC queue or SAC tracking — those have their own lifecycle.
function RoundPipelineClientControllerModule:Reset()
	_lastQueuedCount   = 0
	_lastDispatchCount = 0
	GPIC:Reset()
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RoundPipelineClientControllerModule:Init()
	if _initialized then
		warn("[RoundPipelineClientController] Init called twice — skipping")
		return
	end
	_initialized       = true
	_lastQueuedCount   = 0
	_lastDispatchCount = 0

	print("[RoundPipelineClientController] ready")
end

function RoundPipelineClientControllerModule:Update(_dt: number) end

function RoundPipelineClientControllerModule:Destroy()
	_lastQueuedCount   = 0
	_lastDispatchCount = 0
	_initialized       = false
end

return RoundPipelineClientControllerModule
