--!strict
-- ShopActionBridgeControllerModule — Client singleton (Sprint 21)
-- Domain-specific bridge for shop and cosmetic actions.
-- Validates item IDs and cosmetic slot names, then delegates to
-- ClientActionControllerModule.QueueAction so all requests flow through the
-- single Sprint 20 action queue.
--
-- Valid cosmetic slots:
--   ClubSkin | BallSkin | BallTrail | Caddie | Nameplate | VictoryAnimation
--
-- Item IDs must be non-empty strings.
--
-- _queuedBridgeCount is local to this bridge and independent of other bridges.
-- ClearQueuedBridgeActions() resets only this bridge's counter.
--
-- Public API
--   OpenShop()                           → string?
--   PreviewItem(itemId)                  → string?   (nil if itemId invalid)
--   EquipCosmetic(slot, itemId)          → string?   (nil if slot or itemId invalid)
--   GetQueuedBridgeCount()               → number
--   ClearQueuedBridgeActions()           — reset bridge-local counter to 0
--
-- ShopActionBridgeController.client.lua is the thin runner.

local CAC = require(script.Parent.ClientActionControllerModule)

-- ── Constants ─────────────────────────────────────────────────────────────────

local VALID_SLOTS: { [string]: boolean } = {
	ClubSkin         = true,
	BallSkin         = true,
	BallTrail        = true,
	Caddie           = true,
	Nameplate        = true,
	VictoryAnimation = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:       boolean = false
local _queuedBridgeCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ShopActionBridgeControllerModule = {}
ShopActionBridgeControllerModule.__index = ShopActionBridgeControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _requireItemId(itemId: any, methodName: string): boolean
	if type(itemId) ~= "string" or itemId == "" then
		warn(("[ShopActionBridge] %s: itemId must be a non-empty string, got %s"):format(
			methodName, type(itemId)))
		return false
	end
	return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Queues an OpenShop action.
function ShopActionBridgeControllerModule:OpenShop(): string?
	local actionId = CAC:QueueAction("OpenShop", {})
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

-- Queues a PreviewItem action.
-- Warns and returns nil if itemId is not a non-empty string.
function ShopActionBridgeControllerModule:PreviewItem(itemId: any): string?
	if not _requireItemId(itemId, "PreviewItem") then return nil end
	local actionId = CAC:QueueAction("PreviewItem", { itemId = itemId })
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

-- Queues an EquipCosmetic action.
-- Warns and returns nil if slot is not in VALID_SLOTS or itemId is invalid.
function ShopActionBridgeControllerModule:EquipCosmetic(
	slot:   string,
	itemId: any
): string?
	if not VALID_SLOTS[slot] then
		warn(("[ShopActionBridge] EquipCosmetic: invalid slot %q"):format(tostring(slot)))
		return nil
	end
	if not _requireItemId(itemId, "EquipCosmetic") then return nil end
	local actionId = CAC:QueueAction("EquipCosmetic", { slot = slot, itemId = itemId })
	if actionId then _queuedBridgeCount += 1 end
	return actionId
end

function ShopActionBridgeControllerModule:GetQueuedBridgeCount(): number
	return _queuedBridgeCount
end

function ShopActionBridgeControllerModule:ClearQueuedBridgeActions()
	_queuedBridgeCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ShopActionBridgeControllerModule:Init()
	if _initialized then
		warn("[ShopActionBridge] Init called twice — skipping")
		return
	end
	_initialized       = true
	_queuedBridgeCount = 0

	print("[ShopActionBridge] ready")
end

function ShopActionBridgeControllerModule:Update(_dt: number) end

function ShopActionBridgeControllerModule:Destroy()
	_queuedBridgeCount = 0
	_initialized       = false
end

return ShopActionBridgeControllerModule
