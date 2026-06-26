--!strict
-- Sprint6ClientTest — TEMPORARY client smoke test for Sprint 6 controllers.
-- DELETE this file after Sprint 6 sign-off.
--
-- Covers:
--   InputControllerModule  (14 checks) — state tracking, HoleReady debounce
--   SwingControllerModule  (16 checks) — state tracking, charge/release, debounce
--
-- Each LocalScript runs in its own Lua environment, so requiring either module
-- here gives a FRESH instance isolated from the production runner instances.
-- Init() is deliberately not called, so no live GameBus / UserInputService
-- connections are made. Handler methods are called directly to drive state.
--
-- Note: _fireHoleReady() and _fireSwingIntent() both call GameBus:FireServer().
-- When no active server round exists, EventBusHandler's pcall will catch the
-- resulting error. You may see a server-side warning — harmless.

print("[Sprint6ClientTest] Script started")

local Players = game:GetService("Players")
local LocalPlayer: Player = Players.LocalPlayer

local TAG = "[Sprint6ClientTest]"

-- ── check helper ─────────────────────────────────────────────────────────────

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

-- ── Require helpers ───────────────────────────────────────────────────────────

local function safeRequire(path: Instance): (boolean, any)
	return pcall(function()
		return require(path :: ModuleScript)
	end)
end

-- ── Shared fake-input factory ─────────────────────────────────────────────────

local function fakeInput(keyCode: EnumItem, inputType: EnumItem): any
	return { KeyCode = keyCode, UserInputType = inputType }
end

local SPACE   = fakeInput(Enum.KeyCode.Space,   Enum.UserInputType.Keyboard)
local RETURN  = fakeInput(Enum.KeyCode.Return,  Enum.UserInputType.Keyboard)
local LMB     = fakeInput(Enum.KeyCode.Unknown, Enum.UserInputType.MouseButton1)

local function stateChangedFor(state: string): any
	return {
		eventType = "StateChanged",
		payload   = { playerId = LocalPlayer.UserId, state = state },
		timestamp = os.time(),
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — InputControllerModule (14 checks)
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ── InputControllerModule ──────────────────────────────────")

local icmOk, icmResult = safeRequire(
	script.Parent.Parent.Modules.InputControllerModule)

if not icmOk then
	warn(TAG .. " FATAL: InputControllerModule failed to load — " .. tostring(icmResult))
else

local ICM: any = icmResult
print(TAG .. " InputControllerModule loaded OK")

-- Initial state
check("ICM: initial state = LOBBY", function()
	assert(ICM:GetState() == "LOBBY",
		("expected LOBBY, got %q"):format(ICM:GetState()))
end)

check("ICM: initial IsHoleReadyFired = false", function()
	assert(ICM:IsHoleReadyFired() == false, "expected false")
end)

-- Input blocked before TEE_OFF
check("ICM: Space in LOBBY — HoleReady NOT fired", function()
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == false, "flag must stay false in LOBBY")
end)

-- StateChanged routing
check("ICM: StateChanged(TEE_OFF) — state updates", function()
	ICM:_onClientEvent(stateChangedFor("TEE_OFF"))
	assert(ICM:GetState() == "TEE_OFF",
		("expected TEE_OFF, got %q"):format(ICM:GetState()))
end)

check("ICM: StateChanged(TEE_OFF) — debounce flag reset", function()
	assert(ICM:IsHoleReadyFired() == false, "expected false after TEE_OFF re-arm")
end)

check("ICM: wrong playerId is ignored", function()
	ICM:_onClientEvent({
		eventType = "StateChanged",
		payload   = { playerId = -1, state = "ROUND_COMPLETE" },
		timestamp = os.time(),
	})
	assert(ICM:GetState() == "TEE_OFF", "state must not change for another player")
end)

check("ICM: unknown eventType is ignored", function()
	ICM:_onClientEvent({
		eventType = "BallResolved",
		payload   = { playerId = LocalPlayer.UserId, state = "LOBBY" },
		timestamp = os.time(),
	})
	assert(ICM:GetState() == "TEE_OFF", "non-StateChanged must not change state")
end)

-- Input blocked by gameProcessed
check("ICM: gameProcessed=true in TEE_OFF — HoleReady NOT fired", function()
	ICM:_onInputBegan(SPACE, true)
	assert(ICM:IsHoleReadyFired() == false, "UI-consumed input must be ignored")
end)

-- HoleReady firing
check("ICM: Space in TEE_OFF — HoleReady fired", function()
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == true, "expected flag = true after Space")
end)

check("ICM: debounce — second Space does not re-fire", function()
	local before = ICM:IsHoleReadyFired()
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == before, "flag must not change on duplicate")
end)

ICM:_onClientEvent(stateChangedFor("TEE_OFF"))   -- re-arm
check("ICM: Return in TEE_OFF — HoleReady fired", function()
	ICM:_onInputBegan(RETURN, false)
	assert(ICM:IsHoleReadyFired() == true, "expected flag = true after Return")
end)

ICM:_onClientEvent(stateChangedFor("TEE_OFF"))   -- re-arm
check("ICM: MouseButton1 in TEE_OFF — HoleReady fired", function()
	ICM:_onInputBegan(LMB, false)
	assert(ICM:IsHoleReadyFired() == true, "expected flag = true after MouseButton1")
end)

