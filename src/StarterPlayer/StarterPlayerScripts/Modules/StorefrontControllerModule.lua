--!strict
-- StorefrontControllerModule — Client singleton (Sprint 14)
-- Manages the local cosmetic item catalog.  Pure data module — no UI,
-- no GameBus connection, no inventory or currency changes.
--
-- Items are stored internally as a map keyed by itemId.  All public API
-- methods return deep copies so callers cannot mutate internal state.
--
-- Sort order for GetItems / GetItemsByCategory:
--   1. category  (alphabetical)
--   2. rarity    (Common < Rare < Epic < Legendary)
--   3. priceCoins (ascending)
--
-- Init() seeds a placeholder cosmetic catalog.
-- SetItems() replaces the entire catalog.
--
-- Public API
--   SetItems(items)              — replace catalog with given item array
--   GetItems()                   → { StoreItem }  (sorted copy)
--   GetItemsByCategory(cat)      → { StoreItem }  (sorted copy, filtered)
--   GetItem(itemId)              → StoreItem?      (copy)
--   ClearItems()                 — empty the catalog
--
-- StorefrontController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Rarity sort order ─────────────────────────────────────────────────────────

local RARITY_ORDER: { [string]: number } = {
	Common    = 1,
	Rare      = 2,
	Epic      = 3,
	Legendary = 4,
}

-- ── Type ─────────────────────────────────────────────────────────────────────

export type StoreItem = {
	itemId:      string,
	displayName: string,
	category:    string,
	rarity:      string,
	priceCoins:  number,
	premiumOnly: boolean,
}

-- ── Placeholder catalog (seeded on Init) ──────────────────────────────────────
-- Sprint 14: cosmetic-only items, no pay-to-win, visual presentation only.

local PLACEHOLDER_CATALOG: { StoreItem } = {
	-- Ball Skins
	{ itemId = "BALL_RAINBOW",    displayName = "Rainbow Ball",        category = "Ball Skins",         rarity = "Rare",      priceCoins = 250,  premiumOnly = false },
	{ itemId = "BALL_GOLD",       displayName = "Championship Ball",   category = "Ball Skins",         rarity = "Epic",      priceCoins = 500,  premiumOnly = false },
	{ itemId = "BALL_MIDNIGHT",   displayName = "Midnight Ball",       category = "Ball Skins",         rarity = "Common",    priceCoins = 100,  premiumOnly = false },
	-- Club Skins
	{ itemId = "CLUB_IRON_SKIN",  displayName = "Iron Club Skin",      category = "Club Skins",         rarity = "Common",    priceCoins = 150,  premiumOnly = false },
	{ itemId = "CLUB_GOLD_SKIN",  displayName = "Gold Club Skin",      category = "Club Skins",         rarity = "Epic",      priceCoins = 600,  premiumOnly = false },
	-- Trails
	{ itemId = "TRAIL_SPARKLE",   displayName = "Sparkle Trail",       category = "Trails",             rarity = "Epic",      priceCoins = 400,  premiumOnly = false },
	{ itemId = "TRAIL_FIRE",      displayName = "Flame Trail",         category = "Trails",             rarity = "Legendary", priceCoins = 900,  premiumOnly = false },
	-- Caddies
	{ itemId = "CADDIE_PRO",      displayName = "Pro Caddie",          category = "Caddies",            rarity = "Rare",      priceCoins = 300,  premiumOnly = false },
	{ itemId = "CADDIE_EAGLE",    displayName = "Eagle Caddie",        category = "Caddies",            rarity = "Legendary", priceCoins = 1200, premiumOnly = false },
	-- Nameplates
	{ itemId = "NAMEPLATE_FLAME", displayName = "Flame Nameplate",     category = "Nameplates",         rarity = "Epic",      priceCoins = 500,  premiumOnly = false },
	{ itemId = "NAMEPLATE_GOLD",  displayName = "Gold Nameplate",      category = "Nameplates",         rarity = "Legendary", priceCoins = 1000, premiumOnly = false },
	-- Victory Animations
	{ itemId = "VICTORY_EAGLE",   displayName = "Eagle Victory Dance", category = "Victory Animations", rarity = "Epic",      priceCoins = 600,  premiumOnly = false },
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                    = false
local _items:       { [string]: StoreItem }    = {}   -- itemId → item
local _connections: { RBXScriptConnection }    = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local StorefrontControllerModule = {}
StorefrontControllerModule.__index = StorefrontControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _copyItem(item: StoreItem): StoreItem
	return {
		itemId      = item.itemId,
		displayName = item.displayName,
		category    = item.category,
		rarity      = item.rarity,
		priceCoins  = item.priceCoins,
		premiumOnly = item.premiumOnly,
	}
end

local function _sortedItems(source: { StoreItem }): { StoreItem }
	local sorted: { StoreItem } = {}
	for _, item in ipairs(source) do
		table.insert(sorted, _copyItem(item))
	end
	table.sort(sorted, function(a: StoreItem, b: StoreItem): boolean
		if a.category ~= b.category then
			return a.category < b.category
		end
		local ra = RARITY_ORDER[a.rarity] or 0
		local rb = RARITY_ORDER[b.rarity] or 0
		if ra ~= rb then return ra < rb end
		return a.priceCoins < b.priceCoins
	end)
	return sorted
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Replaces the entire catalog with the provided item array.
-- Deep-copies each entry so the caller cannot retain a reference.
function StorefrontControllerModule:SetItems(items: { StoreItem })
	table.clear(_items)
	for _, item in ipairs(items) do
		_items[item.itemId] = _copyItem(item)
	end
end

-- Returns all catalog items as a sorted deep-copy array.
function StorefrontControllerModule:GetItems(): { StoreItem }
	local flat: { StoreItem } = {}
	for _, item in pairs(_items) do
		table.insert(flat, item)
	end
	return _sortedItems(flat)
end

-- Returns catalog items filtered by category, sorted.
function StorefrontControllerModule:GetItemsByCategory(categoryName: string): { StoreItem }
	local flat: { StoreItem } = {}
	for _, item in pairs(_items) do
		if item.category == categoryName then
			table.insert(flat, item)
		end
	end
	return _sortedItems(flat)
end

-- Returns a deep copy of a single item, or nil if not found.
function StorefrontControllerModule:GetItem(itemId: string): StoreItem?
	local item = _items[itemId]
	if not item then return nil end
	return _copyItem(item)
end

-- Empties the catalog.
function StorefrontControllerModule:ClearItems()
	table.clear(_items)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function StorefrontControllerModule:Init()
	if _initialized then
		warn("[StorefrontController] Init called twice — skipping")
		return
	end
	_initialized = true

	-- Seed placeholder catalog
	self:SetItems(PLACEHOLDER_CATALOG)

	print(("[StorefrontController] ready (player: %s) — %d items"):format(
		LocalPlayer.Name, #self:GetItems()))
end

function StorefrontControllerModule:Update(_dt: number) end

function StorefrontControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	table.clear(_items)
	_initialized = false
end

return StorefrontControllerModule
