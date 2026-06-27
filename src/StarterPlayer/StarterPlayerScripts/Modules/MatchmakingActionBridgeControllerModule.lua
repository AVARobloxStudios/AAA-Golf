--!strict
-- MatchmakingActionBridgeControllerModule — Client singleton (Sprint 21)
-- Domain-specific bridge for matchmaking lifecycle actions.
-- Validates the matchmaking mode name, then delegates to
-- ClientActionControllerModule.QueueAction so all requests flow through the
-- single Sprint 20 action queue.
--
-- Valid matchmaking modes: Solo | Duo | Squad | Private
--
-- _queuedBridgeCount is local to this bridge and independent of other bridges.
-- ClearQueuedBridgeActions() resets only this bridge's counter.
--
-- Public API
--   QueueMatchmaking(modeName)      → string?   (actionId, nil if invalid mode)
--   CancelMatchmaking()             → string?
--   SetReady(isReady)               → string?
--   GetQueuedBridgeCount()          → number
--   ClearQueuedBridgeActions()      — reset bridge-local counter to 0
--
-- MatchmakingActionBridgeController.client.lua is the thin runner.

local CAC = require(script.Parent.ClientActionControllerModule)

-- ── Constants ─────────────────────────────────────────────────────────────────

local VALID_MODES: { [string]: boolean } = {
	Solo    = true,
	Duo     = true,
	Squad   = true,
	Private = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:       boolean = false
local _queuedBridgeCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local MatchmakingActionBridgeControllerModule = {}
MatchmakingActionBridgeControllerModule.__index = MatchmakingActionBridgeControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Queues a QueueMatchmaking action for the given mode.
-- Warns and returns nil if modeName is not a valid mode.
function MatchmakingActionBridgeControllerModule:QueueMatchmaking(
	modeName: string
): string?
	if not VALID_MODES[modeName] then
		warn(("[MatchmakingActionBridge] QueueMatchmaking: invalid mode %q"):format(
			tostring(modeName)))
		return nil
	end
	local actionId = CAC:QueueAction("QueueMatchmaking", { mode = modeName })
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

-- Queues a CancelMatchmaking action.
function MatchmakingActionBridgeControllerModule:CancelMatchmaking(): string?
	local actionId = CAC:QueueAction("CancelMatchmaking", {})
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

-- Queues a SetReady action with the given readiness state.
function MatchmakingActionBridgeControllerModule:SetReady(isReady: boolean): string?
	local actionId = CAC:QueueAction("SetReady", { isReady = isReady })
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

function MatchmakingActionBridgeControllerModule:GetQueuedBridgeCount(): number
	return _queuedBridgeCount
end

function MatchmakingActionBridgeControllerModule:ClearQueuedBridgeActions()
	_queuedBridgeCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function MatchmakingActionBridgeControllerModule:Init()
	if _initialized then
		warn("[MatchmakingActionBridge] Init called twice — skipping")
		return
	end
	_initialized       = true
	_queuedBridgeCount = 0

	print("[MatchmakingActionBridge] ready")
end

function MatchmakingActionBridgeControllerModule:Update(_dt: number) end

function MatchmakingActionBridgeControllerModule:Destroy()
	_queuedBridgeCount = 0
	_initialized       = false
end

return MatchmakingActionBridgeControllerModule