-- Non-TEE_OFF blocks input
check("ICM: Space in SWING — HoleReady NOT fired", function()
	ICM:_onClientEvent(stateChangedFor("TEE_OFF"))      -- resets flag
	ICM:_onClientEvent(stateChangedFor("SWING"))        -- move to SWING, flag still false
	assert(ICM:IsHoleReadyFired() == false, "flag should be false before this check")
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == false, "state guard must block input in SWING")
end)

-- Destroy
check("ICM: Destroy resets state and flag", function()
	ICM:Destroy()
	assert(ICM:GetState() == "LOBBY",
		("expected LOBBY after Destroy, got %q"):format(ICM:GetState()))
	assert(ICM:IsHoleReadyFired() == false, "expected false after Destroy")
end)

end -- icmOk

-- ════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — SwingControllerModule (16 checks)
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ── SwingControllerModule ──────────────────────────────────")

local scmOk, scmResult = safeRequire(
	script.Parent.Parent.Modules.SwingControllerModule)

if not scmOk then
	warn(TAG .. " FATAL: SwingControllerModule failed to load — " .. tostring(scmResult))
else

local SCM: any = scmResult
print(TAG .. " SwingControllerModule loaded OK")

-- Initial state
check("SCM: initial state = LOBBY", function()
	assert(SCM:GetState() == "LOBBY",
		("expected LOBBY, got %q"):format(SCM:GetState()))
end)

check("SCM: initial IsSwingFired = false", function()
	assert(SCM:IsSwingFired() == false, "expected false")
end)

check("SCM: initial IsCharging = false", function()
	assert(SCM:IsCharging() == false, "expected false")
end)

-- State guard: charging must not start outside SWING
check("SCM: Space in LOBBY — charging NOT started", function()
	SCM:_onInputBegan(SPACE, false)
	assert(SCM:IsCharging() == false, "state guard must block charge in LOBBY")
end)

-- StateChanged(SWING) arms the controller
check("SCM: StateChanged(SWING) — state updates to SWING", function()
	SCM:_onClientEvent(stateChangedFor("SWING"))
	assert(SCM:GetState() == "SWING",
		("expected SWING, got %q"):format(SCM:GetState()))
end)

check("SCM: StateChanged(SWING) — IsSwingFired reset to false", function()
	assert(SCM:IsSwingFired() == false, "expected false after SWING re-arm")
end)

check("SCM: StateChanged(SWING) — IsCharging reset to false", function()
	assert(SCM:IsCharging() == false, "expected false after SWING re-arm")
end)

-- gameProcessed guard
check("SCM: gameProcessed=true in SWING — charging NOT started", function()
	SCM:_onInputBegan(SPACE, true)
	assert(SCM:IsCharging() == false, "UI-consumed input must not start charge")
end)

-- Charging starts on valid press
check("SCM: Space in SWING — charging starts", function()
	SCM:_onInputBegan(SPACE, false)
	assert(SCM:IsCharging() == true, "expected IsCharging = true after Space")
end)

-- Duplicate press while charging is ignored
check("SCM: Space again while charging — ignored", function()
	SCM:_onInputBegan(SPACE, false)   -- second press while already charging
	assert(SCM:IsCharging() == true, "must still be charging (not toggled off)")
	assert(SCM:IsSwingFired() == false, "must not have fired yet")
end)

-- Release fires SwingIntent
check("SCM: InputEnded(Space) — IsSwingFired=true, IsCharging=false", function()
	SCM:_onInputEnded(SPACE)
	assert(SCM:IsSwingFired() == true,  "expected SwingFired after release")
	assert(SCM:IsCharging()   == false, "expected charging=false after fire")
end)

-- Debounce prevents new charge after fire
check("SCM: Space after fire — debounce blocks new charge", function()
	SCM:_onInputBegan(SPACE, false)
	assert(SCM:IsCharging() == false, "debounce must block re-charge after fire")
end)

-- Re-arming via second SWING state
check("SCM: StateChanged(SWING) re-arms — IsSwingFired reset", function()
	SCM:_onClientEvent(stateChangedFor("SWING"))
	assert(SCM:IsSwingFired() == false, "expected false after re-arm")
	assert(SCM:IsCharging()   == false, "expected false after re-arm")
end)

-- MouseButton1 path
check("SCM: MouseButton1 in SWING — charging starts", function()
	SCM:_onInputBegan(LMB, false)
	assert(SCM:IsCharging() == true, "expected IsCharging after MouseButton1")
end)

check("SCM: InputEnded(MouseButton1) — IsSwingFired=true", function()
	SCM:_onInputEnded(LMB)
	assert(SCM:IsSwingFired() == true,  "expected SwingFired after MouseButton1 release")
	assert(SCM:IsCharging()   == false, "expected charging=false after fire")
end)

-- Non-SWING state blocks new charge after re-arm
check("SCM: Space in BALL_IN_FLIGHT — charging NOT started", function()
	SCM:_onClientEvent(stateChangedFor("SWING"))          -- re-arm
	SCM:_onClientEvent(stateChangedFor("BALL_IN_FLIGHT")) -- leave SWING
	assert(SCM:IsSwingFired() == false, "flag should be false before check")
	SCM:_onInputBegan(SPACE, false)
	assert(SCM:IsCharging() == false, "state guard must block charge outside SWING")
end)

-- Destroy
check("SCM: Destroy resets state, flags", function()
	SCM:Destroy()
	assert(SCM:GetState()     == "LOBBY", "expected LOBBY after Destroy")
	assert(SCM:IsSwingFired() == false,   "expected false after Destroy")
	assert(SCM:IsCharging()   == false,   "expected false after Destroy")
end)

end -- scmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 6 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
