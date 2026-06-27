--!strict
-- ActionDispatchControllerModule — Client singleton (Sprint 22)
-- Drains the ClientActionController queue by dispatching unsent actions
-- through RequestController.  Each action is wrapped in a GameBus envelope
-- { eventType, actionId, payload } and sent via
-- RequestController.SendRequest("GameBus", envelope).
--
-- Actions are NOT removed from ClientActionController — they are marked sent
-- via MarkActionSent() so the queue consumer can skip them on future passes.
-- No real server response is required for dispatch to be considered complete
-- on the client side.
--
-- Public API
--   DispatchAll()                — send every unsent action in CAC's queue
--   DispatchAction(actionId)     — send one specific action by ID
--   GetDispatchedCount()         → number  (cumulative; resets on Destroy)
--   ResetDispatchedCount()       — reset counter to 0
--
-- ActionDispatchController.client.lua is the thin runner.

local CAC = require(script.Parent.ClientActionControllerModule)
local RC  = require(script.Parent.RequestControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:     boolean = false
local _dispatchedCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ActionDispatchControllerModule = {}
ActionDispatchControllerModule.__index = ActionDispatchControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

-- Sends one unsent action entry through RequestController.
-- Returns true if dispatched, false if the entry was already sent.
local function _dispatchEntry(entry: any): boolean
	if entry.sent then return false end
	RC:SendRequest("GameBus", {
		eventType = entry.actionType,
		actionId  = entry.actionId,
		payload   = entry.payload,
	})
	CAC:MarkActionSent(entry.actionId)
	_dispatchedCount += 1
	return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Dispatches all unsent actions in CAC's queue.
-- Already-sent actions are silently skipped.
function ActionDispatchControllerModule:DispatchAll()
	if not _initialized then return end
	local actions = CAC:GetQueuedActions()
	for _, entry in ipairs(actions) do
		_dispatchEntry(entry)
	end
end

-- Dispatches a single action by actionId.
-- Warns and no-ops if actionId is not a non-empty string, is unknown, or
-- has already been sent.
function ActionDispatchControllerModule:DispatchAction(actionId: any)
	if not _initialized then return end
	if type(actionId) ~= "string" or actionId == "" then
		warn("[ActionDispatchController] DispatchAction: actionId must be a non-empty string")
		return
	end
	local actions = CAC:GetQueuedActions()
	for _, entry in ipairs(actions) do
		if entry.actionId == actionId then
			if entry.sent then
				warn(("[ActionDispatchController] DispatchAction: action %q already sent"):format(
					actionId))
			else
				_dispatchEntry(entry)
			end
			return
		end
	end
	warn(("[ActionDispatchController] DispatchAction: unknown actionId %q"):format(actionId))
end

function ActionDispatchControllerModule:GetDispatchedCount(): number
	return _dispatchedCount
end

function ActionDispatchControllerModule:ResetDispatchedCount()
	_dispatchedCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ActionDispatchControllerModule:Init()
	if _initialized then
		warn("[ActionDispatchController] Init called twice — skipping")
		return
	end
	_initialized     = true
	_dispatchedCount = 0

	print("[ActionDispatchController] ready")
end

function ActionDispatchControllerModule:Update(_dt: number) end

function ActionDispatchControllerModule:Destroy()
	_dispatchedCount = 0
	_initialized     = false
end

return ActionDispatchControllerModule
