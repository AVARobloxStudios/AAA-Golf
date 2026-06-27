--!strict
-- ClientAckIntegrationControllerModule — Client singleton (Sprint 24)
-- A lightweight coordination layer that dispatches queued client actions and
-- immediately tracks them in ServerAckController so their server-side status
-- can be polled via GetLastAckStatus().
--
-- Does NOT wire real network responses — it sets up the tracking side so that
-- when AckBridgeController receives a server ack (via EventRouter), the status
-- is automatically updated in ServerAckController.
--
-- DispatchAllAndTrack / DispatchActionAndTrack pre-register each dispatched
-- action as "Pending" in ServerAckController before the network round-trip
-- completes.  GetLastAckStatus delegates directly to ServerAckController.GetAck,
-- so the status updates automatically once AckBridgeController receives and
-- forwards the server acknowledgement.
--
-- No UI, no GameBus connections, no _connections table needed.
--
-- Public API
--   DispatchAllAndTrack()               — dispatch all unsent, track each in SAC
--   DispatchActionAndTrack(actionId)    — dispatch one, track it in SAC
--   GetLastDispatchCount()              → number
--   GetLastAckStatus(actionId)          → string  ("Pending"|"Accepted"|"Rejected"|"Timeout"|"Unknown")
--   Reset()                            — clear lastDispatchCount
--
-- ClientAckIntegrationController.client.lua is the thin runner.

local CAC = require(script.Parent.ClientActionControllerModule)
local ADC = require(script.Parent.ActionDispatchControllerModule)
local SAC = require(script.Parent.ServerAckControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:       boolean = false
local _lastDispatchCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ClientAckIntegrationControllerModule = {}
ClientAckIntegrationControllerModule.__index = ClientAckIntegrationControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Dispatches all unsent actions from ClientActionController and registers each
-- dispatched action as Pending in ServerAckController.
function ClientAckIntegrationControllerModule:DispatchAllAndTrack()
	if not _initialized then return end

	-- Snapshot unsent actions before dispatch so we know what will be sent.
	local unsent: { any } = {}
	for _, entry in ipairs(CAC:GetQueuedActions()) do
		if not entry.sent then
			table.insert(unsent, entry)
		end
	end

	ADC:DispatchAll()

	for _, entry in ipairs(unsent) do
		SAC:TrackRequest(entry.actionId, entry.actionType)
	end

	_lastDispatchCount = #unsent
end

-- Dispatches one specific action by actionId and registers it as Pending in SAC.
-- Warns and sets lastDispatchCount = 0 if actionId is unknown or already sent.
function ClientAckIntegrationControllerModule:DispatchActionAndTrack(actionId: any)
	if not _initialized then return end

	if type(actionId) ~= "string" or actionId == "" then
		warn("[ClientAckIntegrationController] DispatchActionAndTrack: actionId must be a non-empty string")
		_lastDispatchCount = 0
		return
	end

	local actions = CAC:GetQueuedActions()
	for _, entry in ipairs(actions) do
		if entry.actionId == actionId then
			if entry.sent then
				warn(("[ClientAckIntegrationController] DispatchActionAndTrack: action %q already sent"):format(
					actionId))
				_lastDispatchCount = 0
			else
				ADC:DispatchAction(actionId)
				SAC:TrackRequest(actionId, entry.actionType)
				_lastDispatchCount = 1
			end
			return
		end
	end

	warn(("[ClientAckIntegrationController] DispatchActionAndTrack: unknown actionId %q"):format(
		actionId))
	_lastDispatchCount = 0
end

function ClientAckIntegrationControllerModule:GetLastDispatchCount(): number
	return _lastDispatchCount
end

-- Returns the SAC status string for the given actionId, or "Unknown" if not tracked.
function ClientAckIntegrationControllerModule:GetLastAckStatus(actionId: string): string
	local ack = SAC:GetAck(actionId)
	if not ack then return "Unknown" end
	return ack.status
end

-- Clears local CAIC state only; does not modify SAC, CAC, ADC, or AckBridge.
function ClientAckIntegrationControllerModule:Reset()
	_lastDispatchCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ClientAckIntegrationControllerModule:Init()
	if _initialized then
		warn("[ClientAckIntegrationController] Init called twice — skipping")
		return
	end
	_initialized      = true
	_lastDispatchCount = 0

	print("[ClientAckIntegrationController] ready")
end

function ClientAckIntegrationControllerModule:Update(_dt: number) end

function ClientAckIntegrationControllerModule:Destroy()
	_lastDispatchCount = 0
	_initialized       = false
end

return ClientAckIntegrationControllerModule
