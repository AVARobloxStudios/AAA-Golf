--!strict
-- Sprint5Test — GameService state machine smoke tests
-- Run in Studio Play Solo mode. No API Services required.
-- Requires Rojo sync so that Workspace.Courses and ReplicatedStorage.Network exist.
--
-- What is tested (38 runtime checks):
--   GameService (34 checks): module interface, GetState/GetCurrentHoleId/
--     GetTeePosition/GetPinPosition, StartRound state progression,
--     OnHoleReady, OnSwingFired, _onBallLanded, _advanceFromScoreReveal,
--     hole-completion via ball-near-pin, next-hole loading, ROUND_COMPLETE
--     with session cleanup, AbortRound, multi-shot same-hole retention,
--     error paths for out-of-order calls, duplicate StartRound guard.
--
-- All state transitions tested synchronously: _advanceFromScoreReveal and
-- _enterRoundComplete are called directly so tests never need task.wait.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local GameService        = require(ServerScriptService.Modules.GameService)
local ScoringService     = require(ServerScriptService.Modules.ScoringService)
local PlayerDataService  = require(ServerScriptService.Modules.PlayerDataService)

local TAG = "[Sprint5Test]"

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

-- State name constants — must match GameService's local definitions exactly.
local S_LOBBY          = "LOBBY"
-- COUNTDOWN and LOADING are transient; StartRound exits with TEE_OFF.
local S_TEE_OFF        = "TEE_OFF"
local S_SWING          = "SWING"
local S_BALL_IN_FLIGHT = "BALL_IN_FLIGHT"
local S_SCORE_REVEAL   = "SCORE_REVEAL"
-- S_NEXT_HOLE and S_ROUND_COMPLETE are transient: verified via GetState/GetCurrentHoleId checks.

-- Positions used to simulate ball landings.
local FAR_FROM_PIN = Vector3.new(0, 0, 999)   -- well outside HOLE_IN_RADIUS
local STUB_SURFACE  = "FAIRWAY"

