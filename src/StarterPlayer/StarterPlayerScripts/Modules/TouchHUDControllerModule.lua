--!strict
-- TouchHUDControllerModule — Client singleton (Sprint 16)
-- Tracks layout state for the mobile HUD: compact mode, safe-area insets,
-- and screen orientation.  Pure state — no UI, no GameBus connection.
--
-- Other controllers (HUDController, PowerMeterController, etc.) consume this
-- state in future sprints to reposition their elements for mobile screens.
--
-- Valid orientations:  Landscape | Portrait
--
-- Public API
--   SetCompactMode(enabled)          — toggle compact layout
--   IsCompactMode()                  → boolean
--   SetSafeAreaInsets(insets)        — store notch/home-bar insets (pixels)
--   GetSafeAreaInsets()              → SafeAreaInsets  (copy)
--   SetOrientation(orientationName)  — update orientation; warns on invalid
--   GetOrientation()                 → string
--
-- TouchHUDController.client.lua is the thin runner.

-- ── Types ─────────────────────────────────────────────────────────────────────

export type SafeAreaInsets = {
	top:    number,
	right:  number,
	bottom: number,
	left:   number,
}

-- ── Constants ────────────────────────────────────────────────────────────────

local VALID_ORIENTATIONS: { [string]: boolean } = {
	Landscape = true,
	Portrait  = true,
}

local DEFAULT_ORIENTATION = "Landscape"

local DEFAULT_INSETS: SafeAreaInsets = { top = 0, right = 0, bottom = 0, left = 0 }

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean        = false
local _compactMode:    boolean        = false
local _orientation:    string         = ""
local _safeAreaInsets: SafeAreaInsets = { top = 0, right = 0, bottom = 0, left = 0 }

-- ── Module ───────────────────────────────────────────────────────────────────

local TouchHUDControllerModule = {}
TouchHUDControllerModule.__index = TouchHUDControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _copyInsets(src: SafeAreaInsets): SafeAreaInsets
	return { top = src.top, right = src.right, bottom = src.bottom, left = src.left }
end

-- ── Public API ────────────────────────────────────────────────────────────────

function TouchHUDControllerModule:SetCompactMode(enabled: boolean)
	_compactMode = enabled
end

function TouchHUDControllerModule:IsCompactMode(): boolean
	return _compactMode
end

-- Stores a copy of the provided insets table.
-- Missing or non-numeric fields default to 0.
function TouchHUDControllerModule:SetSafeAreaInsets(insets: { [string]: any })
	if type(insets) ~= "table" then
		warn("[TouchHUDController] SetSafeAreaInsets: expected table — ignored")
		return
	end
	_safeAreaInsets = {
		top    = type(insets["top"])    == "number" and insets["top"]    or 0,
		right  = type(insets["right"])  == "number" and insets["right"]  or 0,
		bottom = type(insets["bottom"]) == "number" and insets["bottom"] or 0,
		left   = type(insets["left"])   == "number" and insets["left"]   or 0,
	}
end

function TouchHUDControllerModule:GetSafeAreaInsets(): SafeAreaInsets
	return _copyInsets(_safeAreaInsets)
end

function TouchHUDControllerModule:SetOrientation(orientationName: string)
	if not VALID_ORIENTATIONS[orientationName] then
		warn(("[TouchHUDController] SetOrientation: unknown orientation %q"):format(
			tostring(orientationName)))
		return
	end
	_orientation = orientationName
end

function TouchHUDControllerModule:GetOrientation(): string
	return _orientation
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function TouchHUDControllerModule:Init()
	if _initialized then
		warn("[TouchHUDController] Init called twice — skipping")
		return
	end
	_initialized    = true
	_compactMode    = false
	_orientation    = DEFAULT_ORIENTATION
	_safeAreaInsets = _copyInsets(DEFAULT_INSETS)

	print("[TouchHUDController] ready")
end

function TouchHUDControllerModule:Update(_dt: number) end

function TouchHUDControllerModule:Destroy()
	_compactMode    = false
	_orientation    = ""
	_safeAreaInsets = _copyInsets(DEFAULT_INSETS)
	_initialized    = false
end

return TouchHUDControllerModule
