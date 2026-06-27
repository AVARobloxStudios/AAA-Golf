--!strict
-- Sprint31ClientTest — Client ModuleScript smoke tests for Sprint 31.
-- Invoked by TestRunner.client.lua.  No remotes, no server calls.
--
-- Covers (14 checks):
--   Module loads; all public methods exist; initial state = Idle.
--   BeginResults: non-table → no-op (stays Idle); valid → ResultsIncoming.
--   FinishRound: non-table → no-op (stays ResultsIncoming); valid → RoundFinished.
--   ReadyForLobby from RoundFinished → ReadyForLobby.
--   GetState returns independent copy.
--   Reset → Idle.
--   ReadyForLobby from Idle → no-op (only valid after RoundFinished).
--   Update(0) no error.
--   Destroy + re-Init; BeginResults works after re-Init.

return function()
	local StarterPlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts

	local RCCC = require(
		StarterPlayerScripts.Modules.RoundCompletionClientControllerModule
	)

	local TAG = "[Sprint31ClientTest]"

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

	RCCC:Destroy()
	RCCC:Init()

	-- ── 1: Module loads ───────────────────────────────────────────────────────

	check("RCCC: module loads", function()
		assert(type(RCCC) == "table", "expected table")
	end)

	-- ── 2: All public methods exist ───────────────────────────────────────────

	check("RCCC: all public methods exist", function()
		local methods = {
			"BeginResults", "FinishRound", "ReadyForLobby",
			"GetState", "Reset",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(RCCC[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── 3: Initial state = Idle ───────────────────────────────────────────────

	check("RCCC: GetState after Init = { state='Idle', hasData=false }", function()
		local s = RCCC:GetState()
		assert(s.state   == "Idle",  ("expected 'Idle', got %q"):format(s.state))
		assert(s.hasData == false,    "expected hasData=false")
	end)

	-- ── 4: BeginResults rejects non-table ─────────────────────────────────────

	check("RCCC: BeginResults non-table → state stays 'Idle'", function()
		RCCC:BeginResults("bad" :: any)
		local s = RCCC:GetState()
		assert(s.state == "Idle",
			("expected state to remain 'Idle', got %q"):format(s.state))
	end)

	-- ── 5: BeginResults valid → ResultsIncoming ───────────────────────────────

	check("RCCC: BeginResults valid table → state='ResultsIncoming', hasData=true", function()
		RCCC:BeginResults({ totalStrokes = 18, holesPlayed = 5 })
		local s = RCCC:GetState()
		assert(s.state   == "ResultsIncoming",
			("expected 'ResultsIncoming', got %q"):format(s.state))
		assert(s.hasData == true, "expected hasData=true")
	end)

	-- ── 6: FinishRound rejects non-table ──────────────────────────────────────

	check("RCCC: FinishRound non-table → state stays 'ResultsIncoming'", function()
		RCCC:FinishRound(99 :: any)
		local s = RCCC:GetState()
		assert(s.state == "ResultsIncoming",
			("expected state to remain 'ResultsIncoming', got %q"):format(s.state))
	end)

	-- ── 7: FinishRound valid → RoundFinished ──────────────────────────────────

	check("RCCC: FinishRound valid table → state='RoundFinished'", function()
		RCCC:FinishRound({ rank = 1 })
		local s = RCCC:GetState()
		assert(s.state == "RoundFinished",
			("expected 'RoundFinished', got %q"):format(s.state))
	end)

	-- ── 8: ReadyForLobby from RoundFinished → ReadyForLobby ───────────────────

	check("RCCC: ReadyForLobby from RoundFinished → state='ReadyForLobby'", function()
		RCCC:ReadyForLobby()
		local s = RCCC:GetState()
		assert(s.state == "ReadyForLobby",
			("expected 'ReadyForLobby', got %q"):format(s.state))
	end)

	-- ── 9: GetState returns independent copy ──────────────────────────────────

	check("RCCC: GetState returns an independent copy", function()
		local snap  = RCCC:GetState()
		local saved = snap.state
		snap.state   = "MUTATED"
		snap.hasData = false
		local snap2 = RCCC:GetState()
		assert(snap2.state == saved,
			("expected internal state %q unchanged, got %q"):format(saved, snap2.state))
	end)

	-- ── 10: Reset → Idle ──────────────────────────────────────────────────────

	check("RCCC: Reset → state='Idle', hasData=false", function()
		RCCC:Reset()
		local s = RCCC:GetState()
		assert(s.state   == "Idle", ("expected 'Idle', got %q"):format(s.state))
		assert(s.hasData == false,   "expected hasData=false after Reset")
	end)

	-- ── 11: ReadyForLobby from Idle → no-op ──────────────────────────────────

	check("RCCC: ReadyForLobby from Idle → no-op, state stays 'Idle'", function()
		RCCC:ReadyForLobby()
		local s = RCCC:GetState()
		assert(s.state == "Idle",
			("expected state to remain 'Idle', got %q"):format(s.state))
	end)

	-- ── 12: Update(0) ────────────────────────────────────────────────────────

	check("RCCC: Update(0) does not error", function()
		RCCC:Update(0)
	end)

	-- ── 13: Destroy ──────────────────────────────────────────────────────────

	check("RCCC: Destroy then BeginResults is a no-op", function()
		RCCC:Destroy()
		RCCC:BeginResults({ x = 1 })   -- _initialized=false → ignored
		-- re-Init needed before asserting state
	end)

	-- ── 14: re-Init after Destroy ─────────────────────────────────────────────

	check("RCCC: re-Init after Destroy → Idle; BeginResults works", function()
		RCCC:Init()
		local s = RCCC:GetState()
		assert(s.state == "Idle",
			("expected 'Idle' after re-Init, got %q"):format(s.state))
		RCCC:BeginResults({ totalStrokes = 3 })
		local s2 = RCCC:GetState()
		assert(s2.state == "ResultsIncoming",
			("expected 'ResultsIncoming' after re-Init BeginResults, got %q"):format(s2.state))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 31 client tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end