-- Polls condition() at 0.1s intervals until it returns true or timeout expires.
-- Must be called from a coroutine (task.spawn satisfies this).
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
	print(TAG .. " ── Sprint 5 GameService smoke tests for " .. player.Name .. " ──")

	-- Ensure a clean initial state: abort any leftover session from the runner.
	GameService:AbortRound(player)

	-- ── Module interface ──────────────────────────────────────────────────

	check("GameService: module loads", function()
		assert(GameService ~= nil)
	end)

	check("GameService: Init function exists", function()
		assert(type(GameService.Init) == "function")
	end)

	check("GameService: GetState function exists", function()
		assert(type(GameService.GetState) == "function")
	end)

	check("GameService: StartRound function exists", function()
		assert(type(GameService.StartRound) == "function")
	end)

	check("GameService: OnHoleReady function exists", function()
		assert(type(GameService.OnHoleReady) == "function")
	end)

	check("GameService: OnSwingFired function exists", function()
		assert(type(GameService.OnSwingFired) == "function")
	end)

	check("GameService: AbortRound function exists", function()
		assert(type(GameService.AbortRound) == "function")
	end)

	check("GameService: GetCurrentHoleId function exists", function()
		assert(type(GameService.GetCurrentHoleId) == "function")
	end)

	check("GameService: GetTeePosition function exists", function()
		assert(type(GameService.GetTeePosition) == "function")
	end)

	check("GameService: GetPinPosition function exists", function()
		assert(type(GameService.GetPinPosition) == "function")
	end)

	-- ── Pre-round LOBBY state ─────────────────────────────────────────────

	check("GetState: returns LOBBY before StartRound", function()
		local state = GameService:GetState(player)
		assert(state == S_LOBBY,
			("expected LOBBY, got %q"):format(state))
	end)

	check("GetCurrentHoleId: returns nil before StartRound", function()
		assert(GameService:GetCurrentHoleId(player) == nil,
			"expected nil before round starts")
	end)

	check("GetTeePosition: returns nil before StartRound", function()
		assert(GameService:GetTeePosition(player) == nil,
			"expected nil before round starts")
	end)

	-- ── Profile readiness gate ───────────────────────────────────────────
	-- StartRound → ScoringService → PlayerDataService requires a loaded profile.
	-- Poll until GetProfile returns non-nil so this test does not race the
	-- PlayerDataService mock initialisation started by other test runners.

	local profileReady = pollUntil(function()
		return PlayerDataService:GetProfile(player) ~= nil
	end, 10)

	if not profileReady then
		warn(TAG .. " Profile not ready after 10s for " .. player.Name
			.. " — aborting (check API Access in Studio settings)")
		return
	end

	-- ── StartRound → TEE_OFF (synchronous) ───────────────────────────────
	-- COUNTDOWN and LOADING fire as transient states before StartRound returns,
	-- so only TEE_OFF is observable after the call.

	check("StartRound: executes without error", function()
		GameService:StartRound(player)
	end)

	check("StartRound: state = TEE_OFF after call returns", function()
		local state = GameService:GetState(player)
		assert(state == S_TEE_OFF,
			("expected TEE_OFF, got %q"):format(state))
	end)

	check("StartRound: GetCurrentHoleId = Hole_01", function()
		local holeId = GameService:GetCurrentHoleId(player)
		assert(holeId == "Hole_01",
			("expected Hole_01, got %q"):format(tostring(holeId)))
	end)

	check("StartRound: GetTeePosition returns a Vector3", function()
		local tee = GameService:GetTeePosition(player)
		assert(typeof(tee) == "Vector3",
			("expected Vector3, got %s"):format(typeof(tee)))
	end)

	check("StartRound: GetPinPosition returns a Vector3", function()
		local pin = GameService:GetPinPosition(player)
		assert(typeof(pin) == "Vector3",
			("expected Vector3, got %s"):format(typeof(pin)))
	end)

	-- ── OnHoleReady: TEE_OFF → SWING ────────────────────────────────────

	check("OnHoleReady: executes without error from TEE_OFF", function()
		GameService:OnHoleReady(player)
	end)

	check("OnHoleReady: state = SWING after call", function()
		local state = GameService:GetState(player)
		assert(state == S_SWING,
			("expected SWING, got %q"):format(state))
	end)

	-- ── OnSwingFired: SWING → BALL_IN_FLIGHT ────────────────────────────

	check("OnSwingFired: executes without error from SWING", function()
		GameService:OnSwingFired(player)
	end)

	check("OnSwingFired: state = BALL_IN_FLIGHT after call", function()
		local state = GameService:GetState(player)
		assert(state == S_BALL_IN_FLIGHT,
			("expected BALL_IN_FLIGHT, got %q"):format(state))
	end)

	-- ── _onBallLanded: BALL_IN_FLIGHT → SCORE_REVEAL ────────────────────

	check("_onBallLanded: executes without error from BALL_IN_FLIGHT", function()
		GameService:_onBallLanded(player, FAR_FROM_PIN, STUB_SURFACE)
	end)

	check("_onBallLanded: state = SCORE_REVEAL after call", function()
		local state = GameService:GetState(player)
		assert(state == S_SCORE_REVEAL,
			("expected SCORE_REVEAL, got %q"):format(state))
	end)

	-- ── _advanceFromScoreReveal: hole not complete → back to TEE_OFF ─────
	-- 1 shot taken, pin is FAR_FROM_PIN (well outside 3-stud radius), hole continues.

	check("_advanceFromScoreReveal: hole not complete → state = TEE_OFF", function()
		GameService:_advanceFromScoreReveal(player)
		local state = GameService:GetState(player)
		assert(state == S_TEE_OFF,
			("expected TEE_OFF (next shot), got %q"):format(state))
	end)

	check("_advanceFromScoreReveal: same hole retained (Hole_01)", function()
		local holeId = GameService:GetCurrentHoleId(player)
		assert(holeId == "Hole_01",
			("expected Hole_01 still active, got %q"):format(tostring(holeId)))
	end)

	-- ── Hole completion via ball near pin ────────────────────────────────
	-- Take one more shot with ball landing within HOLE_IN_RADIUS of pin.

	do
		-- Drive: TEE_OFF → SWING → BALL_IN_FLIGHT.
		GameService:OnHoleReady(player)
		GameService:OnSwingFired(player)

		-- Land ball within 2 studs of pin (HOLE_IN_RADIUS = 3 studs).
		local pin = GameService:GetPinPosition(player)
		assert(pin ~= nil, "pin must be non-nil at this point")
		local nearPin = (pin :: Vector3) + Vector3.new(1, 0, 0)

		GameService:_onBallLanded(player, nearPin, "GREEN")

		check("hole-completion: state = SCORE_REVEAL after ball near pin", function()
			local state = GameService:GetState(player)
			assert(state == S_SCORE_REVEAL,
				("expected SCORE_REVEAL, got %q"):format(state))
		end)

		-- Advance: hole complete → NEXT_HOLE → LOADING → TEE_OFF (hole 2).
		GameService:_advanceFromScoreReveal(player)

		check("hole-completion: state = TEE_OFF after advance (hole done, hole 2 loaded)", function()
			local state = GameService:GetState(player)
			assert(state == S_TEE_OFF,
				("expected TEE_OFF after NEXT_HOLE→LOADING, got %q"):format(state))
		end)

		check("hole-completion: GetCurrentHoleId advanced to Hole_02", function()
			local holeId = GameService:GetCurrentHoleId(player)
			assert(holeId == "Hole_02",
				("expected Hole_02, got %q"):format(tostring(holeId)))
		end)
	end

	-- ── AbortRound: cleanup ───────────────────────────────────────────────

	check("AbortRound: clears session → state = LOBBY", function()
		-- Still in an active session from the hole-completion test.
		GameService:AbortRound(player)
		local state = GameService:GetState(player)
		assert(state == S_LOBBY,
			("expected LOBBY after AbortRound, got %q"):format(state))
	end)

	check("AbortRound: GetCurrentHoleId = nil after abort", function()
		assert(GameService:GetCurrentHoleId(player) == nil,
			"expected nil after AbortRound")
	end)

	check("AbortRound: no error when called with no active session", function()
		GameService:AbortRound(player)  -- second call; session already cleared
	end)

	-- ── ROUND_COMPLETE: session cleanup ───────────────────────────────────

	do
		-- Start fresh, drive to an active shot, then force round completion.
		GameService:StartRound(player)

		GameService:_enterRoundComplete(player)

		check("_enterRoundComplete: GetState = LOBBY after round ends", function()
			local state = GameService:GetState(player)
			assert(state == S_LOBBY,
				("expected LOBBY after round complete, got %q"):format(state))
		end)

		check("_enterRoundComplete: GetCurrentHoleId = nil after round ends", function()
			assert(GameService:GetCurrentHoleId(player) == nil,
				"expected nil after round complete")
		end)
	end

	-- ── Error paths ────────────────────────────────────────────────────────

	check("StartRound: errors if called while session is active", function()
		GameService:StartRound(player)   -- first call succeeds
		local ok = pcall(function()
			GameService:StartRound(player)  -- second call must error
		end)
		assert(not ok, "expected error for duplicate StartRound")
		GameService:AbortRound(player)   -- clean up
	end)

	check("OnHoleReady: errors if not in TEE_OFF state", function()
		GameService:StartRound(player)  -- state = TEE_OFF
		GameService:OnHoleReady(player) -- state = SWING
		-- Now in SWING; calling OnHoleReady again should error.
		local ok = pcall(function()
			GameService:OnHoleReady(player)
		end)
		assert(not ok, "expected error for OnHoleReady when not in TEE_OFF")
		GameService:AbortRound(player)
	end)

	check("OnSwingFired: errors if not in SWING state", function()
		GameService:StartRound(player)  -- state = TEE_OFF
		-- Calling OnSwingFired before OnHoleReady (state = TEE_OFF, not SWING).
		local ok = pcall(function()
			GameService:OnSwingFired(player)
		end)
		assert(not ok, "expected error for OnSwingFired when not in SWING")
		GameService:AbortRound(player)
	end)

	check("OnHoleReady: errors if player has no session", function()
		-- No session for player (AbortRound was called above).
		local ok = pcall(function()
			GameService:OnHoleReady(player)
		end)
		assert(not ok, "expected error for OnHoleReady with no session")
	end)

	-- ── Teardown ──────────────────────────────────────────────────────────
	-- _onBallLanded schedules task.delay(SCORE_REVEAL_DELAY, _advanceFromScoreReveal)
	-- calls that cannot be cancelled. Clearing sessions here makes every pending
	-- callback hit the "if not session then return end" guard and silently exit,
	-- so they never reach ScoringService or PlayerDataService after the test ends.

	GameService:AbortRound(player)      -- idempotent; drains rewards if any session remains

	GameService:Destroy()               -- clears _sessions table; pending callbacks no-op
	ScoringService:Destroy()            -- clears ScoringService session table

	-- ── Summary ────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 5 smoke tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end

-- ── Trigger per-player tests when a player is available ───────────────────

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(runTests, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(runTests, player)
end
