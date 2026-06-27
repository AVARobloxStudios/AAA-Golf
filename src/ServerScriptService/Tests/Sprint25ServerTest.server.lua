--!strict
-- Sprint25ServerTest — Server Script smoke tests for Sprint 25.
-- Run in Studio Play Solo mode. No API Services required for most checks;
-- profile readiness gate (same as Sprint5Test) guards the GameService path.
--
-- Covers (27 checks):
--   Immediate (3):  AES module loading, Init/Destroy exist.
--   Player-gated (24):
--     HoleReady — no session → safe failure, valid session → success + state transition.
--     SwingIntent — invalid aimVector, invalid power → safe failure; valid payload
--       during SWING → success + BALL_IN_FLIGHT; outside SWING → safe failure.
--     Unknown eventType still graceful failure.
--     Stub handlers (QueueMatchmaking, EquipCosmetic) still return success.
--     Execution counter behaviour.
--     Destroy + re-Init recovery.
--
-- AES is reset via Destroy()+Init() for isolation; GameService and ScoringService
-- are left as-is (initialized by their own thin runners).

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local AES               = require(ServerScriptService.Services.ActionExecutionService)
local GameService       = require(ServerScriptService.Modules.GameService)
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)

local TAG = "[Sprint25ServerTest]"

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

