--!strict
-- Sprint30ServerTest — Server Script smoke tests for Sprint 30.
-- Run in Studio Play Solo mode.
--
-- No DataStore profile gate is required — HoleCompletionService stores local
-- state only and does not call GameService:StartRound or ScoringService.
-- CompleteHole is tested without an active session to verify safe no-crash behavior.
--
-- Covers (18 checks):
--   Immediate (3): module loading, Init/Destroy exist.
--   Player-gated (15):
--     API surface — all public methods are functions.
--     Counts — 0 after Init.
--     GetHoleStatus default — WaitingForFinish, completed=false.
--     ProcessLanding non-table       → InvalidData,    rejectedCount=1.
--     ProcessLanding missing pos     → InvalidPosition, rejectedCount=2.
--     ProcessLanding non-Vector3 pos → InvalidPosition, rejectedCount=3.
--     ProcessLanding non-boolean inCup → InvalidInCup,  rejectedCount=4.
--     ProcessLanding inCup=false → NotInCup, status stays WaitingForFinish, completedCount=0.
--     ProcessLanding inCup=true  → success "HoleComplete", completedCount=1.
--     GetHoleStatus → HoleComplete, completed=true.
--     CompleteHole directly (no session) → success, completedCount=2.
--     Cumulative counts: completed=2, rejected=4.
--     ResetPlayer clears player state.
--     ResetCounts.
--     Update(0), Init guard, Destroy + re-Init.
--
-- HoleCompletionService is reset for isolation; GameService is NOT destroyed.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local HCS = require(ServerScriptService.Services.HoleCompletionService)

local TAG = "[Sprint30ServerTest]"

local passed = 0
local failed = 0

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(TAG .. " PASS  " .. label)
	else
		failed += 1
		warn(TAG .. " FAIL  " .. label .. "  (" .. tostring(err) .. ")")
	end
end

-- ── Immediate module-level checks ─────────────────────────────────────────────

check("HCS: module loads", function()
	assert(type(HCS) == "table", "expected table")
end)

check("HCS: Init function exists", function()
	assert(type(HCS.Init) == "function")
end)

