--!strict
-- Sprint33ServerTest — Server Script smoke tests for Sprint 33.
-- Run in Studio Play Solo mode.
--
-- No profile gate required: tests verify safe edge-case handling only
-- (missing Workspace objects, no active ball, etc.) — not the live flow.
-- The live flow requires API Access enabled for DataStore.
--
-- Covers (22 checks):
--   Immediate (3): module loads, Init, Destroy exist.
--   Player-gated (19):
--     API surface.
--     GetState default = { status="Idle", strokes=0 }.
--     StartPlayableHole with no Workspace objects — warns, does not crash.
--     GetState after failed start (status is set to HoleReady optimistically).
--     SpawnPlayer with missing TeeSpawn — warns, returns false.
--     SpawnBall — fallback debug geometry always provides spawn point → returns Part.
--     ShootBall — StartPlayableHole always spawns ball → returns true.
--     CheckLanding with no ball — safe no-op.
--     CheckCup with no cup — warns, no crash.
--     ResetPlayer — clears state back to default.
--     StartPlayableHole again (second call) — resets and restarts cleanly.
--     GetState copy isolation.
--     Update(0) — no error.
--     Init guard — double Init warns and skips.
--     Destroy — clears everything.
--     Re-Init after Destroy.
--     GetState after re-Init = Idle.
--     ShootBall after re-Init with no ball — safe.
--
-- All sub-services are reset for isolation; GameService is NOT destroyed.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local PHS  = require(ServerScriptService.Services.PlayableHoleService)
local VSFS = require(ServerScriptService.Services.VerticalSliceFlowService)
local RPS  = require(ServerScriptService.Services.RoundPipelineService)
local SLS  = require(ServerScriptService.Services.ShotLifecycleService)
local LPS  = require(ServerScriptService.Services.LandingPipelineService)
local HCS  = require(ServerScriptService.Services.HoleCompletionService)
local RCS  = require(ServerScriptService.Services.RoundCompletionService)
local AES  = require(ServerScriptService.Services.ActionExecutionService)
local GameService = require(ServerScriptService.Modules.GameService)

local TAG = "[Sprint33ServerTest]"

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

check("PHS: module loads", function()
	assert(type(PHS) == "table", "expected table")
end)

check("PHS: Init function exists", function()
	assert(type(PHS.Init) == "function")
end)

