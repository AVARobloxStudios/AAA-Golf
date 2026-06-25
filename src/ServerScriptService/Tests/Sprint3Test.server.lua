--!strict
-- Sprint3Test — Temporary server smoke test for Sprint 3 ScoringService.
-- Safe to delete after Sprint 3 sign-off. Does NOT modify production logic.
-- Run in Studio Play Solo mode. No API Services required.
--
-- What is tested:
--   ClassifyScore tier classification, ComputeRoundXP/Coins pure formulas,
--   StartRound / StartHole session initialisation, CommitStroke stroke and
--   penalty accumulation, HoleComplete reward queueing, FinalizeRound summary
--   structure and reward drain.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

-- Require modules only — Init() is handled by production runner scripts.
local Types             = require(ReplicatedStorage.Shared.Modules.Types)
local Constants         = require(ReplicatedStorage.Shared.Modules.Constants)
local ScoringService    = require(ServerScriptService.Modules.ScoringService)
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)

local TAG              = "[Sprint3Test]"
local PROFILE_TIMEOUT  = 10  -- seconds to wait for Studio mock profile to load

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

-- ── Module-level smoke checks ──────────────────────────────────────────────
-- Pure-function and API checks: no player, no profile needed.

check("ScoringService: module loads without error", function()
	assert(ScoringService ~= nil)
end)

check("ScoringService: all TDD §4.3 methods exist", function()
	assert(type(ScoringService.ClassifyScore)   == "function", "ClassifyScore missing")
	assert(type(ScoringService.ComputeRoundXP)  == "function", "ComputeRoundXP missing")
	assert(type(ScoringService.ComputeRoundCoins) == "function", "ComputeRoundCoins missing")
	assert(type(ScoringService.StartRound)      == "function", "StartRound missing")
	assert(type(ScoringService.StartHole)       == "function", "StartHole missing")
	assert(type(ScoringService.CommitStroke)    == "function", "CommitStroke missing")
	assert(type(ScoringService.HoleComplete)    == "function", "HoleComplete missing")
	assert(type(ScoringService.FinalizeRound)   == "function", "FinalizeRound missing")
end)

-- ── ClassifyScore — pure function ──────────────────────────────────────────

check("ClassifyScore: condor — 1 stroke on par-5", function()
	local tier = ScoringService:ClassifyScore(1, 5)
	assert(tier == "CONDOR", "expected CONDOR, got " .. tier)
end)

check("ClassifyScore: albatross — 1 stroke on par-4", function()
	local tier = ScoringService:ClassifyScore(1, 4)
	assert(tier == "ALBATROSS", "expected ALBATROSS, got " .. tier)
end)

check("ClassifyScore: eagle — 2 strokes on par-4", function()
	local tier = ScoringService:ClassifyScore(2, 4)
	assert(tier == "EAGLE", "expected EAGLE, got " .. tier)
end)

check("ClassifyScore: birdie — 3 strokes on par-4", function()
	local tier = ScoringService:ClassifyScore(3, 4)
	assert(tier == "BIRDIE", "expected BIRDIE, got " .. tier)
end)

check("ClassifyScore: par — 4 strokes on par-4", function()
	local tier = ScoringService:ClassifyScore(4, 4)
	assert(tier == "PAR", "expected PAR, got " .. tier)
end)

check("ClassifyScore: bogey — 5 strokes on par-4", function()
	local tier = ScoringService:ClassifyScore(5, 4)
	assert(tier == "BOGEY", "expected BOGEY, got " .. tier)
end)

check("ClassifyScore: double bogey — 6 strokes on par-4", function()
	local tier = ScoringService:ClassifyScore(6, 4)
	assert(tier == "DOUBLE_BOGEY", "expected DOUBLE_BOGEY, got " .. tier)
end)

check("ClassifyScore: worse — 7 strokes on par-4 (> double bogey)", function()
	local tier = ScoringService:ClassifyScore(7, 4)
	assert(tier == "WORSE", "expected WORSE, got " .. tier)
end)

