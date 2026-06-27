--!strict
-- CosmeticsControllerModule — Client singleton (Sprint 13)
-- Manages which cosmetic item is equipped in each cosmetic slot.  Pure state
-- module — no UI, no GameBus connection.  Actual avatar model attachment
-- is a future sprint.
--
-- Cosmetics affect visual presentation only — this module never touches
-- power, aim, club physics, score, XP, or coins.
--
-- Ownership enforcement (InventoryController.HasItem) is the caller's
-- responsibility to avoid a circular-dependency between the two modules.
-- CosmeticsController only validates the slot name and item ID format.
--
-- Cosmetic slots
--   ClubSkin · BallSkin · BallTrail · Caddie · Nameplate · VictoryAnimation
--
-- Public API
--   Equip(slot, itemId)        — equip itemId in slot; rejects invalid slot/id
--   Unequip(slot)              — revert slot to its default item
--   GetEquipped(slot)          → string?  (nil if slot is invalid)
--   GetAllEquipped()           → { [string]: string }  (copy of all slots)
--
-- CosmeticsController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Cosmetic slot catalogue ───────────────────────────────────────────────────

local VALID_SLOTS: { [string]: boolean } = {
	ClubSkin         = true,
	BallSkin         = true,
	BallTrail        = true,
	Caddie           = true,
	Nameplate        = true,
	VictoryAnimation = true,
}

-- Default items — must match the STARTER_ITEMS in InventoryControllerModule.
local DEFAULT_EQUIPPED: { [string]: string } = {
	ClubSkin         = "CLUB_DEFAULT",
	BallSkin         = "BALL_DEFAULT",
	BallTrail        = "TRAIL_NONE",
	Caddie           = "CADDIE_NONE",
	Nameplate        = "NAMEPLATE_DEFAULT",
	VictoryAnimation = "VICTORY_DEFAULT",
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                 = false
local _equipped:    { [string]: string }    = {}   -- slot → itemId
local _connections: { RBXScriptConnection } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local CosmeticsControllerModule = {}
CosmeticsControllerModule.__index = CosmeticsControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _isValidSlot(slot: string): boolean
	return VALID_SLOTS[slot] == true
end

local function _isValidItemId(itemId: string): boolean
	return type(itemId) == "string" and itemId ~= ""
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Equip itemId in the given slot.
-- Warns and returns without changing state for invalid slot or item ID.
function CosmeticsControllerModule:Equip(slot: string, itemId: string)
	if not _isValidSlot(slot) then
		warn(("[CosmeticsController] Equip: unknown slot %q — ignored"):format(
			tostring(slot)))
		return
	end
	if not _isValidItemId(itemId) then
		warn(("[CosmeticsController] Equip: invalid itemId %s — ignored"):format(
			tostring(itemId)))
		return
	end
	_equipped[slot] = itemId
	print(("[CosmeticsController] %s → %q"):format(slot, itemId))
end

-- Revert slot to its default item.
-- Warns for invalid slots but is otherwise a no-op.
function CosmeticsControllerModule:Unequip(slot: string)
	if not _isValidSlot(slot) then
		warn(("[CosmeticsController] Unequip: unknown slot %q — ignored"):format(
			tostring(slot)))
		return
	end
	_equipped[slot] = DEFAULT_EQUIPPED[slot]
	print(("[CosmeticsController] unequipped %s → %q"):format(
		slot, _equipped[slot]))
end

-- Returns the currently equipped item ID for the slot, or nil for invalid slots.
function CosmeticsControllerModule:GetEquipped(slot: string): string?
	if not _isValidSlot(slot) then return nil end
	return _equipped[slot]
end

-- Returns a shallow copy of the full slot→itemId map.
function CosmeticsControllerModule:GetAllEquipped(): { [string]: string }
	local copy: { [string]: string } = {}
	for slot, itemId in pairs(_equipped) do
		copy[slot] = itemId
	end
	return copy
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function CosmeticsControllerModule:Init()
	if _initialized then
		warn("[CosmeticsController] Init called twice — skipping")
		return
	end
	_initialized = true

	-- Populate all slots with their defaults
	for slot, defaultId in pairs(DEFAULT_EQUIPPED) do
		_equipped[slot] = defaultId
	end

	print(("[CosmeticsController] ready (player: %s)"):format(LocalPlayer.Name))
end

function CosmeticsControllerModule:Update(_dt: number) end

function CosmeticsControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	table.clear(_equipped)
	_initialized = false
end

return CosmeticsControllerModule
