--!strict
-- Sprint31ServerTest — Server Script smoke tests for Sprint 31.
-- Run in Studio Play Solo mode.
--
-- No DataStore profile gate required — RoundCompletionService stores local state
-- only and has no dependency on GameService, ScoringService, or DataStore.
--
-- Covers (20 checks):
--   Immediate (3): module loading, Init/Destroy exist.
--   Player-gated (17):
--     NotifyHoleCompleted before Init → NotInitialized.
--     API surface — all public methods are functions.
--     Counts = 0 after Init.
--     GetRoundCompletionState default = { state="Idle", completed=false }.
--     NotifyHoleCompleted success → PendingFinalize.
--     NotifyHoleCompleted duplicate → AlreadyCompleted, rejectedCount=1.
--     FinalizeRound success → Completed, completedRounds=1.
--     GetRoundCompletionState = Completed, completed=true.
--     FinalizeRound invalid state → InvalidState, rejectedCount=2.
--     GetRoundCompletionState copy isolation.
--     completedRounds = 1.
--     rejectedCount = 2.
--     ResetPlayer clears state.
--     ResetCounts.
--     Update(0).
--     Init guard.
--     Destroy + re-Init.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RCS = require(ServerScriptService.Services.RoundCompletionService)

local TAG = "[Sprint31ServerTest]"

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

check("RCS: module loads", function()
	assert(type(RCS) == "table", "expected table")
end)

check("RCS: Init function exists", function()
	assert(type(RCS.Init) == "function")
end)