check("ClassifyScore: worse — 10 strokes on par-3 (max strokes edge case)", function()
	local tier = ScoringService:ClassifyScore(10, 3)
	assert(tier == "WORSE", "expected WORSE, got " .. tier)
end)

-- ── ComputeRoundXP — pure function ─────────────────────────────────────────

check("ComputeRoundXP: empty scoreCard → XP_ROUND_MIN (50)", function()
	local xp = ScoringService:ComputeRoundXP({})
	assert(xp == Constants.XP_ROUND_MIN,
		("expected %d, got %d"):format(Constants.XP_ROUND_MIN, xp))
end)

check("ComputeRoundXP: all pars → 75 (TIER_XP[PAR] = 75)", function()
	local xp = ScoringService:ComputeRoundXP({ "PAR", "PAR", "PAR" })
	assert(xp == 75, ("expected 75, got %d"):format(xp))
end)

check("ComputeRoundXP: all birdies → 100 (TIER_XP[BIRDIE] = 100)", function()
	local xp = ScoringService:ComputeRoundXP({ "BIRDIE", "BIRDIE", "BIRDIE" })
	assert(xp == 100, ("expected 100, got %d"):format(xp))
end)

check("ComputeRoundXP: all eagles → 150, clamped to 150", function()
	local xp = ScoringService:ComputeRoundXP({ "EAGLE", "EAGLE", "EAGLE" })
	assert(xp == 150, ("expected 150, got %d"):format(xp))
end)

check("ComputeRoundXP: result is always in [XP_ROUND_MIN, XP_ROUND_MAX]", function()
	local cases: { { string } } = {
		{ "WORSE", "WORSE", "WORSE" },
		{ "CONDOR", "CONDOR", "CONDOR" },
		{ "PAR", "BIRDIE", "EAGLE", "BOGEY" },
	}
	for _, scoreCard in ipairs(cases) do
		local xp = ScoringService:ComputeRoundXP(scoreCard)
		assert(xp >= Constants.XP_ROUND_MIN and xp <= Constants.XP_ROUND_MAX,
			("xp %d outside [%d, %d] for %s"):format(
				xp, Constants.XP_ROUND_MIN, Constants.XP_ROUND_MAX,
				table.concat(scoreCard, ",")))
	end
end)

-- ── ComputeRoundCoins — pure function ──────────────────────────────────────

check("ComputeRoundCoins: empty scoreCard → 0", function()
	local coins = ScoringService:ComputeRoundCoins({})
	assert(coins == 0, ("expected 0, got %d"):format(coins))
end)

check("ComputeRoundCoins: all pars → 100 (TIER_COINS[PAR] = 100)", function()
	local coins = ScoringService:ComputeRoundCoins({ "PAR", "PAR", "PAR" })
	assert(coins == 100, ("expected 100, got %d"):format(coins))
end)

check("ComputeRoundCoins: all birdies → 150 (TIER_COINS[BIRDIE] = 150)", function()
	local coins = ScoringService:ComputeRoundCoins({ "BIRDIE", "BIRDIE" })
	assert(coins == 150, ("expected 150, got %d"):format(coins))
end)

check("ComputeRoundCoins: all worse → 25 (TIER_COINS[WORSE] = 25)", function()
	local coins = ScoringService:ComputeRoundCoins({ "WORSE", "WORSE" })
	assert(coins == 25, ("expected 25, got %d"):format(coins))
end)

-- ── Per-player session tests ───────────────────────────────────────────────
-- These require a player with a loaded profile (Studio mock is synchronous but
-- PlayerAdded fires asynchronously — we poll with a timeout before proceeding).

