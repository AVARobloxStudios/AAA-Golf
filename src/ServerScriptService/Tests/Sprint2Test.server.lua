--!strict
-- Sprint2Test — Temporary server smoke test for Sprint 2 ball physics.
-- Safe to delete after Sprint 2 sign-off. Does NOT modify production logic.
-- Run in Studio Play Solo mode. No API Services required.
--
-- What is tested:
--   PhysicsService lifecycle, BallPool pre-allocation, SimulateSwing,
--   ball-state-machine transitions (IDLE → IN_FLIGHT → IDLE), position
--   movement, landing detection (CheckLanding), and pool release.

local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

-- Require modules only — Init() is handled by production runner scripts.
local Constants      = require(ReplicatedStorage.Shared.Modules.Constants)
local Types          = require(ReplicatedStorage.Shared.Modules.Types)
local PhysicsService = require(ServerScriptService.Modules.PhysicsService)

local TAG            = "[Sprint2Test]"
local INIT_TIMEOUT   = 10   -- seconds to wait for BallPool to initialise
local FLIGHT_TIMEOUT = 15   -- seconds to wait for the ball to land

-- ── Helpers ────────────────────────────────────────────────────────────────

local passed = 0
local failed = 0

local function pass(label: string)
	passed += 1
	print(TAG .. " PASS  " .. label)
end

local function fail(label: string, reason: string)
	failed += 1
	warn(TAG .. " FAIL  " .. label .. "  (" .. reason .. ")")
end

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		pass(label)
	else
		fail(label, tostring(err))
	end
end

-- Returns the Workspace/ActiveBalls folder, or nil if BallPool has not Init'd yet.
local function getActiveBallsFolder(): Folder?
	return Workspace:FindFirstChild("ActiveBalls") :: Folder?
end

-- Returns all Model instances inside Workspace/ActiveBalls.
local function getPoolBalls(): { Model }
	local folder = getActiveBallsFolder()
	if not folder then return {} end
	local balls: { Model } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(balls, child :: Model)
		end
	end
	return balls
end

-- Reads the StateValue.Value for a ball model; returns "" if not found.
local function getState(ball: Model): string
	local sv = ball:FindFirstChild("StateValue") :: StringValue?
	return if sv then sv.Value else ""
end

-- Returns how many pool balls are currently leased (StateValue ≠ "IDLE").
local function countLeased(): number
	local n = 0
	for _, ball in ipairs(getPoolBalls()) do
		if getState(ball) ~= "IDLE" then
			n += 1
		end
	end
	return n
end

-- Returns the first ball whose StateValue equals the given state, or nil.
local function findBallInState(state: string): Model?
	for _, ball in ipairs(getPoolBalls()) do
		if getState(ball) == state then return ball end
	end
	return nil
end