check("HCS: Destroy function exists", function()
	assert(type(HCS.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 30 hole completion tests for " .. player.Name .. " ──")

	-- Reset for isolation.
	HCS:Destroy()
	HCS:Init({})

	-- ── API surface ───────────────────────────────────────────────────────────

	check("HCS: all public methods exist", function()
		local methods = {
			"ProcessLanding", "CompleteHole", "GetHoleStatus", "ResetPlayer",
			"GetCompletedCount", "GetRejectedCount", "ResetCounts",
		}
		for _, name in ipairs(methods) do
			assert(type(HCS[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	check("HCS: counts = 0 after Init", function()
		assert(HCS:GetCompletedCount() == 0, "completedCount should be 0")
		assert(HCS:GetRejectedCount()  == 0, "rejectedCount should be 0")
	end)

	check("HCS: GetHoleStatus default = { status='WaitingForFinish', completed=false }", function()
		local hs = HCS:GetHoleStatus(player)
		assert(hs.status    == "WaitingForFinish",
			("expected 'WaitingForFinish', got %q"):format(hs.status))
		assert(hs.completed == false,
			"expected completed=false")
	end)

	-- ── ProcessLanding: validation rejections ────────────────────────────────

	check("HCS: ProcessLanding non-table → success=false, status='InvalidData'", function()
		local result = HCS:ProcessLanding(player, "bad" :: any)
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidData",
			("expected 'InvalidData', got %q"):format(result.status))
	end)

	check("HCS: rejectedCount = 1 after non-table", function()
		assert(HCS:GetRejectedCount() == 1,
			("expected 1, got %d"):format(HCS:GetRejectedCount()))
	end)

	check("HCS: ProcessLanding missing position → success=false, status='InvalidPosition'", function()
		local result = HCS:ProcessLanding(player, {} :: any)
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidPosition",
			("expected 'InvalidPosition', got %q"):format(result.status))
	end)

	check("HCS: ProcessLanding non-Vector3 position → success=false, status='InvalidPosition'", function()
		local result = HCS:ProcessLanding(player, { position = "oops" } :: any)
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidPosition",
			("expected 'InvalidPosition', got %q"):format(result.status))
	end)

	check("HCS: ProcessLanding non-boolean inCup → success=false, status='InvalidInCup'", function()
		local result = HCS:ProcessLanding(player, {
			position = Vector3.new(100, 0, 100),
			inCup    = 42,
		} :: any)
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidInCup",
			("expected 'InvalidInCup', got %q"):format(result.status))
	end)

	check("HCS: rejectedCount = 4 after four validation failures", function()
		assert(HCS:GetRejectedCount() == 4,
			("expected 4, got %d"):format(HCS:GetRejectedCount()))
	end)

	-- ── ProcessLanding: inCup=false → NotInCup (not a rejection) ─────────────

	check("HCS: ProcessLanding inCup=false → success=false, status='NotInCup', completedCount stays 0", function()
		local result = HCS:ProcessLanding(player, {
			position = Vector3.new(50, 0, 50),
			inCup    = false,
		})
		assert(result.success == false, "expected success=false")
		assert(result.status == "NotInCup",
			("expected 'NotInCup', got %q"):format(result.status))
		assert(HCS:GetCompletedCount() == 0, "completedCount should not change for NotInCup")
		assert(HCS:GetRejectedCount()  == 4, "rejectedCount should not change for NotInCup")
		local hs = HCS:GetHoleStatus(player)
		assert(hs.status == "WaitingForFinish",
			("expected 'WaitingForFinish', got %q"):format(hs.status))
	end)

	-- ── ProcessLanding: inCup=true → HoleComplete ────────────────────────────

	check("HCS: ProcessLanding inCup=true → success=true, status='HoleComplete', completedCount=1", function()
		local result = HCS:ProcessLanding(player, {
			position = Vector3.new(0, 0, 0),
			inCup    = true,
		})
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "HoleComplete",
			("expected 'HoleComplete', got %q"):format(result.status))
		assert(HCS:GetCompletedCount() == 1,
			("expected completedCount=1, got %d"):format(HCS:GetCompletedCount()))
	end)

	check("HCS: GetHoleStatus after inCup=true = { status='HoleComplete', completed=true }", function()
		local hs = HCS:GetHoleStatus(player)
		assert(hs.status    == "HoleComplete",
			("expected 'HoleComplete', got %q"):format(hs.status))
		assert(hs.completed == true,
			"expected completed=true")
	end)

	-- ── CompleteHole directly: safe even without a GameService session ─────────

	check("HCS: CompleteHole directly (no session) → success=true, completedCount=2", function()
		local result = HCS:CompleteHole(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "HoleComplete",
			("expected 'HoleComplete', got %q"):format(result.status))
		assert(HCS:GetCompletedCount() == 2,
			("expected completedCount=2, got %d"):format(HCS:GetCompletedCount()))
	end)

	-- ── Cumulative counts ─────────────────────────────────────────────────────

	check("HCS: cumulative counts — completed=2, rejected=4", function()
		assert(HCS:GetCompletedCount() == 2,
			("expected completedCount=2, got %d"):format(HCS:GetCompletedCount()))
		assert(HCS:GetRejectedCount()  == 4,
			("expected rejectedCount=4, got %d"):format(HCS:GetRejectedCount()))
	end)

	-- ── ResetPlayer ───────────────────────────────────────────────────────────

	check("HCS: ResetPlayer clears player state to default", function()
		HCS:ResetPlayer(player)
		local hs = HCS:GetHoleStatus(player)
		assert(hs.status    == "WaitingForFinish",
			("expected 'WaitingForFinish' after ResetPlayer, got %q"):format(hs.status))
		assert(hs.completed == false,
			"expected completed=false after ResetPlayer")
	end)

	-- ── ResetCounts ───────────────────────────────────────────────────────────

	check("HCS: ResetCounts clears all to 0", function()
		HCS:ResetCounts()
		assert(HCS:GetCompletedCount() == 0, "expected completedCount=0")
		assert(HCS:GetRejectedCount()  == 0, "expected rejectedCount=0")
	end)

	-- ── Update ────────────────────────────────────────────────────────────────

	check("HCS: Update(0) does not error", function()
		HCS:Update(0)
	end)

	-- ── Init guard ────────────────────────────────────────────────────────────

	check("HCS: Init called twice warns and skips", function()
		HCS:Init({})
		assert(HCS:GetCompletedCount() == 0, "counts should stay 0 after double Init")
	end)

	-- ── Destroy + re-Init ─────────────────────────────────────────────────────

	check("HCS: Destroy + re-Init — GetHoleStatus returns default", function()
		HCS:ProcessLanding(player, { position = Vector3.new(1, 0, 1), inCup = true })
		HCS:Destroy()
		assert(HCS:GetCompletedCount() == 0, "expected completedCount=0 after Destroy")
		assert(HCS:GetRejectedCount()  == 0, "expected rejectedCount=0 after Destroy")
		HCS:Init({})
		local hs = HCS:GetHoleStatus(player)
		assert(hs.status == "WaitingForFinish",
			("expected 'WaitingForFinish' after re-Init, got %q"):format(hs.status))
		assert(HCS:GetCompletedCount() == 0, "expected completedCount=0 after re-Init")
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 30 smoke tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end

-- ── Trigger per-player tests ──────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(runTests, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(runTests, player)
end
