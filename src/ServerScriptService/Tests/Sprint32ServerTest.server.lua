--!strict
-- Sprint32ServerTest — Server Script smoke tests for Sprint 32.
-- Run in Studio Play Solo mode.
--
-- Profile gate required: StartVerticalSlice → RPS:BeginRoundForPlayer →
-- GameService:StartRound → ScoringService:StartRound needs a DataStore profile.
--
-- Covers (24 checks):
--   Immediate (3): module loads, Init, Destroy exist.
--   Player-gated (21):
--     API surface.
--     Counts = 0 after Init.
--     GetFlowState default = LobbyReady.
--     [profile gate]
--     StartVerticalSlice success → RoundStarted, startedCount=1.
--     GetFlowState after start.
--     MarkHoleReady success → HoleReady.
--     SubmitSwing invalid payload → rejection, rejectedCount=1.
--     SubmitSwing valid → ShotInProgress.
--     RecordBallLanding invalid → rejection, rejectedCount=2.
--     RecordBallLanding valid → BallLanded.
--     MarkHoleComplete success → HoleComplete.
--     FinalizeVerticalSlice success → RoundComplete, completedCount=1.
--     GetFlowState = RoundComplete, started=true, completed=true.
--     completedCount=1, rejectedCount=2.
--     GetFlowState copy isolation.
--     ResetPlayer clears to LobbyReady.
--     ResetCounts.
--     Update(0).
--     Init guard.
--     Destroy + re-Init.
--
-- All sub-services are reset for isolation; GameService is NOT destroyed.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local VSFS = require(ServerScriptService.Services.VerticalSliceFlowService)
local RPS  = require(ServerScriptService.Services.RoundPipelineService)
local SLS  = require(ServerScriptService.Services.ShotLifecycleService)
local LPS  = require(ServerScriptService.Services.LandingPipelineService)
local HCS  = require(ServerScriptService.Services.HoleCompletionService)
local RCS  = require(ServerScriptService.Services.RoundCompletionService)
local AES  = require(ServerScriptService.Services.ActionExecutionService)

local GameService       = require(ServerScriptService.Modules.GameService)
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)

local TAG = "[Sprint32ServerTest]"

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

-- ── Immediate module-level checks ─────────────────────────────────────────────

check("VSFS: module loads", function()
	assert(type(VSFS) == "table", "expected table")
end)

check("VSFS: Init function exists", function()
	assert(type(VSFS.Init) == "function")
end)

