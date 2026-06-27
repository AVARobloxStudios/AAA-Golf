--!strict
-- Sprint27ServerTest — Server Script smoke tests for Sprint 27.
-- Run in Studio Play Solo mode. No API Services required for immediate checks;
-- profile readiness gate guards the GameService path (same as Sprint25ServerTest).
--
-- Covers (27 checks):
--   Immediate (3): module loading, Init/Destroy exist.
--   Player-gated (24):
--     API surface — all 10 public methods are functions.
--     Counts — 0 after Init.
--     BeginRoundForPlayer — success path, duplicate AlreadyStarted, startedCount.
--     GameService state — TEE_OFF after begin, correct pipelineState snapshot.
--     QueueHoleReady — success from TEE_OFF, holeReadyCount, state→SWING.
--     QueueSwingIntent — invalid payload rejects (InvalidAimVector), state unchanged,
--       rejectedCount; valid from SWING succeeds (SwingQueued), state→BALL_IN_FLIGHT,
--       swingIntentCount; outside SWING rejects (StateError).
--     QueueHoleReady outside TEE_OFF — rejects (StateError).
--     Cumulative counts — started=1, holeReady=1, swingIntent=1, rejected=3.
--     ResetCounts — all zero.
--     ResetPlayer — true, state→LOBBY, pipelineState.gameState=LOBBY.
--     Update, Init guard, Destroy, re-Init, BeginRoundForPlayer after re-Init.
--
-- RoundPipelineService and AES are reset via Destroy()+Init() for isolation.
-- GameService and ScoringService are left as-is (initialized by thin runners).

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RPS = require(ServerScriptService.Services.RoundPipelineService)
local AES = require(ServerScriptService.Services.ActionExecutionService)

local GameService       = require(ServerScriptService.Modules.GameService)
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)

local TAG = "[Sprint27ServerTest]"

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

-- ── Immediate module-level checks (no player needed) ─────────────────────────

check("RPS: module loads", function()
	assert(type(RPS) == "table", "expected table")
end)

check("RPS: Init function exists", function()
	assert(type(RPS.Init) == "function")
end)

