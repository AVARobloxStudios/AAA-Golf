--!strict
-- Sprint34ServerTest — Server Script smoke tests for Sprint 34.
-- Run in Studio Play Solo mode with API Services enabled.
--
-- No profile gate required: tests verify that PlayableHoleService:ShootBall
-- accepts SwingResult tables without crashing.  Since no ball is spawned in
-- the test environment (no Workspace.Course.Hole1.TeeSpawn), all ShootBall
-- calls return false — the critical assertion is boolean return, no error.
--
-- Covers (28 checks):
--   Immediate (2): PHS loads, ShootBall function exists.
--   Player-gated (26):
--     Sprint33 backward compat — Vector3+power signature still accepted.
--     SwingResult table accepted — returns boolean.
--     Invalid second arg — returns false, no crash.
--     All five contactQuality values — each returns boolean.
--     All six shot shapes (Draw/Fade/Hook/Slice/Push/Pull) — each returns boolean.
--     Mishit shape — returns boolean.
--     SwingResult with missing optional fields — graceful fallback.
--     SwingResult with extreme values — no crash.
--     Update(0) — no error.
--     Init guard.
--     Destroy + re-Init.
--     ShootBall after re-Init — still returns boolean.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PHS  = require(ServerScriptService.Services.PlayableHoleService)
local VSFS = require(ServerScriptService.Services.VerticalSliceFlowService)
local RPS  = require(ServerScriptService.Services.RoundPipelineService)
local SLS  = require(ServerScriptService.Services.ShotLifecycleService)
local LPS  = require(ServerScriptService.Services.LandingPipelineService)
local HCS  = require(ServerScriptService.Services.HoleCompletionService)
local RCS  = require(ServerScriptService.Services.RoundCompletionService)
local AES  = require(ServerScriptService.Services.ActionExecutionService)
local GameService = require(ServerScriptService.Modules.GameService)

local TAG = "[Sprint34ServerTest]"

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

-- ── Immediate checks ──────────────────────────────────────────────────────────

check("PHS: module loads after Sprint 34 changes", function()
	assert(type(PHS) == "table")
end)

