--!strict
return function()
-- Sprint11ClientTest — LocalScript
-- Client smoke tests for Sprint 11: PowerMeterController, AimController,
-- and ClubController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Each thin runner calls Module:Init() before this script loads, so
-- safeRequire() returns already-initialised singletons (same pattern as
-- Sprints 7–10).  Tests drive each module through its public API and
-- _onClientEvent; no live round or network interaction required.

print("[Sprint11ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local TAG     = "[Sprint11ClientTest]"
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

local MY_ID = Players.LocalPlayer.UserId

local function stateEnvelope(state: string): any
	return {
		eventType = "StateChanged",
		payload   = { playerId = MY_ID, state = state },
		timestamp = os.time(),
	}
end

local function stateEnvelopeOther(state: string): any
	return {
		eventType = "StateChanged",
		payload   = { playerId = MY_ID + 99999, state = state },
		timestamp = os.time(),
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — PowerMeterControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local pmOk, pmResult = safeRequire(
	script.Parent.Parent.Modules.PowerMeterControllerModule)

if pmOk then

	local PMC: any = pmResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("PMC: module loads successfully", function()
		assert(type(PMC) == "table", "expected table, got " .. type(PMC))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("PMC: initial GetPower is 0", function()
		assert(PMC:GetPower() == 0,
			("expected 0, got %s"):format(tostring(PMC:GetPower())))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("PMC: initial IsCharging is false", function()
		assert(PMC:IsCharging() == false, "expected not charging initially")
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("PMC: initial IsVisible is false (LOBBY state)", function()
		assert(PMC:IsVisible() == false, "power meter must start hidden in LOBBY")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("PMC: SetPower(0.75) updates GetPower", function()
		PMC:SetPower(0.75)
		assert(PMC:GetPower() == 0.75,
			("expected 0.75, got %s"):format(tostring(PMC:GetPower())))
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("PMC: SetPower > 0 sets IsCharging true", function()
		assert(PMC:IsCharging() == true, "expected IsCharging true when power > 0")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("PMC: SetPower clamps above 1.0", function()
		PMC:SetPower(1.5)
		assert(PMC:GetPower() == 1.0,
			("expected clamped 1.0, got %s"):format(tostring(PMC:GetPower())))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("PMC: SetPower clamps below 0.0", function()
		PMC:SetPower(-0.5)
		assert(PMC:GetPower() == 0.0,
			("expected clamped 0.0, got %s"):format(tostring(PMC:GetPower())))
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("PMC: ResetPower sets power to 0 and IsCharging to false", function()
		PMC:SetPower(0.6)
		PMC:ResetPower()
		assert(PMC:GetPower() == 0,
			("expected 0 after ResetPower, got %s"):format(tostring(PMC:GetPower())))
		assert(PMC:IsCharging() == false, "expected IsCharging false after ResetPower")
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("PMC: StateChanged SWING sets IsVisible true", function()
		PMC:_onClientEvent(stateEnvelope("SWING"))
		assert(PMC:IsVisible() == true, "expected visible in SWING state")
	end)

	-- 10b ─────────────────────────────────────────────────────────────────
	check("PMC: StateChanged other-player SWING is ignored", function()
		PMC:_onClientEvent(stateEnvelopeOther("LOBBY"))
		assert(PMC:IsVisible() == true, "other-player event must not hide power meter")
	end)

	-- 10c ─────────────────────────────────────────────────────────────────
	check("PMC: Leaving SWING auto-resets power", function()
		PMC:SetPower(0.8)
		PMC:_onClientEvent(stateEnvelope("SCORE_REVEAL"))
		assert(PMC:IsVisible() == false, "expected hidden in SCORE_REVEAL")
		assert(PMC:GetPower() == 0, "power must auto-reset on SWING exit")
		assert(PMC:IsCharging() == false, "charging must clear on SWING exit")
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("PMC: Destroy resets all state", function()
		PMC:_onClientEvent(stateEnvelope("SWING"))
		PMC:SetPower(0.5)
		PMC:Destroy()
		assert(PMC:GetPower() == 0,       "expected 0 after Destroy")
		assert(PMC:IsCharging() == false,  "expected not charging after Destroy")
		assert(PMC:IsVisible() == false,   "expected hidden after Destroy")
	end)

	-- Restore the live GameBus connection
	PMC:Init()

	-- 11b ─────────────────────────────────────────────────────────────────
	check("PMC: SetPower and ResetPower work after Init restore", function()
		PMC:SetPower(0.4)
		assert(PMC:GetPower() == 0.4,   "should be 0.4 after restore")
		PMC:ResetPower()
		assert(PMC:GetPower() == 0,     "should be 0 after ResetPower")
	end)

end -- pmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — AimControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local acOk, acResult = safeRequire(
	script.Parent.Parent.Modules.AimControllerModule)

if acOk then

	local ACM: any = acResult

	-- 12 ───────────────────────────────────────────────────────────────────
	check("ACM: module loads successfully", function()
		assert(type(ACM) == "table", "expected table, got " .. type(ACM))
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("ACM: initial GetAimDirection is forward (0,0,-1)", function()
		local d = ACM:GetAimDirection()
		assert(typeof(d) == "Vector3", "expected Vector3")
		assert(math.abs(d.X) < 0.001 and math.abs(d.Z + 1) < 0.001,
			("expected (0,0,-1), got %s"):format(tostring(d)))
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("ACM: initial GetAimAngle is 0", function()
		assert(ACM:GetAimAngle() == 0,
			("expected 0, got %s"):format(tostring(ACM:GetAimAngle())))
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("ACM: initial IsVisible is false (LOBBY state)", function()
		assert(ACM:IsVisible() == false, "aim indicator must start hidden in LOBBY")
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("ACM: SetAimDirection(1,0,0) sets angle to 90", function()
		ACM:SetAimDirection(Vector3.new(1, 0, 0))
		assert(math.abs(ACM:GetAimAngle() - 90) < 0.1,
			("expected 90°, got %s"):format(tostring(ACM:GetAimAngle())))
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("ACM: GetAimDirection returns a unit vector", function()
		local d = ACM:GetAimDirection()
		assert(math.abs(d.Magnitude - 1) < 0.001,
			("expected unit vector, magnitude = %s"):format(tostring(d.Magnitude)))
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("ACM: RotateLeft decrements angle by 5", function()
		ACM:ResetAim()   -- back to 0°
		ACM:RotateLeft()
		assert(math.abs(ACM:GetAimAngle() - 355) < 0.1,
			("expected 355° after RotateLeft from 0, got %s"):format(
				tostring(ACM:GetAimAngle())))
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("ACM: RotateRight increments angle by 5", function()
		ACM:ResetAim()   -- back to 0°
		ACM:RotateRight()
		assert(math.abs(ACM:GetAimAngle() - 5) < 0.1,
			("expected 5° after RotateRight from 0, got %s"):format(
				tostring(ACM:GetAimAngle())))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("ACM: ResetAim restores default direction", function()
		ACM:SetAimDirection(Vector3.new(1, 0, 0))
		ACM:ResetAim()
		local d = ACM:GetAimDirection()
		assert(math.abs(d.Z + 1) < 0.001,
			("expected Z=-1 after ResetAim, got %s"):format(tostring(d)))
		assert(ACM:GetAimAngle() == 0, "expected 0° after ResetAim")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("ACM: StateChanged TEE_OFF sets IsVisible true", function()
		ACM:_onClientEvent(stateEnvelope("TEE_OFF"))
		assert(ACM:IsVisible() == true, "expected visible in TEE_OFF")
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("ACM: StateChanged BALL_IN_FLIGHT hides aim indicator", function()
		ACM:_onClientEvent(stateEnvelope("BALL_IN_FLIGHT"))
		assert(ACM:IsVisible() == false, "expected hidden in BALL_IN_FLIGHT")
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("ACM: Destroy resets all state", function()
		ACM:_onClientEvent(stateEnvelope("TEE_OFF"))
		ACM:SetAimDirection(Vector3.new(1, 0, 0))
		ACM:Destroy()
		local d = ACM:GetAimDirection()
		assert(math.abs(d.Z + 1) < 0.001, "expected default direction after Destroy")
		assert(ACM:GetAimAngle() == 0,     "expected 0° after Destroy")
		assert(ACM:IsVisible() == false,   "expected hidden after Destroy")
	end)

	-- Restore the live GameBus connection
	ACM:Init()

	-- 24 ───────────────────────────────────────────────────────────────────
	check("ACM: RotateRight and RotateLeft work after Init restore", function()
		ACM:RotateRight()
		assert(math.abs(ACM:GetAimAngle() - 5) < 0.1, "should be 5° after RotateRight")
		ACM:RotateLeft()
		assert(ACM:GetAimAngle() == 0,                 "should be back to 0°")
	end)

end -- acOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — ClubControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local ccOk, ccResult = safeRequire(
	script.Parent.Parent.Modules.ClubControllerModule)

if ccOk then

	local CCM: any = ccResult

	-- 25 ───────────────────────────────────────────────────────────────────
	check("CCM: module loads successfully", function()
		assert(type(CCM) == "table", "expected table, got " .. type(CCM))
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("CCM: initial GetCurrentClub is 'Driver'", function()
		assert(CCM:GetCurrentClub() == "Driver",
			("expected 'Driver', got %q"):format(CCM:GetCurrentClub()))
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("CCM: GetAvailableClubs returns 5 clubs", function()
		local clubs = CCM:GetAvailableClubs()
		assert(type(clubs) == "table", "expected table from GetAvailableClubs")
		assert(#clubs == 5, ("expected 5 clubs, got %d"):format(#clubs))
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("CCM: GetAvailableClubs includes all expected clubs", function()
		local clubs = CCM:GetAvailableClubs()
		local set: { [string]: boolean } = {}
		for _, c in ipairs(clubs) do set[c] = true end
		assert(set["Driver"] and set["Wood"] and set["Iron"]
			and set["Wedge"] and set["Putter"],
			"missing expected club in roster")
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("CCM: NextClub advances to 'Wood'", function()
		CCM:NextClub()
		assert(CCM:GetCurrentClub() == "Wood",
			("expected 'Wood', got %q"):format(CCM:GetCurrentClub()))
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("CCM: PreviousClub returns to 'Driver'", function()
		CCM:PreviousClub()
		assert(CCM:GetCurrentClub() == "Driver",
			("expected 'Driver', got %q"):format(CCM:GetCurrentClub()))
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("CCM: SetClub('Putter') selects Putter", function()
		CCM:SetClub("Putter")
		assert(CCM:GetCurrentClub() == "Putter",
			("expected 'Putter', got %q"):format(CCM:GetCurrentClub()))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("CCM: SetClub with invalid name is rejected", function()
		CCM:SetClub("MagicStick")
		assert(CCM:GetCurrentClub() == "Putter",
			("expected 'Putter' unchanged after invalid SetClub, got %q"):format(
				CCM:GetCurrentClub()))
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("CCM: NextClub wraps from Putter to Driver", function()
		-- Current: Putter (last in list)
		CCM:NextClub()
		assert(CCM:GetCurrentClub() == "Driver",
			("expected wrap to 'Driver', got %q"):format(CCM:GetCurrentClub()))
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("CCM: PreviousClub wraps from Driver to Putter", function()
		-- Current: Driver (first in list)
		CCM:PreviousClub()
		assert(CCM:GetCurrentClub() == "Putter",
			("expected wrap to 'Putter', got %q"):format(CCM:GetCurrentClub()))
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("CCM: Destroy resets to Driver", function()
		CCM:SetClub("Iron")
		assert(CCM:GetCurrentClub() == "Iron", "should be Iron before Destroy")
		CCM:Destroy()
		assert(CCM:GetCurrentClub() == "Driver",
			("expected 'Driver' after Destroy, got %q"):format(CCM:GetCurrentClub()))
	end)

	-- Restore the thin runner state
	CCM:Init()

	-- 36 ───────────────────────────────────────────────────────────────────
	check("CCM: SetClub and NextClub work after Init restore", function()
		assert(CCM:GetCurrentClub() == "Driver", "should reset to Driver on re-Init")
		CCM:SetClub("Iron")
		assert(CCM:GetCurrentClub() == "Iron", "SetClub should work after restore")
		CCM:NextClub()
		assert(CCM:GetCurrentClub() == "Wedge", "NextClub after Iron should be Wedge")
	end)

end -- ccOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 11 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
end
