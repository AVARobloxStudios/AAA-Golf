--!strict
-- GameplayActionBridgeControllerModule — Client singleton (Sprint 21)
-- Domain-specific bridge for core gameplay actions (swing, hole-ready).
-- Validates payloads, then delegates to ClientActionControllerModule.QueueAction
-- so actions flow through the single Sprint 20 queue rather than being wired
-- to SwingController or InputController directly.
--
-- _queuedBridgeCount tracks how many actions THIS bridge has successfully
-- handed off to ClientActionController.  It is independent of other bridges.
-- ClearQueuedBridgeActions() resets only this bridge's counter — it does not
-- wipe ClientActionController's queue.
--
-- Payloads must be Luau tables; non-table values are rejected with a warning.
--
-- Public API
--   QueueSwingIntent(payload)       → string?   (actionId from CAC, nil if rejected)
--   QueueHoleReady(payload)         → string?
--   GetQueuedBridgeCount()          → number
--   ClearQueuedBridgeActions()      — reset bridge-local counter to 0
--
-- GameplayActionBridgeController.client.lua is the thin runner.

local CAC = require(script.Parent.ClientActionControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:        boolean = false
local _queuedBridgeCount:  number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local GameplayActionBridgeControllerModule = {}
GameplayActionBridgeControllerModule.__index = GameplayActionBridgeControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _requireTable(payload: any, methodName: string): boolean
	if type(payload) ~= "table" then
		warn(("[GameplayActionBridge] %s: payload must be a table, got %s"):format(
			methodName, type(payload)))
		return false
	end
	return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Queues a SwingIntent action.  payload must be a table (e.g. { power = 0.75 }).
function GameplayActionBridgeControllerModule:QueueSwingIntent(payload: any): string?
	if not _requireTable(payload, "QueueSwingIntent") then return nil end
	local actionId = CAC:QueueAction("SwingIntent", payload)
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

-- Queues a HoleReady action.  payload must be a table (may be empty: {}).
function GameplayActionBridgeControllerModule:QueueHoleReady(payload: any): string?
	if not _requireTable(payload, "QueueHoleReady") then return nil end
	local actionId = CAC:QueueAction("HoleReady", payload)
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

function GameplayActionBridgeControllerModule:GetQueuedBridgeCount(): number
	return _queuedBridgeCount
end

function GameplayActionBridgeControllerModule:ClearQueuedBridgeActions()
	_queuedBridgeCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function GameplayActionBridgeControllerModule:Init()
	if _initialized then
		warn("[GameplayActionBridge] Init called twice — skipping")
		return
	end
	_initialized       = true
	_queuedBridgeCount = 0

	print("[GameplayActionBridge] ready")
end

function GameplayActionBridgeControllerModule:Update(_dt: number) end

function GameplayActionBridgeControllerModule:Destroy()
	_queuedBridgeCount = 0
	_initialized       = false
end

return GameplayActionBridgeControllerModule