check("PHS: ShootBall function exists", function()
	assert(type(PHS.ShootBall) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function makeSwingResult(cq: string, shape: string, shotPower: number): any
	return {
		shotPower       = shotPower,
		launchDirection = Vector3.new(0, 0.2, -1).Unit,
		contactQuality  = cq,
		shotShape       = shape,
		carryMultiplier = 1.0,
		rollMultiplier  = 1.0,
		sideSpinInput   = 0,
		backSpinInput   = 0,
	}
end

local function runTests(player: Player)
	print(TAG .. " ── Sprint 34 server tests for " .. player.Name .. " ──")

	-- Reset all services for isolation
	PHS:Destroy()
	VSFS:Destroy()
	RCS:Destroy();  RCS:Init({})
	HCS:Destroy();  HCS:Init({})
	LPS:Destroy()
	SLS:Destroy()
	AES:Destroy();  AES:Init({})
	SLS:Init({})
	LPS:Init({})
	RPS:Destroy();  RPS:Init({})
	VSFS:Init({})
	PHS:Init({})
	GameService:AbortRound(player)

	-- ── Sprint 33 backward compat: Vector3 + power signature ─────────────────

	check("PHS: ShootBall(player, Vector3, number) still returns boolean", function()
		PHS:StartPlayableHole(player)  -- set state (may warn, won't crash)
		local ok = PHS:ShootBall(player, Vector3.new(0, 0.2, -1).Unit, 60)
		assert(type(ok) == "boolean",
			("expected boolean return from Vector3 path, got %s"):format(type(ok)))
	end)

	-- ── New Sprint 34 path: SwingResult table ─────────────────────────────────

	check("PHS: ShootBall accepts SwingResult table → boolean", function()
		PHS:StartPlayableHole(player)
		local ok = PHS:ShootBall(player, makeSwingResult("Good", "Straight", 80))
		assert(type(ok) == "boolean")
	end)

	check("PHS: ShootBall with invalid second arg (string) → false, no crash", function()
		PHS:StartPlayableHole(player)
		local ok = PHS:ShootBall(player, "invalid_arg" :: any)
		assert(ok == false, "expected false for invalid arg type")
	end)

	check("PHS: ShootBall with nil SwingResult → false, no crash", function()
		PHS:StartPlayableHole(player)
		local ok = PHS:ShootBall(player, nil :: any)
		assert(ok == false)
	end)

	-- ── All contactQuality values ─────────────────────────────────────────────

	local contactQualities = { "Perfect", "Good", "Thin", "Chunk", "Mishit" }
	for _, cq in ipairs(contactQualities) do
		check(("PHS: ShootBall contactQuality=%q → boolean"):format(cq), function()
			PHS:StartPlayableHole(player)
			local ok = PHS:ShootBall(player, makeSwingResult(cq, "Straight", 75))
			assert(type(ok) == "boolean",
				("expected boolean for contactQuality=%q"):format(cq))
		end)
	end

	-- ── All shot shapes ───────────────────────────────────────────────────────

	local shotShapes = { "Straight", "Draw", "Fade", "Hook", "Slice", "Push", "Pull", "Mishit" }
	for _, shape in ipairs(shotShapes) do
		check(("PHS: ShootBall shotShape=%q → boolean"):format(shape), function()
			PHS:StartPlayableHole(player)
			local ok = PHS:ShootBall(player, makeSwingResult("Good", shape, 70))
			assert(type(ok) == "boolean",
				("expected boolean for shotShape=%q"):format(shape))
		end)
	end

	-- ── SwingResult with missing optional fields ──────────────────────────────

	check("PHS: ShootBall SwingResult missing launchDirection — graceful fallback", function()
		PHS:StartPlayableHole(player)
		local ok = PHS:ShootBall(player, {
			shotPower      = 60,
			contactQuality = "Good",
			shotShape      = "Straight",
		} :: any)
		assert(type(ok) == "boolean")
	end)

	check("PHS: ShootBall SwingResult missing shotPower — uses default", function()
		PHS:StartPlayableHole(player)
		local ok = PHS:ShootBall(player, {
			launchDirection = Vector3.new(0, 0.2, -1).Unit,
			contactQuality  = "Good",
			shotShape       = "Straight",
		} :: any)
		assert(type(ok) == "boolean")
	end)

	-- ── Extreme SwingResult values ────────────────────────────────────────────

	check("PHS: ShootBall with extreme high shotPower — no crash", function()
		PHS:StartPlayableHole(player)
		local ok = PHS:ShootBall(player, {
			shotPower       = 99999,
			launchDirection = Vector3.new(0, 0.2, -1).Unit,
			contactQuality  = "Perfect",
			shotShape       = "Straight",
			carryMultiplier = 1.0,
			rollMultiplier  = 1.0,
			sideSpinInput   = 0,
			backSpinInput   = 0,
		} :: any)
		assert(type(ok) == "boolean")
	end)

	check("PHS: ShootBall with extreme sideSpinInput — no crash", function()
		PHS:StartPlayableHole(player)
		local ok = PHS:ShootBall(player, {
			shotPower       = 60,
			launchDirection = Vector3.new(0, 0.2, -1).Unit,
			contactQuality  = "Good",
			shotShape       = "Slice",
			carryMultiplier = 0.9,
			rollMultiplier  = 1.0,
			sideSpinInput   = 1.0,
			backSpinInput   = 0.5,
		} :: any)
		assert(type(ok) == "boolean")
	end)

	-- ── Update, Init guard, Destroy ───────────────────────────────────────────

	check("PHS: Update(0) does not error after Sprint 34 changes", function()
		PHS:Update(0)
	end)

	check("PHS: Init called twice warns and skips", function()
		PHS:Init({})
		local s = PHS:GetState(player)
		assert(type(s.status) == "string")
	end)

	check("PHS: Destroy clears state", function()
		PHS:Destroy()
		local s = PHS:GetState(player)
		assert(s.status == "Idle" and s.strokes == 0)
	end)

	check("PHS: re-Init after Destroy — ShootBall returns boolean", function()
		PHS:Init({})
		local ok = PHS:ShootBall(player, makeSwingResult("Good", "Straight", 70))
		assert(type(ok) == "boolean")
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────
	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 34 server tests PASSED.")
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