check("RPS: Destroy function exists", function()
	assert(type(RPS.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 27 pipeline tests for " .. player.Name .. " ──")

	-- Reset for test isolation. Leave GameService/ScoringService as-is.
	RPS:Destroy()
	AES:Destroy()
	AES:Init({})
	RPS:Init({})
	GameService:AbortRound(player)

	-- ── API surface ───────────────────────────────────────────────────────────

	check("RPS: all public methods exist", function()
		local methods = {
			"BeginRoundForPlayer", "QueueHoleReady", "QueueSwingIntent",
			"GetPlayerPipelineState", "ResetPlayer",
			"GetStartedCount", "GetHoleReadyCount", "GetSwingIntentCount",
			"GetRejectedCount", "ResetCounts",
		}
		for _, name in ipairs(methods) do
			assert(type(RPS[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	check("RPS: all counts = 0 after Init", function()
		assert(RPS:GetStartedCount()     == 0, "startedCount should be 0")
		assert(RPS:GetHoleReadyCount()   == 0, "holeReadyCount should be 0")
		assert(RPS:GetSwingIntentCount() == 0, "swingIntentCount should be 0")
		assert(RPS:GetRejectedCount()    == 0, "rejectedCount should be 0")
	end)

	-- ── Profile readiness gate ────────────────────────────────────────────────
	-- GameService:StartRound → ScoringService:StartRound requires a loaded profile.

	local profileReady = pollUntil(function()
		return PlayerDataService:GetProfile(player) ~= nil
	end, 10)

	if not profileReady then
		warn(TAG .. " Profile not ready after 10s for " .. player.Name
			.. " — aborting (check API Access in Studio settings)")
		return
	end

	-- ── BeginRoundForPlayer ───────────────────────────────────────────────────

	check("RPS: BeginRoundForPlayer → success=true, status='Started'", function()
		local result = RPS:BeginRoundForPlayer(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "Started",
			("expected 'Started', got %q"):format(result.status))
	end)

	check("RPS: startedCount = 1 after BeginRoundForPlayer", function()
		assert(RPS:GetStartedCount() == 1,
			("expected 1, got %d"):format(RPS:GetStartedCount()))
	end)

	check("RPS: duplicate BeginRoundForPlayer → success=false, status='AlreadyStarted'", function()
		local result = RPS:BeginRoundForPlayer(player)
		assert(result.success == false,
			"expected success=false for duplicate call")
		assert(result.status == "AlreadyStarted",
			("expected 'AlreadyStarted', got %q"):format(result.status))
		assert(RPS:GetStartedCount() == 1,
			"startedCount must not increment on failure")
	end)

	check("RPS: GameService state = TEE_OFF after BeginRoundForPlayer", function()
		local state = GameService:GetState(player)
		assert(state == "TEE_OFF",
			("expected TEE_OFF, got %q"):format(state))
	end)

	check("RPS: GetPlayerPipelineState at TEE_OFF returns correct fields", function()
		local ps = RPS:GetPlayerPipelineState(player)
		assert(ps.gameState == "TEE_OFF",
			("expected gameState='TEE_OFF', got %q"):format(ps.gameState))
		assert(ps.currentHoleId == "Hole_01",
			("expected currentHoleId='Hole_01', got %s"):format(tostring(ps.currentHoleId)))
		assert(ps.hasTeePosition == true, "expected hasTeePosition=true")
		assert(ps.hasPinPosition == true, "expected hasPinPosition=true")
	end)

	-- ── QueueHoleReady ────────────────────────────────────────────────────────

	check("RPS: QueueHoleReady from TEE_OFF → success=true, state→SWING", function()
		local result = RPS:QueueHoleReady(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(GameService:GetState(player) == "SWING",
			("expected SWING after QueueHoleReady, got %q"):format(
				GameService:GetState(player)))
	end)

	check("RPS: holeReadyCount = 1 after successful QueueHoleReady", function()
		assert(RPS:GetHoleReadyCount() == 1,
			("expected 1, got %d"):format(RPS:GetHoleReadyCount()))
	end)

	-- ── QueueSwingIntent: invalid payload ─────────────────────────────────────

	check("RPS: QueueSwingIntent empty payload → success=false, state stays SWING", function()
		local result = RPS:QueueSwingIntent(player, {})
		assert(result.success == false,
			"expected success=false for empty SwingIntent payload")
		assert(result.status == "InvalidAimVector",
			("expected 'InvalidAimVector', got %q"):format(result.status))
		assert(GameService:GetState(player) == "SWING",
			"state must remain SWING after invalid SwingIntent")
	end)

	check("RPS: rejectedCount = 1 after invalid QueueSwingIntent", function()
		assert(RPS:GetRejectedCount() == 1,
			("expected 1, got %d"):format(RPS:GetRejectedCount()))
	end)

	-- ── QueueSwingIntent: valid payload from SWING ────────────────────────────

	check("RPS: QueueSwingIntent valid from SWING → success=true, state→BALL_IN_FLIGHT", function()
		local result = RPS:QueueSwingIntent(player, {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.75,
		})
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "SwingQueued",
			("expected 'SwingQueued', got %q"):format(result.status))
		assert(GameService:GetState(player) == "BALL_IN_FLIGHT",
			("expected BALL_IN_FLIGHT, got %q"):format(GameService:GetState(player)))
	end)

	check("RPS: swingIntentCount = 1 after successful QueueSwingIntent", function()
		assert(RPS:GetSwingIntentCount() == 1,
			("expected 1, got %d"):format(RPS:GetSwingIntentCount()))
	end)

	-- ── QueueSwingIntent: outside SWING ──────────────────────────────────────

	check("RPS: QueueSwingIntent from BALL_IN_FLIGHT → success=false, status=StateError", function()
		local result = RPS:QueueSwingIntent(player, {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.5,
		})
		assert(result.success == false,
			"expected success=false for SwingIntent outside SWING")
		assert(result.status == "StateError",
			("expected 'StateError', got %q"):format(result.status))
	end)

	-- ── QueueHoleReady: outside TEE_OFF ──────────────────────────────────────

	check("RPS: QueueHoleReady from BALL_IN_FLIGHT → success=false, status=StateError", function()
		local result = RPS:QueueHoleReady(player)
		assert(result.success == false,
			"expected success=false for HoleReady outside TEE_OFF")
		assert(result.status == "StateError",
			("expected 'StateError', got %q"):format(result.status))
	end)

	-- ── Cumulative count assertions ───────────────────────────────────────────
	-- At this point: started=1, holeReady=1, swingIntent=1, rejected=3
	-- (invalid SwingIntent + outside-SWING SwingIntent + outside-TEE_OFF HoleReady)

	check("RPS: cumulative counts — started=1, holeReady=1, swingIntent=1, rejected=3", function()
		assert(RPS:GetStartedCount()     == 1,
			("expected startedCount=1, got %d"):format(RPS:GetStartedCount()))
		assert(RPS:GetHoleReadyCount()   == 1,
			("expected holeReadyCount=1, got %d"):format(RPS:GetHoleReadyCount()))
		assert(RPS:GetSwingIntentCount() == 1,
			("expected swingIntentCount=1, got %d"):format(RPS:GetSwingIntentCount()))
		assert(RPS:GetRejectedCount()    == 3,
			("expected rejectedCount=3, got %d"):format(RPS:GetRejectedCount()))
	end)

	-- ── ResetCounts ───────────────────────────────────────────────────────────

	check("RPS: ResetCounts clears all to 0", function()
		RPS:ResetCounts()
		assert(RPS:GetStartedCount()     == 0, "expected startedCount=0")
		assert(RPS:GetHoleReadyCount()   == 0, "expected holeReadyCount=0")
		assert(RPS:GetSwingIntentCount() == 0, "expected swingIntentCount=0")
		assert(RPS:GetRejectedCount()    == 0, "expected rejectedCount=0")
	end)

	-- ── ResetPlayer ───────────────────────────────────────────────────────────

	check("RPS: ResetPlayer aborts active round and returns true", function()
		local ok = RPS:ResetPlayer(player)
		assert(ok == true, "expected ResetPlayer to return true")
	end)

	check("RPS: state = LOBBY after ResetPlayer", function()
		assert(GameService:GetState(player) == "LOBBY",
			("expected LOBBY, got %q"):format(GameService:GetState(player)))
	end)

	check("RPS: GetPlayerPipelineState.gameState = LOBBY, currentHoleId = nil", function()
		local ps = RPS:GetPlayerPipelineState(player)
		assert(ps.gameState == "LOBBY",
			("expected gameState='LOBBY', got %q"):format(ps.gameState))
		assert(ps.currentHoleId == nil,
			("expected currentHoleId=nil, got %s"):format(tostring(ps.currentHoleId)))
	end)

	-- ── Update ────────────────────────────────────────────────────────────────

	check("RPS: Update(0) does not error", function()
		RPS:Update(0)
	end)

	-- ── Init guard ────────────────────────────────────────────────────────────

	check("RPS: Init called twice warns and skips (counts unchanged)", function()
		RPS:Init({})
		assert(RPS:GetStartedCount() == 0, "counts must be 0 after double Init")
	end)

	-- ── Destroy + re-Init ─────────────────────────────────────────────────────

	check("RPS: Destroy resets all counts to 0", function()
		RPS:BeginRoundForPlayer(player)   -- startedCount → 1
		RPS:Destroy()
		assert(RPS:GetStartedCount() == 0, "expected 0 after Destroy")
	end)

	GameService:AbortRound(player)

	check("RPS: re-Init after Destroy works — counts = 0", function()
		RPS:Init({})
		assert(RPS:GetStartedCount()     == 0, "expected startedCount=0 after re-Init")
		assert(RPS:GetHoleReadyCount()   == 0, "expected holeReadyCount=0 after re-Init")
		assert(RPS:GetSwingIntentCount() == 0, "expected swingIntentCount=0 after re-Init")
		assert(RPS:GetRejectedCount()    == 0, "expected rejectedCount=0 after re-Init")
	end)

	check("RPS: BeginRoundForPlayer works after re-Init", function()
		local result = RPS:BeginRoundForPlayer(player)
		assert(result.success == true,
			("expected success after re-Init, got status=%q"):format(result.status))
		assert(RPS:GetStartedCount() == 1, "expected startedCount=1 after re-Init")
	end)

	-- ── Teardown ──────────────────────────────────────────────────────────────

	GameService:AbortRound(player)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 27 smoke tests PASSED.")
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