local function pollUntil(condition: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if condition() then return true end
		task.wait(0.1)
	end
	return false
end

-- Convenience: build a minimal valid envelope for AES:Execute.
local function _envelope(eventType: string, payload: any): { [string]: any }
	return { eventType = eventType, actionId = "test_action", payload = payload }
end

-- ── Immediate module-level checks (no player needed) ─────────────────────────

check("AES: module loads", function()
	assert(type(AES) == "table", "expected table")
end)

check("AES: Init function exists", function()
	assert(type(AES.Init) == "function")
end)

check("AES: Destroy function exists", function()
	assert(type(AES.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 25 AES real-handler tests for " .. player.Name .. " ──")

	-- Reset AES for test isolation; leave GameService/ScoringService alive.
	AES:Destroy()
	AES:Init({})
	GameService:AbortRound(player)    -- clear any leftover session

	-- ── Counts reset on Init ──────────────────────────────────────────────────

	check("AES: GetExecutionCount = 0 after fresh Init", function()
		assert(AES:GetExecutionCount() == 0,
			("expected 0, got %d"):format(AES:GetExecutionCount()))
	end)

	-- ── HoleReady: no active session ─────────────────────────────────────────
	-- GameService:OnHoleReady errors on missing session; AES should catch and
	-- return a failure result rather than propagating the error.

	check("AES HoleReady: no session → result.success == false (safe failure)", function()
		local result = AES:Execute(player, _envelope("HoleReady", {}))
		assert(result.success == false,
			("expected success=false, got success=%s status=%q"):format(
				tostring(result.success), result.status))
	end)

	check("AES HoleReady: no session → status is 'NoSession'", function()
		local result = AES:Execute(player, _envelope("HoleReady", {}))
		assert(result.status == "NoSession",
			("expected 'NoSession', got %q"):format(result.status))
	end)

	check("AES HoleReady: non-table payload → result.success == false", function()
		local result = AES:Execute(player, _envelope("HoleReady", "bad" :: any))
		assert(result.success == false,
			("expected success=false for non-table payload, got %s"):format(
				tostring(result.success)))
	end)

	-- ── Profile readiness gate ────────────────────────────────────────────────
	-- GameService:StartRound → ScoringService → PlayerDataService requires a
	-- loaded profile.  Poll as Sprint5Test does.

	local profileReady = pollUntil(function()
		return PlayerDataService:GetProfile(player) ~= nil
	end, 10)

	if not profileReady then
		warn(TAG .. " Profile not ready after 10s for " .. player.Name
			.. " — aborting (check API Access in Studio settings)")
		return
	end

	-- ── Set up a valid session: TEE_OFF ──────────────────────────────────────

	check("GameService: StartRound executes without error", function()
		GameService:StartRound(player)
	end)

	check("GameService: state = TEE_OFF after StartRound", function()
		local state = GameService:GetState(player)
		assert(state == "TEE_OFF",
			("expected TEE_OFF, got %q"):format(state))
	end)

	-- ── HoleReady: valid session in TEE_OFF ───────────────────────────────────

	check("AES HoleReady: valid session in TEE_OFF → success=true", function()
		local result = AES:Execute(player, _envelope("HoleReady", {}))
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
	end)

	check("AES HoleReady: status = 'HoleReadyAcked'", function()
		-- State is now SWING after the previous check's Execute.
		-- Verify by checking GameService state.
		local state = GameService:GetState(player)
		assert(state == "SWING",
			("expected SWING after HoleReady, got %q"):format(state))
	end)

	-- ── SwingIntent: payload validation failures ──────────────────────────────
	-- These must not change state (player stays in SWING).

	check("AES SwingIntent: missing aimVector → success=false, state unchanged", function()
		local result = AES:Execute(player, _envelope("SwingIntent", {
			power = 0.5,
		}))
		assert(result.success == false,
			("expected success=false for missing aimVector, got %s"):format(
				tostring(result.success)))
		assert(result.status == "InvalidAimVector",
			("expected 'InvalidAimVector', got %q"):format(result.status))
		assert(GameService:GetState(player) == "SWING",
			"state must not change for invalid aimVector")
	end)

	check("AES SwingIntent: non-Vector3 aimVector → success=false", function()
		local result = AES:Execute(player, _envelope("SwingIntent", {
			aimVector = "forward",
			power     = 0.5,
		}))
		assert(result.success == false,
			"expected success=false for non-Vector3 aimVector")
		assert(result.status == "InvalidAimVector",
			("expected 'InvalidAimVector', got %q"):format(result.status))
	end)

	check("AES SwingIntent: power > 1 → success=false, status='InvalidPower'", function()
		local result = AES:Execute(player, _envelope("SwingIntent", {
			aimVector = Vector3.new(0, 0, -1),
			power     = 1.5,
		}))
		assert(result.success == false,
			"expected success=false for power > 1")
		assert(result.status == "InvalidPower",
			("expected 'InvalidPower', got %q"):format(result.status))
	end)

	check("AES SwingIntent: power < 0 → success=false, status='InvalidPower'", function()
		local result = AES:Execute(player, _envelope("SwingIntent", {
			aimVector = Vector3.new(0, 0, -1),
			power     = -0.1,
		}))
		assert(result.success == false,
			"expected success=false for power < 0")
		assert(result.status == "InvalidPower",
			("expected 'InvalidPower', got %q"):format(result.status))
	end)

	check("AES SwingIntent: empty clubName → success=false", function()
		local result = AES:Execute(player, _envelope("SwingIntent", {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.5,
			clubName  = "",
		}))
		assert(result.success == false,
			"expected success=false for empty clubName")
		assert(result.status == "InvalidClubName",
			("expected 'InvalidClubName', got %q"):format(result.status))
	end)

	-- ── SwingIntent: valid payload during SWING ───────────────────────────────

	check("AES SwingIntent: valid payload during SWING → success=true", function()
		local result = AES:Execute(player, _envelope("SwingIntent", {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.75,
		}))
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "SwingQueued",
			("expected 'SwingQueued', got %q"):format(result.status))
	end)

	check("AES SwingIntent: state = BALL_IN_FLIGHT after successful SwingIntent", function()
		local state = GameService:GetState(player)
		assert(state == "BALL_IN_FLIGHT",
			("expected BALL_IN_FLIGHT, got %q"):format(state))
	end)

	-- ── SwingIntent: outside SWING state ─────────────────────────────────────
	-- State is BALL_IN_FLIGHT; OnSwingFired errors → AES returns StateError.

	check("AES SwingIntent: outside SWING (BALL_IN_FLIGHT) → success=false", function()
		local result = AES:Execute(player, _envelope("SwingIntent", {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.5,
		}))
		assert(result.success == false,
			"expected success=false for SwingIntent when not in SWING")
		assert(result.status == "StateError",
			("expected 'StateError', got %q"):format(result.status))
	end)

	-- ── HoleReady: outside TEE_OFF state ─────────────────────────────────────
	-- State is still BALL_IN_FLIGHT; OnHoleReady errors → StateError.

	check("AES HoleReady: outside TEE_OFF (BALL_IN_FLIGHT) → success=false, StateError", function()
		local result = AES:Execute(player, _envelope("HoleReady", {}))
		assert(result.success == false,
			"expected success=false for HoleReady when not in TEE_OFF")
		assert(result.status == "StateError",
			("expected 'StateError', got %q"):format(result.status))
	end)

	-- Cleanup session before remaining tests.
	GameService:AbortRound(player)

	-- ── Unknown eventType ─────────────────────────────────────────────────────

	check("AES: unknown eventType → success=false, status='UnknownEvent'", function()
		local result = AES:Execute(player, _envelope("DoSomethingInvalid", {}))
		assert(result.success == false,
			"expected success=false for unknown eventType")
		assert(result.status == "UnknownEvent",
			("expected 'UnknownEvent', got %q"):format(result.status))
	end)

	-- ── Stub handlers still return success ────────────────────────────────────

	check("AES QueueMatchmaking stub → success=true", function()
		local result = AES:Execute(player, _envelope("QueueMatchmaking", {}))
		assert(result.success == true,
			("expected success=true for QueueMatchmaking, got %s"):format(
				tostring(result.success)))
	end)

	check("AES EquipCosmetic stub → success=true", function()
		local result = AES:Execute(player, _envelope("EquipCosmetic", {}))
		assert(result.success == true,
			("expected success=true for EquipCosmetic, got %s"):format(
				tostring(result.success)))
	end)

	check("AES CancelMatchmaking stub → success=true", function()
		local result = AES:Execute(player, _envelope("CancelMatchmaking", {}))
		assert(result.success == true,
			("expected success=true for CancelMatchmaking, got %s"):format(
				tostring(result.success)))
	end)

	-- ── Execution counter ────────────────────────────────────────────────────
	-- _executionCount increments for every handler that returns normally
	-- (including validation-failure returns; only throwing handlers skip the increment).

	check("AES: executionCount increments for each non-throwing Execute call", function()
		AES:ResetExecutionCount()
		AES:Execute(player, _envelope("QueueMatchmaking", {}))   -- success
		AES:Execute(player, _envelope("EquipCosmetic", {}))      -- success
		AES:Execute(player, _envelope("SwingIntent", {           -- validation failure (no aimVector)
			power = 0.5,
		}))
		assert(AES:GetExecutionCount() == 3,
			("expected 3, got %d"):format(AES:GetExecutionCount()))
	end)

	check("AES: ResetExecutionCount resets to 0", function()
		AES:ResetExecutionCount()
		assert(AES:GetExecutionCount() == 0,
			("expected 0 after reset, got %d"):format(AES:GetExecutionCount()))
	end)

	-- ── Destroy + re-Init ─────────────────────────────────────────────────────

	check("AES: Destroy resets executionCount to 0", function()
		AES:Execute(player, _envelope("SetReady", {}))  -- make count non-zero
		AES:Destroy()
		assert(AES:GetExecutionCount() == 0,
			("expected 0 after Destroy, got %d"):format(AES:GetExecutionCount()))
	end)

	check("AES: re-Init after Destroy works", function()
		AES:Init({})
		assert(AES:GetExecutionCount() == 0,
			("expected 0 after re-Init, got %d"):format(AES:GetExecutionCount()))
	end)

	-- Verify HoleReady still works after re-Init (real handler still functional).
	check("AES: HoleReady works after re-Init — no session → safe failure", function()
		local result = AES:Execute(player, _envelope("HoleReady", {}))
		assert(result.success == false,
			"expected false after re-Init (no session)")
		assert(result.status == "NoSession",
			("expected 'NoSession', got %q"):format(result.status))
	end)

	check("AES: Update(0) does not error", function()
		AES:Update(0)
	end)

	-- ── Teardown ──────────────────────────────────────────────────────────────
	GameService:AbortRound(player)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 25 smoke tests PASSED.")
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
