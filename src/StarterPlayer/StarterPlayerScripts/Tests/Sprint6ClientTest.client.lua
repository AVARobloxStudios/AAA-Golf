--!strict
-- Sprint6ClientTest — TEMPORARY client smoke test for InputController (Sprint 6)
-- DELETE this file after Sprint 6 sign-off.

-- !! First executable line — proves the LocalScript is running at all.
print("[Sprint6ClientTest] Script started")

local Players = game:GetService("Players")
local LocalPlayer: Player = Players.LocalPlayer

local TAG = "[Sprint6ClientTest]"

-- Wrap require so a crash inside InputControllerModule surfaces as a named
-- error here instead of silently killing the script before any output.
local requireOk, M = pcall(function()
	return require(script.Parent.Parent.Modules.InputControllerModule)
end)
if not requireOk then
	warn(TAG .. " FATAL: InputControllerModule failed to load — " .. tostring(M))
	return
end

print(TAG .. " InputControllerModule loaded OK")

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

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function stateChangedEnvelope(state: string): any
	return {
		eventType = "StateChanged",
		payload   = { playerId = LocalPlayer.UserId, state = state },
		timestamp = os.time(),
	}
end

local function fakeInput(keyCode: EnumItem, inputType: EnumItem): any
	return { KeyCode = keyCode, UserInputType = inputType }
end

local SPACE  = fakeInput(Enum.KeyCode.Space,  Enum.UserInputType.Keyboard)
local RETURN = fakeInput(Enum.KeyCode.Return, Enum.UserInputType.Keyboard)
local LMB    = fakeInput(Enum.KeyCode.Unknown, Enum.UserInputType.MouseButton1)

-- Cast M to any so strict mode allows method calls on a pcall-returned value.
local ICM: any = M

-- ── Initial state ─────────────────────────────────────────────────────────────

check("initial state = LOBBY", function()
	assert(ICM:GetState() == "LOBBY",
		("expected LOBBY, got %q"):format(ICM:GetState()))
end)

check("initial IsHoleReadyFired = false", function()
	assert(ICM:IsHoleReadyFired() == false, "expected false")
end)

-- ── Input blocked before TEE_OFF ─────────────────────────────────────────────

check("Space in LOBBY: HoleReady NOT fired", function()
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == false, "flag must stay false in LOBBY")
end)

-- ── StateChanged routing ──────────────────────────────────────────────────────

check("StateChanged(TEE_OFF): state updates to TEE_OFF", function()
	ICM:_onClientEvent(stateChangedEnvelope("TEE_OFF"))
	assert(ICM:GetState() == "TEE_OFF",
		("expected TEE_OFF, got %q"):format(ICM:GetState()))
end)

check("StateChanged(TEE_OFF): debounce flag reset to false", function()
	assert(ICM:IsHoleReadyFired() == false, "expected false after TEE_OFF re-arm")
end)

check("StateChanged: wrong playerId is ignored", function()
	ICM:_onClientEvent({
		eventType = "StateChanged",
		payload   = { playerId = -1, state = "ROUND_COMPLETE" },
		timestamp = os.time(),
	})
	assert(ICM:GetState() == "TEE_OFF",
		"state must not change for a different player's event")
end)

check("StateChanged: unknown eventType is ignored", function()
	ICM:_onClientEvent({
		eventType = "BallResolved",
		payload   = { playerId = LocalPlayer.UserId, state = "LOBBY" },
		timestamp = os.time(),
	})
	assert(ICM:GetState() == "TEE_OFF", "non-StateChanged event must not change state")
end)

-- ── Input blocked by gameProcessed ───────────────────────────────────────────

check("gameProcessed=true in TEE_OFF: HoleReady NOT fired", function()
	ICM:_onInputBegan(SPACE, true)
	assert(ICM:IsHoleReadyFired() == false, "UI-consumed input must be ignored")
end)

-- ── HoleReady firing ─────────────────────────────────────────────────────────

check("Space in TEE_OFF: HoleReady fired", function()
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == true, "expected flag = true after Space")
end)

check("debounce: second Space does not re-fire (flag stays true)", function()
	local before = ICM:IsHoleReadyFired()   -- true from previous check
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == before, "flag must not change on duplicate fire")
end)

-- Re-arm debounce for next two checks.
ICM:_onClientEvent(stateChangedEnvelope("TEE_OFF"))

check("Return in TEE_OFF: HoleReady fired", function()
	ICM:_onInputBegan(RETURN, false)
	assert(ICM:IsHoleReadyFired() == true, "expected flag = true after Return")
end)

ICM:_onClientEvent(stateChangedEnvelope("TEE_OFF"))

check("MouseButton1 in TEE_OFF: HoleReady fired", function()
	ICM:_onInputBegan(LMB, false)
	assert(ICM:IsHoleReadyFired() == true, "expected flag = true after MouseButton1")
end)

-- ── Non-TEE_OFF state blocks input ───────────────────────────────────────────

check("Space in SWING: HoleReady NOT fired", function()
	-- Re-arm cleanly: send TEE_OFF (resets flag) then SWING.
	ICM:_onClientEvent(stateChangedEnvelope("TEE_OFF"))
	ICM:_onClientEvent(stateChangedEnvelope("SWING"))
	assert(ICM:IsHoleReadyFired() == false, "flag should be false before test")
	ICM:_onInputBegan(SPACE, false)
	assert(ICM:IsHoleReadyFired() == false, "state guard must block input in SWING")
end)

-- ── Destroy resets everything ─────────────────────────────────────────────────

check("Destroy: state resets to LOBBY and flag resets to false", function()
	ICM:Destroy()
	assert(ICM:GetState() == "LOBBY",
		("expected LOBBY after Destroy, got %q"):format(ICM:GetState()))
	assert(ICM:IsHoleReadyFired() == false, "expected false after Destroy")
end)

-- ── Summary ──────────────────────────────────────────────────────────────────

print(TAG .. " ─────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 6 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
