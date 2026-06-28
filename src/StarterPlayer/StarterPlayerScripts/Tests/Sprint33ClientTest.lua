--!strict
-- Sprint33ClientTest — Client ModuleScript smoke tests for Sprint 33.
-- Invoked by TestRunner.client.lua.  No remotes, no server calls.
--
-- DeveloperAction:FireServer is pcall-guarded in each test because the
-- RemoteEvent may not have a live server listener in test context.
--
-- Covers (14 checks):
--   Module loads; all public methods exist; Init; Destroy.
--   StartPlayableHole updates local status to "Starting…".
--   Shoot updates local lastInput to "Shoot".
--   Reset returns state to Idle, strokes=0.
--   GetState returns independent copy.
--   Update(0) no error.
--   Init guard — double Init skips.
--   Destroy then calls are no-ops.
--   re-Init after Destroy; GetState = Idle.

return function()
	local StarterPlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts

	local PHCM = require(
		StarterPlayerScripts.Modules.PlayableHoleControllerModule
	)

	local TAG = "[Sprint33ClientTest]"

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

	PHCM:Destroy()
	PHCM:Init()

	-- ── 1: Module loads ───────────────────────────────────────────────────────

	check("PHCM: module loads", function()
		assert(type(PHCM) == "table", "expected table")
	end)

	-- ── 2: All public methods exist ───────────────────────────────────────────

	check("PHCM: all public methods exist", function()
		local methods = {
			"StartPlayableHole", "Shoot", "Reset", "GetState",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(PHCM[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── 3: Init ───────────────────────────────────────────────────────────────

	check("PHCM: Init — GetState default = Idle, strokes=0", function()
		local s = PHCM:GetState()
		assert(s.status  == "Idle",
			("expected 'Idle', got %q"):format(s.status))
		assert(s.strokes == 0, "expected strokes=0 after Init")
	end)

	-- ── 4: StartPlayableHole ──────────────────────────────────────────────────
	-- FireServer is wrapped in pcall here since there is no live server in test.

	check("PHCM: StartPlayableHole sets status = 'Starting…'", function()
		pcall(function() PHCM:StartPlayableHole() end)
		local s = PHCM:GetState()
		-- Status should have been updated to "Starting…" before FireServer was called
		assert(s.status == "Starting…",
			("expected 'Starting…', got %q"):format(s.status))
	end)

	-- ── 5: Shoot ─────────────────────────────────────────────────────────────

	check("PHCM: Shoot sets lastInput = 'Shoot'", function()
		pcall(function() PHCM:Shoot() end)
		local s = PHCM:GetState()
		assert(s.lastInput == "Shoot",
			("expected lastInput='Shoot', got %q"):format(s.lastInput))
	end)

	-- ── 6: Reset ─────────────────────────────────────────────────────────────

	check("PHCM: Reset → status='Idle', strokes=0", function()
		pcall(function() PHCM:Reset() end)
		local s = PHCM:GetState()
		assert(s.status  == "Idle",
			("expected 'Idle' after Reset, got %q"):format(s.status))
		assert(s.strokes == 0, "expected strokes=0 after Reset")
	end)

	-- ── 7: GetState copy isolation ────────────────────────────────────────────

	check("PHCM: GetState returns independent copy", function()
		local snap  = PHCM:GetState()
		local saved = snap.status
		snap.status  = "MUTATED"
		snap.strokes = 999
		local snap2 = PHCM:GetState()
		assert(snap2.status == saved,
			("expected internal status %q unchanged, got %q"):format(saved, snap2.status))
		assert(snap2.strokes == 0, "expected strokes=0 unchanged")
	end)

	-- ── 8: aimDirection is a Vector3 ─────────────────────────────────────────

	check("PHCM: GetState.aimDirection is a Vector3", function()
		local s = PHCM:GetState()
		assert(typeof(s.aimDirection) == "Vector3", "expected Vector3 aimDirection")
	end)

	-- ── 9: power is a positive number ────────────────────────────────────────

	check("PHCM: GetState.power > 0", function()
		local s = PHCM:GetState()
		assert(type(s.power) == "number" and s.power > 0,
			("expected power > 0, got %s"):format(tostring(s.power)))
	end)

	-- ── 10: Update(0) ─────────────────────────────────────────────────────────

	check("PHCM: Update(0) does not error", function()
		PHCM:Update(0)
	end)

	-- ── 11: Init guard ────────────────────────────────────────────────────────

	check("PHCM: Init called twice warns and skips", function()
		PHCM:Init()
		local s = PHCM:GetState()
		assert(s.status == "Idle",
			("expected 'Idle' after double Init, got %q"):format(s.status))
	end)

	-- ── 12: Destroy — calls after Destroy are no-ops ──────────────────────────

	check("PHCM: Destroy then StartPlayableHole is a no-op", function()
		PHCM:Destroy()
		PHCM:StartPlayableHole()  -- _initialized=false → no-op; no crash
	end)

	-- ── 13: re-Init after Destroy ─────────────────────────────────────────────

	check("PHCM: re-Init after Destroy → status='Idle'", function()
		PHCM:Init()
		local s = PHCM:GetState()
		assert(s.status == "Idle",
			("expected 'Idle' after re-Init, got %q"):format(s.status))
	end)

	-- ── 14: full flow after re-Init ───────────────────────────────────────────

	check("PHCM: StartPlayableHole + Shoot + Reset work after re-Init", function()
		pcall(function() PHCM:StartPlayableHole() end)
		pcall(function() PHCM:Shoot() end)
		pcall(function() PHCM:Reset() end)
		local s = PHCM:GetState()
		assert(s.status == "Idle",
			("expected 'Idle' after reset, got %q"):format(s.status))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 33 client tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end
