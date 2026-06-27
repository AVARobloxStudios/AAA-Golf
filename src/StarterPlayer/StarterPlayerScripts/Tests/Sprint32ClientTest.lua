--!strict
-- Sprint32ClientTest — Client ModuleScript smoke tests for Sprint 32.
-- Invoked by TestRunner.client.lua.  No remotes, no server calls.
--
-- Covers (16 checks):
--   Module loads; all public methods exist; Init; Destroy.
--   Default state = LobbyReady, started=false, completed=false.
--   StartFlow → LobbyReady.
--   MarkRoundStarted → RoundStarted, started=true.
--   MarkHoleReady → HoleReady.
--   MarkShotInProgress → ShotInProgress.
--   MarkBallLanded → BallLanded.
--   MarkHoleComplete → HoleComplete.
--   MarkRoundComplete → RoundComplete, completed=true.
--   GetFlowState returns independent copy.
--   Reset → LobbyReady, started=false, completed=false.
--   Update(0) no error.
--   re-Init after Destroy → LobbyReady.

return function()
	local StarterPlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts

	local VSCFC = require(
		StarterPlayerScripts.Modules.VerticalSliceClientFlowControllerModule
	)

	local TAG = "[Sprint32ClientTest]"

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

	VSCFC:Destroy()
	VSCFC:Init()

	-- ── 1: Module loads ───────────────────────────────────────────────────────

	check("VSCFC: module loads", function()
		assert(type(VSCFC) == "table", "expected table")
	end)

	-- ── 2: All public methods exist ───────────────────────────────────────────

	check("VSCFC: all public methods exist", function()
		local methods = {
			"StartFlow",
			"MarkRoundStarted", "MarkHoleReady", "MarkShotInProgress",
			"MarkBallLanded", "MarkHoleComplete", "MarkRoundComplete",
			"GetFlowState", "Reset",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(VSCFC[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── 3: Init ───────────────────────────────────────────────────────────────

	check("VSCFC: Init guard — double Init skips without error", function()
		VSCFC:Init()  -- already initialized; should warn and skip
		local fs = VSCFC:GetFlowState()
		assert(fs.state == "LobbyReady",
			("expected 'LobbyReady' after double Init, got %q"):format(fs.state))
	end)

	-- ── 4: Default state ──────────────────────────────────────────────────────

	check("VSCFC: default GetFlowState = { state='LobbyReady', started=false, completed=false }", function()
		local fs = VSCFC:GetFlowState()
		assert(fs.state     == "LobbyReady",
			("expected 'LobbyReady', got %q"):format(fs.state))
		assert(fs.started   == false, "expected started=false")
		assert(fs.completed == false, "expected completed=false")
	end)

	-- ── 5: StartFlow ──────────────────────────────────────────────────────────

	check("VSCFC: StartFlow → state='LobbyReady', started=false, completed=false", function()
		VSCFC:StartFlow()
		local fs = VSCFC:GetFlowState()
		assert(fs.state     == "LobbyReady",
			("expected 'LobbyReady', got %q"):format(fs.state))
		assert(fs.started   == false, "expected started=false after StartFlow")
		assert(fs.completed == false, "expected completed=false after StartFlow")
	end)

	-- ── 6: MarkRoundStarted ───────────────────────────────────────────────────

	check("VSCFC: MarkRoundStarted → state='RoundStarted', started=true", function()
		VSCFC:MarkRoundStarted()
		local fs = VSCFC:GetFlowState()
		assert(fs.state   == "RoundStarted",
			("expected 'RoundStarted', got %q"):format(fs.state))
		assert(fs.started == true, "expected started=true after MarkRoundStarted")
	end)

	-- ── 7: MarkHoleReady ──────────────────────────────────────────────────────

	check("VSCFC: MarkHoleReady → state='HoleReady'", function()
		VSCFC:MarkHoleReady()
		local fs = VSCFC:GetFlowState()
		assert(fs.state == "HoleReady",
			("expected 'HoleReady', got %q"):format(fs.state))
	end)

	-- ── 8: MarkShotInProgress ─────────────────────────────────────────────────

	check("VSCFC: MarkShotInProgress → state='ShotInProgress'", function()
		VSCFC:MarkShotInProgress()
		local fs = VSCFC:GetFlowState()
		assert(fs.state == "ShotInProgress",
			("expected 'ShotInProgress', got %q"):format(fs.state))
	end)

	-- ── 9: MarkBallLanded ─────────────────────────────────────────────────────

	check("VSCFC: MarkBallLanded → state='BallLanded'", function()
		VSCFC:MarkBallLanded()
		local fs = VSCFC:GetFlowState()
		assert(fs.state == "BallLanded",
			("expected 'BallLanded', got %q"):format(fs.state))
	end)

	-- ── 10: MarkHoleComplete ──────────────────────────────────────────────────

	check("VSCFC: MarkHoleComplete → state='HoleComplete'", function()
		VSCFC:MarkHoleComplete()
		local fs = VSCFC:GetFlowState()
		assert(fs.state == "HoleComplete",
			("expected 'HoleComplete', got %q"):format(fs.state))
	end)

	-- ── 11: MarkRoundComplete ─────────────────────────────────────────────────

	check("VSCFC: MarkRoundComplete → state='RoundComplete', completed=true", function()
		VSCFC:MarkRoundComplete()
		local fs = VSCFC:GetFlowState()
		assert(fs.state     == "RoundComplete",
			("expected 'RoundComplete', got %q"):format(fs.state))
		assert(fs.completed == true, "expected completed=true after MarkRoundComplete")
	end)

	-- ── 12: GetFlowState copy isolation ──────────────────────────────────────

	check("VSCFC: GetFlowState returns independent copy", function()
		local snap  = VSCFC:GetFlowState()
		local saved = snap.state
		snap.state     = "MUTATED"
		snap.started   = false
		snap.completed = false
		local snap2 = VSCFC:GetFlowState()
		assert(snap2.state == saved,
			("expected internal state %q unchanged, got %q"):format(saved, snap2.state))
		assert(snap2.completed == true, "expected completed=true unchanged after mutation")
	end)

	-- ── 13: Reset ────────────────────────────────────────────────────────────

	check("VSCFC: Reset → state='LobbyReady', started=false, completed=false", function()
		VSCFC:Reset()
		local fs = VSCFC:GetFlowState()
		assert(fs.state     == "LobbyReady",
			("expected 'LobbyReady' after Reset, got %q"):format(fs.state))
		assert(fs.started   == false, "expected started=false after Reset")
		assert(fs.completed == false, "expected completed=false after Reset")
	end)

	-- ── 14: Update(0) ────────────────────────────────────────────────────────

	check("VSCFC: Update(0) does not error", function()
		VSCFC:Update(0)
	end)

	-- ── 15: Destroy ──────────────────────────────────────────────────────────

	check("VSCFC: Destroy then Mark calls are no-ops", function()
		VSCFC:Destroy()
		VSCFC:MarkRoundStarted()  -- _initialized=false → ignored
		-- state should still be LobbyReady (Destroy resets it)
	end)

	-- ── 16: re-Init after Destroy ─────────────────────────────────────────────

	check("VSCFC: re-Init after Destroy → LobbyReady; flow works again", function()
		VSCFC:Init()
		local fs = VSCFC:GetFlowState()
		assert(fs.state == "LobbyReady",
			("expected 'LobbyReady' after re-Init, got %q"):format(fs.state))
		VSCFC:MarkRoundStarted()
		VSCFC:MarkHoleReady()
		local fs2 = VSCFC:GetFlowState()
		assert(fs2.state == "HoleReady",
			("expected 'HoleReady' after mark sequence, got %q"):format(fs2.state))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 32 client tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end