check("RCS: Destroy function exists", function()
	assert(type(RCS.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 31 round completion tests for " .. player.Name .. " ──")

	-- ── Pre-Init: verify not-initialized behavior ─────────────────────────────

	RCS:Destroy()

	check("RCS: NotifyHoleCompleted before Init → success=false, status='NotInitialized'", function()
		local result = RCS:NotifyHoleCompleted(player)
		assert(result.success == false, "expected success=false")
		assert(result.status == "NotInitialized",
			("expected 'NotInitialized', got %q"):format(result.status))
	end)

	RCS:Init({})

	-- ── API surface ───────────────────────────────────────────────────────────

	check("RCS: all public methods exist", function()
		local methods = {
			"NotifyHoleCompleted", "FinalizeRound", "GetRoundCompletionState",
			"ResetPlayer", "GetCompletedRounds", "GetRejectedCount", "ResetCounts",
		}
		for _, name in ipairs(methods) do
			assert(type(RCS[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	check("RCS: counts = 0 after Init", function()
		assert(RCS:GetCompletedRounds() == 0, "completedRounds should be 0")
		assert(RCS:GetRejectedCount()   == 0, "rejectedCount should be 0")
	end)

	check("RCS: GetRoundCompletionState default = { state='Idle', completed=false }", function()
		local rs = RCS:GetRoundCompletionState(player)
		assert(rs.state     == "Idle",  ("expected 'Idle', got %q"):format(rs.state))
		assert(rs.completed == false,    "expected completed=false")
	end)

	-- ── NotifyHoleCompleted: success ──────────────────────────────────────────

	check("RCS: NotifyHoleCompleted success → success=true, status='PendingFinalize'", function()
		local result = RCS:NotifyHoleCompleted(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "PendingFinalize",
			("expected 'PendingFinalize', got %q"):format(result.status))
	end)

	-- ── NotifyHoleCompleted: duplicate rejection ──────────────────────────────

	check("RCS: NotifyHoleCompleted duplicate → success=false, status='AlreadyCompleted', rejectedCount=1", function()
		local result = RCS:NotifyHoleCompleted(player)
		assert(result.success == false, "expected success=false on duplicate")
		assert(result.status == "AlreadyCompleted",
			("expected 'AlreadyCompleted', got %q"):format(result.status))
		assert(RCS:GetRejectedCount() == 1,
			("expected rejectedCount=1, got %d"):format(RCS:GetRejectedCount()))
	end)

	-- ── FinalizeRound: success ────────────────────────────────────────────────

	check("RCS: FinalizeRound success → success=true, status='RoundCompleted', completedRounds=1", function()
		local result = RCS:FinalizeRound(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "RoundCompleted",
			("expected 'RoundCompleted', got %q"):format(result.status))
		assert(RCS:GetCompletedRounds() == 1,
			("expected completedRounds=1, got %d"):format(RCS:GetCompletedRounds()))
	end)

	check("RCS: GetRoundCompletionState after FinalizeRound = { state='Completed', completed=true }", function()
		local rs = RCS:GetRoundCompletionState(player)
		assert(rs.state     == "Completed",
			("expected 'Completed', got %q"):format(rs.state))
		assert(rs.completed == true,
			"expected completed=true")
	end)

	-- ── FinalizeRound: invalid state ──────────────────────────────────────────

	check("RCS: FinalizeRound invalid state → success=false, status='InvalidState', rejectedCount=2", function()
		local result = RCS:FinalizeRound(player)
		assert(result.success == false, "expected success=false on invalid state")
		assert(result.status == "InvalidState",
			("expected 'InvalidState', got %q"):format(result.status))
		assert(RCS:GetRejectedCount() == 2,
			("expected rejectedCount=2, got %d"):format(RCS:GetRejectedCount()))
	end)

	-- ── GetRoundCompletionState copy isolation ────────────────────────────────

	check("RCS: GetRoundCompletionState returns independent copy", function()
		local snap  = RCS:GetRoundCompletionState(player)
		local saved = snap.state
		snap.state     = "MUTATED"
		snap.completed = false
		local snap2 = RCS:GetRoundCompletionState(player)
		assert(snap2.state == saved,
			("expected internal state %q unchanged, got %q"):format(saved, snap2.state))
		assert(snap2.completed == true,
			"expected completed=true unchanged after mutation")
	end)

	-- ── Cumulative counts ─────────────────────────────────────────────────────

	check("RCS: completedRounds = 1", function()
		assert(RCS:GetCompletedRounds() == 1,
			("expected 1, got %d"):format(RCS:GetCompletedRounds()))
	end)

	check("RCS: rejectedCount = 2", function()
		assert(RCS:GetRejectedCount() == 2,
			("expected 2, got %d"):format(RCS:GetRejectedCount()))
	end)

	-- ── ResetPlayer ───────────────────────────────────────────────────────────

	check("RCS: ResetPlayer clears state to default Idle", function()
		RCS:ResetPlayer(player)
		local rs = RCS:GetRoundCompletionState(player)
		assert(rs.state     == "Idle",
			("expected 'Idle' after ResetPlayer, got %q"):format(rs.state))
		assert(rs.completed == false,
			"expected completed=false after ResetPlayer")
	end)

	-- ── ResetCounts ───────────────────────────────────────────────────────────

	check("RCS: ResetCounts clears all to 0", function()
		RCS:ResetCounts()
		assert(RCS:GetCompletedRounds() == 0, "expected completedRounds=0")
		assert(RCS:GetRejectedCount()   == 0, "expected rejectedCount=0")
	end)

	-- ── Update ────────────────────────────────────────────────────────────────

	check("RCS: Update(0) does not error", function()
		RCS:Update(0)
	end)

	-- ── Init guard ────────────────────────────────────────────────────────────

	check("RCS: Init called twice warns and skips", function()
		RCS:Init({})
		assert(RCS:GetCompletedRounds() == 0, "counts should stay 0 after double Init")
	end)

	-- ── Destroy + re-Init ─────────────────────────────────────────────────────

	check("RCS: Destroy + re-Init — GetRoundCompletionState returns Idle", function()
		RCS:NotifyHoleCompleted(player)    -- PendingFinalize, completedRounds=0, rejected=0
		RCS:FinalizeRound(player)          -- Completed, completedRounds=1
		RCS:Destroy()
		assert(RCS:GetCompletedRounds() == 0, "expected completedRounds=0 after Destroy")
		assert(RCS:GetRejectedCount()   == 0, "expected rejectedCount=0 after Destroy")
		RCS:Init({})
		local rs = RCS:GetRoundCompletionState(player)
		assert(rs.state == "Idle",
			("expected 'Idle' after re-Init, got %q"):format(rs.state))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 31 smoke tests PASSED.")
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
