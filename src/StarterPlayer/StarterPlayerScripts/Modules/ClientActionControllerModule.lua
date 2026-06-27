--!strict
-- ClientActionControllerModule — Client singleton (Sprint 20)
-- Maintains a local queue of pending client action requests before they are
-- sent to the server.  This is a pure-state preparation layer — it does not
-- fire any remotes.  Future sprints will drain the queue via RequestController.
--
-- Each action gets a unique session-scoped ID generated from an incrementing
-- counter.  GetQueuedActions() and GetAck() return shallow copies so callers
-- cannot accidentally mutate internal state.
--
-- Valid action types (VS §05 and gameplay spec):
--   SwingIntent, HoleReady, QueueMatchmaking, CancelMatchmaking,
--   OpenShop, PreviewItem, EquipCosmetic, SetReady
--
-- Public API
--   QueueAction(actionType, payload) → string?   (actionId, nil if invalid type)
--   GetQueuedActions()               → { ActionEntry }   (array copy)
--   GetActionCount()                 → number
--   ClearActions()                   — remove all queued actions
--   MarkActionSent(actionId)         — mark an action as dispatched
--   IsActionSent(actionId)           → boolean
--
-- ClientActionController.client.lua is the thin runner.

-- ── Types ─────────────────────────────────────────────────────────────────────

export type ActionEntry = {
	actionId:   string,
	actionType: string,
	payload:    any,
	timestamp:  number,
	sent:       boolean,
}

-- ── Constants ─────────────────────────────────────────────────────────────────

local VALID_ACTION_TYPES: { [string]: boolean } = {
	SwingIntent       = true,
	HoleReady         = true,
	QueueMatchmaking  = true,
	CancelMatchmaking = true,
	OpenShop          = true,
	PreviewItem       = true,
	EquipCosmetic     = true,
	SetReady          = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:     boolean                   = false
local _actions:         { [string]: ActionEntry } = {}
local _actionIdCounter: number                    = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ClientActionControllerModule = {}
ClientActionControllerModule.__index = ClientActionControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Adds a new action to the queue. Returns the new actionId, or nil if
-- actionType is not in VALID_ACTION_TYPES.
function ClientActionControllerModule:QueueAction(
	actionType: string,
	payload:    any
): string?
	if not VALID_ACTION_TYPES[actionType] then
		warn(("[ClientActionController] QueueAction: invalid actionType %q"):format(
			tostring(actionType)))
		return nil
	end
	_actionIdCounter += 1
	local actionId = ("action_%d"):format(_actionIdCounter)
	_actions[actionId] = {
		actionId   = actionId,
		actionType = actionType,
		payload    = payload,
		timestamp  = os.clock(),
		sent       = false,
	}
	return actionId
end

-- Returns a shallow copy of all queued actions.
-- Callers may read but must not write to the returned table to affect state.
function ClientActionControllerModule:GetQueuedActions(): { ActionEntry }
	local copy: { ActionEntry } = {}
	for _, entry in pairs(_actions) do
		table.insert(copy, {
			actionId   = entry.actionId,
			actionType = entry.actionType,
			payload    = entry.payload,
			timestamp  = entry.timestamp,
			sent       = entry.sent,
		})
	end
	return copy
end

function ClientActionControllerModule:GetActionCount(): number
	local count = 0
	for _ in pairs(_actions) do count += 1 end
	return count
end

function ClientActionControllerModule:ClearActions()
	table.clear(_actions)
end

-- Marks an action as sent so the queue consumer can skip it.
-- Warns if actionId is unknown.
function ClientActionControllerModule:MarkActionSent(actionId: string)
	local entry = _actions[actionId]
	if not entry then
		warn(("[ClientActionController] MarkActionSent: unknown actionId %q"):format(
			tostring(actionId)))
		return
	end
	entry.sent = true
end

function ClientActionControllerModule:IsActionSent(actionId: string): boolean
	local entry = _actions[actionId]
	if not entry then return false end
	return entry.sent
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ClientActionControllerModule:Init()
	if _initialized then
		warn("[ClientActionController] Init called twice — skipping")
		return
	end
	_initialized     = true
	_actionIdCounter = 0
	table.clear(_actions)

	print("[ClientActionController] ready")
end

function ClientActionControllerModule:Update(_dt: number) end

function ClientActionControllerModule:Destroy()
	table.clear(_actions)
	_actionIdCounter = 0
	_initialized     = false
end

return ClientActionControllerModule
