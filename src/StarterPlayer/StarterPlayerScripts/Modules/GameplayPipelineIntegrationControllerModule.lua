--!strict
-- GameplayPipelineIntegrationControllerModule — Client singleton (Sprint 26)
-- Integrates the gameplay intent layer with the completed action pipeline.
-- Registers named callbacks in ControllerBridgeController so other modules can
-- trigger pipeline queuing without creating circular requires.
--
-- Duplicate prevention: HoleReady and SwingIntent can each be queued at most
-- once per Reset() cycle.  Call Reset() at the start of each new hole or shot.
--
-- Flow: GPIC → GameplayActionBridgeController → ClientActionController
-- Never fires GameBus directly.  Never calls RequestController.
--
-- Public API
--   QueueHoleReady()            — queue HoleReady once per cycle
--   QueueSwingIntent(payload)   — queue SwingIntent once per cycle
--   GetQueuedCount()            → number
--   Reset()                     — clear per-cycle duplicate guards and count
--   IsReady()                   → boolean
--
-- GameplayPipelineIntegrationController.client.lua is the thin runner.

local GABC = require(script.Parent.GameplayActionBridgeControllerModule)
local CBC  = require(script.Parent.ControllerBridgeControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:       boolean = false
local _holeReadyQueued:   boolean = false
local _swingIntentQueued: boolean = false
local _queuedCount:       number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local GameplayPipelineIntegrationControllerModule = {}
GameplayPipelineIntegrationControllerModule.__index =
	GameplayPipelineIntegrationControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

function GameplayPipelineIntegrationControllerModule:QueueHoleReady()
	if not _initialized then return end
	if _holeReadyQueued then
		warn("[GameplayPipelineIntegration] QueueHoleReady: already queued this cycle — ignoring")
		return
	end
	local actionId = GABC:QueueHoleReady({})
	if actionId then
		_holeReadyQueued = true
		_queuedCount    += 1
	end
end

function GameplayPipelineIntegrationControllerModule:QueueSwingIntent(payload: any)
	if not _initialized then return end
	if _swingIntentQueued then
		warn("[GameplayPipelineIntegration] QueueSwingIntent: already queued this cycle — ignoring")
		return
	end
	if type(payload) ~= "table" then
		warn("[GameplayPipelineIntegration] QueueSwingIntent: payload must be a table")
		return
	end
	local actionId = GABC:QueueSwingIntent(payload)
	if actionId then
		_swingIntentQueued = true
		_queuedCount      += 1
	end
end

function GameplayPipelineIntegrationControllerModule:GetQueuedCount(): number
	return _queuedCount
end

function GameplayPipelineIntegrationControllerModule:Reset()
	_holeReadyQueued   = false
	_swingIntentQueued = false
	_queuedCount       = 0
end

function GameplayPipelineIntegrationControllerModule:IsReady(): boolean
	return _initialized
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function GameplayPipelineIntegrationControllerModule:Init()
	if _initialized then
		warn("[GameplayPipelineIntegration] Init called twice — skipping")
		return
	end
	_initialized       = true
	_holeReadyQueued   = false
	_swingIntentQueued = false
	_queuedCount       = 0

	-- Register named bridges so external modules (SwingController, InputController)
	-- can trigger queuing via CBC without creating circular requires.
	CBC:RegisterBridge("GameplayPipeline.QueueHoleReady", function(_payload: any)
		GameplayPipelineIntegrationControllerModule:QueueHoleReady()
	end)
	CBC:RegisterBridge("GameplayPipeline.QueueSwingIntent", function(payload: any)
		GameplayPipelineIntegrationControllerModule:QueueSwingIntent(payload)
	end)

	print("[GameplayPipelineIntegration] ready — 2 bridges registered")
end

function GameplayPipelineIntegrationControllerModule:Update(_dt: number) end

function GameplayPipelineIntegrationControllerModule:Destroy()
	-- After Destroy, _initialized = false so all bridge callbacks become no-ops.
	-- CBC has no UnregisterBridge; re-Init will overwrite the registrations.
	_holeReadyQueued   = false
	_swingIntentQueued = false
	_queuedCount       = 0
	_initialized       = false
end

return GameplayPipelineIntegrationControllerModule