-- Polls until condition() returns true or the timeout expires.
-- Must be called from a coroutine (yields via task.wait).
local function pollUntil(condition: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if condition() then return true end
		task.wait(0.1)
	end
	return false
end

-- ── Test suite ─────────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 2 physics smoke tests for " .. player.Name .. " ──")

	-- ── 1–3: Module interface ─────────────────────────────────────────────

	check("PhysicsService: module loads with Init function", function()
		assert(type(PhysicsService.Init) == "function")
	end)
	check("PhysicsService: SimulateSwing function exists", function()
		assert(type(PhysicsService.SimulateSwing) == "function")
	end)
	check("PhysicsService: SetWind function exists", function()
		assert(type(PhysicsService.SetWind) == "function")
	end)

	-- ── 4: Wait for BallPool.Init to complete ─────────────────────────────
	-- BallPool:Init creates workspace/ActiveBalls. Poll until it appears.

	local poolReady = pollUntil(function()
		return getActiveBallsFolder() ~= nil
	end, INIT_TIMEOUT)

	check("BallPool: workspace.ActiveBalls folder created after Init", function()
		assert(poolReady,
			"workspace.ActiveBalls not found within " .. INIT_TIMEOUT .. " s — is PhysicsService.server running?")
	end)

	if not poolReady then
		warn(TAG .. " Aborting remaining tests — BallPool did not initialise in time")
		return
	end

	-- ── 5–7: Initial pool state ───────────────────────────────────────────

	check("BallPool: pre-allocates exactly BALL_POOL_SIZE balls", function()
		local count = #getPoolBalls()
		assert(count == Constants.BALL_POOL_SIZE,
			("expected %d balls, got %d"):format(Constants.BALL_POOL_SIZE, count))
	end)

	check("BallPool: all balls start with StateValue = IDLE", function()
		for _, ball in ipairs(getPoolBalls()) do
			local state = getState(ball)
			assert(state == "IDLE",
				("%s has StateValue %q — expected IDLE"):format(ball.Name, state))
		end
	end)

	check("BallPool: all balls start invisible (Transparency = 1)", function()
		for _, ball in ipairs(getPoolBalls()) do
			local part = ball.PrimaryPart
			assert(part, ball.Name .. " has no PrimaryPart")
			assert((part :: BasePart).Transparency == 1,
				("%s Transparency = %s, expected 1"):format(
					ball.Name, tostring((part :: BasePart).Transparency)))
		end
	end)

	-- ── 8: Fire a simulated swing ─────────────────────────────────────────
	-- Launch from Y = 500 so the ball has ~3–5 s of visible flight under
	-- gravity + drag before CheckLanding triggers at Y ≤ BALL_RADIUS.
	-- Driver at half power → ~210 studs/s, 10° loft.

	local swingIntent: Types.SwingIntent = {
		eventType = "SwingIntent",
		aimVector = Vector3.new(0, 0, 1),  -- straight ahead (+Z)
		power     = 0.5,
		accuracy  = 0.0,                   -- no hook or slice
		clubId    = "DRIVER",
		timestamp = os.time(),
	}

	-- Driver stats inlined to avoid ClubData return-type ambiguity in strict mode.
	local driverData = {
		maxSpeed    = 420,   -- studs/s at 100% power
		loftDegrees = 10,
		spinRPM     = 2500,
	}

	local launchCFrame = CFrame.new(0, 500, 0)

	check("PhysicsService: SimulateSwing executes without error", function()
		PhysicsService:SimulateSwing(player, swingIntent, driverData, launchCFrame)
	end)

	-- Let at least one Heartbeat tick run so the pool state updates.
	task.wait(0.1)

	-- ── 9–12: Immediate post-swing pool state ─────────────────────────────

	check("BallPool: exactly one ball leased after swing", function()
		local n = countLeased()
		assert(n == 1, ("expected 1 leased ball, got %d"):format(n))
	end)

	check("BallPool: leased ball StateValue = IN_FLIGHT", function()
		local ball = findBallInState("IN_FLIGHT")
		assert(ball ~= nil, "no ball with StateValue = IN_FLIGHT found")
	end)

	check("BallPool: leased ball is visible (Transparency = 0)", function()
		local ball = findBallInState("IN_FLIGHT")
		assert(ball, "no in-flight ball")
		local part = (ball :: Model).PrimaryPart
		assert(part, "in-flight ball has no PrimaryPart")
		assert((part :: BasePart).Transparency == 0,
			"in-flight ball is not visible (Transparency = "
			.. tostring((part :: BasePart).Transparency) .. ")")
	end)

	check("BallPool: OwnerValue points to the swinging player", function()
		local ball = findBallInState("IN_FLIGHT")
		assert(ball, "no in-flight ball")
		local ov = (ball :: Model):FindFirstChild("OwnerValue") :: ObjectValue?
		assert(ov, "OwnerValue not found on in-flight ball")
		assert((ov :: ObjectValue).Value == player,
			"OwnerValue is not " .. player.Name)
	end)

	-- ── 13: Confirm the physics loop is actually stepping ─────────────────
	-- Capture position now, wait 0.5 s, then compare.

	local inFlightBall: Model? = findBallInState("IN_FLIGHT")
	local posBefore: Vector3?  = nil

	if inFlightBall then
		local part = inFlightBall.PrimaryPart
		if part then
			posBefore = (part :: BasePart).CFrame.Position
		end
	end

	task.wait(0.5)

	check("PhysicsIntegrator: ball position advances by > 1 stud over 0.5 s", function()
		assert(inFlightBall,  "in-flight ball reference was not captured before the wait")
		assert(posBefore,     "launch position was not captured before the wait")
		local part = (inFlightBall :: Model).PrimaryPart
		assert(part, "ball PrimaryPart missing after 0.5 s — ball may have been destroyed")
		local posAfter = (part :: BasePart).CFrame.Position
		local delta = (posAfter - (posBefore :: Vector3)).Magnitude
		assert(delta > 1.0,
			("ball moved only %.3f studs in 0.5 s — Heartbeat loop may not be stepping"):format(delta))
	end)

	-- ── 14–16: Wait for landing and verify full cleanup ───────────────────
	-- Poll until all pool balls return to IDLE (BallPool:Release was called).

	local landed = pollUntil(function()
		return countLeased() == 0
	end, FLIGHT_TIMEOUT)

	check("PhysicsService: ball lands (CheckLanding fires) within " .. FLIGHT_TIMEOUT .. " s", function()
		assert(landed,
			"ball did not land within " .. FLIGHT_TIMEOUT
			.. " s — CheckLanding may never return true from Y=500")
	end)

	check("BallPool: zero balls remain leased after landing", function()
		local n = countLeased()
		assert(n == 0, ("expected 0 leased balls after landing, got %d"):format(n))
	end)

	check("BallPool: all balls IDLE and invisible after BallPool:Release", function()
		for _, ball in ipairs(getPoolBalls()) do
			local state = getState(ball)
			assert(state == "IDLE",
				("%s StateValue = %q after release — expected IDLE"):format(ball.Name, state))
			local part = ball.PrimaryPart
			if part then
				assert((part :: BasePart).Transparency == 1,
					("%s still visible (Transparency = %s) after release"):format(
						ball.Name, tostring((part :: BasePart).Transparency)))
			end
		end
	end)

	-- ── Summary ───────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 2 smoke tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end

-- ── Module-level smoke check (runs before any player joins) ───────────────

check("PhysicsService: module loads without error", function()
	assert(PhysicsService ~= nil)
end)

-- ── Trigger per-player tests when a player is available ───────────────────

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(runTests, player)
end)

-- Catch the local player already present in Studio play-solo.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(runTests, player)
end
