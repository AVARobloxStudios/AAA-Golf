--!strict
-- Sprint35ClientTest — Sprint 34.5: Swing Engine Refactor & Consolidation
--
-- Covers (22 checks):
--   SwingEngineControllerModule (15 checks) — lifecycle, callbacks, state isolation,
--     smoothed SwingResult, swingEnergy field, server-transport isolation.
--   PlayableHoleControllerModule integration (4 checks) — SECM as back-end,
--     Sprint 33 Shoot() compat, idempotent Destroy.
--   Old Sprint 6 SwingControllerModule gated (3 checks) — module still loads,
--     LOBBY guard intact, no competing input.

return function()

print("[Sprint35ClientTest] Sprint 34.5 — Swing Engine Refactor & Consolidation")

local TAG = "[Sprint35ClientTest]"

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

local function safeRequire(path: Instance): (boolean, any)
	return pcall(function() return require(path :: ModuleScript) end)
end

-- ── Module paths ──────────────────────────────────────────────────────────────

local Modules = script.Parent.Parent.Modules

local secmOk, secmResult = safeRequire(Modules.SwingEngineControllerModule)
local phcmOk, phcmResult = safeRequire(Modules.PlayableHoleControllerModule)
local scmOk,  scmResult  = safeRequire(Modules.SwingControllerModule)
local sicmOk, sicmResult = safeRequire(Modules.SwingInputControllerModule)

-- ════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — SwingEngineControllerModule (15 checks)
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ── SwingEngineControllerModule ─────────────────────────────")

check("SECM: module loads", function()
	assert(secmOk, tostring(secmResult))
end)

if not secmOk then
	warn(TAG .. " FATAL: SECM failed to load — skipping SECM section")
else

local SECM: any = secmResult
local SICM: any = if sicmOk then sicmResult else nil

-- Isolation: tear down PHCM (which may have been initialized by a prior test)
if phcmOk then (phcmResult :: any):Destroy() end

check("SECM: all public methods exist", function()
	assert(type(SECM.Init)                    == "function", "Init missing")
	assert(type(SECM.Update)                  == "function", "Update missing")
	assert(type(SECM.Destroy)                 == "function", "Destroy missing")
	assert(type(SECM.SetEnabled)              == "function", "SetEnabled missing")
	assert(type(SECM.SetAimDirectionProvider) == "function", "SetAimDirectionProvider missing")
	assert(type(SECM.SetSwingResultCallback)  == "function", "SetSwingResultCallback missing")
	assert(type(SECM.Start)                   == "function", "Start missing")
	assert(type(SECM.Stop)                    == "function", "Stop missing")
	assert(type(SECM.Reset)                   == "function", "Reset missing")
	assert(type(SECM.GetState)                == "function", "GetState missing")
	assert(type(SECM.ProcessSwing)            == "function", "ProcessSwing missing")
end)

SECM:Init()

check("SECM: Init — GetState returns enabled=false, swingPhase='Idle'", function()
	local s = SECM:GetState()
	assert(type(s) == "table",          "GetState must return a table")
	assert(s.enabled == false,          ("expected enabled=false, got %s"):format(tostring(s.enabled)))
	assert(s.swingPhase == "Idle",      ("expected Idle, got %q"):format(tostring(s.swingPhase)))
	assert(type(s.lastContact) == "string", "lastContact must be a string")
	assert(type(s.lastShape)   == "string", "lastShape must be a string")
end)

check("SECM: SetEnabled(true/false) toggles enabled in GetState", function()
	SECM:SetEnabled(true)
	assert(SECM:GetState().enabled == true,  "expected true after SetEnabled(true)")
	SECM:SetEnabled(false)
	assert(SECM:GetState().enabled == false, "expected false after SetEnabled(false)")
end)

check("SECM: SetAimDirectionProvider — no crash", function()
	SECM:SetAimDirectionProvider(function(): Vector3
		return Vector3.new(0, 0, -1)
	end)
end)

check("SECM: SetSwingResultCallback + ProcessSwing — callback fires for valid swing", function()
	assert(SICM ~= nil, "SICM required for this check")

	-- Start the engine so SICM accepts input — matches production: StartPlayableHole → SECM:Start()
	SECM:Start()

	-- Drive a complete swing through SICM directly (SECM:Init initialized SICM)
	SICM:BeginInput(Vector2.new(400, 300))
	SICM:UpdateInput(Vector2.new(400, 355))  -- 55 px down → Backswing
	SICM:UpdateInput(Vector2.new(400, 338))  -- 17 px back → Downswing
	SICM:EndInput(Vector2.new(400, 255))     -- release above start → valid follow-through

	local callbackFired = false
	local receivedResult: any = nil
	SECM:SetSwingResultCallback(function(sr: any)
		callbackFired  = true
		receivedResult = sr
	end)

	SECM:ProcessSwing()

	assert(callbackFired == true,                  "callback must fire for a valid swing")
	assert(type(receivedResult) == "table",        "callback must receive a SwingResult table")
	assert(typeof(receivedResult.launchDirection) == "Vector3",
		"SwingResult must include launchDirection as Vector3")
	assert(type(receivedResult.swingEnergy) == "number",
		"SwingResult must include swingEnergy (Sprint 34.5 addition)")
	assert(receivedResult.swingEnergy >= 0 and receivedResult.swingEnergy <= 1,
		("swingEnergy must be in [0,1], got %f"):format(receivedResult.swingEnergy))
end)

check("SECM: GetState returns copy — external mutation does not affect state", function()
	local s1 = SECM:GetState()
	local original = s1.enabled
	s1.enabled = not s1.enabled  -- mutate the copy
	local s2 = SECM:GetState()
	assert(s2.enabled == original,
		"SECM internal state must not be affected by mutating GetState() copy")
end)

