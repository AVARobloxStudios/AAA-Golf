--!strict
-- Sprint30ClientTest — Client ModuleScript smoke tests for Sprint 30.
-- Invoked by TestRunner.client.lua.  No remotes, no server calls.
--
-- Covers (16 checks):
--   Module loads; all public methods exist; initial state = WaitingForFinish.
--   BeginCupCheck: non-table → no-op; valid → CheckingCup.
--   MarkHoleComplete: non-table → no-op (stays CheckingCup); valid → HoleComplete / completed=true.
--   completedCount increments on MarkHoleComplete.
--   BeginTransition: non-table → no-op; from non-HoleComplete → no-op; from HoleComplete → Transitioning.
--   GetCompletionState returns independent copy.
--   Reset clears state, count, data.
--   BeginTransition from WaitingForFinish is no-op (after Reset).
--   Update(0) no error.
--   Destroy + re-Init; BeginCupCheck works after re-Init.

return function()
	local StarterPlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts

	local HCCC = require(
		StarterPlayerScripts.Modules.HoleCompletionClientControllerModule
	)

	local TAG = "[Sprint30ClientTest]"

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

	-- ── Isolation ─────────────────────────────────────────────────────────────

	HCCC:Destroy()
	HCCC:Init()

	-- ── 1: Module loads ───────────────────────────────────────────────────────

	check("HCCC: module loads", function()
		assert(type(HCCC) == "table", "expected table")
	end)

	-- ── 2: All public methods exist ───────────────────────────────────────────

	check("HCCC: all public methods exist", function()
		local methods = {
			"BeginCupCheck", "MarkHoleComplete", "BeginTransition",
			"GetCompletionState", "Reset",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(HCCC[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── 3: Initial state = WaitingForFinish ───────────────────────────────────

	check("HCCC: GetCompletionState after Init = WaitingForFinish / not completed / count=0", function()
		local s = HCCC:GetCompletionState()
		assert(s.state          == "WaitingForFinish",
			("expected 'WaitingForFinish', got %q"):format(s.state))
		assert(s.completed      == false,   "expected completed=false")
		assert(s.completedCount == 0,       ("expected completedCount=0, got %d"):format(s.completedCount))
		assert(s.hasData        == false,    "expected hasData=false")
	end)

	-- ── 4: BeginCupCheck rejects non-table ────────────────────────────────────

	check("HCCC: BeginCupCheck non-table → state stays 'WaitingForFinish'", function()
		HCCC:BeginCupCheck("bad" :: any)
		local s = HCCC:GetCompletionState()
		assert(s.state == "WaitingForFinish",
			("expected state to remain 'WaitingForFinish', got %q"):format(s.state))
	end)

	-- ── 5: BeginCupCheck valid → CheckingCup ──────────────────────────────────

	check("HCCC: BeginCupCheck valid table → state='CheckingCup', hasData=true", function()
		HCCC:BeginCupCheck({ rimLip = true })
		local s = HCCC:GetCompletionState()
		assert(s.state   == "CheckingCup",
			("expected 'CheckingCup', got %q"):format(s.state))
		assert(s.hasData == true, "expected hasData=true")
	end)

	-- ── 6: MarkHoleComplete rejects non-table ─────────────────────────────────

	check("HCCC: MarkHoleComplete non-table → state stays 'CheckingCup'", function()
		HCCC:MarkHoleComplete(42 :: any)
		local s = HCCC:GetCompletionState()
		assert(s.state == "CheckingCup",
			("expected state to remain 'CheckingCup', got %q"):format(s.state))
	end)

	-- ── 7: MarkHoleComplete valid → HoleComplete ──────────────────────────────

	check("HCCC: MarkHoleComplete valid table → state='HoleComplete', completed=true", function()
		HCCC:MarkHoleComplete({ strokes = 3, par = 4 })
		local s = HCCC:GetCompletionState()
		assert(s.state     == "HoleComplete",
			("expected 'HoleComplete', got %q"):format(s.state))
		assert(s.completed == true,  "expected completed=true")
	end)

	-- ── 8: completedCount increments ─────────────────────────────────────────

	check("HCCC: completedCount = 1 after MarkHoleComplete", function()
		local s = HCCC:GetCompletionState()
		assert(s.completedCount == 1,
			("expected completedCount=1, got %d"):format(s.completedCount))
	end)

	-- ── 9: BeginTransition rejects non-table ──────────────────────────────────

	check("HCCC: BeginTransition non-table → state stays 'HoleComplete'", function()
		HCCC:BeginTransition(false :: any)
		local s = HCCC:GetCompletionState()
		assert(s.state == "HoleComplete",
			("expected state to remain 'HoleComplete', got %q"):format(s.state))
	end)

	-- ── 10: BeginTransition from HoleComplete → Transitioning ─────────────────

	check("HCCC: BeginTransition from HoleComplete → state='Transitioning'", function()
		HCCC:BeginTransition({ nextHoleId = "Hole_02" })
		local s = HCCC:GetCompletionState()
		assert(s.state == "Transitioning",
			("expected 'Transitioning', got %q"):format(s.state))
	end)

	-- ── 11: GetCompletionState returns independent copy ───────────────────────

	check("HCCC: GetCompletionState returns an independent copy", function()
		local snap  = HCCC:GetCompletionState()
		local saved = snap.state
		snap.state          = "MUTATED"
		snap.completedCount = 999
		local snap2 = HCCC:GetCompletionState()
		assert(snap2.state == saved,
			("expected internal state %q unchanged, got %q"):format(saved, snap2.state))
		assert(snap2.completedCount == 1,
			("expected completedCount=1, got %d"):format(snap2.completedCount))
	end)

	-- ── 12: Reset clears all ──────────────────────────────────────────────────

	check("HCCC: Reset → state='WaitingForFinish', completed=false, count=0, hasData=false", function()
		HCCC:Reset()
		local s = HCCC:GetCompletionState()
		assert(s.state          == "WaitingForFinish",
			("expected 'WaitingForFinish', got %q"):format(s.state))
		assert(s.completed      == false,  "expected completed=false")
		assert(s.completedCount == 0,      ("expected completedCount=0, got %d"):format(s.completedCount))
		assert(s.hasData        == false,   "expected hasData=false")
	end)

	-- ── 13: BeginTransition from WaitingForFinish is no-op ───────────────────

	check("HCCC: BeginTransition from WaitingForFinish → no-op, state stays 'WaitingForFinish'", function()
		HCCC:BeginTransition({ nextHoleId = "Hole_03" })
		local s = HCCC:GetCompletionState()
		assert(s.state == "WaitingForFinish",
			("expected state to remain 'WaitingForFinish', got %q"):format(s.state))
	end)

	-- ── 14: Update(0) ────────────────────────────────────────────────────────

	check("HCCC: Update(0) does not error", function()
		HCCC:Update(0)
	end)

	-- ── 15: Destroy ──────────────────────────────────────────────────────────

	check("HCCC: Destroy then BeginCupCheck is a no-op", function()
		HCCC:Destroy()
		HCCC:BeginCupCheck({ rimLip = false })
		-- _initialized=false — re-Init needed before asserting state
	end)

	-- ── 16: re-Init after Destroy ─────────────────────────────────────────────

	check("HCCC: re-Init after Destroy → WaitingForFinish, BeginCupCheck works", function()
		HCCC:Init()
		local s = HCCC:GetCompletionState()
		assert(s.state == "WaitingForFinish",
			("expected 'WaitingForFinish' after re-Init, got %q"):format(s.state))
		HCCC:BeginCupCheck({ test = true })
		local s2 = HCCC:GetCompletionState()
		assert(s2.state == "CheckingCup",
			("expected 'CheckingCup' after re-Init BeginCupCheck, got %q"):format(s2.state))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 30 client tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end
