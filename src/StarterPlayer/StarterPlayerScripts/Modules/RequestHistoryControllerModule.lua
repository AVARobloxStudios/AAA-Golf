--!strict
-- RequestHistoryControllerModule — Client singleton (Sprint 22)
-- Maintains a capped, ordered log of outbound request/action events.
-- Entries are appended via RecordRequest() and kept in insertion order
-- (oldest first).  When the log exceeds MAX_HISTORY (50), the oldest entry
-- is discarded to make room.
--
-- All retrieval methods return shallow copies so callers cannot mutate
-- internal state.
--
-- Public API
--   RecordRequest(requestId, requestType, payload) — append a new entry
--   GetHistory()              → { HistoryEntry }   (ordered copy, oldest first)
--   GetRequest(requestId)     → HistoryEntry?       (copy, or nil if unknown)
--   GetHistoryCount()         → number
--   ClearHistory()            — empty the log
--
-- RequestHistoryController.client.lua is the thin runner.

-- ── Constants ─────────────────────────────────────────────────────────────────

local MAX_HISTORY: number = 50

-- ── Types ─────────────────────────────────────────────────────────────────────

export type HistoryEntry = {
	requestId:   string,
	requestType: string,
	payload:     any,
	recordedAt:  number,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean          = false
local _history:     { HistoryEntry } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local RequestHistoryControllerModule = {}
RequestHistoryControllerModule.__index = RequestHistoryControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _copyEntry(e: HistoryEntry): HistoryEntry
	return {
		requestId   = e.requestId,
		requestType = e.requestType,
		payload     = e.payload,
		recordedAt  = e.recordedAt,
	}
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Appends a new entry to the history log.
-- Warns and no-ops for non-empty-string requestId or requestType.
-- Trims the oldest entry when MAX_HISTORY is exceeded.
function RequestHistoryControllerModule:RecordRequest(
	requestId:   any,
	requestType: any,
	payload:     any
)
	if type(requestId) ~= "string" or requestId == "" then
		warn("[RequestHistoryController] RecordRequest: requestId must be a non-empty string")
		return
	end
	if type(requestType) ~= "string" or requestType == "" then
		warn("[RequestHistoryController] RecordRequest: requestType must be a non-empty string")
		return
	end
	table.insert(_history, {
		requestId   = requestId,
		requestType = requestType,
		payload     = payload,
		recordedAt  = os.clock(),
	})
	if #_history > MAX_HISTORY then
		table.remove(_history, 1)
	end
end

-- Returns an ordered shallow copy of all history entries (oldest first).
function RequestHistoryControllerModule:GetHistory(): { HistoryEntry }
	local copy: { HistoryEntry } = {}
	for i, e in ipairs(_history) do
		copy[i] = _copyEntry(e)
	end
	return copy
end

-- Returns a shallow copy of the entry for requestId, or nil if not found.
function RequestHistoryControllerModule:GetRequest(requestId: string): HistoryEntry?
	for _, e in ipairs(_history) do
		if e.requestId == requestId then
			return _copyEntry(e)
		end
	end
	return nil
end

function RequestHistoryControllerModule:GetHistoryCount(): number
	return #_history
end

function RequestHistoryControllerModule:ClearHistory()
	table.clear(_history)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RequestHistoryControllerModule:Init()
	if _initialized then
		warn("[RequestHistoryController] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_history)

	print("[RequestHistoryController] ready")
end

function RequestHistoryControllerModule:Update(_dt: number) end

function RequestHistoryControllerModule:Destroy()
	table.clear(_history)
	_initialized = false
end

return RequestHistoryControllerModule
