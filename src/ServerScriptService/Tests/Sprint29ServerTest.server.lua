--!strict
-- Sprint29ServerTest — Server Script smoke tests for Sprint 29.
-- Run in Studio Play Solo mode.  No API Services required for immediate checks;
-- profile readiness gate guards the GameService/StartRound path.
--
-- Covers (19 checks):
--   Immediate (3): module loading, Init/Destroy exist.
--   Player-gated (16):
--     API surface — all public methods are functions.
--     Counts — 0 after Init.
--     GetLandingState before any landing — state="None".
--     RecordLanding non-Vector3 — fail, status="InvalidLandingPosition".
--     rejectedCount = 1.
--     RecordLanding valid Vector3, SLS has no InFlight shot — fail, status="NotInFlight".
--     rejectedCount = 2.
--     [profile gate]
--     RecordLanding succeeds after StartShot path (GameService→HoleReady→StartShot).
--     GetLandingState = Landed with hasLandingPosition=true.
--     landingCount = 1.
--     ResetLanding clears state to None.
--     Cumulative counts: landing=1, rejected=2.
--     ResetCounts.
--     Update(0).
--     Init guard.
--     Destroy + re-Init.
--
-- LandingPipelineService, ShotLifecycleService, and AES are reset for isolation;
-- GameService is NOT destroyed.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local LPS = require(ServerScriptService.Services.LandingPipelineService)
local SLS = require(ServerScriptService.Services.ShotLifecycleService)
local AES = require(ServerScriptService.Services.ActionExecutionService)

local GameService       = require(ServerScriptService.Modules.GameService)
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)

local TAG = "[Sprint29ServerTest]"

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

check("LPS: module loads", function()
	assert(type(LPS) == "table", "expected table")
end)

check("LPS: Init function exists", function()
	assert(type(LPS.Init) == "function")
end)

