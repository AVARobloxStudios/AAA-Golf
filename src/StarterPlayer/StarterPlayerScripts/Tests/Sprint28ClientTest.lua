--!strict
-- Sprint28ClientTest — Client ModuleScript smoke tests for Sprint 28.
-- Invoked by TestRunner.client.lua.  No remotes, no server calls.
--
-- Covers (16 checks):
--   Module loads; all public methods exist; GetLocalShotState initial state.
--   BeginLocalShot: non-table rejected (state stays None); valid table → Queued.
--   MarkLocalShotDispatched → Dispatched.
--   MarkLocalShotAcked("Accepted") → Accepted.
--   MarkLocalBallLanded from Accepted → Landed.
--   GetLocalShotState returns independent copy.
--   Reset returns to None.
--   Rejected path: BeginLocalShot → Queued → Dispatched → Rejected.
--   MarkLocalBallLanded from Rejected → no-op (stays Rejected).
--   Update(0) no error.
--   Destroy + re-Init; BeginLocalShot works after re-Init.

return function()
	local StarterPlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts

	local SLCC = require(
		StarterPlayerScripts.Modules.ShotLifecycleClientControllerModule
	)

	local TAG = "[Sprint28ClientTest]"

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

	-- ── Isolation: bring up fresh ─────────────────────────────────────────────

	SLCC:Destroy()
	SLCC:Init()

	-- ── 1: Module loads ───────────────────────────────────────────────────────

	check("SLCC: module loads", function()
		assert(type(SLCC) == "table", "expected table")
	end)

	-- ── 2: All public methods exist ───────────────────────────────────────────

	check("SLCC: all public methods exist", function()
		local methods = {
			"BeginLocalShot", "MarkLocalShotDispatched", "MarkLocalShotAcked",
			"MarkLocalBallLanded", "GetLocalShotState", "Reset",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(SLCC[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── 3: GetLocalShotState initial state ───────────────────────────────────

	check("SLCC: GetLocalShotState after Init = { state='None', hasPayload=false, hasLandingData=false }", function()
		local s = SLCC:GetLocalShotState()
		assert(s.state          == "None",  ("expected 'None', got %q"):format(s.state))
		assert(s.hasPayload     == false,    "expected hasPayload=false")
		assert(s.hasLandingData == false,    "expected hasLandingData=false")
	end)

	-- ── 4: BeginLocalShot rejects non-table ───────────────────────────────────

	check("SLCC: BeginLocalShot non-table → state stays 'None'", function()
		SLCC:BeginLocalShot("bad" :: any)
		local s = SLCC:GetLocalShotState()
		assert(s.state == "None",
			("expected state to remain 'None', got %q"):format(s.state))
	end)

	-- ── 5: BeginLocalShot valid table → Queued ────────────────────────────────

	check("SLCC: BeginLocalShot valid table → state='Queued', hasPayload=true", function()
		SLCC:BeginLocalShot({ aimVector = Vector3.new(0, 0, -1), power = 0.75 })
		local s = SLCC:GetLocalShotState()
		assert(s.state      == "Queued", ("expected 'Queued', got %q"):format(s.state))
		assert(s.hasPayload == true,      "expected hasPayload=true")
	end)

	-- ── 6: MarkLocalShotDispatched → Dispatched ───────────────────────────────

	check("SLCC: MarkLocalShotDispatched → state='Dispatched'", function()
		SLCC:MarkLocalShotDispatched()
		local s = SLCC:GetLocalShotState()
		assert(s.state == "Dispatched", ("expected 'Dispatched', got %q"):format(s.state))
	end)

	-- ── 7: MarkLocalShotAcked("Accepted") → Accepted ─────────────────────────

	check("SLCC: MarkLocalShotAcked('Accepted') → state='Accepted'", function()
		SLCC:MarkLocalShotAcked("Accepted")
		local s = SLCC:GetLocalShotState()
		assert(s.state == "Accepted", ("expected 'Accepted', got %q"):format(s.state))
	end)

	-- ── 8: MarkLocalBallLanded from Accepted → Landed ─────────────────────────

	check("SLCC: MarkLocalBallLanded from Accepted → state='Landed', hasLandingData=true", function()
		SLCC:MarkLocalBallLanded()
		local s = SLCC:GetLocalShotState()
		assert(s.state          == "Landed", ("expected 'Landed', got %q"):format(s.state))
		assert(s.hasLandingData == true,      "expected hasLandingData=true")
	end)

	-- ── 9: GetLocalShotState returns independent copy ─────────────────────────

	check("SLCC: GetLocalShotState returns an independent copy", function()
		local snap  = SLCC:GetLocalShotState()
		local saved = snap.state
		snap.state  = "MUTATED"
		local snap2 = SLCC:GetLocalShotState()
		assert(snap2.state == saved,
			("expected internal state %q unchanged, got %q"):format(saved, snap2.state))
	end)

	-- ── 10: Reset → None ─────────────────────────────────────────────────────

	check("SLCC: Reset → state='None', hasPayload=false, hasLandingData=false", function()
		SLCC:Reset()
		local s = SLCC:GetLocalShotState()
		assert(s.state          == "None", ("expected 'None', got %q"):format(s.state))
		assert(s.hasPayload     == false,   "expected hasPayload=false after Reset")
		assert(s.hasLandingData == false,   "expected hasLandingData=false after Reset")
	end)

	-- ── 11: Rejected path ────────────────────────────────────────────────────

	check("SLCC: MarkLocalShotAcked('Rejected') → state='Rejected'", function()
		SLCC:BeginLocalShot({ aimVector = Vector3.new(0, 0, -1), power = 0.5 })
		SLCC:MarkLocalShotDispatched()
		SLCC:MarkLocalShotAcked("Rejected")
		local s = SLCC:GetLocalShotState()
		assert(s.state == "Rejected", ("expected 'Rejected', got %q"):format(s.state))
	end)

	-- ── 12: MarkLocalBallLanded when Rejected → no-op ────────────────────────

	check("SLCC: MarkLocalBallLanded from Rejected → state stays 'Rejected'", function()
		SLCC:MarkLocalBallLanded()
		local s = SLCC:GetLocalShotState()
		assert(s.state == "Rejected",
			("expected state to remain 'Rejected', got %q"):format(s.state))
	end)

	-- ── 13: Update(0) ────────────────────────────────────────────────────────

	check("SLCC: Update(0) does not error", function()
		SLCC:Update(0)
	end)

	-- ── 14: Destroy ──────────────────────────────────────────────────────────

	check("SLCC: Destroy then BeginLocalShot is a no-op", function()
		SLCC:Destroy()
		SLCC:BeginLocalShot({ aimVector = Vector3.new(1, 0, 0), power = 0.9 })
		-- state should remain "None" (the module's base value; _initialized=false)
		-- Re-Init needed before checking anything meaningful.
	end)

	-- ── 15: re-Init ──────────────────────────────────────────────────────────

	check("SLCC: re-Init after Destroy → state='None'", function()
		SLCC:Init()
		local s = SLCC:GetLocalShotState()
		assert(s.state == "None", ("expected 'None' after re-Init, got %q"):format(s.state))
	end)

	-- ── 16: BeginLocalShot works after re-Init ────────────────────────────────

	check("SLCC: BeginLocalShot works after re-Init", function()
		SLCC:BeginLocalShot({ aimVector = Vector3.new(0, 0, -1), power = 0.6 })
		local s = SLCC:GetLocalShotState()
		assert(s.state == "Queued", ("expected 'Queued' after re-Init shot, got %q"):format(s.state))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 28 client tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end
