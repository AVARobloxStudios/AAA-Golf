--!strict
-- FaceControlControllerModule — Client singleton (Sprint 34)
-- Temporary face-control timing module using Spacebar input.
-- A timing window opens during downswing; Spacebar press relative to the ideal
-- impact moment determines club face angle (negative = closed/draw, positive = open/fade).
-- Architecture allows replacing Spacebar with another input method in a future sprint.

local IDEAL_IMPACT_DELAY:  number = 0.15  -- seconds after StartFaceWindow that ideal impact occurs
local PERFECT_WINDOW:      number = 0.08  -- |delta| ≤ this → timedPerfect=true (display only)
local MAX_FACE_ANGLE:      number = 10.0  -- degrees maximum face deflection (±10° range)
local FACE_SENSITIVITY:    number = 80.0  -- degrees per second of timing error (0.1s error → 8°)
local DEFAULT_OPEN_FACE:   number = 8.0   -- right-handed open face when Spacebar is missed

-- ── Types ─────────────────────────────────────────────────────────────────────

export type FaceInputData = {
	faceAngle:    number,   -- degrees; negative = closed/draw, positive = open/fade
	noInput:      boolean,  -- true if no Spacebar press was registered
	timedPerfect: boolean,
	timedEarly:   boolean,
	timedLate:    boolean,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean = false
local _windowOpen:     boolean = false
local _windowStartTime: number  = 0     -- os.clock() when StartFaceWindow was called
local _registeredTime: number?  = nil   -- nil until RegisterFaceInput called

-- ── Module ───────────────────────────────────────────────────────────────────

local FaceControlControllerModule = {}
FaceControlControllerModule.__index = FaceControlControllerModule

-- ── Private ───────────────────────────────────────────────────────────────────

local function _computeFaceAngle(registeredTime: number): (number, boolean, boolean, boolean)
	local idealTime = _windowStartTime + IDEAL_IMPACT_DELAY
	local delta     = registeredTime - idealTime  -- negative = early, positive = late

	-- Continuous: face angle scales linearly with timing error, clamped to ±MAX_FACE_ANGLE.
	-- Perfect timing (delta≈0) naturally produces ~0°; no discrete buckets.
	local angle = math.clamp(delta * FACE_SENSITIVITY, -MAX_FACE_ANGLE, MAX_FACE_ANGLE)

	local timedPerfect = math.abs(delta) <= PERFECT_WINDOW
	local timedEarly   = delta < -PERFECT_WINDOW
	local timedLate    = delta > PERFECT_WINDOW

	return angle, timedPerfect, timedEarly, timedLate
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called when downswing begins. Opens the timing window.
-- overrideStartTime: optional timestamp for testing (defaults to os.clock())
function FaceControlControllerModule:StartFaceWindow(overrideStartTime: number?)
	if not _initialized then return end
	_windowOpen      = true
	_windowStartTime = if type(overrideStartTime) == "number"
		then overrideStartTime :: number
		else os.clock()
	_registeredTime  = nil
end

-- Called when the player presses the face-control input (Spacebar in Sprint 34).
-- overrideTime: optional timestamp for testing (defaults to os.clock())
function FaceControlControllerModule:RegisterFaceInput(overrideTime: number?)
	if not _initialized then return end
	if not _windowOpen then return end
	if _registeredTime ~= nil then return end  -- only first press counts
	_registeredTime = if type(overrideTime) == "number"
		then overrideTime :: number
		else os.clock()
end

-- Called when the swing is released (EndInput). Closes the timing window.
function FaceControlControllerModule:EndFaceWindow()
	_windowOpen = false
end

-- Returns the FaceInputData for the most recently completed window.
-- If no input was registered, returns DEFAULT_OPEN_FACE (+8°) — right-handed open face penalty.
function FaceControlControllerModule:GetFaceInputData(): FaceInputData
	local registered = _registeredTime
	if registered == nil then
		return {
			faceAngle    = DEFAULT_OPEN_FACE,
			noInput      = true,
			timedPerfect = false,
			timedEarly   = false,
			timedLate    = false,
		}
	end

	local angle, perfect, early, late = _computeFaceAngle(registered)
	return {
		faceAngle    = angle,
		noInput      = false,
		timedPerfect = perfect,
		timedEarly   = early,
		timedLate    = late,
	}
end

-- Resets state for the next swing.
function FaceControlControllerModule:Reset()
	_windowOpen      = false
	_windowStartTime = 0
	_registeredTime  = nil
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function FaceControlControllerModule:Init()
	if _initialized then
		warn("[FaceControlControllerModule] Init called twice — skipping")
		return
	end
	_initialized = true
	FaceControlControllerModule:Reset()
end

function FaceControlControllerModule:Update(_dt: number) end

function FaceControlControllerModule:Destroy()
	FaceControlControllerModule:Reset()
	_initialized = false
end

return FaceControlControllerModule