check("LPS: Destroy function exists", function()
	assert(type(LPS.Destroy) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 29 landing pipeline tests for " .. player.Name .. " ──")

	-- Reset for isolation: bring all three services up clean.
	LPS:Destroy()
	SLS:Destroy()
	AES:Destroy()
	AES:Init({})
	SLS:Init({})
	LPS:Init({})
	GameService:AbortRound(player)

	-- ── API surface ───────────────────────────────────────────────────────────

	check("LPS: all public methods exist", function()
		local methods = {
			"RecordLanding", "GetLandingState", "ResetLanding",
			"GetLandingCount", "GetRejectedCount", "ResetCounts",
		}
		for _, name in ipairs(methods) do
			assert(type(LPS[name]) == "function",
				("expected function for %q"):format(name))
		end
	end)

	check("LPS: all counts = 0 after Init", function()
		assert(LPS:GetLandingCount()  == 0, "landingCount should be 0")
		assert(LPS:GetRejectedCount() == 0, "rejectedCount should be 0")
	end)

	check("LPS: GetLandingState before any landing = { state='None', hasLandingPosition=false }", function()
		local ls = LPS:GetLandingState(player)
		assert(ls.state              == "None",  ("expected 'None', got %q"):format(ls.state))
		assert(ls.hasLandingPosition == false,    "expected hasLandingPosition=false")
	end)

	-- ── RecordLanding: LPS-level validation ──────────────────────────────────

	check("LPS: RecordLanding non-Vector3 → success=false, status='InvalidLandingPosition'", function()
		local result = LPS:RecordLanding(player, "bad" :: any)
		assert(result.success == false, "expected success=false")
		assert(result.status == "InvalidLandingPosition",
			("expected 'InvalidLandingPosition', got %q"):format(result.status))
	end)

	check("LPS: rejectedCount = 1 after non-Vector3 rejection", function()
		assert(LPS:GetRejectedCount() == 1,
			("expected 1, got %d"):format(LPS:GetRejectedCount()))
	end)

	-- ── RecordLanding: SLS has no InFlight shot ───────────────────────────────
	-- SLS._shots[player.UserId] is nil; MarkBallLanded returns NotInFlight.

	check("LPS: RecordLanding valid Vector3, no InFlight shot → success=false, status='NotInFlight'", function()
		local result = LPS:RecordLanding(player, Vector3.new(0, 0, 0))
		assert(result.success == false, "expected success=false when SLS has no InFlight shot")
		assert(result.status == "NotInFlight",
			("expected 'NotInFlight', got %q"):format(result.status))
	end)

	check("LPS: rejectedCount = 2 after two failures", function()
		assert(LPS:GetRejectedCount() == 2,
			("expected 2, got %d"):format(LPS:GetRejectedCount()))
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

	-- ── RecordLanding: success path ───────────────────────────────────────────
	-- GameService:StartRound → TEE_OFF
	-- AES:Execute(HoleReady) → SWING
	-- SLS:StartShot → InFlight
	-- LPS:RecordLanding → calls SLS:MarkBallLanded → success → Landed

	GameService:StartRound(player)
	AES:Execute(player, { eventType = "HoleReady", payload = {} })

	local shotResult = SLS:StartShot(player, {
		aimVector = Vector3.new(0, 0, -1),
		power     = 0.75,
	})
	assert(shotResult.success, "[LPS test setup] SLS:StartShot failed — " .. tostring(shotResult.status))

	check("LPS: RecordLanding valid Vector3 after InFlight shot → success=true, status='Landed'", function()
		local result = LPS:RecordLanding(player, Vector3.new(100, 0, 100))
		assert(result.success == true,
			("expected success=true, got success=%s status=%q"):format(
				tostring(result.success), result.status))
		assert(result.status == "Landed",
			("expected 'Landed', got %q"):format(result.status))
	end)

	check("LPS: GetLandingState = Landed with hasLandingPosition=true after success", function()
		local ls = LPS:GetLandingState(player)
		assert(ls.state              == "Landed", ("expected 'Landed', got %q"):format(ls.state))
		assert(ls.hasLandingPosition == true,      "expected hasLandingPosition=true")
	end)

	check("LPS: landingCount = 1 after successful RecordLanding", function()
		assert(LPS:GetLandingCount() == 1,
			("expected 1, got %d"):format(LPS:GetLandingCount()))
	end)

	-- ── ResetLanding ──────────────────────────────────────────────────────────

	check("LPS: ResetLanding clears landing state to None", function()
		LPS:ResetLanding(player)
		local ls = LPS:GetLandingState(player)
		assert(ls.state              == "None",  ("expected 'None', got %q"):format(ls.state))
		assert(ls.hasLandingPosition == false,    "expected hasLandingPosition=false after ResetLanding")
	end)

	-- ── Cumulative count assertions ───────────────────────────────────────────

	check("LPS: cumulative counts — landing=1, rejected=2", function()
		assert(LPS:GetLandingCount()  == 1,
			("expected landingCount=1, got %d"):format(LPS:GetLandingCount()))
		assert(LPS:GetRejectedCount() == 2,
			("expected rejectedCount=2, got %d"):format(LPS:GetRejectedCount()))
	end)

	-- ── ResetCounts ───────────────────────────────────────────────────────────

	check("LPS: ResetCounts clears all to 0", function()
		LPS:ResetCounts()
		assert(LPS:GetLandingCount()  == 0, "expected landingCount=0")
		assert(LPS:GetRejectedCount() == 0, "expected rejectedCount=0")
	end)

	-- ── Update ────────────────────────────────────────────────────────────────

	check("LPS: Update(0) does not error", function()
		LPS:Update(0)
	end)

	-- ── Init guard ────────────────────────────────────────────────────────────

	check("LPS: Init called twice warns and skips (counts unchanged)", function()
		LPS:Init({})
		assert(LPS:GetLandingCount() == 0, "counts should be 0 after double Init")
	end)

	-- ── Destroy + re-Init ─────────────────────────────────────────────────────

	check("LPS: Destroy clears landing state and counts", function()
		-- Prime a non-zero state so Destroy has something to clear.
		LPS:ResetCounts()
		LPS:GetRejectedCount() -- counts are now 0; prime by landing a rejection
		LPS:RecordLanding(player, "bad" :: any)  -- rejectedCount=1
		LPS:Destroy()
		assert(LPS:GetLandingCount()  == 0, "expected landingCount=0 after Destroy")
		assert(LPS:GetRejectedCount() == 0, "expected rejectedCount=0 after Destroy")
	end)

	GameService:AbortRound(player)

	check("LPS: re-Init after Destroy works — GetLandingState returns None", function()
		LPS:Init({})
		local ls = LPS:GetLandingState(player)
		assert(ls.state == "None", ("expected 'None' after re-Init, got %q"):format(ls.state))
		assert(LPS:GetLandingCount() == 0, "expected landingCount=0 after re-Init")
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 29 smoke tests PASSED.")
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
