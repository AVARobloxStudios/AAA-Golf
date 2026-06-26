--!strict
-- Sprint9ClientTest — LocalScript
-- Client smoke tests for HUDControllerModule (Sprint 9).
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Does NOT call Init() during checks.  HUDController.client.lua runs Init()
-- before this script loads, so safeRequire() returns the already-initialised
-- singleton (same pattern as Sprint 7 and 8 tests).
-- Tests drive the module through _onClientEvent and verify internal state
-- via the five public getters; no live network or UI interaction required.

print("[Sprint9ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local TAG     = "[Sprint9ClientTest]"
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

local MY_ID    = Players.LocalPlayer.UserId
local OTHER_ID = MY_ID + 55555

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

local function strokeCommitted(strokes: number, par: number, coins: number, xp: number): any
	return {
		eventType = "StrokeCommitted",
		payload   = {
			strokes   = strokes,
			par       = par,
			scoreTier = "PAR",
			coinDelta = coins,
			xpDelta   = xp,
		},
		timestamp = os.time(),
	}
end

local function holeComplete(): any
	return { eventType = "HoleComplete", payload = {}, timestamp = os.time() }
end

local function matchComplete(): any
	return { eventType = "MatchComplete", payload = {}, timestamp = os.time() }
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — HUDControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local hcmOk, hcmResult = safeRequire(
	script.Parent.Parent.Modules.HUDControllerModule)

if hcmOk then

	local HCM: any = hcmResult

	-- ── Initial state ─────────────────────────────────────────────────────────
	-- HUDController.client.lua already called Init(); singleton is live.

	-- 1 ────────────────────────────────────────────────────────────────────
	check("HCM: module loads successfully", function()
		assert(type(HCM) == "table", "expected table, got " .. type(HCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("HCM: initial GetState is LOBBY", function()
		assert(HCM:GetState() == "LOBBY",
			("expected LOBBY, got %q"):format(HCM:GetState()))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("HCM: initial IsVisible is false (HUD hidden in LOBBY)", function()
		assert(HCM:IsVisible() == false, "expected false in LOBBY state")
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("HCM: initial GetStrokeCount is 0", function()
		assert(HCM:GetStrokeCount() == 0,
			("expected 0, got %d"):format(HCM:GetStrokeCount()))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("HCM: initial GetHoleNumber is 1", function()
		assert(HCM:GetHoleNumber() == 1,
			("expected 1, got %d"):format(HCM:GetHoleNumber()))
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("HCM: initial GetStatusMessage is empty", function()
		assert(HCM:GetStatusMessage() == "",
			("expected empty string, got %q"):format(HCM:GetStatusMessage()))
	end)

	-- ── Envelope validation ───────────────────────────────────────────────────

	-- 7 ────────────────────────────────────────────────────────────────────
	check("HCM: non-table envelope is ignored", function()
		HCM:_onClientEvent("a string")
		HCM:_onClientEvent(123)
		HCM:_onClientEvent(false)
		assert(HCM:GetState() == "LOBBY", "state should still be LOBBY")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("HCM: unknown eventType is ignored", function()
		HCM:_onClientEvent({ eventType = "WeatherChanged", payload = {}, timestamp = 0 })
		assert(HCM:GetState() == "LOBBY", "state should still be LOBBY")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("HCM: StateChanged for other player is ignored", function()
		HCM:_onClientEvent(stateChangedForOther("TEE_OFF"))
		assert(HCM:GetState() == "LOBBY",
			("other player event must not change state; got %q"):format(HCM:GetState()))
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("HCM: StateChanged with nil payload is ignored", function()
		HCM:_onClientEvent({ eventType = "StateChanged", payload = nil, timestamp = 0 })
		assert(HCM:GetState() == "LOBBY", "state should still be LOBBY")
	end)

	-- ── StateChanged → visibility transitions ─────────────────────────────────

	-- 11 ───────────────────────────────────────────────────────────────────
	check("HCM: StateChanged TEE_OFF → state=TEE_OFF", function()
		HCM:_onClientEvent(stateChangedFor("TEE_OFF"))
		assert(HCM:GetState() == "TEE_OFF",
			("expected TEE_OFF, got %q"):format(HCM:GetState()))
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("HCM: IsVisible true in TEE_OFF", function()
		assert(HCM:IsVisible() == true, "HUD must be visible in TEE_OFF")
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("HCM: StateChanged SWING → visible stays true", function()
		HCM:_onClientEvent(stateChangedFor("SWING"))
		assert(HCM:IsVisible() == true, "HUD must stay visible in SWING")
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("HCM: StateChanged BALL_IN_FLIGHT → visible stays true", function()
		HCM:_onClientEvent(stateChangedFor("BALL_IN_FLIGHT"))
		assert(HCM:IsVisible() == true, "HUD must stay visible in BALL_IN_FLIGHT")
	end)

	-- ── StrokeCommitted ───────────────────────────────────────────────────────

	-- 15 ───────────────────────────────────────────────────────────────────
	check("HCM: StrokeCommitted updates stroke count", function()
		HCM:_onClientEvent(strokeCommitted(1, 4, 10, 5))
		assert(HCM:GetStrokeCount() == 1,
			("expected 1, got %d"):format(HCM:GetStrokeCount()))
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("HCM: StrokeCommitted second stroke increments to 2", function()
		HCM:_onClientEvent(strokeCommitted(2, 4, 10, 5))
		assert(HCM:GetStrokeCount() == 2,
			("expected 2, got %d"):format(HCM:GetStrokeCount()))
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("HCM: StrokeCommitted with non-number strokes leaves count unchanged", function()
		local before = HCM:GetStrokeCount()
		HCM:_onClientEvent({
			eventType = "StrokeCommitted",
			payload   = { strokes = "bad", par = 4, coinDelta = 0, xpDelta = 0 },
			timestamp = os.time(),
		})
		assert(HCM:GetStrokeCount() == before,
			"non-number strokes must not change stroke count")
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("HCM: StrokeCommitted with non-table payload is ignored", function()
		local before = HCM:GetStrokeCount()
		HCM:_onClientEvent({ eventType = "StrokeCommitted", payload = nil, timestamp = 0 })
		assert(HCM:GetStrokeCount() == before,
			"nil payload must not change stroke count")
	end)

	-- ── StateChanged SCORE_REVEAL ─────────────────────────────────────────────

	-- 19 ───────────────────────────────────────────────────────────────────
	check("HCM: StateChanged SCORE_REVEAL → state and visible", function()
		HCM:_onClientEvent(stateChangedFor("SCORE_REVEAL"))
		assert(HCM:GetState() == "SCORE_REVEAL",
			("expected SCORE_REVEAL, got %q"):format(HCM:GetState()))
		assert(HCM:IsVisible() == true, "HUD must be visible in SCORE_REVEAL")
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("HCM: GetStatusMessage is 'Nice shot!' in SCORE_REVEAL", function()
		assert(HCM:GetStatusMessage() == "Nice shot!",
			("expected 'Nice shot!', got %q"):format(HCM:GetStatusMessage()))
	end)

	-- ── HoleComplete ──────────────────────────────────────────────────────────
	-- Current state: SCORE_REVEAL, holeNumber=1, strokeCount=2

	-- 21 ───────────────────────────────────────────────────────────────────
	check("HCM: HoleComplete increments hole number", function()
		HCM:_onClientEvent(holeComplete())
		assert(HCM:GetHoleNumber() == 2,
			("expected 2 after HoleComplete, got %d"):format(HCM:GetHoleNumber()))
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("HCM: HoleComplete resets stroke count to 0", function()
		assert(HCM:GetStrokeCount() == 0,
			("expected 0 after HoleComplete, got %d"):format(HCM:GetStrokeCount()))
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("HCM: HoleComplete sets status message to completion text", function()
		assert(HCM:GetStatusMessage() == "Hole 1 complete!",
			("expected 'Hole 1 complete!', got %q"):format(HCM:GetStatusMessage()))
	end)

	-- ── StateChanged LOBBY ────────────────────────────────────────────────────
	-- Transitioning back to LOBBY resets per-round state.

	-- 24 ───────────────────────────────────────────────────────────────────
	check("HCM: StateChanged LOBBY → visible=false", function()
		HCM:_onClientEvent(stateChangedFor("LOBBY"))
		assert(HCM:IsVisible() == false, "HUD must be hidden in LOBBY")
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("HCM: LOBBY transition resets status message", function()
		assert(HCM:GetStatusMessage() == "",
			("expected empty after LOBBY, got %q"):format(HCM:GetStatusMessage()))
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("HCM: LOBBY transition resets hole number to 1", function()
		assert(HCM:GetHoleNumber() == 1,
			("expected 1 after LOBBY, got %d"):format(HCM:GetHoleNumber()))
	end)

	-- ── MatchComplete ─────────────────────────────────────────────────────────

	-- 27 ───────────────────────────────────────────────────────────────────
	check("HCM: MatchComplete forces HUD visible", function()
		HCM:_onClientEvent(matchComplete())
		assert(HCM:IsVisible() == true, "HUD must be visible after MatchComplete")
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("HCM: MatchComplete sets round-end status message", function()
		local msg = HCM:GetStatusMessage()
		assert(type(msg) == "string" and #msg > 0,
			"MatchComplete must set a non-empty status message")
	end)

	-- ── Destroy ───────────────────────────────────────────────────────────────

	-- 29 ───────────────────────────────────────────────────────────────────
	check("HCM: Destroy resets GetState to LOBBY", function()
		-- State is currently LOBBY (set in check 24), but drive to TEE_OFF
		-- first so the reset is observable.
		HCM:_onClientEvent(stateChangedFor("TEE_OFF"))
		assert(HCM:GetState() == "TEE_OFF", "state should be TEE_OFF before Destroy")

		HCM:Destroy()

		assert(HCM:GetState() == "LOBBY",
			("expected LOBBY after Destroy, got %q"):format(HCM:GetState()))
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("HCM: Destroy resets IsVisible to false", function()
		assert(HCM:IsVisible() == false, "expected false after Destroy")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("HCM: Destroy resets GetStrokeCount to 0", function()
		assert(HCM:GetStrokeCount() == 0,
			("expected 0 after Destroy, got %d"):format(HCM:GetStrokeCount()))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("HCM: Destroy resets GetHoleNumber to 1", function()
		assert(HCM:GetHoleNumber() == 1,
			("expected 1 after Destroy, got %d"):format(HCM:GetHoleNumber()))
	end)

	-- Restore the live GameBus connection that Destroy() disconnected,
	-- so HUDController remains active for the rest of the session.
	HCM:Init()

end -- hcmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 9 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
