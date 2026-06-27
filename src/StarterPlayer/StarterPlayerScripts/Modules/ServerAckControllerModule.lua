--!strict
-- ServerAckControllerModule — Client singleton (Sprint 20)
-- Tracks pending request acknowledgements from the server.  Entries are
-- created by TrackRequest() when a request is dispatched and updated by
-- ReceiveAck() when a server response (or a timeout sentinel) arrives.
--
-- This module is pure client-side state — it does not connect to any remote
-- events or fire any server calls.  Future sprints will wire ReceiveAck() to
-- the appropriate GameBus/EventRouter handlers.
--
-- Valid ack statuses: Pending | Accepted | Rejected | Timeout
--
-- GetAck() returns a shallow copy so callers cannot mutate internal entries.
--
-- Public API
--   TrackRequest(requestId, requestType)          — register a new pending ack
--   ReceiveAck(requestId, status, payload)        — update status for a request
--   GetPendingCount()                             → number
--   GetAck(requestId)                             → AckEntry? (copy)
--   ClearAcks()                                   — remove all tracked acks
--
-- ServerAckController.client.lua is the thin runner.

-- ── Types ─────────────────────────────────────────────────────────────────────

export type AckEntry = {
	requestId:   string,
	requestType: string,
	status:      string,
	payload:     any,
	receivedAt:  number?,
}

-- ── Constants ─────────────────────────────────────────────────────────────────

local VALID_STATUSES: { [string]: boolean } = {
	Pending  = true,
	Accepted = true,
	Rejected = true,
	Timeout  = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                 = false
local _acks:        { [string]: AckEntry }  = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local ServerAckControllerModule = {}
ServerAckControllerModule.__index = ServerAckControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Registers a new pending acknowledgement for the given requestId.
-- Overwrites any existing entry with the same requestId.
function ServerAckControllerModule:TrackRequest(requestId: string, requestType: string)
	if type(requestId) ~= "string" or requestId == "" then
		warn("[ServerAckController] TrackRequest: requestId must be a non-empty string")
		return
	end
	_acks[requestId] = {
		requestId   = requestId,
		requestType = requestType,
		status      = "Pending",
		payload     = nil,
		receivedAt  = nil,
	}
end

-- Updates the status of a tracked request.
-- Warns and no-ops for unknown requestIds or invalid statuses.
function ServerAckControllerModule:ReceiveAck(
	requestId: string,
	status:    string,
	payload:   any
)
	if not VALID_STATUSES[status] then
		warn(("[ServerAckController] ReceiveAck: invalid status %q"):format(
			tostring(status)))
		return
	end
	local entry = _acks[requestId]
	if not entry then
		warn(("[ServerAckController] ReceiveAck: unknown requestId %q"):format(
			tostring(requestId)))
		return
	end
	entry.status     = status
	entry.payload    = payload
	entry.receivedAt = os.clock()
end

-- Returns the number of entries whose status is currently "Pending".
function ServerAckControllerModule:GetPendingCount(): number
	local count = 0
	for _, entry in pairs(_acks) do
		if entry.status == "Pending" then count += 1 end
	end
	return count
end

-- Returns a shallow copy of the ack entry for requestId, or nil if unknown.
function ServerAckControllerModule:GetAck(requestId: string): AckEntry?
	local entry = _acks[requestId]
	if not entry then return nil end
	return {
		requestId   = entry.requestId,
		requestType = entry.requestType,
		status      = entry.status,
		payload     = entry.payload,
		receivedAt  = entry.receivedAt,
	}
end

function ServerAckControllerModule:ClearAcks()
	table.clear(_acks)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ServerAckControllerModule:Init()
	if _initialized then
		warn("[ServerAckController] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_acks)

	print("[ServerAckController] ready")
end

function ServerAckControllerModule:Update(_dt: number) end

function ServerAckControllerModule:Destroy()
	table.clear(_acks)
	_initialized = false
end

return ServerAckControllerModule
