--!strict
-- Sprint28ServerTest — Server Script smoke tests for Sprint 28.
-- Run in Studio Play Solo mode.  No API Services required for immediate checks;
-- profile readiness gate guards the GameService path (same as Sprint25/27).
--
-- Covers (27 checks):
--   Immediate (3): module loading, Init/Destroy exist.
--   Player-gated (24):
--     API surface — all public methods are functions.
--     Counts — 0 after Init.
--     GetShotState before any shot — state = None.
--     StartShot payload validation — non-table, invalid aimVector, invalid power,
--       empty clubName all reject before reaching AES.
--     StartShot in TEE_OFF (wrong state) — AES returns StateError, rejected safely.
--     StartShot success from SWING — state → InFlight, startedCount.
--     MarkBallLanded — non-Vector3 rejects; success from InFlight; state → Landed;
--       landedCount; second call rejects (not InFlight).
--     ResetShot — state → None.
--     Cumulative counts — started=1, landed=1, rejected=5.
--     ResetCounts.
--     Update, Init guard, Destroy, re-Init.
--
-- ShotLifecycleService and AES are reset for isolation; GameService is NOT
-- destroyed (initialized by its own thin runner).

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local SLS = require(ServerScriptService.Services.ShotLifecycleService)
local AES = require(ServerScriptService.Services.ActionExecutionService)

local GameService       = require(ServerScriptService.Modules.GameService)
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)

local TAG = "[Sprint28ServerTest]"

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

check("SLS: module loads", function()
	assert(type(SLS) == "table", "expected table")
end)

check("SLS: Init function exists", function()
	assert(type(SLS.Init) == "function")
end)

