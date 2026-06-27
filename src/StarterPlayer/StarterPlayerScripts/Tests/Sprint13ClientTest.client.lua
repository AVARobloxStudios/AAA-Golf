--!strict
-- Sprint13ClientTest — LocalScript
-- Client smoke tests for Sprint 13: InventoryController, CosmeticsController,
-- and UnlockController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads, so safeRequire()
-- returns already-initialised singletons (same pattern as Sprints 7–12).

print("[Sprint13ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint13ClientTest]"
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
-- Section 1 — InventoryControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local invOk, invResult = safeRequire(
	script.Parent.Parent.Modules.InventoryControllerModule)

if invOk then

	local ICM: any = invResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("ICM: module loads successfully", function()
		assert(type(ICM) == "table", "expected table, got " .. type(ICM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("ICM: HasItem('BALL_DEFAULT') true after Init (starter items seeded)", function()
		assert(ICM:HasItem("BALL_DEFAULT") == true,
			"expected BALL_DEFAULT to be owned as a starter item")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("ICM: HasItem('CLUB_DEFAULT') true after Init", function()
		assert(ICM:HasItem("CLUB_DEFAULT") == true, "expected CLUB_DEFAULT as starter")
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("ICM: HasItem for non-existent item returns false", function()
		assert(ICM:HasItem("BALL_RAINBOW") == false,
			"expected false for unowned item")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("ICM: GetOwnedItems returns at least 6 starter items", function()
		local items = ICM:GetOwnedItems()
		assert(type(items) == "table" and #items >= 6,
			("expected ≥6 starter items, got %d"):format(#items))
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("ICM: AddItem('BALL_RAINBOW') → HasItem true", function()
		ICM:AddItem("BALL_RAINBOW")
		assert(ICM:HasItem("BALL_RAINBOW") == true,
			"expected BALL_RAINBOW to be owned after AddItem")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("ICM: GetOwnedItems count increases after AddItem", function()
		local before = #ICM:GetOwnedItems()
		ICM:AddItem("TRAIL_SPARKLE")
		local after = #ICM:GetOwnedItems()
		assert(after == before + 1,
			("expected count %d, got %d"):format(before + 1, after))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("ICM: RemoveItem('BALL_RAINBOW') → HasItem false", function()
		ICM:RemoveItem("BALL_RAINBOW")
		assert(ICM:HasItem("BALL_RAINBOW") == false,
			"expected BALL_RAINBOW removed after RemoveItem")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("ICM: AddItem with empty string is rejected", function()
		local before = #ICM:GetOwnedItems()
		ICM:AddItem("")    -- should warn and do nothing
		assert(#ICM:GetOwnedItems() == before,
			"AddItem('') should not change inventory")
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("ICM: RemoveItem for non-owned item is a safe no-op", function()
		local before = #ICM:GetOwnedItems()
		ICM:RemoveItem("NEVER_ADDED_ITEM")
		assert(#ICM:GetOwnedItems() == before, "RemoveItem no-op should not throw")
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("ICM: AddItem is idempotent (double-add stays same count)", function()
		local before = #ICM:GetOwnedItems()
		ICM:AddItem("CLUB_GOLD")
		ICM:AddItem("CLUB_GOLD")   -- second call should not add a duplicate
		assert(#ICM:GetOwnedItems() == before + 1,
			"double AddItem should not duplicate the item")
		ICM:RemoveItem("CLUB_GOLD")
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("ICM: GetOwnedItems returns a copy (mutation does not affect internal)", function()
		local copy1 = ICM:GetOwnedItems()
		local origLen = #copy1
		table.clear(copy1)              -- wipe the returned copy
		local copy2 = ICM:GetOwnedItems()
		assert(#copy2 == origLen,
			"clearing the returned copy must not affect internal inventory")
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("ICM: ClearInventory removes all items", function()
		ICM:ClearInventory()
		assert(#ICM:GetOwnedItems() == 0, "expected empty inventory after ClearInventory")
		assert(ICM:HasItem("BALL_DEFAULT") == false,
			"starter items must also be cleared by ClearInventory")
	end)

	-- 13b ─────────────────────────────────────────────────────────────────
	check("ICM: Destroy resets all state", function()
		ICM:AddItem("TEMP_ITEM")
		ICM:Destroy()
		assert(#ICM:GetOwnedItems() == 0, "expected empty inventory after Destroy")
		assert(ICM:HasItem("TEMP_ITEM") == false, "expected item gone after Destroy")
	end)

	-- Restore the thin runner state (re-seeds starter items)
	ICM:Init()

	-- 14 ───────────────────────────────────────────────────────────────────
	check("ICM: starter items re-seeded after Init restore", function()
		assert(ICM:HasItem("BALL_DEFAULT") == true,
			"expected BALL_DEFAULT re-seeded after Init restore")
		assert(ICM:HasItem("CLUB_DEFAULT") == true,
			"expected CLUB_DEFAULT re-seeded after Init restore")
	end)

end -- invOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — CosmeticsControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local cosOk, cosResult = safeRequire(
	script.Parent.Parent.Modules.CosmeticsControllerModule)

if cosOk then

	local CCM: any = cosResult

	-- 15 ───────────────────────────────────────────────────────────────────
	check("CCM: module loads successfully", function()
		assert(type(CCM) == "table", "expected table, got " .. type(CCM))
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("CCM: GetEquipped('BallSkin') returns 'BALL_DEFAULT' initially", function()
		assert(CCM:GetEquipped("BallSkin") == "BALL_DEFAULT",
			("expected 'BALL_DEFAULT', got %q"):format(
				tostring(CCM:GetEquipped("BallSkin"))))
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("CCM: GetEquipped('ClubSkin') returns 'CLUB_DEFAULT' initially", function()
		assert(CCM:GetEquipped("ClubSkin") == "CLUB_DEFAULT",
			("expected 'CLUB_DEFAULT', got %q"):format(
				tostring(CCM:GetEquipped("ClubSkin"))))
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("CCM: GetAllEquipped returns all 6 slots", function()
		local all = CCM:GetAllEquipped()
		local count = 0
		for _ in pairs(all) do count += 1 end
		assert(count == 6, ("expected 6 slots, got %d"):format(count))
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("CCM: Equip('BallSkin', 'BALL_RAINBOW') updates GetEquipped", function()
		CCM:Equip("BallSkin", "BALL_RAINBOW")
		assert(CCM:GetEquipped("BallSkin") == "BALL_RAINBOW",
			("expected 'BALL_RAINBOW', got %q"):format(
				tostring(CCM:GetEquipped("BallSkin"))))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("CCM: Equip('BallTrail', 'TRAIL_SPARKLE') updates correct slot", function()
		CCM:Equip("BallTrail", "TRAIL_SPARKLE")
		assert(CCM:GetEquipped("BallTrail") == "TRAIL_SPARKLE",
			"expected BallTrail updated independently of BallSkin")
		-- BallSkin should still be BALL_RAINBOW
		assert(CCM:GetEquipped("BallSkin") == "BALL_RAINBOW",
			"BallSkin should be unchanged after equipping a different slot")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("CCM: Unequip('BallSkin') reverts to 'BALL_DEFAULT'", function()
		CCM:Unequip("BallSkin")
		assert(CCM:GetEquipped("BallSkin") == "BALL_DEFAULT",
			("expected default 'BALL_DEFAULT' after Unequip, got %q"):format(
				tostring(CCM:GetEquipped("BallSkin"))))
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("CCM: Equip with invalid slot is rejected (state unchanged)", function()
		local before = CCM:GetEquipped("BallSkin")
		CCM:Equip("InvalidSlot", "SOME_ITEM")
		-- GetEquipped of the invalid slot returns nil
		assert(CCM:GetEquipped("InvalidSlot") == nil,
			"expected nil for invalid slot")
		-- Other slots unaffected
		assert(CCM:GetEquipped("BallSkin") == before,
			"BallSkin should be unchanged after invalid Equip")
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("CCM: Equip with empty itemId is rejected", function()
		local before = CCM:GetEquipped("ClubSkin")
		CCM:Equip("ClubSkin", "")
		assert(CCM:GetEquipped("ClubSkin") == before,
			"ClubSkin should be unchanged after Equip with empty itemId")
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("CCM: GetAllEquipped returns a copy (mutation does not affect internal)", function()
		local copy = CCM:GetAllEquipped()
		copy["BallSkin"] = "MUTATION_TEST"
		assert(CCM:GetEquipped("BallSkin") ~= "MUTATION_TEST",
			"mutating the returned copy must not change internal equipped state")
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("CCM: all 6 valid slots accept Equip", function()
		local SLOTS = {
			"ClubSkin", "BallSkin", "BallTrail", "Caddie",
			"Nameplate", "VictoryAnimation",
		}
		for _, slot in ipairs(SLOTS) do
			CCM:Equip(slot, "TEST_" .. slot)
			assert(CCM:GetEquipped(slot) == "TEST_" .. slot,
				("Equip failed for slot %q"):format(slot))
		end
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("CCM: Destroy clears all equipped slots", function()
		CCM:Destroy()
		local all = CCM:GetAllEquipped()
		local count = 0
		for _ in pairs(all) do count += 1 end
		assert(count == 0, ("expected 0 slots after Destroy, got %d"):format(count))
	end)

	-- Restore
	CCM:Init()

	-- 27 ───────────────────────────────────────────────────────────────────
	check("CCM: defaults restored after Init and Equip works post-restore", function()
		assert(CCM:GetEquipped("BallSkin") == "BALL_DEFAULT",
			"expected BallSkin default after Init restore")
		CCM:Equip("Caddie", "CADDIE_PRO")
		assert(CCM:GetEquipped("Caddie") == "CADDIE_PRO",
			"Equip should work after Init restore")
	end)

end -- cosOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — UnlockControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local ucOk, ucResult = safeRequire(
	script.Parent.Parent.Modules.UnlockControllerModule)

if ucOk then

	local UCM: any = ucResult

	local ITEM_A: any = {
		itemId      = "BALL_RAINBOW",
		displayName = "Rainbow Ball",
		description = "Leaves a rainbow streak.",
		rarity      = "Rare",
	}
	local ITEM_B: any = {
		itemId      = "TRAIL_SPARKLE",
		displayName = "Sparkle Trail",
		description = "Glittery trail effect.",
		rarity      = "Epic",
	}
	local ITEM_C: any = {
		itemId      = "CADDIE_EAGLE",
		displayName = "Eagle Caddie",
		rarity      = "Legendary",
	}

	-- 28 ───────────────────────────────────────────────────────────────────
	check("UCM: module loads successfully", function()
		assert(type(UCM) == "table", "expected table, got " .. type(UCM))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("UCM: GetQueue returns empty table initially", function()
		local q = UCM:GetQueue()
		assert(type(q) == "table" and #q == 0,
			("expected empty queue, got length %d"):format(#q))
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("UCM: IsVisible is false initially", function()
		assert(UCM:IsVisible() == false, "unlock popup must start hidden")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("UCM: QueueUnlock adds one item to the queue", function()
		UCM:QueueUnlock(ITEM_A)
		assert(#UCM:GetQueue() == 1,
			("expected 1 item in queue, got %d"):format(#UCM:GetQueue()))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("UCM: QueueUnlock adds second item; queue has 2", function()
		UCM:QueueUnlock(ITEM_B)
		assert(#UCM:GetQueue() == 2,
			("expected 2 items, got %d"):format(#UCM:GetQueue()))
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("UCM: GetQueue returns a copy (mutation does not affect internal)", function()
		local copy = UCM:GetQueue()
		table.clear(copy)
		assert(#UCM:GetQueue() == 2,
			"clearing the returned copy must not empty the internal queue")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("UCM: ShowNextUnlock pops first item and sets IsVisible true", function()
		UCM:ShowNextUnlock()
		assert(UCM:IsVisible() == true, "expected visible after ShowNextUnlock")
		-- ITEM_A was first; it should be popped, leaving ITEM_B in queue
		assert(#UCM:GetQueue() == 1,
			("expected 1 item remaining in queue, got %d"):format(#UCM:GetQueue()))
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("UCM: ShowNextUnlock again pops second item; queue now empty", function()
		UCM:ShowNextUnlock()
		assert(UCM:IsVisible() == true, "expected visible for second item")
		assert(#UCM:GetQueue() == 0,
			("expected empty queue after second ShowNextUnlock, got %d"):format(
				#UCM:GetQueue()))
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("UCM: ShowNextUnlock on empty queue hides popup", function()
		UCM:ShowNextUnlock()   -- queue is empty → should hide
		assert(UCM:IsVisible() == false,
			"expected hidden when ShowNextUnlock called with empty queue")
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("UCM: QueueUnlock with invalid data is rejected", function()
		UCM:QueueUnlock({ itemId = "", displayName = "Bad" } :: any)
		assert(#UCM:GetQueue() == 0, "invalid QueueUnlock should not add to queue")
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("UCM: ClearQueue empties pending items", function()
		UCM:QueueUnlock(ITEM_A)
		UCM:QueueUnlock(ITEM_B)
		UCM:QueueUnlock(ITEM_C)
		assert(#UCM:GetQueue() == 3, "expected 3 before ClearQueue")
		UCM:ClearQueue()
		assert(#UCM:GetQueue() == 0, "expected 0 after ClearQueue")
	end)

	-- 39 ───────────────────────────────────────────────────────────────────
	check("UCM: Destroy resets all state", function()
		UCM:QueueUnlock(ITEM_A)
		UCM:ShowNextUnlock()   -- makes it visible
		UCM:Destroy()
		assert(UCM:IsVisible()   == false, "expected hidden after Destroy")
		assert(#UCM:GetQueue()   == 0,     "expected empty queue after Destroy")
	end)

	-- Restore the thin runner state
	UCM:Init()

	-- 40 ───────────────────────────────────────────────────────────────────
	check("UCM: QueueUnlock and ShowNextUnlock work after Init restore", function()
		UCM:QueueUnlock(ITEM_C)
		assert(#UCM:GetQueue() == 1, "should have 1 item after restore QueueUnlock")
		UCM:ShowNextUnlock()
		assert(UCM:IsVisible() == true,    "should be visible after restore ShowNextUnlock")
		assert(#UCM:GetQueue() == 0,       "queue should be empty after pop")
		UCM:ShowNextUnlock()               -- hide
		assert(UCM:IsVisible() == false,   "should be hidden when queue empty on restore")
	end)

end -- ucOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 13 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
