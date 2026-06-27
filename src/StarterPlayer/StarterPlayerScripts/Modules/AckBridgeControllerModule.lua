--!strict
-- AckBridgeControllerModule — Client singleton (Sprint 22)
-- Bridges routed ack-style events from EventRouterController into
-- ServerAckController.ReceiveAck() calls.
--
-- Registers handlers with EventRouterController for three event types:
--   RequestAck — server acknowledged a generic request
--   ActionAck  — server acknowledged a gameplay action
--   ServerAck  — generic server-side acknowledgement broadcast
--
-- Each envelope must carry a payload table with:
--   requestId (or actionId as a fallback) — non-empty string
--   status                                — forwarded to ServerAckController
--   payload                               — optional additional data
--
-- _receivedAckCount increments only when the envelope payload is structurally
-- valid (non-empty requestId or actionId, non-empty status string).
-- Valid status values are still enforced by ServerAckController.
--
-- Handler functions are declared at module scope so Destroy() can unregister
-- them by exact function reference (same pattern as StateSyncController).
-- This guarantees no duplicate registrations across Destroy()/Init() cycles.
--
-- Public API
--   GetReceivedAckCount()   → number
--   ResetReceivedAckCount() — reset counter to 0
--
-- AckBridgeController.client.lua is the thin runner.

local EventRouter = require(script.Parent.EventRouterControllerModule)
local SAC         = require(script.Parent.ServerAckControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean = false
local _receivedAckCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local AckBridgeControllerModule = {}
AckBridgeControllerModule.__index = AckBridgeControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

-- Shared logic: validates envelope payload, increments count, forwards to SAC.
local function _handleAck(envelope: any)
	local payload = envelope.payload
	if type(payload) ~= "table" then return end

	-- Accept either requestId or actionId as the SAC tracking key.
	local requestId: string? = nil
	if type(payload.requestId) == "string" and payload.requestId ~= "" then
		requestId = payload.requestId
	elseif type(payload.actionId) == "string" and payload.actionId ~= "" then
		requestId = payload.actionId
	end
	if not requestId then return end

	local status = payload.status
	if type(status) ~= "string" or status == "" then return end

	_receivedAckCount += 1
	SAC:ReceiveAck(requestId :: string, status, payload.payload)
end

-- ── Private handlers (module-scope for unregistration by identity) ────────────

local function _handleRequestAck(envelope: any)
	_handleAck(envelope)
end

local function _handleActionAck(envelope: any)
	_handleAck(envelope)
end

local function _handleServerAck(envelope: any)
	_handleAck(envelope)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function AckBridgeControllerModule:GetReceivedAckCount(): number
	return _receivedAckCount
end

function AckBridgeControllerModule:ResetReceivedAckCount()
	_receivedAckCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function AckBridgeControllerModule:Init()
	if _initialized then
		warn("[AckBridgeController] Init called twice — skipping")
		return
	end
	_initialized      = true
	_receivedAckCount = 0

	EventRouter:RegisterHandler("RequestAck", _handleRequestAck)
	EventRouter:RegisterHandler("ActionAck",  _handleActionAck)
	EventRouter:RegisterHandler("ServerAck",  _handleServerAck)

	print("[AckBridgeController] ready — 3 handlers registered")
end

function AckBridgeControllerModule:Update(_dt: number) end

function AckBridgeControllerModule:Destroy()
	EventRouter:UnregisterHandler("RequestAck", _handleRequestAck)
	EventRouter:UnregisterHandler("ActionAck",  _handleActionAck)
	EventRouter:UnregisterHandler("ServerAck",  _handleServerAck)

	_receivedAckCount = 0
	_initialized      = false
end

return AckBridgeControllerModule