local function runTests(player: Player)
	print(TAG .. " ── Session tests for " .. player.Name .. " ──")

	-- Wait for the Studio mock profile to be available.
	local deadline = os.clock() + PROFILE_TIMEOUT
	while not PlayerDataService:GetProfile(player) and os.clock() < deadline do
		task.wait(0.2)
	end

	if not PlayerDataService:GetProfile(player) then
		fail("Profile load",
			("timed out after %ds for %s — is the Studio mock active?")
				:format(PROFILE_TIMEOUT, player.Name))
		return
	end

	-- ── Session initialisation ─────────────────────────────────────────────
	-- Scenario: par-4 hole 1, three shots — FAIRWAY → WATER → SAND — ending at
	-- exactly 4 strokes (PAR). WATER adds 1 penalty stroke; SAND adds none.

	-- Declare result captures before the check closures that populate them.
	local stroke1: { strokeDelta: number, penalty: number }? = nil
	local stroke2: { strokeDelta: number, penalty: number }? = nil
	local stroke3: { strokeDelta: number, penalty: number }? = nil
	local holeScore: Types.HoleScore? = nil
	local summary: Types.RoundSummary? = nil

	check("StartRound: initialises session without error", function()
		ScoringService:StartRound(player, "course_1")
	end)

	check("StartHole: initialises hole 1 (par 4) without error", function()
		ScoringService:StartHole(player, 1, 4)
	end)

	-- ── CommitStroke ───────────────────────────────────────────────────────
	-- Stroke 1: FAIRWAY — swing (1) + no penalty → total = 1, delta = 1−4 = −3

	check("CommitStroke (FAIRWAY): executes without error", function()
		stroke1 = ScoringService:CommitStroke(player, "FAIRWAY")
		assert(stroke1 ~= nil)
	end)

	check("CommitStroke (FAIRWAY): strokeDelta = −3 (1 stroke on par-4)", function()
		assert(stroke1, "FAIRWAY stroke result not captured")
		assert(stroke1.strokeDelta == -3,
			("expected -3, got %d"):format(stroke1.strokeDelta))
	end)

	check("CommitStroke (FAIRWAY): penalty = 0 (no hazard)", function()
		assert(stroke1, "FAIRWAY stroke result not captured")
		assert(stroke1.penalty == 0,
			("expected 0, got %d"):format(stroke1.penalty))
	end)

	-- Stroke 2: WATER — swing (1) + WATER penalty (1) → total = 3, delta = 3−4 = −1

	check("CommitStroke (WATER): executes without error", function()
		stroke2 = ScoringService:CommitStroke(player, "WATER")
		assert(stroke2 ~= nil)
	end)

	check("CommitStroke (WATER): penalty = 1 (WATER hazard)", function()
		assert(stroke2, "WATER stroke result not captured")
		assert(stroke2.penalty == 1,
			("expected 1, got %d"):format(stroke2.penalty))
	end)

	check("CommitStroke (WATER): strokeDelta = −1 (3 total strokes vs par-4)", function()
		assert(stroke2, "WATER stroke result not captured")
		assert(stroke2.strokeDelta == -1,
			("expected -1, got %d"):format(stroke2.strokeDelta))
	end)

	-- Stroke 3: SAND — swing (1) + no penalty → total = 4, delta = 4−4 = 0

	check("CommitStroke (SAND): executes without error", function()
		stroke3 = ScoringService:CommitStroke(player, "SAND")
		assert(stroke3 ~= nil)
	end)

	check("CommitStroke (SAND): penalty = 0 (SAND is a lie penalty only, TDD §4.3)", function()
		assert(stroke3, "SAND stroke result not captured")
		assert(stroke3.penalty == 0,
			("expected 0, got %d"):format(stroke3.penalty))
	end)

	check("CommitStroke (SAND): strokeDelta = 0 (4 total strokes = par-4)", function()
		assert(stroke3, "SAND stroke result not captured")
		assert(stroke3.strokeDelta == 0,
			("expected 0, got %d"):format(stroke3.strokeDelta))
	end)

	-- ── HoleComplete ───────────────────────────────────────────────────────
	-- 4 total strokes on par-4 → PAR tier → 100 coins, 75 XP

	local coinsBefore = PlayerDataService:GetCoins(player)

	check("HoleComplete: executes without error and returns HoleScore", function()
		holeScore = ScoringService:HoleComplete(player)
		assert(holeScore ~= nil)
	end)

	check("HoleComplete: scoreTier = PAR (4 strokes on par-4)", function()
		assert(holeScore, "HoleScore not captured")
		assert(holeScore.scoreTier == "PAR",
			"expected PAR, got " .. holeScore.scoreTier)
	end)

	check("HoleComplete: strokes = 4", function()
		assert(holeScore, "HoleScore not captured")
		assert(holeScore.strokes == 4,
			("expected 4, got %d"):format(holeScore.strokes))
	end)

	check("HoleComplete: coins = 100 (TIER_COINS[PAR])", function()
		assert(holeScore, "HoleScore not captured")
		assert(holeScore.coins == 100,
			("expected 100, got %d"):format(holeScore.coins))
	end)

	check("HoleComplete: xp = 75 (TIER_XP[PAR])", function()
		assert(holeScore, "HoleScore not captured")
		assert(holeScore.xp == 75,
			("expected 75, got %d"):format(holeScore.xp))
	end)

	check("HoleComplete: rewards queued but NOT yet drained (GetCoins unchanged)", function()
		local coinsNow = PlayerDataService:GetCoins(player)
		assert(coinsNow == coinsBefore,
			("expected coins still %d immediately after HoleComplete (rewards should be "
				.. "queued, not applied), got %d"):format(coinsBefore, coinsNow))
	end)

	-- ── FinalizeRound ──────────────────────────────────────────────────────
	-- Expected totals for a 1-hole round (PAR):
	--   per-hole coins = 100, round bonus coins = ComputeRoundCoins(["PAR"]) = 100
	--   per-hole xp    = 75,  round bonus xp    = ComputeRoundXP(["PAR"])    = 75
	--   totalCoins = 200,  totalXP = 150

	check("FinalizeRound: executes without error and returns RoundSummary", function()
		summary = ScoringService:FinalizeRound(player)
		assert(summary ~= nil)
	end)

	check("FinalizeRound: courseId = 'course_1'", function()
		assert(summary, "RoundSummary not captured")
		assert(summary.courseId == "course_1",
			"expected course_1, got " .. summary.courseId)
	end)

	check("FinalizeRound: 1 completed hole in summary", function()
		assert(summary, "RoundSummary not captured")
		assert(#summary.holes == 1,
			("expected 1 hole, got %d"):format(#summary.holes))
	end)

	check("FinalizeRound: totalStrokes = 4", function()
		assert(summary, "RoundSummary not captured")
		assert(summary.totalStrokes == 4,
			("expected 4, got %d"):format(summary.totalStrokes))
	end)

	check("FinalizeRound: totalPar = 4", function()
		assert(summary, "RoundSummary not captured")
		assert(summary.totalPar == 4,
			("expected 4, got %d"):format(summary.totalPar))
	end)

	check("FinalizeRound: totalCoins = 200 (100 per-hole PAR + 100 round bonus)", function()
		assert(summary, "RoundSummary not captured")
		assert(summary.totalCoins == 200,
			("expected 200 (100 per-hole + 100 round bonus), got %d"):format(summary.totalCoins))
	end)

	check("FinalizeRound: totalXP = 150 (75 per-hole PAR + 75 round bonus)", function()
		assert(summary, "RoundSummary not captured")
		assert(summary.totalXP == 150,
			("expected 150 (75 per-hole + 75 round bonus), got %d"):format(summary.totalXP))
	end)

	-- DrainRewards is called inside FinalizeRound; coins should now be applied.
	check("FinalizeRound: all rewards drained — GetCoins increased by 200", function()
		local coinsAfter = PlayerDataService:GetCoins(player)
		assert(coinsAfter == coinsBefore + 200,
			("expected %d (coinsBefore %d + 200), got %d")
				:format(coinsBefore + 200, coinsBefore, coinsAfter))
	end)

	check("FinalizeRound: session cleared — second call raises an error", function()
		local ok = pcall(function()
			ScoringService:FinalizeRound(player)
		end)
		assert(not ok, "expected FinalizeRound to error after session was cleared")
	end)

	-- ── Summary ───────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 3 smoke tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end

-- ── Per-player trigger ─────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(runTests, player)
end)

-- Catch the local player already present in Studio play-solo.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(runTests, player)
end
