--!strict
-- Sprint1Test — Temporary server test for Sprint 1 data + economy services.
-- Safe to delete after Sprint 1 sign-off. Does NOT modify production logic.
-- Run in Studio Play mode (solo) with "Enable Studio Access to API Services" on.

local Players           = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Require modules only — Init() is handled by the production runner scripts.
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)
local EconomyService    = require(ServerScriptService.Modules.EconomyService)

local TAG                  = "[Sprint1Test]"
local PROFILE_LOAD_TIMEOUT = 15  -- seconds to wait for ProfileService

-- ── Helpers ────────────────────────────────────────────────────────────────

local passed = 0
local failed = 0

local function pass(label: string)
	passed += 1
	print(TAG .. " PASS  " .. label)
end

local function fail(label: string, reason: string)
	failed += 1
	warn(TAG .. " FAIL  " .. label .. "  (" .. reason .. ")")
end

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		pass(label)
	else
		fail(label, tostring(err))
	end
end

-- ── Test suite ─────────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 1 tests for " .. player.Name .. " ──────────")

	-- 1. Profile accessible after load.
	check("PlayerDataService: profile loaded", function()
		local profile = PlayerDataService:GetProfile(player)
		assert(profile ~= nil, "GetProfile returned nil")
	end)

	-- 2. GetCoins returns a non-negative integer.
	check("PlayerDataService: GetCoins returns integer", function()
		local coins = PlayerDataService:GetCoins(player)
		assert(type(coins) == "number", "expected number, got " .. type(coins))
		assert(math.floor(coins) == coins, "coins is not an integer: " .. tostring(coins))
		assert(coins >= 0, "coins is negative: " .. tostring(coins))
	end)

	-- 3. AddCoins increments the balance by exactly the granted amount.
	check("PlayerDataService: AddCoins increments balance", function()
		local before = PlayerDataService:GetCoins(player)
		PlayerDataService:AddCoins(player, 100)
		local after = PlayerDataService:GetCoins(player)
		assert(after == before + 100,
			("expected %d, got %d"):format(before + 100, after))
	end)

	-- 4. AddCoins rejects float input.
	check("PlayerDataService: AddCoins rejects floats", function()
		local ok = pcall(function()
			PlayerDataService:AddCoins(player, 1.5)
		end)
		assert(not ok, "AddCoins should have errored on float input but did not")
	end)

	-- 5. AddXP increments the raw XP field.
	check("PlayerDataService: AddXP increments xp", function()
		local profile = PlayerDataService:GetProfile(player)
		assert(profile, "no profile")
		local before = profile.Data.xp :: number
		PlayerDataService:AddXP(player, 50)
		local after = profile.Data.xp :: number
		assert(after == before + 50,
			("expected %d, got %d"):format(before + 50, after))
	end)

	-- 6. AddXP rejects float input.
	check("PlayerDataService: AddXP rejects floats", function()
		local ok = pcall(function()
			PlayerDataService:AddXP(player, 0.5)
		end)
		assert(not ok, "AddXP should have errored on float input but did not")
	end)

	-- 7. HasPurchaseId returns false for an id that was never recorded.
	check("PlayerDataService: HasPurchaseId unknown id → false", function()
		local has = PlayerDataService:HasPurchaseId(player, "sprint1_test_unknown_99")
		assert(has == false, "expected false, got " .. tostring(has))
	end)

	-- 8. AddPurchaseId / HasPurchaseId round-trip.
	check("PlayerDataService: AddPurchaseId + HasPurchaseId round-trip", function()
		local testId = "sprint1_test_receipt_001"
		PlayerDataService:AddPurchaseId(player, testId)
		local has = PlayerDataService:HasPurchaseId(player, testId)
		assert(has == true, "expected true after AddPurchaseId, got " .. tostring(has))
	end)

	-- 9. GetDailyRewardState returns the three expected fields with correct types.
	check("PlayerDataService: GetDailyRewardState shape", function()
		local state = PlayerDataService:GetDailyRewardState(player)
		assert(type(state.date)   == "string", "state.date should be string")
		assert(type(state.time)   == "number", "state.time should be number")
		assert(type(state.streak) == "number", "state.streak should be number")
	end)

	-- 10. GrantHoleReward — birdie (3 strokes, par 4).
	check("EconomyService: GrantHoleReward birdie returns correct tier/xp/coins", function()
		local result = EconomyService:GrantHoleReward(player, 3, 4)
		assert(result.tier  == "BIRDIE", "expected BIRDIE, got " .. tostring(result.tier))
		assert(result.xp    == 100,      "expected xp=100, got "    .. tostring(result.xp))
		assert(result.coins == 150,      "expected coins=150, got " .. tostring(result.coins))
	end)

	-- 11. GrantHoleReward — eagle (2 strokes, par 4).
	check("EconomyService: GrantHoleReward eagle returns correct tier", function()
		local result = EconomyService:GrantHoleReward(player, 2, 4)
		assert(result.tier == "EAGLE", "expected EAGLE, got " .. tostring(result.tier))
	end)

	-- 12. GrantHoleReward — bogey (5 strokes, par 4).
	check("EconomyService: GrantHoleReward bogey returns correct tier", function()
		local result = EconomyService:GrantHoleReward(player, 5, 4)
		assert(result.tier == "BOGEY", "expected BOGEY, got " .. tostring(result.tier))
	end)

	-- 13. GrantRoundReward solo (no placement) — base grant only.
	check("EconomyService: GrantRoundReward solo grants base xp and coins", function()
		local coinsBefore = PlayerDataService:GetCoins(player)
		local result      = EconomyService:GrantRoundReward(player, nil)
		local coinsAfter  = PlayerDataService:GetCoins(player)
		assert(result.xp    > 0, "expected xp > 0")
		assert(result.coins > 0, "expected coins > 0")
		assert(coinsAfter == coinsBefore + result.coins,
			("balance mismatch: expected %d, got %d"):format(coinsBefore + result.coins, coinsAfter))
	end)

	-- 14. GrantRoundReward 1st place — placement bonus applied.
	check("EconomyService: GrantRoundReward 1st place grants placement bonus", function()
		local result = EconomyService:GrantRoundReward(player, 1)
		assert(result.coins == 500, "expected coins=500 for 1st place, got " .. tostring(result.coins))
	end)

	-- 15. GrantRoundReward 3rd place — lower placement bonus.
	check("EconomyService: GrantRoundReward 3rd place grants lower bonus", function()
		local result = EconomyService:GrantRoundReward(player, 3)
		assert(result.coins == 200, "expected coins=200 for 3rd place, got " .. tostring(result.coins))
	end)

	-- 16. ClaimDailyReward — first claim succeeds (or already-claimed is handled gracefully).
	local dailyClaimedToday = false
	check("EconomyService: ClaimDailyReward first claim", function()
		local result = EconomyService:ClaimDailyReward(player)
		if result.claimed == false and result.reason == "already_claimed" then
			-- Profile already has today's date — not an error; test re-run same day.
			dailyClaimedToday = true
			return
		end
		assert(result.claimed == true,  "expected claimed=true")
		assert(type(result.xp)     == "number" and result.xp     > 0, "expected xp > 0")
		assert(type(result.coins)  == "number" and result.coins  > 0, "expected coins > 0")
		assert(type(result.streak) == "number" and result.streak >= 1, "expected streak >= 1")
		dailyClaimedToday = true
	end)

	-- 17. ClaimDailyReward — same-day duplicate is rejected.
	check("EconomyService: ClaimDailyReward duplicate rejected", function()
		-- Only meaningful if today's reward is marked (either just claimed above, or pre-existing).
		if not dailyClaimedToday then
			-- Shouldn't reach here, but guard defensively.
			error("precondition failed: dailyClaimedToday not set")
		end
		local result = EconomyService:ClaimDailyReward(player)
		assert(result.claimed == false,          "expected claimed=false on duplicate")
		assert(result.reason  == "already_claimed",
			"expected reason=already_claimed, got " .. tostring(result.reason))
	end)

	-- ── Summary ──────────────────────────────────────────────────────────
	print(TAG .. " ──────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 1 tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end

-- ── Module-level smoke checks (run immediately, before any player joins) ───

check("PlayerDataService: module loads with Init function",
	function() assert(type(PlayerDataService.Init) == "function") end)

check("EconomyService: module loads with Init function",
	function() assert(type(EconomyService.Init) == "function") end)

-- ── Per-player test trigger ─────────────────────────────────────────────────

local function awaitProfileAndTest(player: Player)
	local deadline = os.clock() + PROFILE_LOAD_TIMEOUT
	while not PlayerDataService:GetProfile(player) and os.clock() < deadline do
		task.wait(0.5)
	end
	if not PlayerDataService:GetProfile(player) then
		fail("Profile load", ("timed out after %ds for %s — is API Access enabled in Studio?")
			:format(PROFILE_LOAD_TIMEOUT, player.Name))
		return
	end
	runTests(player)
end

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(awaitProfileAndTest, player)
end)

-- Catch the local player already present in Studio play-solo.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(awaitProfileAndTest, player)
end
