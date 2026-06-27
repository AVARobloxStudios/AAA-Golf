--!strict
return function()
-- Sprint14ClientTest — LocalScript
-- Client smoke tests for Sprint 14: ShopController, StorefrontController,
-- and PurchasePreviewController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.  Tests drive
-- each module via its public API.  No live purchase, no real golf round.

print("[Sprint14ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint14ClientTest]"
local passed = 0
local failed = 0

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(TAG .. " PASS: " .. label)
	else
		failed += 1
		warn(TAG .. " FAIL: " .. label .. " — " .. tostring(err))
	end
end

local function safeRequire(path: Instance): (boolean, any)
	local ok, result = pcall(require, path :: any)
	if not ok then
		warn(TAG .. " FATAL: require failed — " .. tostring(result))
	end
	return ok, result
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — ShopControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local shOk, shResult = safeRequire(
	script.Parent.Parent.Modules.ShopControllerModule)

if shOk then

	local SCM: any = shResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("SCM: module loads successfully", function()
		assert(type(SCM) == "table", "expected table, got " .. type(SCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("SCM: IsVisible is false initially", function()
		assert(SCM:IsVisible() == false, "shop must start hidden")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("SCM: GetActiveCategory returns 'Ball Skins' by default", function()
		assert(SCM:GetActiveCategory() == "Ball Skins",
			("expected 'Ball Skins', got %q"):format(SCM:GetActiveCategory()))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("SCM: GetCategories returns 6 categories", function()
		local cats = SCM:GetCategories()
		assert(type(cats) == "table" and #cats == 6,
			("expected 6 categories, got %d"):format(#cats))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("SCM: GetCategories includes all expected categories", function()
		local cats = SCM:GetCategories()
		local set: { [string]: boolean } = {}
		for _, c in ipairs(cats) do set[c] = true end
		assert(set["Ball Skins"]         == true, "missing Ball Skins")
		assert(set["Club Skins"]         == true, "missing Club Skins")
		assert(set["Trails"]             == true, "missing Trails")
		assert(set["Caddies"]            == true, "missing Caddies")
		assert(set["Nameplates"]         == true, "missing Nameplates")
		assert(set["Victory Animations"] == true, "missing Victory Animations")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("SCM: GetCategories returns a copy (mutation does not affect internal)", function()
		local copy = SCM:GetCategories()
		local origLen = #copy
		table.clear(copy)
		assert(#SCM:GetCategories() == origLen,
			"clearing the returned copy must not affect internal category list")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("SCM: OpenShop sets IsVisible true", function()
		SCM:OpenShop()
		assert(SCM:IsVisible() == true, "expected visible after OpenShop")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("SCM: CloseShop sets IsVisible false", function()
		SCM:CloseShop()
		assert(SCM:IsVisible() == false, "expected hidden after CloseShop")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("SCM: SetActiveCategory('Trails') updates GetActiveCategory", function()
		SCM:SetActiveCategory("Trails")
		assert(SCM:GetActiveCategory() == "Trails",
			("expected 'Trails', got %q"):format(SCM:GetActiveCategory()))
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("SCM: SetActiveCategory with invalid name is rejected", function()
		local before = SCM:GetActiveCategory()
		SCM:SetActiveCategory("Hats")   -- not a valid category
		assert(SCM:GetActiveCategory() == before,
			"invalid SetActiveCategory should leave category unchanged")
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("SCM: all 6 valid categories accepted by SetActiveCategory", function()
		local CATS = {
			"Ball Skins", "Club Skins", "Trails",
			"Caddies", "Nameplates", "Victory Animations",
		}
		for _, cat in ipairs(CATS) do
			SCM:SetActiveCategory(cat)
			assert(SCM:GetActiveCategory() == cat,
				("SetActiveCategory failed for %q"):format(cat))
		end
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("SCM: OpenShop / CloseShop toggle correctly", function()
		SCM:OpenShop()
		assert(SCM:IsVisible() == true,  "expected open after OpenShop")
		SCM:CloseShop()
		assert(SCM:IsVisible() == false, "expected closed after CloseShop")
		SCM:OpenShop()
		assert(SCM:IsVisible() == true,  "expected re-opened")
		SCM:CloseShop()
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("SCM: Destroy resets all state", function()
		SCM:OpenShop()
		SCM:SetActiveCategory("Caddies")
		SCM:Destroy()
		assert(SCM:IsVisible()        == false, "expected hidden after Destroy")
		assert(SCM:GetActiveCategory() == "",    "expected empty category after Destroy")
	end)

	-- Restore
	SCM:Init()

	-- 14 ───────────────────────────────────────────────────────────────────
	check("SCM: defaults restored after Init and OpenShop works", function()
		assert(SCM:GetActiveCategory() == "Ball Skins",
			"expected 'Ball Skins' as default after re-Init")
		SCM:OpenShop()
		assert(SCM:IsVisible() == true,  "OpenShop should work after re-Init")
		SCM:CloseShop()
	end)

end -- shOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — StorefrontControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local sfOk, sfResult = safeRequire(
	script.Parent.Parent.Modules.StorefrontControllerModule)

if sfOk then

	local SFC: any = sfResult

	-- 15 ───────────────────────────────────────────────────────────────────
	check("SFC: module loads successfully", function()
		assert(type(SFC) == "table", "expected table, got " .. type(SFC))
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItems returns placeholder catalog (≥10 items)", function()
		local items = SFC:GetItems()
		assert(type(items) == "table" and #items >= 10,
			("expected ≥10 placeholder items, got %d"):format(#items))
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItem('BALL_RAINBOW') returns correct data", function()
		local item = SFC:GetItem("BALL_RAINBOW")
		assert(item ~= nil,                            "expected BALL_RAINBOW to exist")
		assert(item.displayName == "Rainbow Ball",     "wrong displayName")
		assert(item.category    == "Ball Skins",       "wrong category")
		assert(item.rarity      == "Rare",             "wrong rarity")
		assert(item.priceCoins  == 250,                "wrong priceCoins")
		assert(item.premiumOnly == false,              "expected premiumOnly=false")
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItem for unknown itemId returns nil", function()
		assert(SFC:GetItem("NONEXISTENT_ITEM") == nil,
			"expected nil for unknown item")
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItemsByCategory('Ball Skins') returns only Ball Skins", function()
		local balls = SFC:GetItemsByCategory("Ball Skins")
		assert(#balls >= 1, "expected at least 1 Ball Skin item")
		for _, item in ipairs(balls) do
			assert(item.category == "Ball Skins",
				("expected Ball Skins category, got %q"):format(item.category))
		end
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItemsByCategory for unknown category returns empty table", function()
		local result = SFC:GetItemsByCategory("HatsAndWigs")
		assert(type(result) == "table" and #result == 0,
			("expected empty, got %d items"):format(#result))
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItems first item is Ball Skin (alphabetical category order)", function()
		local items = SFC:GetItems()
		-- "Ball Skins" sorts before all other category names alphabetically
		assert(items[1].category == "Ball Skins",
			("expected first item in Ball Skins, got %q"):format(items[1].category))
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("SFC: within Ball Skins, Common < Rare < Epic by rarity sort", function()
		local balls = SFC:GetItemsByCategory("Ball Skins")
		-- BALL_MIDNIGHT (Common) < BALL_RAINBOW (Rare) < BALL_GOLD (Epic)
		local found: { [string]: number } = {}
		for i, item in ipairs(balls) do
			found[item.itemId] = i
		end
		assert((found["BALL_MIDNIGHT"] or 99) < (found["BALL_RAINBOW"] or 99),
			"Common ball should sort before Rare ball")
		assert((found["BALL_RAINBOW"]  or 99) < (found["BALL_GOLD"]    or 99),
			"Rare ball should sort before Epic ball")
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItems returns a copy (item mutation does not affect catalog)", function()
		local copy = SFC:GetItems()
		copy[1].displayName = "MUTATED"
		local fresh = SFC:GetItems()
		assert(fresh[1].displayName ~= "MUTATED",
			"mutating returned item must not change internal catalog")
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("SFC: GetItem returns a copy (mutation does not affect catalog)", function()
		local copy = SFC:GetItem("BALL_RAINBOW")
		assert(copy ~= nil, "expected BALL_RAINBOW")
		copy.priceCoins = 99999
		local fresh = SFC:GetItem("BALL_RAINBOW")
		assert(fresh ~= nil and fresh.priceCoins == 250,
			"mutating returned item must not change internal price")
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("SFC: SetItems replaces catalog", function()
		SFC:SetItems({
			{ itemId = "TEST_A", displayName = "Test A", category = "Trails",
			  rarity = "Common", priceCoins = 99, premiumOnly = false },
		})
		local items = SFC:GetItems()
		assert(#items == 1, ("expected 1 item after SetItems, got %d"):format(#items))
		assert(items[1].itemId == "TEST_A", "expected TEST_A")
		assert(SFC:GetItem("BALL_RAINBOW") == nil,
			"old items should be gone after SetItems")
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("SFC: ClearItems empties the catalog", function()
		SFC:ClearItems()
		assert(#SFC:GetItems() == 0, "expected empty catalog after ClearItems")
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("SFC: Destroy resets catalog", function()
		SFC:Destroy()
		assert(#SFC:GetItems() == 0, "expected empty catalog after Destroy")
	end)

	-- Restore (re-seeds placeholder catalog)
	SFC:Init()

	-- 27b ─────────────────────────────────────────────────────────────────
	check("SFC: placeholder catalog re-seeded after Init restore", function()
		local items = SFC:GetItems()
		assert(#items >= 10, ("expected ≥10 items after re-Init, got %d"):format(#items))
		assert(SFC:GetItem("BALL_RAINBOW") ~= nil, "BALL_RAINBOW should be back")
	end)

end -- sfOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — PurchasePreviewControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local ppOk, ppResult = safeRequire(
	script.Parent.Parent.Modules.PurchasePreviewControllerModule)

if ppOk then

	local PPC: any = ppResult

	local TEST_ITEM: any = {
		itemId      = "TRAIL_SPARKLE",
		displayName = "Sparkle Trail",
		category    = "Trails",
		rarity      = "Epic",
		priceCoins  = 400,
		premiumOnly = false,
	}

	-- 28 ───────────────────────────────────────────────────────────────────
	check("PPC: module loads successfully", function()
		assert(type(PPC) == "table", "expected table, got " .. type(PPC))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("PPC: IsPreviewing is false initially", function()
		assert(PPC:IsPreviewing() == false, "should not be previewing initially")
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("PPC: GetPreviewItem is nil initially", function()
		assert(PPC:GetPreviewItem() == nil, "expected nil preview item initially")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("PPC: PreviewItem sets IsPreviewing true", function()
		PPC:PreviewItem(TEST_ITEM)
		assert(PPC:IsPreviewing() == true, "expected IsPreviewing true after PreviewItem")
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("PPC: GetPreviewItem returns correct itemId", function()
		local item = PPC:GetPreviewItem()
		assert(item ~= nil and item.itemId == "TRAIL_SPARKLE",
			("expected 'TRAIL_SPARKLE', got %s"):format(tostring(item and item.itemId)))
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("PPC: GetPreviewItem returns all correct fields", function()
		local item = PPC:GetPreviewItem()
		assert(item ~= nil,                         "expected item to exist")
		assert(item.displayName == "Sparkle Trail", "wrong displayName")
		assert(item.category    == "Trails",        "wrong category")
		assert(item.rarity      == "Epic",           "wrong rarity")
		assert(item.priceCoins  == 400,             "wrong priceCoins")
		assert(item.premiumOnly == false,            "wrong premiumOnly")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("PPC: GetPreviewItem returns a copy (mutation does not affect internal)", function()
		local copy = PPC:GetPreviewItem()
		assert(copy ~= nil, "expected copy to exist")
		copy.priceCoins = 99999
		local fresh = PPC:GetPreviewItem()
		assert(fresh ~= nil and fresh.priceCoins == 400,
			"mutating returned copy must not change internal preview item")
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("PPC: ClearPreview sets IsPreviewing false", function()
		PPC:ClearPreview()
		assert(PPC:IsPreviewing() == false, "expected IsPreviewing false after ClearPreview")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("PPC: GetPreviewItem is nil after ClearPreview", function()
		assert(PPC:GetPreviewItem() == nil, "expected nil after ClearPreview")
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("PPC: PreviewItem with invalid data is rejected", function()
		PPC:PreviewItem({ itemId = "", displayName = "Bad" } :: any)
		assert(PPC:IsPreviewing() == false, "invalid PreviewItem should not set previewing")
		assert(PPC:GetPreviewItem() == nil,  "expected nil after invalid PreviewItem")
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("PPC: Destroy resets all state", function()
		PPC:PreviewItem(TEST_ITEM)
		PPC:Destroy()
		assert(PPC:IsPreviewing()    == false, "expected not previewing after Destroy")
		assert(PPC:GetPreviewItem()  == nil,   "expected nil preview after Destroy")
	end)

	-- Restore
	PPC:Init()

	-- 39 ───────────────────────────────────────────────────────────────────
	check("PPC: PreviewItem and ClearPreview work after Init restore", function()
		PPC:PreviewItem(TEST_ITEM)
		assert(PPC:IsPreviewing() == true, "should be previewing after restore PreviewItem")
		local item = PPC:GetPreviewItem()
		assert(item ~= nil and item.itemId == "TRAIL_SPARKLE",
			"should return correct item after restore")
		PPC:ClearPreview()
		assert(PPC:IsPreviewing() == false, "should not be previewing after ClearPreview")
	end)

end -- ppOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 14 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
end
