--!strict
-- Sprint12ClientTest — LocalScript
-- Client smoke tests for Sprint 12: ScoreboardController, RoundSummaryController,
-- and LeaderboardController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.  Tests drive
-- each module through its public API and _onClientEvent with no live
-- round or network interaction required.

print("[Sprint12ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local TAG     = "[Sprint12ClientTest]"
local passed  = 0
local failed  = 0

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

local MY_ID = Players.LocalPlayer.UserId

local function stateEnvelope(state: string): any
	return {
		eventType = "StateChanged",
		payload   = { playerId = MY_ID, state = state },
		timestamp = os.time(),
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — ScoreboardControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local scOk, scResult = safeRequire(
	script.Parent.Parent.Modules.ScoreboardControllerModule)

if scOk then

	local SCM: any = scResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("SCM: module loads successfully", function()
		assert(type(SCM) == "table", "expected table, got " .. type(SCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("SCM: initial GetTotalStrokes is 0", function()
		assert(SCM:GetTotalStrokes() == 0,
			("expected 0, got %s"):format(tostring(SCM:GetTotalStrokes())))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("SCM: initial GetTotalPar is 0", function()
		assert(SCM:GetTotalPar() == 0,
			("expected 0, got %s"):format(tostring(SCM:GetTotalPar())))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("SCM: initial GetScoreToPar is 0", function()
		assert(SCM:GetScoreToPar() == 0,
			("expected 0, got %s"):format(tostring(SCM:GetScoreToPar())))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("SCM: initial IsVisible is false (LOBBY state)", function()
		assert(SCM:IsVisible() == false, "scoreboard must start hidden in LOBBY")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("SCM: GetHoleScore returns nil for unset hole", function()
		assert(SCM:GetHoleScore(1) == nil, "expected nil for hole 1 before SetHoleScore")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("SCM: SetHoleScore(1, 4, 3, 'Bogey') stores data", function()
		SCM:SetHoleScore(1, 4, 3, "Bogey")
		local hs = SCM:GetHoleScore(1)
		assert(hs ~= nil, "expected hole score to exist after SetHoleScore")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("SCM: GetHoleScore(1) returns correct strokes", function()
		local hs = SCM:GetHoleScore(1)
		assert(hs ~= nil and hs.strokes == 4,
			("expected strokes=4, got %s"):format(tostring(hs and hs.strokes)))
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("SCM: GetHoleScore(1) returns correct par", function()
		local hs = SCM:GetHoleScore(1)
		assert(hs ~= nil and hs.par == 3,
			("expected par=3, got %s"):format(tostring(hs and hs.par)))
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("SCM: GetHoleScore(1) returns correct tier", function()
		local hs = SCM:GetHoleScore(1)
		assert(hs ~= nil and hs.tier == "Bogey",
			("expected tier='Bogey', got %s"):format(tostring(hs and hs.tier)))
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("SCM: GetTotalStrokes = 4 after hole 1", function()
		assert(SCM:GetTotalStrokes() == 4,
			("expected 4, got %s"):format(tostring(SCM:GetTotalStrokes())))
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("SCM: GetTotalPar = 3 after hole 1", function()
		assert(SCM:GetTotalPar() == 3,
			("expected 3, got %s"):format(tostring(SCM:GetTotalPar())))
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("SCM: GetScoreToPar = 1 after hole 1 (4−3)", function()
		assert(SCM:GetScoreToPar() == 1,
			("expected 1, got %s"):format(tostring(SCM:GetScoreToPar())))
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("SCM: Multiple holes accumulate totals correctly", function()
		-- hole 2: birdie (2 strokes on par 3 = −1)
		SCM:SetHoleScore(2, 2, 3, "Birdie")
		assert(SCM:GetTotalStrokes() == 6, "expected 6 total strokes (4+2)")
		assert(SCM:GetTotalPar()     == 6, "expected 6 total par (3+3)")
		assert(SCM:GetScoreToPar()   == 0, "expected even par (6−6=0)")
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("SCM: ClearScores resets all totals to 0", function()
		SCM:ClearScores()
		assert(SCM:GetTotalStrokes() == 0, "expected 0 strokes after ClearScores")
		assert(SCM:GetTotalPar()     == 0, "expected 0 par after ClearScores")
		assert(SCM:GetScoreToPar()   == 0, "expected 0 stp after ClearScores")
		assert(SCM:GetHoleScore(1)   == nil, "expected nil hole 1 after ClearScores")
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("SCM: StateChanged SCORE_REVEAL sets IsVisible true", function()
		SCM:_onClientEvent(stateEnvelope("SCORE_REVEAL"))
		assert(SCM:IsVisible() == true, "expected visible in SCORE_REVEAL")
	end)

	-- 16b ─────────────────────────────────────────────────────────────────
	check("SCM: StateChanged ROUND_COMPLETE keeps IsVisible true", function()
		SCM:_onClientEvent(stateEnvelope("ROUND_COMPLETE"))
		assert(SCM:IsVisible() == true, "expected visible in ROUND_COMPLETE")
	end)

	-- 16c ─────────────────────────────────────────────────────────────────
	check("SCM: StateChanged LOBBY hides scoreboard", function()
		SCM:_onClientEvent(stateEnvelope("LOBBY"))
		assert(SCM:IsVisible() == false, "expected hidden in LOBBY")
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("SCM: Destroy resets all state", function()
		SCM:SetHoleScore(1, 5, 4, "Bogey")
		SCM:_onClientEvent(stateEnvelope("SCORE_REVEAL"))
		SCM:Destroy()
		assert(SCM:GetTotalStrokes() == 0,     "expected 0 strokes after Destroy")
		assert(SCM:GetHoleScore(1)   == nil,   "expected nil hole after Destroy")
		assert(SCM:IsVisible()       == false,  "expected hidden after Destroy")
	end)

	-- Restore the live GameBus connection
	SCM:Init()

	-- 17b ─────────────────────────────────────────────────────────────────
	check("SCM: SetHoleScore and GetScoreToPar work after Init restore", function()
		SCM:SetHoleScore(1, 3, 4, "Birdie")   -- −1 under par
		assert(SCM:GetTotalStrokes() == 3,  "expected 3 strokes after restore")
		assert(SCM:GetScoreToPar()   == -1, "expected −1 stp after restore")
		SCM:ClearScores()
	end)

end -- scOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — RoundSummaryControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local rsOk, rsResult = safeRequire(
	script.Parent.Parent.Modules.RoundSummaryControllerModule)

if rsOk then

	local RSM: any = rsResult

	local TEST_SUMMARY = {
		courseId       = "Fairway Course",
		totalStrokes   = 34,
		totalPar       = 36,
		scoreToPar     = -2,
		totalCoins     = 500,
		totalXP        = 1200,
		completedHoles = 9,
	}

	-- 18 ───────────────────────────────────────────────────────────────────
	check("RSM: module loads successfully", function()
		assert(type(RSM) == "table", "expected table, got " .. type(RSM))
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("RSM: initial IsVisible is false", function()
		assert(RSM:IsVisible() == false, "round summary must start hidden")
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("RSM: initial GetSummary is nil", function()
		assert(RSM:GetSummary() == nil, "expected nil summary initially")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("RSM: ShowSummary sets IsVisible true", function()
		RSM:ShowSummary(TEST_SUMMARY)
		assert(RSM:IsVisible() == true, "expected visible after ShowSummary")
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("RSM: GetSummary returns correct courseId", function()
		local s = RSM:GetSummary()
		assert(s ~= nil and s.courseId == "Fairway Course",
			("expected 'Fairway Course', got %s"):format(tostring(s and s.courseId)))
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("RSM: GetSummary returns correct totalStrokes", function()
		local s = RSM:GetSummary()
		assert(s ~= nil and s.totalStrokes == 34,
			("expected 34, got %s"):format(tostring(s and s.totalStrokes)))
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("RSM: GetSummary returns correct scoreToPar", function()
		local s = RSM:GetSummary()
		assert(s ~= nil and s.scoreToPar == -2,
			("expected −2, got %s"):format(tostring(s and s.scoreToPar)))
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("RSM: HideSummary sets IsVisible false", function()
		RSM:HideSummary()
		assert(RSM:IsVisible() == false, "expected hidden after HideSummary")
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("RSM: GetSummary is nil after HideSummary", function()
		assert(RSM:GetSummary() == nil, "expected nil summary after HideSummary")
	end)

	-- 26b ─────────────────────────────────────────────────────────────────
	check("RSM: ShowSummary then StateChanged LOBBY auto-hides", function()
		RSM:ShowSummary(TEST_SUMMARY)
		assert(RSM:IsVisible() == true, "should be visible after ShowSummary")
		RSM:_onClientEvent(stateEnvelope("LOBBY"))
		assert(RSM:IsVisible()   == false, "expected hidden on LOBBY state")
		assert(RSM:GetSummary()  == nil,   "expected nil summary on LOBBY state")
	end)

	-- 26c ─────────────────────────────────────────────────────────────────
	check("RSM: GetSummary returns all expected fields", function()
		RSM:ShowSummary(TEST_SUMMARY)
		local s = RSM:GetSummary()
		assert(s ~= nil, "expected summary to exist")
		assert(s.totalCoins     == 500,  "expected 500 coins")
		assert(s.totalXP        == 1200, "expected 1200 XP")
		assert(s.completedHoles == 9,    "expected 9 completed holes")
		assert(s.totalPar       == 36,   "expected par 36")
		RSM:HideSummary()
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("RSM: Destroy resets all state", function()
		RSM:ShowSummary(TEST_SUMMARY)
		RSM:Destroy()
		assert(RSM:IsVisible()  == false, "expected hidden after Destroy")
		assert(RSM:GetSummary() == nil,   "expected nil summary after Destroy")
	end)

	-- Restore the live GameBus connection
	RSM:Init()

	-- 27b ─────────────────────────────────────────────────────────────────
	check("RSM: ShowSummary and HideSummary work after Init restore", function()
		RSM:ShowSummary(TEST_SUMMARY)
		assert(RSM:IsVisible() == true, "should be visible after restore ShowSummary")
		RSM:HideSummary()
		assert(RSM:IsVisible() == false, "should be hidden after restore HideSummary")
	end)

end -- rsOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — LeaderboardControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local lbOk, lbResult = safeRequire(
	script.Parent.Parent.Modules.LeaderboardControllerModule)

if lbOk then

	local LCM: any = lbResult

	local UNSORTED_ENTRIES = {
		{ displayName = "Alice",   userId = 1, scoreToPar = -1, totalStrokes = 17 },
		{ displayName = "Bob",     userId = 2, scoreToPar =  2, totalStrokes = 20 },
		{ displayName = "Charlie", userId = 3, scoreToPar = -1, totalStrokes = 16 },
		{ displayName = "Dave",    userId = 4, scoreToPar =  0, totalStrokes = 18 },
	}

	-- 28 ───────────────────────────────────────────────────────────────────
	check("LCM: module loads successfully", function()
		assert(type(LCM) == "table", "expected table, got " .. type(LCM))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("LCM: initial GetEntries returns empty table", function()
		local e = LCM:GetEntries()
		assert(type(e) == "table" and #e == 0,
			("expected empty table, got length %d"):format(#e))
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("LCM: initial IsVisible is false", function()
		assert(LCM:IsVisible() == false, "leaderboard must start hidden")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("LCM: SetEntries stores 4 entries", function()
		LCM:SetEntries(UNSORTED_ENTRIES)
		local e = LCM:GetEntries()
		assert(#e == 4, ("expected 4 entries, got %d"):format(#e))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("LCM: GetEntries returns entries sorted by scoreToPar asc", function()
		local e = LCM:GetEntries()
		-- Sorted: Charlie(−1,16), Alice(−1,17), Dave(0,18), Bob(+2,20)
		assert(e[1].displayName == "Charlie",
			("expected Charlie first, got %q"):format(e[1].displayName))
		assert(e[4].displayName == "Bob",
			("expected Bob last, got %q"):format(e[4].displayName))
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("LCM: Sort tie-breaker: same scoreToPar, fewer strokes wins", function()
		-- Charlie(−1,16) before Alice(−1,17)
		local e = LCM:GetEntries()
		assert(e[1].displayName == "Charlie" and e[2].displayName == "Alice",
			("expected Charlie then Alice, got %q then %q"):format(
				e[1].displayName, e[2].displayName))
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("LCM: Middle entries sorted correctly", function()
		local e = LCM:GetEntries()
		assert(e[3].displayName == "Dave",
			("expected Dave third, got %q"):format(e[3].displayName))
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("LCM: GetEntries returns a copy (mutation does not affect internal)", function()
		local copy = LCM:GetEntries()
		table.remove(copy, 1)   -- remove first entry from copy
		local again = LCM:GetEntries()
		assert(#again == 4, "internal entries should still be 4 after copy mutation")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("LCM: ClearEntries empties the list", function()
		LCM:ClearEntries()
		local e = LCM:GetEntries()
		assert(#e == 0, ("expected 0 entries after ClearEntries, got %d"):format(#e))
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("LCM: StateChanged ROUND_COMPLETE sets IsVisible true", function()
		LCM:_onClientEvent(stateEnvelope("ROUND_COMPLETE"))
		assert(LCM:IsVisible() == true, "expected visible in ROUND_COMPLETE")
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("LCM: StateChanged TEE_OFF hides leaderboard", function()
		LCM:_onClientEvent(stateEnvelope("TEE_OFF"))
		assert(LCM:IsVisible() == false, "expected hidden in TEE_OFF")
	end)

	-- 38b ─────────────────────────────────────────────────────────────────
	check("LCM: Destroy resets all state", function()
		LCM:SetEntries(UNSORTED_ENTRIES)
		LCM:_onClientEvent(stateEnvelope("ROUND_COMPLETE"))
		LCM:Destroy()
		assert(#LCM:GetEntries() == 0,   "expected empty entries after Destroy")
		assert(LCM:IsVisible()   == false, "expected hidden after Destroy")
	end)

	-- Restore the live GameBus connection
	LCM:Init()

	-- 39 ───────────────────────────────────────────────────────────────────
	check("LCM: SetEntries and sorting work after Init restore", function()
		LCM:SetEntries({
			{ displayName = "Zara", userId = 10, scoreToPar = -3, totalStrokes = 15 },
			{ displayName = "Max",  userId = 11, scoreToPar =  1, totalStrokes = 19 },
		})
		local e = LCM:GetEntries()
		assert(#e == 2,                         "expected 2 entries after restore SetEntries")
		assert(e[1].displayName == "Zara",      "Zara should be first (−3)")
		LCM:ClearEntries()
	end)

end -- lbOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 12 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
