--!strict
-- InputModeControllerModule — Client singleton (Sprint 16)
-- Tracks the current input mode (KeyboardMouse / Touch / Gamepad).
-- Pure state — no UI, no GameBus connection.
--
-- Init() auto-detects the platform via UserInputService and sets a sensible
-- default:  Touch mode when only touch is available, KeyboardMouse otherwise.
-- Callers may override at any time with SetInputMode().
--
-- Valid modes:  KeyboardMouse | Touch | Gamepad
--
-- Public API
--   SetInputMode(modeName)    — switch mode; warns on invalid names
--   GetInputMode()            → string
--   IsTouchMode()             → boolean
--   IsKeyboardMouseMode()     → boolean
--   IsGamepadMode()           → boolean
--
-- InputModeController.client.lua is the thin runner.

local UserInputService = game:GetService("UserInputService")

-- ── Mode catalogue ────────────────────────────────────────────────────────────

local VALID_MODES: { [string]: boolean } = {
	KeyboardMouse = true,
	Touch         = true,
	Gamepad       = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean = false
local _mode:        string  = ""

-- ── Module ───────────────────────────────────────────────────────────────────

local InputModeControllerModule = {}
InputModeControllerModule.__index = InputModeControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

function InputModeControllerModule:SetInputMode(modeName: string)
	if not VALID_MODES[modeName] then
		warn(("[InputModeController] SetInputMode: unknown mode %q"):format(
			tostring(modeName)))
		return
	end
	_mode = modeName
end

function InputModeControllerModule:GetInputMode(): string
	return _mode
end

function InputModeControllerModule:IsTouchMode(): boolean
	return _mode == "Touch"
end

function InputModeControllerModule:IsKeyboardMouseMode(): boolean
	return _mode == "KeyboardMouse"
end

function InputModeControllerModule:IsGamepadMode(): boolean
	return _mode == "Gamepad"
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function InputModeControllerModule:Init()
	if _initialized then
		warn("[InputModeController] Init called twice — skipping")
		return
	end
	_initialized = true

	-- Auto-detect: if only touch is available (no keyboard), default to Touch.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		_mode = "Touch"
	else
		_mode = "KeyboardMouse"
	end

	print(("[InputModeController] ready — mode: %s"):format(_mode))
end

function InputModeControllerModule:Update(_dt: number) end

function InputModeControllerModule:Destroy()
	_mode        = ""
	_initialized = false
end

return InputModeControllerModule