check("SLS: Destroy function exists", function()
	assert(type(SLS.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 28 shot lifecycle tests for " .. player.Name .. " ──")

	-- Reset for isolation.
	SLS:Destroy()
	AES:Destroy()
	AES:Init({})
	SLS:Init({})
	GameService:AbortRound(player)

	-- ── API surface ───────────────────────────────────────────────────────────

	check("SLS: all public methods exist", function()
		local methods = {
			"StartShot", "MarkBallLanded", "GetShotState", "ResetShot",
			"GetStartedCount", "GetLandedCount", "GetRejectedCount", "ResetCounts",
		}
		for _, name in ipairs(methods) do
			assert(type(SLS[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	check("SLS: all counts = 0 after Init", function()
		assert(SLS:GetStartedCount()  == 0, "startedCount should be 0")
		assert(SLS:GetLandedCount()   == 0, "landedCount should be 0")
		assert(SLS:GetRejectedCount() == 0, "rejectedCount should be 0")
	end)

	check("SLS: GetShotState before any shot returns state='None'", function()
		local ss = SLS:GetShotState(player)
		assert(ss.state              == "None",  ("expected 'None', got %q"):format(ss.state))
		assert(ss.hasPayload         == false,   "expected hasPayload=false")
		assert(ss.hasLandingPosition == false,   "expected hasLandingPosition=false")
	end)

	-- ── StartShot: payload validation rejections ──────────────────────────────

	check("SLS: StartShot non-table payload → success=false, status='InvalidPayload'", function()
		local result = SLS:StartShot(player, "bad" :: any)
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidPayload",
			("expected 'InvalidPayload', got %q"):format(result.status))
	end)

	check("SLS: rejectedCount = 1 after non-table rejection", function()
		assert(SLS:GetRejectedCount() == 1,
			("expected 1, got %d"):format(SLS:GetRejectedCount()))
	end)

	check("SLS: StartShot invalid aimVector → success=false, status='InvalidAimVector'", function()
		local result = SLS:StartShot(player, {
			aimVector = "forward",
			power     = 0.5,
		} :: any)
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidAimVector",
			("expected 'InvalidAimVector', got %q"):format(result.status))
	end)

	check("SLS: StartShot invalid power (>1) → success=false, status='InvalidPower'", function()
		local result = SLS:StartShot(player, {
			aimVector = Vector3.new(0, 0, -1),
			power     = 1.5,
		})
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidPower",
			("expected 'InvalidPower', got %q"):format(result.status))
	end)

	check("SLS: StartShot empty clubName → success=false, status='InvalidClubName'", function()
		local result = SLS:StartShot(player, {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.5,
			clubName  = "",
		})
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidClubName",
			("expected 'InvalidClubName', got %q"):format(result.status))
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

	-- ── StartShot: wrong GameService state ────────────────────────────────────
	-- Player is in TEE_OFF after StartRound; SwingIntent requires SWING.

	GameService:StartRound(player)

	check("SLS: StartShot in TEE_OFF → success=false (AES returns StateError)", function()
		local result = SLS:StartShot(player, {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.75,
		})
		assert(result.success == false, "expected success=false in TEE_OFF")
		assert(result.status == "StateError",
			("expected 'StateError', got %q"):format(result.status))
		assert(SLS:GetShotState(player).state == "None",
			"shot state must remain None after failure")
	end)

	check("SLS: rejectedCount = 5 after 4 validation + 1 state failure", function()
		assert(SLS:GetRejectedCount() == 5,
			("expected 5, got %d"):format(SLS:GetRejectedCount()))
	end)

	-- ── StartShot: success from SWING ────────────────────────────────────────
	-- Transition TEE_OFF → SWING via AES:Execute(HoleReady).

	AES:Execute(player, { eventType = "HoleReady", payload = {} })

	check("SLS: StartShot valid payload from SWING → success=true, state=InFlight", function()
		local result = SLS:StartShot(player, {
			aimVector = Vector3.new(0, 0, -1),
			power     = 0.75,
		})
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		local ss = SLS:GetShotState(player)
		assert(ss.state     == "InFlight", ("expected 'InFlight', got %q"):format(ss.state))
		assert(ss.hasPayload == true,       "expected hasPayload=true")
	end)

	check("SLS: startedCount = 1 after successful StartShot", function()
		assert(SLS:GetStartedCount() == 1,
			("expected 1, got %d"):format(SLS:GetStartedCount()))
	end)

	-- ── MarkBallLanded ────────────────────────────────────────────────────────

	check("SLS: MarkBallLanded non-Vector3 → success=false, status='InvalidLandingPosition'", function()
		local result = SLS:MarkBallLanded(player, "not a vector" :: any)
		assert(result.success == false, "expected success=false for non-Vector3")
		assert(result.status == "InvalidLandingPosition",
			("expected 'InvalidLandingPosition', got %q"):format(result.status))
		assert(SLS:GetShotState(player).state == "InFlight",
			"shot state must remain InFlight after invalid MarkBallLanded")
	end)

	check("SLS: MarkBallLanded valid Vector3 → success=true, status='Landed'", function()
		local result = SLS:MarkBallLanded(player, Vector3.new(100, 0, 100))
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "Landed",
			("expected 'Landed', got %q"):format(result.status))
	end)

	check("SLS: GetShotState = Landed with hasLandingPosition=true after MarkBallLanded", function()
		local ss = SLS:GetShotState(player)
		assert(ss.state              == "Landed", ("expected 'Landed', got %q"):format(ss.state))
		assert(ss.hasPayload         == true,      "expected hasPayload=true")
		assert(ss.hasLandingPosition == true,      "expected hasLandingPosition=true")
	end)

	check("SLS: landedCount = 1 after successful MarkBallLanded", function()
		assert(SLS:GetLandedCount() == 1,
			("expected 1, got %d"):format(SLS:GetLandedCount()))
	end)

	check("SLS: MarkBallLanded again → success=false (not InFlight)", function()
		local result = SLS:MarkBallLanded(player, Vector3.new(200, 0, 200))
		assert(result.success == false, "expected success=false when state=Landed")
		assert(result.status == "NotInFlight",
			("expected 'NotInFlight', got %q"):format(result.status))
		assert(SLS:GetLandedCount() == 1,
			"landedCount must not change on duplicate MarkBallLanded")
	end)

	-- ── ResetShot ─────────────────────────────────────────────────────────────

	check("SLS: ResetShot clears shot state to None", function()
		SLS:ResetShot(player)
		local ss = SLS:GetShotState(player)
		assert(ss.state              == "None",  ("expected 'None', got %q"):format(ss.state))
		assert(ss.hasPayload         == false,   "expected hasPayload=false after ResetShot")
		assert(ss.hasLandingPosition == false,   "expected hasLandingPosition=false after ResetShot")
	end)

	-- ── Cumulative count assertions ───────────────────────────────────────────

	check("SLS: cumulative counts — started=1, landed=1, rejected=5", function()
		assert(SLS:GetStartedCount()  == 1,
			("expected startedCount=1, got %d"):format(SLS:GetStartedCount()))
		assert(SLS:GetLandedCount()   == 1,
			("expected landedCount=1, got %d"):format(SLS:GetLandedCount()))
		assert(SLS:GetRejectedCount() == 5,
			("expected rejectedCount=5, got %d"):format(SLS:GetRejectedCount()))
	end)

	-- ── ResetCounts ───────────────────────────────────────────────────────────

	check("SLS: ResetCounts clears all to 0", function()
		SLS:ResetCounts()
		assert(SLS:GetStartedCount()  == 0, "expected startedCount=0")
		assert(SLS:GetLandedCount()   == 0, "expected landedCount=0")
		assert(SLS:GetRejectedCount() == 0, "expected rejectedCount=0")
	end)

	-- ── Update ────────────────────────────────────────────────────────────────

	check("SLS: Update(0) does not error", function()
		SLS:Update(0)
	end)

	-- ── Init guard ────────────────────────────────────────────────────────────

	check("SLS: Init called twice warns and skips (counts unchanged)", function()
		SLS:Init({})
		assert(SLS:GetStartedCount() == 0, "counts should be 0 after double Init")
	end)

	-- ── Destroy + re-Init ─────────────────────────────────────────────────────

	check("SLS: Destroy clears all shot state and counts", function()
		-- Prime a non-zero count so Destroy has something to clear.
		SLS:StartShot(player, "bad" :: any)   -- validation fail → rejectedCount=1
		SLS:Destroy()
		assert(SLS:GetStartedCount()  == 0, "expected startedCount=0 after Destroy")
		assert(SLS:GetLandedCount()   == 0, "expected landedCount=0 after Destroy")
		assert(SLS:GetRejectedCount() == 0, "expected rejectedCount=0 after Destroy")
	end)

	GameService:AbortRound(player)

	check("SLS: re-Init after Destroy works — GetShotState returns None", function()
		SLS:Init({})
		local ss = SLS:GetShotState(player)
		assert(ss.state == "None", ("expected 'None' after re-Init, got %q"):format(ss.state))
		assert(SLS:GetStartedCount() == 0, "expected startedCount=0 after re-Init")
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 28 smoke tests PASSED.")
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
