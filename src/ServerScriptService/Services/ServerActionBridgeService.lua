--!strict
-- ServerActionBridgeService — Server-only singleton (Sprint 24)
-- Owns the single additional GameBus.OnServerEvent connection for the Sprint 23
-- action pipeline.  Runs in parallel with EventBusHandler (Sprint 5), which
-- handles real gameplay effects (GameService/PhysicsService).  This service
-- handles the new stub pipeline (RequestProcessorService → ActionExecutionService
-- → ResponseDispatchService) without touching gameplay services directly.
--
-- All envelope validation happens here before forwarding to RPS.  If RPS is not
-- yet initialized (no runner called RPS:Init) it will warn and return false;
-- this service safely handles that case.
--
-- Counter semantics:
--   receivedCount  — every OnServerEvent call, valid or not
--   forwardedCount — envelopes that passed local validation and were handed to RPS
--   rejectedCount  — envelopes dropped by local validation (before reaching RPS)
--
-- Public API
--   IsConnected()         → boolean
--   GetReceivedCount()    → number
--   GetForwardedCount()   → number
--   GetRejectedCount()    → number
--   ResetCounts()
--   _dispatch(player, envelope)   — semi-public for Sprint24ServerTest
--
-- ServerActionBridgeRunner.server.lua is the thin runner.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Logger)

local RPS = require(ServerScriptService.Services.RequestProcessorService)

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean               = false
local _connection:     RBXScriptConnection?  = nil
local _receivedCount:  number                = 0
local _forwardedCount: number                = 0
local _rejectedCount:  number                = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ServerActionBridgeService = {}
ServerActionBridgeService.__index = ServerActionBridgeService

-- ── Public API ────────────────────────────────────────────────────────────────

function ServerActionBridgeService:IsConnected(): boolean
	return _connection ~= nil
end

function ServerActionBridgeService:GetReceivedCount(): number
	return _receivedCount
end

function ServerActionBridgeService:GetForwardedCount(): number
	return _forwardedCount
end

function ServerActionBridgeService:GetRejectedCount(): number
	return _rejectedCount
end

function ServerActionBridgeService:ResetCounts()
	_receivedCount  = 0
	_forwardedCount = 0
	_rejectedCount  = 0
end

-- ── Semi-public: exposed for Sprint24ServerTest ───────────────────────────────

-- Validates and routes one envelope from the client.
-- Called by the OnServerEvent connection in production; called directly in tests.
function ServerActionBridgeService:_dispatch(player: Player, envelope: any)
	if not _initialized then return end

	_receivedCount += 1

	if type(envelope) ~= "table" then
		_rejectedCount += 1
		Logger:Warn("ServerActionBridgeService",
			("non-table envelope from %s — rejecting"):format(player.Name))
		return
	end

	if type(envelope.actionId) ~= "string" or envelope.actionId == "" then
		_rejectedCount += 1
		Logger:Warn("ServerActionBridgeService",
			("missing actionId from %s — rejecting"):format(player.Name))
		return
	end

	if type(envelope.eventType) ~= "string" or envelope.eventType == "" then
		_rejectedCount += 1
		Logger:Warn("ServerActionBridgeService",
			("missing eventType from %s — rejecting"):format(player.Name))
		return
	end

	if type(envelope.payload) ~= "table" then
		_rejectedCount += 1
		Logger:Warn("ServerActionBridgeService",
			("non-table payload for %q from %s — rejecting"):format(
				tostring(envelope.eventType), player.Name))
		return
	end

	_forwardedCount += 1
	Logger:Debug("ServerActionBridgeService",
		("forwarding %q actionId=%s from %s"):format(
			envelope.eventType, envelope.actionId, player.Name))

	RPS:ProcessRequest(player, envelope)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ServerActionBridgeService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[ServerActionBridgeService] Init called twice — skipping")
		return
	end
	_initialized    = true
	_receivedCount  = 0
	_forwardedCount = 0
	_rejectedCount  = 0

	_connection = GameBus.OnServerEvent:Connect(function(player: Player, envelope: any)
		ServerActionBridgeService:_dispatch(player, envelope)
	end)

	Logger:Info("ServerActionBridgeService", "ready — GameBus.OnServerEvent connected")
end

function ServerActionBridgeService:Update(_dt: number) end

function ServerActionBridgeService:Destroy()
	if _connection then
		_connection:Disconnect()
		_connection = nil
	end
	_receivedCount  = 0
	_forwardedCount = 0
	_rejectedCount  = 0
	_initialized    = false
end

return ServerActionBridgeService