check("SECM: Start — enabled=true in GetState", function()
	SECM:Start()
	assert(SECM:GetState().enabled == true, "expected enabled=true after Start()")
end)

check("SECM: Stop — enabled=false, swingPhase is a string", function()
	SECM:Stop()
	local s = SECM:GetState()
	assert(s.enabled == false,              "expected enabled=false after Stop()")
	assert(type(s.swingPhase) == "string",  "swingPhase must remain a string after Stop()")
end)

check("SECM: Reset — no crash", function()
	SECM:Start()
	SECM:Reset()
	local s = SECM:GetState()
	assert(type(s) == "table", "GetState must not error after Reset()")
end)

check("SECM: ProcessSwing with no pending raw data — silent no-op, no crash", function()
	-- After Reset(), SICM has no raw data; ProcessSwing must silently do nothing
	SECM:ProcessSwing()
end)

check("SECM: ProcessSwing cancelled swing — callback NOT fired", function()
	assert(SICM ~= nil, "SICM required for this check")

	-- Cancel: release within 28 px of start while still in Backswing
	SICM:BeginInput(Vector2.new(400, 300))
	SICM:UpdateInput(Vector2.new(400, 355))  -- Backswing
	SICM:EndInput(Vector2.new(400, 310))     -- 10 px from start → cancelled

	local callbackFired = false
	SECM:SetSwingResultCallback(function(_: any) callbackFired = true end)
	SECM:ProcessSwing()
	assert(callbackFired == false, "cancelled swing must not fire callback")
end)

check("SECM: does NOT directly fire server remotes (callback-only architecture)", function()
	-- ProcessSwing must not error even without an active DeveloperAction remote,
	-- proving SECM has no direct dependency on server transport.
	assert(SICM ~= nil, "SICM required for this check")
	SICM:BeginInput(Vector2.new(400, 300))
	SICM:UpdateInput(Vector2.new(400, 355))
	SICM:UpdateInput(Vector2.new(400, 338))
	SICM:EndInput(Vector2.new(400, 255))

	local callbackReceived = false
	SECM:SetSwingResultCallback(function(_: any) callbackReceived = true end)

	-- If SECM tried to FireServer here, it would error (no RemoteEvent in test env).
	-- Success = no error thrown.
	SECM:ProcessSwing()
	-- callback may or may not fire (depends on result validity); the key is: no error.
	local _ = callbackReceived
end)

check("SECM: Update(0) — no crash", function()
	SECM:Update(0)
end)

check("SECM: Destroy + re-Init — lifecycle resets cleanly", function()
	SECM:Destroy()
	-- GetState after Destroy must not crash (returns module-level defaults)
	SECM:Init()
	local s = SECM:GetState()
	assert(s.enabled == false,    "expected enabled=false after re-Init")
	assert(s.swingPhase == "Idle", "expected Idle after re-Init")
end)

end -- secmOk

-- ════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — PlayableHoleControllerModule integration (4 checks)
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ── PlayableHoleControllerModule integration ─────────────────")

check("PHCM: module still loads after Sprint 34.5", function()
	assert(phcmOk, tostring(phcmResult))
end)

if not phcmOk then
	warn(TAG .. " FATAL: PHCM failed to load — skipping integration section")
else

local PHCM: any = phcmResult

PHCM:Destroy()
PHCM:Init()

check("PHCM: Init wires SwingEngine — GetState returns valid table", function()
	local s = PHCM:GetState()
	assert(type(s) == "table",                     "GetState must return a table")
	assert(s.status == "Idle",                     ("expected Idle, got %q"):format(tostring(s.status)))
	assert(type(s.power) == "number" and s.power > 0,
		("expected power > 0, got %s"):format(tostring(s.power)))
	assert(typeof(s.aimDirection) == "Vector3",    "aimDirection must be a Vector3")
end)

check("PHCM: Sprint 33 compat — Shoot() sets lastInput='Shoot'", function()
	pcall(function() PHCM:Shoot() end)
	local s = PHCM:GetState()
	assert(s.lastInput == "Shoot",
		("expected lastInput='Shoot', got %q"):format(tostring(s.lastInput)))
end)

check("PHCM: Destroy cleans up SwingEngine — no crash", function()
	PHCM:Destroy()
end)

check("PHCM: Destroy is idempotent — second Destroy does not crash", function()
	PHCM:Destroy()
end)

end -- phcmOk

-- ════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — Old Sprint 6 path gated (3 checks)
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ── Old Sprint 6 SwingControllerModule (gated) ──────────────")

check("SCM: module still loads — Sprint 6 tests are unaffected", function()
	assert(scmOk, tostring(scmResult))
end)

if not scmOk then
	warn(TAG .. " FATAL: SCM failed to load — skipping old-path section")
else

local SCM: any = scmResult

check("SCM: initial state is LOBBY (thin runner did not call Init)", function()
	local state = SCM:GetState()
	assert(state == "LOBBY",
		("expected LOBBY, got %q — thin runner must not have moved SCM to SWING state"):format(tostring(state)))
end)

check("SCM: LOBBY guard blocks MouseButton1 (not competing with SwingEngine)", function()
	-- Simulate a mouse press in LOBBY state; the state guard must prevent charging.
	local fakeLMB: any = {
		KeyCode       = Enum.KeyCode.Unknown,
		UserInputType = Enum.UserInputType.MouseButton1,
	}
	SCM:_onInputBegan(fakeLMB, false)
	assert(SCM:IsCharging() == false,
		"SCM must NOT start charging in LOBBY — it would compete with SwingEngineControllerModule")
end)

end -- scmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 35 client tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end

end
