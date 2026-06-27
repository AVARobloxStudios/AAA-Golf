--!strict
return function()
-- Sprint21ClientTest — LocalScript
-- Client smoke tests for Sprint 21: GameplayActionBridgeController,
-- MatchmakingActionBridgeController, and ShopActionBridgeController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.
-- No real round or real server response required.
-- All bridge modules delegate to ClientActionControllerModule which is
-- verified at the end of each section.

print("[Sprint21ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint21ClientTest]"
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

-- Pre-load CAC so we can confirm actions are enqueued there.
local cacOk, cacResult = safeRequire(
	script.Parent.Parent.Modules.ClientActionControllerModule)

local CAC: any = cacResult

-- Baseline: clear CAC so each section starts with a known count.
if cacOk then CAC:ClearActions() end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — GameplayActionBridgeControllerModule  (checks 1–12)
-- ════════════════════════════════════════════════════════════════════════════

local gabOk, gabResult = safeRequire(
	script.Parent.Parent.Modules.GameplayActionBridgeControllerModule)

if gabOk and cacOk then

	local GAB: any = gabResult
	CAC:ClearActions()

	-- 1 ────────────────────────────────────────────────────────────────────
	check("GAB: module loads successfully", function()
		assert(type(GAB) == "table", "expected table, got " .. type(GAB))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("GAB: GetQueuedBridgeCount() is 0 initially", function()
		assert(GAB:GetQueuedBridgeCount() == 0,
			("expected 0, got %d"):format(GAB:GetQueuedBridgeCount()))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	local swingId: string = ""
	check("GAB: QueueSwingIntent with valid table payload returns actionId", function()
		local id = GAB:QueueSwingIntent({ power = 0.8, angle = 15 })
		assert(type(id) == "string" and id ~= "",
			"expected non-empty string actionId")
		swingId = id :: string
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("GAB: GetQueuedBridgeCount() is 1 after QueueSwingIntent", function()
		assert(GAB:GetQueuedBridgeCount() == 1,
			("expected 1, got %d"):format(GAB:GetQueuedBridgeCount()))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	local holeId: string = ""
	check("GAB: QueueHoleReady with valid table payload returns actionId", function()
		local id = GAB:QueueHoleReady({})
		assert(type(id) == "string" and id ~= "",
			"expected non-empty string actionId")
		holeId = id :: string
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("GAB: GetQueuedBridgeCount() is 2 after two queued actions", function()
		assert(GAB:GetQueuedBridgeCount() == 2,
			("expected 2, got %d"):format(GAB:GetQueuedBridgeCount()))
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("GAB: QueueSwingIntent with non-table payload returns nil", function()
		local id = GAB:QueueSwingIntent("not a table" :: any)
		assert(id == nil, "expected nil for invalid payload type")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("GAB: bridge count unchanged after invalid payload", function()
		assert(GAB:GetQueuedBridgeCount() == 2,
			"bridge count must not change for rejected action")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("GAB: QueueHoleReady with nil payload returns nil", function()
		local id = GAB:QueueHoleReady(nil :: any)
		assert(id == nil, "expected nil for nil payload")
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("GAB: ClientActionController received the queued actions", function()
		-- CAC was cleared before this section; GAB queued 2 valid actions
		assert(CAC:GetActionCount() == 2,
			("expected 2 actions in CAC, got %d"):format(CAC:GetActionCount()))
		-- Verify the action types are correct
		local found = { SwingIntent = false, HoleReady = false }
		for _, entry in ipairs(CAC:GetQueuedActions()) do
			found[entry.actionType] = true
		end
		assert(found.SwingIntent, "expected SwingIntent in CAC queue")
		assert(found.HoleReady,   "expected HoleReady in CAC queue")
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("GAB: ClearQueuedBridgeActions resets bridge count to 0", function()
		GAB:ClearQueuedBridgeActions()
		assert(GAB:GetQueuedBridgeCount() == 0,
			"expected 0 after ClearQueuedBridgeActions")
		-- CAC still holds the entries (bridge clear is local-only)
		assert(CAC:GetActionCount() == 2,
			"CAC queue must be unaffected by bridge ClearQueuedBridgeActions")
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("GAB: Destroy resets bridge count; QueueSwingIntent works after re-Init", function()
		GAB:Destroy()
		assert(GAB:GetQueuedBridgeCount() == 0, "expected 0 after Destroy")
		GAB:Init()
		local id = GAB:QueueSwingIntent({ power = 0.5 })
		assert(type(id) == "string", "expected actionId after re-Init")
		assert(GAB:GetQueuedBridgeCount() == 1, "expected count 1 after re-Init queue")
		GAB:ClearQueuedBridgeActions()
	end)

	CAC:ClearActions()

end -- gabOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — MatchmakingActionBridgeControllerModule  (checks 13–24)
-- ════════════════════════════════════════════════════════════════════════════

local mabOk, mabResult = safeRequire(
	script.Parent.Parent.Modules.MatchmakingActionBridgeControllerModule)

if mabOk and cacOk then

	local MAB: any = mabResult
	CAC:ClearActions()

	-- 13 ───────────────────────────────────────────────────────────────────
	check("MAB: module loads successfully", function()
		assert(type(MAB) == "table", "expected table, got " .. type(MAB))
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("MAB: GetQueuedBridgeCount() is 0 initially", function()
		assert(MAB:GetQueuedBridgeCount() == 0,
			("expected 0, got %d"):format(MAB:GetQueuedBridgeCount()))
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("MAB: QueueMatchmaking with valid mode 'Solo' returns actionId", function()
		local id = MAB:QueueMatchmaking("Solo")
		assert(type(id) == "string" and id ~= "",
			"expected non-empty string actionId for valid mode")
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("MAB: GetQueuedBridgeCount() is 1 after QueueMatchmaking", function()
		assert(MAB:GetQueuedBridgeCount() == 1,
			("expected 1, got %d"):format(MAB:GetQueuedBridgeCount()))
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("MAB: QueueMatchmaking with invalid mode returns nil", function()
		local id = MAB:QueueMatchmaking("INVALID_MODE_XYZ")
		assert(id == nil, "expected nil for invalid matchmaking mode")
		assert(MAB:GetQueuedBridgeCount() == 1,
			"bridge count must not change for rejected mode")
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("MAB: all valid modes are accepted (Duo, Squad, Private)", function()
		local idDuo     = MAB:QueueMatchmaking("Duo")
		local idSquad   = MAB:QueueMatchmaking("Squad")
		local idPrivate = MAB:QueueMatchmaking("Private")
		assert(type(idDuo)     == "string", "Duo mode must be accepted")
		assert(type(idSquad)   == "string", "Squad mode must be accepted")
		assert(type(idPrivate) == "string", "Private mode must be accepted")
		assert(MAB:GetQueuedBridgeCount() == 4,
			("expected 4, got %d"):format(MAB:GetQueuedBridgeCount()))
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("MAB: CancelMatchmaking queues action and increments count", function()
		local id = MAB:CancelMatchmaking()
		assert(type(id) == "string", "expected actionId from CancelMatchmaking")
		assert(MAB:GetQueuedBridgeCount() == 5,
			("expected 5, got %d"):format(MAB:GetQueuedBridgeCount()))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("MAB: SetReady queues action and increments count", function()
		local id = MAB:SetReady(true)
		assert(type(id) == "string", "expected actionId from SetReady")
		assert(MAB:GetQueuedBridgeCount() == 6,
			("expected 6, got %d"):format(MAB:GetQueuedBridgeCount()))
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("MAB: ClientActionController received all matchmaking actions", function()
		-- CAC cleared before section; 6 valid actions queued
		assert(CAC:GetActionCount() == 6,
			("expected 6 in CAC, got %d"):format(CAC:GetActionCount()))
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("MAB: ClearQueuedBridgeActions resets bridge count, CAC unaffected", function()
		MAB:ClearQueuedBridgeActions()
		assert(MAB:GetQueuedBridgeCount() == 0, "expected 0 after bridge clear")
		assert(CAC:GetActionCount() == 6,       "CAC must be unaffected by bridge clear")
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("MAB: bridge count is independent of other bridges", function()
		-- GAB was already reset; its count is 0
		if gabOk then
			local GAB: any = gabResult
			assert(GAB:GetQueuedBridgeCount() == 0,
				"GAB bridge count must not be affected by MAB operations")
		end
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("MAB: Destroy resets bridge count; QueueMatchmaking works after re-Init", function()
		MAB:Destroy()
		assert(MAB:GetQueuedBridgeCount() == 0, "expected 0 after Destroy")
		MAB:Init()
		local id = MAB:QueueMatchmaking("Squad")
		assert(type(id) == "string", "expected actionId after re-Init")
		assert(MAB:GetQueuedBridgeCount() == 1, "expected count 1 after re-Init queue")
		MAB:ClearQueuedBridgeActions()
	end)

	CAC:ClearActions()

end -- mabOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — ShopActionBridgeControllerModule  (checks 25–38)
-- ════════════════════════════════════════════════════════════════════════════

local sabOk, sabResult = safeRequire(
	script.Parent.Parent.Modules.ShopActionBridgeControllerModule)

if sabOk and cacOk then

	local SAB: any = sabResult
	CAC:ClearActions()

	-- 25 ───────────────────────────────────────────────────────────────────
	check("SAB: module loads successfully", function()
		assert(type(SAB) == "table", "expected table, got " .. type(SAB))
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("SAB: GetQueuedBridgeCount() is 0 initially", function()
		assert(SAB:GetQueuedBridgeCount() == 0,
			("expected 0, got %d"):format(SAB:GetQueuedBridgeCount()))
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("SAB: OpenShop queues action and returns actionId", function()
		local id = SAB:OpenShop()
		assert(type(id) == "string" and id ~= "",
			"expected non-empty string actionId")
		assert(SAB:GetQueuedBridgeCount() == 1,
			("expected 1, got %d"):format(SAB:GetQueuedBridgeCount()))
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("SAB: PreviewItem with valid itemId returns actionId", function()
		local id = SAB:PreviewItem("club_gold_001")
		assert(type(id) == "string" and id ~= "",
			"expected actionId for valid itemId")
		assert(SAB:GetQueuedBridgeCount() == 2,
			("expected 2, got %d"):format(SAB:GetQueuedBridgeCount()))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("SAB: PreviewItem with empty string itemId returns nil", function()
		local id = SAB:PreviewItem("")
		assert(id == nil, "expected nil for empty itemId")
		assert(SAB:GetQueuedBridgeCount() == 2,
			"bridge count must not change for rejected itemId")
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("SAB: PreviewItem with nil itemId returns nil", function()
		local id = SAB:PreviewItem(nil :: any)
		assert(id == nil, "expected nil for nil itemId")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("SAB: EquipCosmetic with valid slot and itemId returns actionId", function()
		local id = SAB:EquipCosmetic("ClubSkin", "club_gold_001")
		assert(type(id) == "string" and id ~= "",
			"expected actionId for valid slot/itemId")
		assert(SAB:GetQueuedBridgeCount() == 3,
			("expected 3, got %d"):format(SAB:GetQueuedBridgeCount()))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("SAB: all valid cosmetic slots accepted", function()
		local slots = { "BallSkin", "BallTrail", "Caddie", "Nameplate", "VictoryAnimation" }
		for _, slot in ipairs(slots) do
			local id = SAB:EquipCosmetic(slot, "item_test")
			assert(type(id) == "string",
				("slot %q was rejected unexpectedly"):format(slot))
		end
		-- 5 additional actions queued (3 + 5 = 8)
		assert(SAB:GetQueuedBridgeCount() == 8,
			("expected 8, got %d"):format(SAB:GetQueuedBridgeCount()))
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("SAB: EquipCosmetic with invalid slot returns nil", function()
		local id = SAB:EquipCosmetic("INVALID_SLOT_XYZ", "item_test")
		assert(id == nil, "expected nil for invalid slot")
		assert(SAB:GetQueuedBridgeCount() == 8,
			"bridge count must not change for rejected slot")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("SAB: EquipCosmetic with invalid itemId returns nil", function()
		local id = SAB:EquipCosmetic("BallSkin", "")
		assert(id == nil, "expected nil for empty itemId in EquipCosmetic")
		assert(SAB:GetQueuedBridgeCount() == 8,
			"bridge count must not change for rejected itemId")
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("SAB: ClientActionController received all shop actions", function()
		-- CAC was cleared before this section; 8 valid actions queued
		assert(CAC:GetActionCount() == 8,
			("expected 8 in CAC, got %d"):format(CAC:GetActionCount()))
		-- Spot-check action types
		local types: { [string]: boolean } = {}
		for _, entry in ipairs(CAC:GetQueuedActions()) do
			types[entry.actionType] = true
		end
		assert(types.OpenShop,      "expected OpenShop in CAC queue")
		assert(types.PreviewItem,   "expected PreviewItem in CAC queue")
		assert(types.EquipCosmetic, "expected EquipCosmetic in CAC queue")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("SAB: ClearQueuedBridgeActions resets bridge count, CAC unaffected", function()
		SAB:ClearQueuedBridgeActions()
		assert(SAB:GetQueuedBridgeCount() == 0, "expected 0 after bridge clear")
		assert(CAC:GetActionCount() == 8,       "CAC must be unaffected by bridge clear")
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("SAB: shop bridge count is independent of gameplay bridge count", function()
		if gabOk then
			local GAB: any = gabResult
			assert(GAB:GetQueuedBridgeCount() == 0,
				"GAB count must not be affected by SAB operations")
		end
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("SAB: Destroy resets bridge count; OpenShop works after re-Init", function()
		SAB:Destroy()
		assert(SAB:GetQueuedBridgeCount() == 0, "expected 0 after Destroy")
		SAB:Init()
		local id = SAB:OpenShop()
		assert(type(id) == "string", "expected actionId after re-Init")
		assert(SAB:GetQueuedBridgeCount() == 1, "expected count 1 after re-Init queue")
		SAB:ClearQueuedBridgeActions()
	end)

	CAC:ClearActions()

end -- sabOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 21 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
end
