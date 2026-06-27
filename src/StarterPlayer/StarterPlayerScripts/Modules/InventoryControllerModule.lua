--!strict
-- InventoryControllerModule — Client singleton (Sprint 13)
-- Tracks owned cosmetic item IDs locally.  Pure state module — no UI, no
-- GameBus connection.  Server DataStore persistence is a future sprint.
--
-- Cosmetics affect visual presentation only — this module never touches
-- power, aim, club physics, score, XP, or coins.
--
-- The module is seeded with STARTER_ITEMS on every Init() so the player
-- always owns the default cosmetics.
--
-- Public API
--   AddItem(itemId)         — add an item; rejects nil/non-string/empty
--   RemoveItem(itemId)      — remove an item; no-op if not owned
--   HasItem(itemId)         → boolean
--   GetOwnedItems()         → { string }  (unordered copy)
--   ClearInventory()        — remove all items including starters
--
-- InventoryController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Default starter cosmetics ─────────────────────────────────────────────────

-- These item IDs must match the defaults used by CosmeticsControllerModule.
local STARTER_ITEMS: { string } = {
	"BALL_DEFAULT",
	"CLUB_DEFAULT",
	"TRAIL_NONE",
	"CADDIE_NONE",
	"NAMEPLATE_DEFAULT",
	"VICTORY_DEFAULT",
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                = false
local _ownedItems:  { [string]: boolean }  = {}
local _connections: { RBXScriptConnection } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local InventoryControllerModule = {}
InventoryControllerModule.__index = InventoryControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Adds itemId to the owned set.
-- Rejects nil, non-string, and empty-string IDs with a warning.
function InventoryControllerModule:AddItem(itemId: string)
	if type(itemId) ~= "string" or itemId == "" then
		warn(("[InventoryController] AddItem: invalid itemId %s — ignored"):format(
			tostring(itemId)))
		return
	end
	_ownedItems[itemId] = true
	print(("[InventoryController] added %q (total: %d)"):format(
		itemId, #self:GetOwnedItems()))
end

-- Removes itemId from the owned set.  No-op if the item is not owned.
function InventoryControllerModule:RemoveItem(itemId: string)
	if type(itemId) ~= "string" or itemId == "" then
		warn(("[InventoryController] RemoveItem: invalid itemId %s — ignored"):format(
			tostring(itemId)))
		return
	end
	_ownedItems[itemId] = nil
end

function InventoryControllerModule:HasItem(itemId: string): boolean
	if type(itemId) ~= "string" then return false end
	return _ownedItems[itemId] == true
end

-- Returns an unordered array copy of owned item IDs.
function InventoryControllerModule:GetOwnedItems(): { string }
	local copy: { string } = {}
	for id in pairs(_ownedItems) do
		table.insert(copy, id)
	end
	return copy
end

-- Removes all items including starters.  Call Init() to re-seed.
function InventoryControllerModule:ClearInventory()
	table.clear(_ownedItems)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function InventoryControllerModule:Init()
	if _initialized then
		warn("[InventoryController] Init called twice — skipping")
		return
	end
	_initialized = true

	-- Seed default cosmetics so the player always starts with usable items
	for _, id in ipairs(STARTER_ITEMS) do
		_ownedItems[id] = true
	end

	print(("[InventoryController] ready (player: %s) — %d starter items"):format(
		LocalPlayer.Name, #STARTER_ITEMS))
end

function InventoryControllerModule:Update(_dt: number) end

function InventoryControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	table.clear(_ownedItems)
	_initialized = false
end

return InventoryControllerModule
