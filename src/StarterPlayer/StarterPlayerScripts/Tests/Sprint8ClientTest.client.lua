--!strict
-- Sprint8ClientTest — LocalScript
-- Client smoke tests for CameraControllerModule (Sprint 8).
-- Run in Play mode; output appears in the Roblox Studio Output window.
-- Does NOT call Init() during checks — tests drive the module through
-- semi-public methods so no live RemoteEvent or RunService connections
-- are created during the assertion phase.

print("[Sprint8ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local TAG     = "[Sprint8ClientTest]"
local passed  = 0
local failed  = 0

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(TAG .. " PASS: " .. label)
	else
		failed += 1
		warn(TAG .. " FAIL: " .. label .. " — " .. tostring(err))
	end
end

local function safeRequire(path: Instance): (boolean, any)
	local ok, result = pcall(require, path :: any)
	if not ok then
		warn(TAG .. " FATAL: require failed — " .. tostring(result))
	end
	return ok, result
end

-- ── Shared test constants ─────────────────────────────────────────────────────

local MY_ID       = Players.LocalPlayer.UserId
local OTHER_ID    = MY_ID + 99999
local MY_BALL_ID  = "ball_" .. tostring(MY_ID)
local OTH_BALL_ID = "ball_" .. tostring(OTHER_ID)

local FAKE_LANDING = Vector3.new(50, 0, -120)

local function stateChangedFor(state: string): any
	return {
		eventType = "StateChanged",
		payload   = { playerId = MY_ID, state = state },
		timestamp = os.time(),
	}
end

local function stateChangedForOther(state: string): any
	return {
		eventType = "StateChanged",
		payload   = { playerId = OTHER_ID, state = state },
		timestamp = os.time(),
	}
end

local function ballResolvedFor(ballId: string, landingPos: any): any
	return {
		eventType = "BallResolved",
		payload   = {
			ballId         = ballId,
			landingPos     = landingPos,
			landingSurface = "FAIRWAY",
			trajectory     = {},
		},
		timestamp = os.time(),
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — CameraControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local ccmOk, ccmResult = safeRequire(
	script.Parent.Parent.Modules.CameraControllerModule)

if ccmOk then

	local CCM: any = ccmResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("CCM: module loads successfully", function()
		assert(type(CCM) == "table", "expected table, got " .. type(CCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("CCM: initial GetState is LOBBY", function()
		local state = CCM:GetState()
		assert(state == "LOBBY", ("expected LOBBY, got %q"):format(tostring(state)))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("CCM: initial GetLandingPos is nil", function()
		assert(CCM:GetLandingPos() == nil, "expected nil landing pos initially")
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	-- CameraController.client.lua runs Init() before this test script loads,
	-- so the singleton is already initialised when require() returns it here.
	check("CCM: IsInitialized is true (runner already called Init)", function()
		assert(CCM:IsInitialized() == true, "expected true — CameraController.client.lua calls Init() at startup")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent non-table envelope is ignored", function()
		CCM:_onClientEvent("not a table")
		CCM:_onClientEvent(42)
		CCM:_onClientEvent(nil)
		assert(CCM:GetState() == "LOBBY", "state should still be LOBBY")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent wrong eventType is ignored", function()
		CCM:_onClientEvent({ eventType = "SomeOtherEvent", payload = {}, timestamp = 0 })
		assert(CCM:GetState() == "LOBBY", "state should still be LOBBY")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent StateChanged own player updates state to TEE_OFF", function()
		CCM:_onClientEvent(stateChangedFor("TEE_OFF"))
		assert(CCM:GetState() == "TEE_OFF",
			("expected TEE_OFF, got %q"):format(CCM:GetState()))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("CCM: GetState reflects TEE_OFF after event", function()
		assert(CCM:GetState() == "TEE_OFF", "GetState must return TEE_OFF")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent StateChanged other player id leaves state unchanged", function()
		CCM:_onClientEvent(stateChangedForOther("LOBBY"))
		assert(CCM:GetState() == "TEE_OFF",
			("other player event should not change state; got %q"):format(CCM:GetState()))
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent StateChanged with nil payload is ignored", function()
		CCM:_onClientEvent({ eventType = "StateChanged", payload = nil, timestamp = 0 })
		assert(CCM:GetState() == "TEE_OFF", "state should still be TEE_OFF")
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent StateChanged to SWING updates state", function()
		CCM:_onClientEvent(stateChangedFor("SWING"))
		assert(CCM:GetState() == "SWING",
			("expected SWING, got %q"):format(CCM:GetState()))
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent StateChanged to BALL_IN_FLIGHT updates state", function()
		-- Pre-store a landing pos to verify it is cleared on BALL_IN_FLIGHT.
		CCM:_onClientEvent(ballResolvedFor(MY_BALL_ID, FAKE_LANDING))
		assert(CCM:GetLandingPos() ~= nil, "landing pos should be set before BALL_IN_FLIGHT")

		CCM:_onClientEvent(stateChangedFor("BALL_IN_FLIGHT"))
		assert(CCM:GetState() == "BALL_IN_FLIGHT",
			("expected BALL_IN_FLIGHT, got %q"):format(CCM:GetState()))
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("CCM: transitioning to BALL_IN_FLIGHT clears stale landing pos", function()
		assert(CCM:GetLandingPos() == nil,
			"landing pos should be nil after BALL_IN_FLIGHT transition")
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent BallResolved own ball stores landing pos", function()
		CCM:_onClientEvent(ballResolvedFor(MY_BALL_ID, FAKE_LANDING))
		assert(CCM:GetLandingPos() ~= nil, "landing pos should be stored after BallResolved")
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("CCM: GetLandingPos returns the stored Vector3", function()
		assert(CCM:GetLandingPos() == FAKE_LANDING,
			("expected %s, got %s"):format(
				tostring(FAKE_LANDING), tostring(CCM:GetLandingPos())))
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent StateChanged to SCORE_REVEAL updates state", function()
		CCM:_onClientEvent(stateChangedFor("SCORE_REVEAL"))
		assert(CCM:GetState() == "SCORE_REVEAL",
			("expected SCORE_REVEAL, got %q"):format(CCM:GetState()))
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent BallResolved other ball does not overwrite landing pos", function()
		local before = CCM:GetLandingPos()
		CCM:_onClientEvent(ballResolvedFor(OTH_BALL_ID, Vector3.new(999, 0, 999)))
		assert(CCM:GetLandingPos() == before,
			"other ball BallResolved must not change our landing pos")
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent BallResolved non-Vector3 landingPos is ignored", function()
		local before = CCM:GetLandingPos()
		CCM:_onClientEvent({
			eventType = "BallResolved",
			payload   = { ballId = MY_BALL_ID, landingPos = "not a vector" },
			timestamp = os.time(),
		})
		assert(CCM:GetLandingPos() == before,
			"non-Vector3 landingPos must not overwrite stored landing pos")
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("CCM: _onClientEvent StateChanged back to LOBBY updates state", function()
		CCM:_onClientEvent(stateChangedFor("LOBBY"))
		assert(CCM:GetState() == "LOBBY",
			("expected LOBBY, got %q"):format(CCM:GetState()))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("CCM: Destroy resets state to LOBBY", function()
		-- Drive to a non-LOBBY state first.
		CCM:_onClientEvent(stateChangedFor("TEE_OFF"))
		assert(CCM:GetState() == "TEE_OFF", "state should be TEE_OFF before Destroy")

		CCM:Destroy()

		assert(CCM:GetState() == "LOBBY",
			("expected LOBBY after Destroy, got %q"):format(CCM:GetState()))
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("CCM: Destroy clears landing pos to nil", function()
		-- LandingPos was set in check 14 and not cleared by LOBBY (only by BALL_IN_FLIGHT).
		-- Destroy must have wiped it.
		assert(CCM:GetLandingPos() == nil,
			"landing pos should be nil after Destroy")
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("CCM: Destroy sets IsInitialized to false", function()
		assert(CCM:IsInitialized() == false,
			"IsInitialized should be false after Destroy")
	end)

	-- Restore the live GameBus and RenderStepped connections that Destroy()
	-- disconnected, so CameraController remains active for the rest of the session.
	CCM:Init()

end -- ccmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 8 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