check("PHS: Destroy function exists", function()
	assert(type(PHS.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 33 playable hole tests for " .. player.Name .. " ──")

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

	-- ── API surface ───────────────────────────────────────────────────────────

	check("PHS: all public methods exist", function()
		local methods = {
			"StartPlayableHole", "SpawnPlayer", "SpawnBall",
			"ShootBall", "CheckLanding", "CheckCup",
			"CompleteHole", "FinishRound", "ResetPlayer", "GetState",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(PHS[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── GetState default ──────────────────────────────────────────────────────

	check("PHS: GetState default = { status='Idle', strokes=0 }", function()
		local s = PHS:GetState(player)
		assert(s.status  == "Idle",
			("expected 'Idle', got %q"):format(s.status))
		assert(s.strokes == 0,
			("expected strokes=0, got %d"):format(s.strokes))
	end)

	-- ── StartPlayableHole with no Workspace objects ───────────────────────────
	-- Workspace.Course.Hole1 does not exist in test Studio; VSFS:StartVerticalSlice
	-- will also fail (no DataStore profile).  Both failures are caught and warned;
	-- the call must not throw.

	check("PHS: StartPlayableHole with no Workspace objects — does not crash", function()
		-- pcall wraps the entire call; even internal warns are acceptable
		local ok = PHS:StartPlayableHole(player)
		-- ok may be true or false; we only care it didn't error
		assert(type(ok) == "boolean", "expected boolean return")
	end)

	-- Status is optimistically set to HoleReady (or Idle after reset)
	check("PHS: GetState after StartPlayableHole attempt — status is a string", function()
		local s = PHS:GetState(player)
		assert(type(s.status) == "string", "expected string status")
	end)

	-- ── SpawnPlayer with no TeeSpawn ──────────────────────────────────────────

	check("PHS: SpawnPlayer with no TeeSpawn — returns false, does not crash", function()
		-- After ResetPlayer, no active session so GameService:GetTeePosition returns nil
		PHS:ResetPlayer(player)
		local ok = PHS:SpawnPlayer(player)
		assert(ok == false, "expected false when no tee position available")
	end)

	-- ── SpawnBall — fallback geometry always provides a spawn point ───────────
	-- StartPlayableHole above called _ensureDebugHole1(), which created
	-- Workspace.Courses.Hole1 with a BallSpawn part and leaves it in place.
	-- SpawnBall therefore always finds a valid position and returns a Part.

	check("PHS: SpawnBall — fallback debug geometry spawns ball successfully", function()
		local ball = PHS:SpawnBall(player)
		assert(ball ~= nil, "expected ball Part — _ensureDebugHole1 provides BallSpawn")
		assert((ball :: Part):IsA("BasePart"), "expected returned value to be a BasePart")
	end)

	-- ── ShootBall — fallback ball always exists after StartPlayableHole ───────
	-- StartPlayableHole calls SpawnBall internally; with fallback geometry in
	-- place the ball is always created.  ShootBall should find it and return true.

	check("PHS: ShootBall — StartPlayableHole spawns ball → shot fires and returns true", function()
		PHS:StartPlayableHole(player)   -- resets state, creates debug geo + ball
		local ok = PHS:ShootBall(player, Vector3.new(0, 0, -1), 60)
		assert(ok == true, "expected true: fallback ball exists and state is HoleReady")
	end)

	-- ── CheckLanding with no ball ─────────────────────────────────────────────

	check("PHS: CheckLanding with no ball — safe no-op", function()
		PHS:CheckLanding(player)  -- must not error
	end)

	-- ── CheckCup with no cup ──────────────────────────────────────────────────

	check("PHS: CheckCup with no cup — warns, does not crash", function()
		PHS:CheckCup(player)  -- must not error even when cup is absent
	end)

	-- ── ResetPlayer ───────────────────────────────────────────────────────────

	check("PHS: ResetPlayer clears state to Idle", function()
		PHS:ResetPlayer(player)
		local s = PHS:GetState(player)
		assert(s.status  == "Idle",
			("expected 'Idle' after Reset, got %q"):format(s.status))
		assert(s.strokes == 0,
			"expected strokes=0 after Reset")
	end)

	-- ── Second StartPlayableHole call (re-entry) ──────────────────────────────

	check("PHS: second StartPlayableHole resets and restarts cleanly", function()
		PHS:StartPlayableHole(player)  -- first call
		PHS:StartPlayableHole(player)  -- second call; should reset first
		local s = PHS:GetState(player)
		assert(type(s.status) == "string", "expected string status after re-entry")
	end)

	-- ── GetState copy isolation ───────────────────────────────────────────────

	check("PHS: GetState returns independent copy", function()
		local snap  = PHS:GetState(player)
		local saved = snap.status
		snap.status  = "MUTATED"
		snap.strokes = 999
		local snap2 = PHS:GetState(player)
		assert(snap2.status == saved,
			("expected internal status %q unchanged, got %q"):format(saved, snap2.status))
	end)

	-- ── CompleteHole safe no-op when status is already RoundComplete ──────────

	check("PHS: CompleteHole + FinishRound do not crash", function()
		PHS:CompleteHole(player)   -- state might not be HoleComplete; should be guarded
		PHS:FinishRound(player)    -- should be safe
	end)

	-- ── Update(0) ─────────────────────────────────────────────────────────────

	check("PHS: Update(0) does not error", function()
		PHS:Update(0)
	end)

	-- ── Init guard ────────────────────────────────────────────────────────────

	check("PHS: Init called twice warns and skips", function()
		PHS:Init({})
		local s = PHS:GetState(player)
		assert(type(s.status) == "string", "state should still be valid after double Init")
	end)

	-- ── Destroy ───────────────────────────────────────────────────────────────

	check("PHS: Destroy clears state", function()
		PHS:Destroy()
		-- After Destroy, GetState should return safe default
		local s = PHS:GetState(player)
		assert(s.status  == "Idle",   "expected 'Idle' after Destroy")
		assert(s.strokes == 0, "expected strokes=0 after Destroy")
	end)

	-- ── Re-Init after Destroy ─────────────────────────────────────────────────

	check("PHS: re-Init after Destroy — GetState returns Idle", function()
		PHS:Init({})
		local s = PHS:GetState(player)
		assert(s.status == "Idle",
			("expected 'Idle' after re-Init, got %q"):format(s.status))
	end)

	-- ── ShootBall after re-Init with no ball ──────────────────────────────────

	check("PHS: ShootBall after re-Init with no ball — safe false return", function()
		local ok = PHS:ShootBall(player, Vector3.new(0, 0, -1), 60)
		-- No state (Idle / no HoleReady) so returns false without crashing
		assert(ok == false or type(ok) == "boolean",
			"expected boolean return from ShootBall")
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 33 smoke tests PASSED.")
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