check("VSFS: Destroy function exists", function()
	assert(type(VSFS.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 32 vertical slice flow tests for " .. player.Name .. " ──")

	-- Reset all services for isolation.
	VSFS:Destroy()
	RCS:Destroy(); RCS:Init({})
	HCS:Destroy(); HCS:Init({})
	LPS:Destroy()
	SLS:Destroy()
	AES:Destroy(); AES:Init({})
	SLS:Init({})
	LPS:Init({})
	RPS:Destroy(); RPS:Init({})
	VSFS:Init({})
	GameService:AbortRound(player)

	-- ── API surface ───────────────────────────────────────────────────────────

	check("VSFS: all public methods exist", function()
		local methods = {
			"StartVerticalSlice", "MarkHoleReady", "SubmitSwing",
			"RecordBallLanding", "MarkHoleComplete", "FinalizeVerticalSlice",
			"GetFlowState", "ResetPlayer",
			"GetStartedCount", "GetCompletedCount", "GetRejectedCount", "ResetCounts",
			"Init", "Update", "Destroy",
		}
		for _, name in ipairs(methods) do
			assert(type(VSFS[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	-- ── Counts = 0 ────────────────────────────────────────────────────────────

	check("VSFS: all counts = 0 after Init", function()
		assert(VSFS:GetStartedCount()   == 0, "startedCount should be 0")
		assert(VSFS:GetCompletedCount() == 0, "completedCount should be 0")
		assert(VSFS:GetRejectedCount()  == 0, "rejectedCount should be 0")
	end)

	-- ── GetFlowState default ──────────────────────────────────────────────────

	check("VSFS: GetFlowState default = { state='LobbyReady', started=false, completed=false }", function()
		local fs = VSFS:GetFlowState(player)
		assert(fs.state     == "LobbyReady",
			("expected 'LobbyReady', got %q"):format(fs.state))
		assert(fs.started   == false, "expected started=false")
		assert(fs.completed == false, "expected completed=false")
	end)

	-- ── Profile readiness gate ────────────────────────────────────────────────

	local profileReady = pollUntil(function()
		return PlayerDataService:GetProfile(player) ~= nil
	end, 10)

	if not profileReady then
		warn(TAG .. " Profile not ready after 10s for " .. player.Name
			.. " — aborting (check API Access in Studio settings)")
		return
	end

	-- ── StartVerticalSlice ────────────────────────────────────────────────────

	check("VSFS: StartVerticalSlice → success=true", function()
		local result = VSFS:StartVerticalSlice(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
	end)

	check("VSFS: GetFlowState after StartVerticalSlice = { state='RoundStarted', started=true }", function()
		local fs = VSFS:GetFlowState(player)
		assert(fs.state   == "RoundStarted",
			("expected 'RoundStarted', got %q"):format(fs.state))
		assert(fs.started == true, "expected started=true")
	end)

	check("VSFS: startedCount = 1 after StartVerticalSlice", function()
		assert(VSFS:GetStartedCount() == 1,
			("expected 1, got %d"):format(VSFS:GetStartedCount()))
	end)

	-- ── MarkHoleReady ─────────────────────────────────────────────────────────

	check("VSFS: MarkHoleReady → success=true, state='HoleReady'", function()
		local result = VSFS:MarkHoleReady(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		local fs = VSFS:GetFlowState(player)
		assert(fs.state == "HoleReady",
			("expected 'HoleReady', got %q"):format(fs.state))
	end)

	-- ── SubmitSwing: invalid payload ──────────────────────────────────────────
	-- Non-table payload fails at SLS level before AES; GameService stays SWING.

	check("VSFS: SubmitSwing invalid payload → success=false, rejectedCount=1", function()
		local result = VSFS:SubmitSwing(player, "not-a-table" :: any)
		assert(result.success == false, "expected success=false for invalid payload")
		assert(VSFS:GetRejectedCount() == 1,
			("expected rejectedCount=1, got %d"):format(VSFS:GetRejectedCount()))
	end)

	-- ── SubmitSwing: valid ────────────────────────────────────────────────────

	check("VSFS: SubmitSwing valid payload → success=true, state='ShotInProgress'", function()
		local result = VSFS:SubmitSwing(player, {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.75,
		})
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		local fs = VSFS:GetFlowState(player)
		assert(fs.state == "ShotInProgress",
			("expected 'ShotInProgress', got %q"):format(fs.state))
	end)

	-- ── RecordBallLanding: invalid ────────────────────────────────────────────
	-- Non-Vector3 fails at LPS level; SLS shot stays InFlight.

	check("VSFS: RecordBallLanding invalid → success=false, rejectedCount=2", function()
		local result = VSFS:RecordBallLanding(player, "bad" :: any)
		assert(result.success == false, "expected success=false for non-Vector3")
		assert(VSFS:GetRejectedCount() == 2,
			("expected rejectedCount=2, got %d"):format(VSFS:GetRejectedCount()))
	end)

	-- ── RecordBallLanding: valid ──────────────────────────────────────────────

	check("VSFS: RecordBallLanding valid → success=true, state='BallLanded'", function()
		local result = VSFS:RecordBallLanding(player, Vector3.new(100, 0, 100))
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		local fs = VSFS:GetFlowState(player)
		assert(fs.state == "BallLanded",
			("expected 'BallLanded', got %q"):format(fs.state))
	end)

	-- ── MarkHoleComplete ──────────────────────────────────────────────────────

	check("VSFS: MarkHoleComplete → success=true, state='HoleComplete'", function()
		local result = VSFS:MarkHoleComplete(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		local fs = VSFS:GetFlowState(player)
		assert(fs.state == "HoleComplete",
			("expected 'HoleComplete', got %q"):format(fs.state))
	end)

	-- ── FinalizeVerticalSlice ─────────────────────────────────────────────────

	check("VSFS: FinalizeVerticalSlice → success=true, state='RoundComplete', completedCount=1", function()
		local result = VSFS:FinalizeVerticalSlice(player)
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		local fs = VSFS:GetFlowState(player)
		assert(fs.state == "RoundComplete",
			("expected 'RoundComplete', got %q"):format(fs.state))
		assert(fs.completed == true, "expected completed=true")
		assert(VSFS:GetCompletedCount() == 1,
			("expected completedCount=1, got %d"):format(VSFS:GetCompletedCount()))
	end)

	-- ── GetFlowState: full read ───────────────────────────────────────────────

	check("VSFS: GetFlowState = { state='RoundComplete', started=true, completed=true }", function()
		local fs = VSFS:GetFlowState(player)
		assert(fs.state     == "RoundComplete",
			("expected 'RoundComplete', got %q"):format(fs.state))
		assert(fs.started   == true, "expected started=true")
		assert(fs.completed == true, "expected completed=true")
	end)

	-- ── Cumulative counts ─────────────────────────────────────────────────────

	check("VSFS: completedCount=1, rejectedCount=2", function()
		assert(VSFS:GetCompletedCount() == 1,
			("expected completedCount=1, got %d"):format(VSFS:GetCompletedCount()))
		assert(VSFS:GetRejectedCount() == 2,
			("expected rejectedCount=2, got %d"):format(VSFS:GetRejectedCount()))
	end)

	-- ── GetFlowState copy isolation ───────────────────────────────────────────

	check("VSFS: GetFlowState returns independent copy", function()
		local snap  = VSFS:GetFlowState(player)
		local saved = snap.state
		snap.state     = "MUTATED"
		snap.started   = false
		snap.completed = false
		local snap2 = VSFS:GetFlowState(player)
		assert(snap2.state == saved,
			("expected internal state %q unchanged, got %q"):format(saved, snap2.state))
		assert(snap2.completed == true, "expected completed=true unchanged after mutation")
	end)

	-- ── ResetPlayer ───────────────────────────────────────────────────────────

	check("VSFS: ResetPlayer clears state to LobbyReady", function()
		VSFS:ResetPlayer(player)
		local fs = VSFS:GetFlowState(player)
		assert(fs.state     == "LobbyReady",
			("expected 'LobbyReady' after ResetPlayer, got %q"):format(fs.state))
		assert(fs.started   == false, "expected started=false after ResetPlayer")
		assert(fs.completed == false, "expected completed=false after ResetPlayer")
	end)

	-- ── ResetCounts ───────────────────────────────────────────────────────────

	check("VSFS: ResetCounts clears all to 0", function()
		VSFS:ResetCounts()
		assert(VSFS:GetStartedCount()   == 0, "expected startedCount=0")
		assert(VSFS:GetCompletedCount() == 0, "expected completedCount=0")
		assert(VSFS:GetRejectedCount()  == 0, "expected rejectedCount=0")
	end)

	-- ── Update ────────────────────────────────────────────────────────────────

	check("VSFS: Update(0) does not error", function()
		VSFS:Update(0)
	end)

	-- ── Init guard ────────────────────────────────────────────────────────────

	check("VSFS: Init called twice warns and skips", function()
		VSFS:Init({})
		assert(VSFS:GetStartedCount() == 0, "counts should stay 0 after double Init")
	end)

	-- ── Destroy + re-Init ─────────────────────────────────────────────────────

	check("VSFS: Destroy + re-Init — GetFlowState returns LobbyReady", function()
		VSFS:Destroy()
		assert(VSFS:GetStartedCount()   == 0, "expected startedCount=0 after Destroy")
		assert(VSFS:GetCompletedCount() == 0, "expected completedCount=0 after Destroy")
		assert(VSFS:GetRejectedCount()  == 0, "expected rejectedCount=0 after Destroy")
		VSFS:Init({})
		local fs = VSFS:GetFlowState(player)
		assert(fs.state == "LobbyReady",
			("expected 'LobbyReady' after re-Init, got %q"):format(fs.state))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 32 smoke tests PASSED.")
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
