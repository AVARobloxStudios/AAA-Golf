--!strict
-- GameBusBridgeControllerModule — Client singleton (Sprint 19)
-- Connects to ReplicatedStorage.Network.RemoteEvents.GameBus.OnClientEvent
-- and fans every valid envelope out through EventRouterControllerModule.
--
-- This module is the single point where the live GameBus wire meets the
-- local EventRouter dispatch table.  All other Sprint 19+ modules that need
-- to react to server events should register handlers with EventRouter, not
-- add their own OnClientEvent connections.
--
-- Connection is established once in Init().  The double-init guard prevents
-- duplicate subscriptions across repeated Init() calls (e.g. in tests).
--
-- _simulateEvent() is a semi-public test helper: it drives the same
-- _handleEnvelope path without a live GameBus, mirroring the _onClientEvent
-- pattern used by Sprint 11 modules.
--
-- Public API
--   IsConnected()         → boolean
--   GetRoutedCount()      → number   (envelopes successfully routed)
--   Disconnect()          — drop the GameBus connection
--   _simulateEvent(env)   — test helper; same path as OnClientEvent
--
-- GameBusBridgeController.client.lua is the thin runner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventRouter =
	require(script.Parent.EventRouterControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:  boolean                  = false
local _connected:    boolean                  = false
local _routedCount:  number                   = 0
local _gameBusConn:  RBXScriptConnection?     = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local GameBusBridgeControllerModule = {}
GameBusBridgeControllerModule.__index = GameBusBridgeControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _handleEnvelope(envelope: any)
	if not _connected then return end
	if type(envelope) ~= "table" then return end
	_routedCount += 1
	EventRouter:RouteEvent(envelope)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function GameBusBridgeControllerModule:IsConnected(): boolean
	return _connected
end

function GameBusBridgeControllerModule:GetRoutedCount(): number
	return _routedCount
end

function GameBusBridgeControllerModule:Disconnect()
	if _gameBusConn then
		_gameBusConn:Disconnect()
		_gameBusConn = nil
	end
	_connected = false
end

-- Semi-public: drives _handleEnvelope without a live GameBus connection.
-- Used by Sprint19ClientTest to verify routing behaviour without server calls.
function GameBusBridgeControllerModule:_simulateEvent(envelope: any)
	_handleEnvelope(envelope)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function GameBusBridgeControllerModule:Init()
	if _initialized then
		warn("[GameBusBridgeController] Init called twice — skipping")
		return
	end
	_initialized = true
	_routedCount = 0

	local network      = ReplicatedStorage:FindFirstChild("Network")
	local eventsFolder = network and (network :: Instance):FindFirstChild("RemoteEvents")
	local gameBus      = eventsFolder and (eventsFolder :: Instance):FindFirstChild("GameBus")

	if not gameBus then
		warn("[GameBusBridgeController] GameBus remote not found — staying disconnected")
		return
	end

	_gameBusConn = (gameBus :: RemoteEvent).OnClientEvent:Connect(function(envelope: any)
		_handleEnvelope(envelope)
	end)
	_connected = true
	print("[GameBusBridgeController] connected to GameBus")
end

function GameBusBridgeControllerModule:Update(_dt: number) end

function GameBusBridgeControllerModule:Destroy()
	if _gameBusConn then
		_gameBusConn:Disconnect()
		_gameBusConn = nil
	end
	_connected   = false
	_routedCount = 0
	_initialized = false
end

return GameBusBridgeControllerModule
