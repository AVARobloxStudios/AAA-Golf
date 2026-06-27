--!strict
-- ResponseDispatchService — Server-only singleton (Sprint 23)
-- Converts execution results from ActionExecutionService into GameBus response
-- envelopes and fires them to the requesting player via GameBus:FireClient.
--
-- Three ack event types are supported:
--   RequestAck — generic request acknowledgement
--   ActionAck  — acknowledgement for a specific gameplay action
--   ServerAck  — broad server-side acknowledgement broadcast
--
-- DispatchResult is the primary entry point: it maps an ExecutionResult to an
-- ActionAck with status "Accepted" or "Rejected" and fires it to the player.
-- DispatchRequestAck and DispatchServerAck are available for targeted use by
-- RequestProcessorService or future services.
--
-- _dispatchCount tracks total FireClient calls regardless of ack type.
--
-- Public API
--   DispatchResult(player, actionId, result)
--   DispatchRequestAck(player, requestId, status, payload)
--   DispatchActionAck(player, actionId, status, payload)
--   DispatchServerAck(player, requestId, status, payload)
--   GetDispatchCount()    → number
--   ResetDispatchCount()
--
-- No runner Script for Sprint 23 — initialized by Sprint23ServerTest or a
-- future runner in Services/.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Types ─────────────────────────────────────────────────────────────────────

type ExecutionResult = {
	success: boolean,
	status:  string,
	payload: any,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean = false
local _dispatchCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ResponseDispatchService = {}
ResponseDispatchService.__index = ResponseDispatchService

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _fire(player: Player, envelope: { [string]: any })
	GameBus:FireClient(player, envelope)
	_dispatchCount += 1
	Logger:Debug("ResponseDispatchService",
		("fired %q to %s"):format(tostring(envelope.eventType), player.Name))
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Primary pipeline entry: maps a success/failure ExecutionResult to an ActionAck.
-- "Accepted" for success, "Rejected" for failure.
function ResponseDispatchService:DispatchResult(
	player:   Player,
	actionId: string,
	result:   ExecutionResult
)
	if not _initialized then
		warn("[ResponseDispatchService] DispatchResult called before Init — skipping")
		return
	end
	local status = if result.success then "Accepted" else "Rejected"
	ResponseDispatchService:DispatchActionAck(player, actionId, status, result.payload)
end

-- Fires a RequestAck envelope to the player.
function ResponseDispatchService:DispatchRequestAck(
	player:    Player,
	requestId: string,
	status:    string,
	payload:   any
)
	if not _initialized then return end
	_fire(player, {
		eventType = "RequestAck",
		payload   = { requestId = requestId, status = status, payload = payload },
		timestamp = os.time(),
	})
end

-- Fires an ActionAck envelope to the player.
function ResponseDispatchService:DispatchActionAck(
	player:   Player,
	actionId: string,
	status:   string,
	payload:  any
)
	if not _initialized then return end
	_fire(player, {
		eventType = "ActionAck",
		payload   = { requestId = actionId, actionId = actionId, status = status, payload = payload },
		timestamp = os.time(),
	})
end

-- Fires a ServerAck envelope to the player.
function ResponseDispatchService:DispatchServerAck(
	player:    Player,
	requestId: string,
	status:    string,
	payload:   any
)
	if not _initialized then return end
	_fire(player, {
		eventType = "ServerAck",
		payload   = { requestId = requestId, status = status, payload = payload },
		timestamp = os.time(),
	})
end

function ResponseDispatchService:GetDispatchCount(): number
	return _dispatchCount
end

function ResponseDispatchService:ResetDispatchCount()
	_dispatchCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ResponseDispatchService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[ResponseDispatchService] Init called twice — skipping")
		return
	end
	_initialized  = true
	_dispatchCount = 0

	Logger:Info("ResponseDispatchService", "ready")
end

function ResponseDispatchService:Update(_dt: number) end

function ResponseDispatchService:Destroy()
	_dispatchCount = 0
	_initialized   = false
end

return ResponseDispatchService
