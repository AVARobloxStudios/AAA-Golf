--!strict
-- Sprint16ClientTest — LocalScript
-- Client smoke tests for Sprint 16: MobileControlsController,
-- InputModeController, and TouchHUDController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.
-- Tests drive each module via its public API only.
-- No real mobile device required.

print("[Sprint16ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint16ClientTest]"
local passed = 0
local failed = 0

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

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — MobileControlsControllerModule  (checks 1–13)
-- ════════════════════════════════════════════════════════════════════════════

local mccOk, mccResult = safeRequire(
	script.Parent.Parent.Modules.MobileControlsControllerModule)

if mccOk then

	local MCC: any = mccResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("MCC: module loads successfully", function()
		assert(type(MCC) == "table", "expected table, got " .. type(MCC))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("MCC: IsVisible is false initially", function()
		assert(MCC:IsVisible() == false, "controls must start hidden")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("MCC: GetButtonState('Swing') is false initially", function()
		assert(MCC:GetButtonState("Swing") == false, "Swing must start not-pressed")
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("MCC: GetButtonState for unknown button returns false safely", function()
		assert(MCC:GetButtonState("FlyButton") == false,
			"unknown button should return false without error")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("MCC: ShowControls sets IsVisible true", function()
		MCC:ShowControls()
		assert(MCC:IsVisible() == true, "expected visible after ShowControls")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("MCC: HideControls sets IsVisible false", function()
		MCC:HideControls()
		assert(MCC:IsVisible() == false, "expected hidden after HideControls")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("MCC: SetButtonState('Swing', true) reflects in GetButtonState", function()
		MCC:SetButtonState("Swing", true)
		assert(MCC:GetButtonState("Swing") == true, "expected Swing pressed")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("MCC: SetButtonState('Swing', false) clears state", function()
		MCC:SetButtonState("Swing", false)
		assert(MCC:GetButtonState("Swing") == false, "expected Swing not pressed")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("MCC: SetButtonState with invalid name is rejected", function()
		MCC:SetButtonState("Rocket", true)   -- invalid
		assert(MCC:GetButtonState("Rocket") == false,
			"invalid SetButtonState should not register state")
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("MCC: all 6 valid button names are accepted by SetButtonState", function()
		local BUTTONS = {
			"Swing", "AimLeft", "AimRight", "ClubNext", "ClubPrevious", "Pause",
		}
		for _, name in ipairs(BUTTONS) do
			MCC:SetButtonState(name, true)
			assert(MCC:GetButtonState(name) == true,
				("SetButtonState failed for button %q"):format(name))
		end
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("MCC: ResetButtons sets all buttons to not-pressed", function()
		-- All 6 are currently pressed from check 10
		MCC:ResetButtons()
		local BUTTONS = {
			"Swing", "AimLeft", "AimRight", "ClubNext", "ClubPrevious", "Pause",
		}
		for _, name in ipairs(BUTTONS) do
			assert(MCC:GetButtonState(name) == false,
				("expected %q not pressed after ResetButtons"):format(name))
		end
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("MCC: Destroy resets all state", function()
		MCC:ShowControls()
		MCC:SetButtonState("Pause", true)
		MCC:Destroy()
		assert(MCC:IsVisible()              == false, "expected hidden after Destroy")
		assert(MCC:GetButtonState("Pause")  == false, "expected Pause not pressed after Destroy")
		assert(MCC:GetButtonState("Swing")  == false, "expected Swing not pressed after Destroy")
	end)

	-- Restore
	MCC:Init()

	-- 13 ───────────────────────────────────────────────────────────────────
	check("MCC: ShowControls and SetButtonState work after Init restore", function()
		MCC:ShowControls()
		assert(MCC:IsVisible() == true, "expected visible after restore ShowControls")
		MCC:SetButtonState("AimLeft", true)
		assert(MCC:GetButtonState("AimLeft") == true, "expected AimLeft pressed after restore")
		MCC:ResetButtons()
		MCC:HideControls()
	end)

end -- mccOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — InputModeControllerModule  (checks 14–24)
-- ════════════════════════════════════════════════════════════════════════════

local imcOk, imcResult = safeRequire(
	script.Parent.Parent.Modules.InputModeControllerModule)

if imcOk then

	local IMC: any = imcResult

	-- 14 ───────────────────────────────────────────────────────────────────
	check("IMC: module loads successfully", function()
		assert(type(IMC) == "table", "expected table, got " .. type(IMC))
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	-- In Studio on PC: TouchEnabled=false, KeyboardEnabled=true → KeyboardMouse.
	check("IMC: GetInputMode defaults to 'KeyboardMouse' in Studio", function()
		assert(IMC:GetInputMode() == "KeyboardMouse",
			("expected 'KeyboardMouse', got %q"):format(IMC:GetInputMode()))
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("IMC: IsKeyboardMouseMode is true initially", function()
		assert(IMC:IsKeyboardMouseMode() == true, "expected keyboard/mouse mode")
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("IMC: IsTouchMode is false initially", function()
		assert(IMC:IsTouchMode() == false, "expected not touch mode initially")
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("IMC: IsGamepadMode is false initially", function()
		assert(IMC:IsGamepadMode() == false, "expected not gamepad mode initially")
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("IMC: SetInputMode('Touch') → IsTouchMode true", function()
		IMC:SetInputMode("Touch")
		assert(IMC:IsTouchMode()         == true,  "expected touch mode")
		assert(IMC:IsKeyboardMouseMode() == false, "expected not keyboard mode")
		assert(IMC:IsGamepadMode()       == false, "expected not gamepad mode")
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("IMC: SetInputMode('Gamepad') → IsGamepadMode true", function()
		IMC:SetInputMode("Gamepad")
		assert(IMC:IsGamepadMode()       == true,  "expected gamepad mode")
		assert(IMC:IsTouchMode()         == false, "expected not touch mode")
		assert(IMC:IsKeyboardMouseMode() == false, "expected not keyboard mode")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("IMC: SetInputMode('KeyboardMouse') restores keyboard mode", function()
		IMC:SetInputMode("KeyboardMouse")
		assert(IMC:IsKeyboardMouseMode() == true,  "expected keyboard/mouse mode")
		assert(IMC:IsTouchMode()         == false, "expected not touch mode")
		assert(IMC:IsGamepadMode()       == false, "expected not gamepad mode")
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("IMC: SetInputMode with invalid name is rejected", function()
		local before = IMC:GetInputMode()
		IMC:SetInputMode("VoiceControl")
		assert(IMC:GetInputMode() == before,
			"invalid SetInputMode should leave mode unchanged")
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("IMC: Destroy resets mode to ''", function()
		IMC:Destroy()
		assert(IMC:GetInputMode() == "",
			("expected '' after Destroy, got %q"):format(IMC:GetInputMode()))
	end)

	-- Restore
	IMC:Init()

	-- 24 ───────────────────────────────────────────────────────────────────
	check("IMC: SetInputMode works after Init restore", function()
		IMC:SetInputMode("Touch")
		assert(IMC:IsTouchMode() == true, "expected touch mode after restore")
		IMC:SetInputMode("KeyboardMouse")
		assert(IMC:IsKeyboardMouseMode() == true, "expected keyboard mode after reset")
	end)

end -- imcOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — TouchHUDControllerModule  (checks 25–36)
-- ════════════════════════════════════════════════════════════════════════════

local thcOk, thcResult = safeRequire(
	script.Parent.Parent.Modules.TouchHUDControllerModule)

if thcOk then

	local THC: any = thcResult

	-- 25 ───────────────────────────────────────────────────────────────────
	check("THC: module loads successfully", function()
		assert(type(THC) == "table", "expected table, got " .. type(THC))
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("THC: IsCompactMode is false initially", function()
		assert(THC:IsCompactMode() == false, "compact mode must default to false")
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("THC: GetOrientation is 'Landscape' initially", function()
		assert(THC:GetOrientation() == "Landscape",
			("expected 'Landscape', got %q"):format(THC:GetOrientation()))
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("THC: GetSafeAreaInsets defaults to all zeros", function()
		local ins = THC:GetSafeAreaInsets()
		assert(ins.top    == 0, ("expected top=0, got %d"):format(ins.top))
		assert(ins.right  == 0, ("expected right=0, got %d"):format(ins.right))
		assert(ins.bottom == 0, ("expected bottom=0, got %d"):format(ins.bottom))
		assert(ins.left   == 0, ("expected left=0, got %d"):format(ins.left))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("THC: SetCompactMode(true) → IsCompactMode true", function()
		THC:SetCompactMode(true)
		assert(THC:IsCompactMode() == true, "expected compact mode on")
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("THC: SetCompactMode(false) → IsCompactMode false", function()
		THC:SetCompactMode(false)
		assert(THC:IsCompactMode() == false, "expected compact mode off")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("THC: SetOrientation('Portrait') updates GetOrientation", function()
		THC:SetOrientation("Portrait")
		assert(THC:GetOrientation() == "Portrait",
			("expected 'Portrait', got %q"):format(THC:GetOrientation()))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("THC: SetOrientation with invalid name is rejected", function()
		local before = THC:GetOrientation()
		THC:SetOrientation("Diagonal")
		assert(THC:GetOrientation() == before,
			"invalid SetOrientation should leave orientation unchanged")
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("THC: both valid orientations accepted", function()
		THC:SetOrientation("Landscape")
		assert(THC:GetOrientation() == "Landscape", "expected Landscape")
		THC:SetOrientation("Portrait")
		assert(THC:GetOrientation() == "Portrait",  "expected Portrait")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("THC: SetSafeAreaInsets stores correct values", function()
		THC:SetSafeAreaInsets({ top = 44, right = 0, bottom = 34, left = 0 })
		local ins = THC:GetSafeAreaInsets()
		assert(ins.top    == 44, ("expected top=44, got %d"):format(ins.top))
		assert(ins.right  == 0,  ("expected right=0, got %d"):format(ins.right))
		assert(ins.bottom == 34, ("expected bottom=34, got %d"):format(ins.bottom))
		assert(ins.left   == 0,  ("expected left=0, got %d"):format(ins.left))
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("THC: GetSafeAreaInsets returns a copy (mutation does not affect internal)", function()
		local copy = THC:GetSafeAreaInsets()
		copy.top = 9999
		local fresh = THC:GetSafeAreaInsets()
		assert(fresh.top == 44,
			("mutating copy should not affect internal: expected 44, got %d"):format(fresh.top))
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("THC: Destroy resets all state", function()
		THC:Destroy()
		assert(THC:IsCompactMode()    == false,      "expected compact off after Destroy")
		assert(THC:GetOrientation()   == "",         "expected empty orientation after Destroy")
		local ins = THC:GetSafeAreaInsets()
		assert(ins.top    == 0, "expected insets reset after Destroy (top)")
		assert(ins.bottom == 0, "expected insets reset after Destroy (bottom)")
	end)

	-- Restore
	THC:Init()

	-- 37 ───────────────────────────────────────────────────────────────────
	check("THC: defaults restored correctly after Init restore", function()
		assert(THC:IsCompactMode()  == false,      "expected compact off after re-Init")
		assert(THC:GetOrientation() == "Landscape","expected Landscape after re-Init")
		local ins = THC:GetSafeAreaInsets()
		assert(ins.top    == 0, "expected top=0 after re-Init")
		assert(ins.bottom == 0, "expected bottom=0 after re-Init")
		THC:SetCompactMode(true)
		assert(THC:IsCompactMode() == true, "SetCompactMode should work after restore")
		THC:SetCompactMode(false)
	end)

end -- thcOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 16 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
