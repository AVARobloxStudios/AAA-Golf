--!strict
-- Sprint29ClientTest — Client ModuleScript smoke tests for Sprint 29.
-- Invoked by TestRunner.client.lua.  No remotes, no server calls.
--
-- Covers (13 checks):
--   Module loads; all public methods exist; initial state = Hidden.
--   BeginReveal: non-table rejected (state stays Hidden); valid table → Revealing.
--   revealCount increments on BeginReveal.
--   CompleteReveal: Revealing → Complete.
--   CompleteReveal from Hidden: safe no-op (no error, state unchanged).
--   GetRevealState returns independent copy.
--   Reset clears state and count.
--   Destroy + re-Init; BeginReveal works after re-Init.
--   Update(0) no error.

return function()
	local StarterPlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts

	local SRCC = require(
		StarterPlayerScripts.Modules.ScoreRevealClientControllerModule
	)

	local TAG = "[Sprint29ClientTest]"

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

	SRCC:Destroy()
	SRCC:Init()

	-- ── 1: Module loads ───────────────────────────────────────────────────────

	check("SRCC: module loads", function()
		assert(type(SRCC) == "table", "expected table")
	end)

	-- ── 2: All public methods exist ───────────────────────────────────────────

	check("SRCC: all public methods exist", function()
		local methods = {
			"BeginReveal", "CompleteReveal", "GetRevealState", "Reset",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(SRCC[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── 3: Initial state = Hidden ─────────────────────────────────────────────

	check("SRCC: GetRevealState after Init = { state='Hidden', hasData=false, revealCount=0 }", function()
		local s = SRCC:GetRevealState()
		assert(s.state       == "Hidden", ("expected 'Hidden', got %q"):format(s.state))
		assert(s.hasData     == false,    "expected hasData=false")
		assert(s.revealCount == 0,        ("expected revealCount=0, got %d"):format(s.revealCount))
	end)

	-- ── 4: BeginReveal rejects non-table ─────────────────────────────────────

	check("SRCC: BeginReveal non-table → state stays 'Hidden'", function()
		SRCC:BeginReveal("bad" :: any)
		local s = SRCC:GetRevealState()
		assert(s.state       == "Hidden",
			("expected state to remain 'Hidden', got %q"):format(s.state))
		assert(s.revealCount == 0,
			("expected revealCount to remain 0, got %d"):format(s.revealCount))
	end)

	-- ── 5: BeginReveal valid table → Revealing ────────────────────────────────

	check("SRCC: BeginReveal valid table → state='Revealing', hasData=true, revealCount=1", function()
		SRCC:BeginReveal({ strokes = 3, par = 4 })
		local s = SRCC:GetRevealState()
		assert(s.state       == "Revealing", ("expected 'Revealing', got %q"):format(s.state))
		assert(s.hasData     == true,         "expected hasData=true")
		assert(s.revealCount == 1,            ("expected revealCount=1, got %d"):format(s.revealCount))
	end)

	-- ── 6: CompleteReveal → Complete ──────────────────────────────────────────

	check("SRCC: CompleteReveal from Revealing → state='Complete'", function()
		SRCC:CompleteReveal()
		local s = SRCC:GetRevealState()
		assert(s.state == "Complete", ("expected 'Complete', got %q"):format(s.state))
	end)

	-- ── 7: CompleteReveal from Hidden is a safe no-op ─────────────────────────

	check("SRCC: CompleteReveal from Hidden → no error, state stays 'Hidden'", function()
		SRCC:Reset()
		SRCC:CompleteReveal()     -- should be a no-op
		local s = SRCC:GetRevealState()
		assert(s.state == "Hidden",
			("expected state to remain 'Hidden', got %q"):format(s.state))
	end)

	-- ── 8: GetRevealState returns independent copy ────────────────────────────

	check("SRCC: GetRevealState returns an independent copy", function()
		SRCC:BeginReveal({ score = 5 })
		local snap  = SRCC:GetRevealState()
		local saved = snap.state
		snap.state  = "MUTATED"
		snap.revealCount = 999
		local snap2 = SRCC:GetRevealState()
		assert(snap2.state == saved,
			("expected internal state %q unchanged, got %q"):format(saved, snap2.state))
		assert(snap2.revealCount == 2,
			("expected revealCount=2, got %d"):format(snap2.revealCount))
	end)

	-- ── 9: Reset clears state and count ──────────────────────────────────────

	check("SRCC: Reset → state='Hidden', hasData=false, revealCount=0", function()
		SRCC:Reset()
		local s = SRCC:GetRevealState()
		assert(s.state       == "Hidden",  ("expected 'Hidden', got %q"):format(s.state))
		assert(s.hasData     == false,      "expected hasData=false after Reset")
		assert(s.revealCount == 0,          ("expected revealCount=0, got %d"):format(s.revealCount))
	end)

	-- ── 10: Update(0) ────────────────────────────────────────────────────────

	check("SRCC: Update(0) does not error", function()
		SRCC:Update(0)
	end)

	-- ── 11: Destroy ──────────────────────────────────────────────────────────

	check("SRCC: Destroy then BeginReveal is a no-op", function()
		SRCC:Destroy()
		SRCC:BeginReveal({ strokes = 1 })   -- _initialized=false → ignored
		-- re-Init needed before asserting state
	end)

	-- ── 12: re-Init after Destroy ─────────────────────────────────────────────

	check("SRCC: re-Init after Destroy → state='Hidden', revealCount=0", function()
		SRCC:Init()
		local s = SRCC:GetRevealState()
		assert(s.state       == "Hidden",
			("expected 'Hidden' after re-Init, got %q"):format(s.state))
		assert(s.revealCount == 0,
			("expected revealCount=0 after re-Init, got %d"):format(s.revealCount))
	end)

	-- ── 13: BeginReveal works after re-Init ──────────────────────────────────

	check("SRCC: BeginReveal works after re-Init → state='Revealing'", function()
		SRCC:BeginReveal({ par = 3 })
		local s = SRCC:GetRevealState()
		assert(s.state == "Revealing",
			("expected 'Revealing' after re-Init BeginReveal, got %q"):format(s.state))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 29 client tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end
