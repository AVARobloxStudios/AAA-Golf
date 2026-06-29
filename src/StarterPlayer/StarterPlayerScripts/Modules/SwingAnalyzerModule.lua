--!strict
-- SwingAnalyzerModule — Client singleton (Sprint 34, updated Sprint 34.5)
-- Converts RawSwingData + FaceInputData + aimDirection into a SwingResult.
-- Pure computation: no side effects, no server calls, no UserInputService.
-- Sprint 34.5: adds path smoothing (3-sample moving average) before vertical/accel
-- analysis, and adds swingEnergy (power01 × tempoScore) for future club integration.

local MIN_BACKSWING_PIXELS:  number = 40
local MAX_BACKSWING_PIXELS:  number = 340   -- was 260; more physical drag range for full power
local MAX_PATH_OFFSET_PIXELS: number = 160  -- was 140; wider before max path deviation
local MAX_CLUB_PATH_DEGREES: number = 12    -- was 15; less extreme curving at max path

local MIN_SHOT_POWER:        number = 35
local MAX_SHOT_POWER:        number = 125

local IDEAL_TEMPO_MIN:       number = 2.2
local IDEAL_TEMPO_MAX:       number = 3.6

local MAX_FACE_ANGLE:        number = 12.0  -- was 15; align with FaceControl MAX_FACE_ANGLE

-- ── Types ─────────────────────────────────────────────────────────────────────

export type SwingResult = {
	valid:                   boolean,
	power01:                 number,
	swingEnergy:             number,   -- 0..1; power01 × tempoScore; future: multiply by club carry factor
	shotPower:               number,   -- TEMPORARY: linear velocity (studs/s) for Sprint 33/34 dev physics
	clubPath:                number,   -- degrees; negative = left, positive = right
	faceAngle:               number,   -- degrees; negative = closed, positive = open
	pathOffset:              number,   -- normalized –1..1
	horizontalError:         number,   -- pixels
	verticalAccuracy:        number,   -- 0..1
	tempoScore:              number,   -- 0..1
	tempoRatio:              number,   -- backswingDuration / downswingDuration
	accelerationConsistency: number,   -- 0..1
	contactQuality:          string,   -- Perfect | Good | Thin | Chunk | Poor | Mishit
	shotShape:               string,   -- Straight | Push | Pull | Draw | Fade | Hook | Slice | Mishit
	launchDirection:         Vector3,
	carryMultiplier:         number,
	rollMultiplier:          number,
	sideSpinInput:           number,   -- normalized –1..1 (negative = draw/hook)
	backSpinInput:           number,   -- 0..1
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean      = false
local _lastResult:  SwingResult? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local SwingAnalyzerModule = {}
SwingAnalyzerModule.__index = SwingAnalyzerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

-- 3-sample moving average; endpoints are kept exact to preserve start/end accuracy.
-- Smoothed array length always equals input length, so rawDownIdx remains valid.
local function _smooth(positions: { Vector2 }): { Vector2 }
	local n = #positions
	if n <= 2 then return positions end
	local out: { Vector2 } = table.create(n)
	out[1] = positions[1]
	for i = 2, n - 1 do
		out[i] = (positions[i - 1] + positions[i] + positions[i + 1]) / 3
	end
	out[n] = positions[n]
	return out
end

-- Tempo score: 1.0 when ratio is in ideal range, decays outside.
local function _tempoScore(ratio: number): number
	if ratio >= IDEAL_TEMPO_MIN and ratio <= IDEAL_TEMPO_MAX then
		return 1.0
	elseif ratio > IDEAL_TEMPO_MAX then
		return math.clamp(1.0 - (ratio - IDEAL_TEMPO_MAX) / IDEAL_TEMPO_MAX, 0, 1)
	else
		return math.clamp(ratio / IDEAL_TEMPO_MIN, 0, 1)
	end
end

-- Vertical accuracy: how straight (vertically) the overall swing path was.
local function _verticalAccuracy(positions: { Vector2 }, startX: number): number
	if #positions == 0 then return 0.5 end
	local maxDev = 0
	for _, pos in ipairs(positions) do
		local d = math.abs(pos.X - startX)
		if d > maxDev then maxDev = d end
	end
	return 1 - math.clamp(maxDev / MAX_PATH_OFFSET_PIXELS, 0, 1)
end

-- Acceleration consistency: compares first-half vs second-half downswing upward speed.
local function _accelConsistency(
	positions: { Vector2 },
	times:     { number },
	startIdx:  number
): number
	if startIdx == 0 then return 1.0 end
	local speeds: { number } = {}
	for i = math.max(startIdx + 1, 2), #positions do
		local dt = times[i] - times[i - 1]
		if dt > 0 then
			-- Upward = Y decreases in screen space → positive speed
			local dy = positions[i - 1].Y - positions[i].Y
			table.insert(speeds, dy / dt)
		end
	end
	if #speeds < 2 then return 1.0 end
	local half  = math.floor(#speeds / 2)
	local sumA  = 0
	local sumB  = 0
	for i = 1, half do sumA += speeds[i] end
	for i = half + 1, #speeds do sumB += speeds[i] end
	local avgA = sumA / math.max(half, 1)
	local avgB = sumB / math.max(#speeds - half, 1)
	if avgA <= 0 then return 0.5 end
	return math.clamp((avgB / avgA) * 0.5, 0, 1)
end

-- Contact quality: acceleration consistency is the primary factor.
-- accelCons tiers: ≥0.92 Perfect, 0.80–0.92 Good, 0.60–0.80 Thin/Chunk, 0.35–0.60 Poor, <0.35 Mishit.
local function _contactQuality(
	tempoRatio:   number,
	pathOffset:   number,
	backswingDist: number,
	followThru:   number,
	accelCons:    number
): string
	if backswingDist < MIN_BACKSWING_PIXELS * 0.5 then return "Mishit" end
	if math.abs(pathOffset) > 0.88 then return "Mishit" end
	if accelCons < 0.35 then return "Mishit" end
	if accelCons < 0.60 then return "Poor" end
	if accelCons < 0.80 then
		-- Moderate accel: tempo discriminates Chunk vs Thin
		if tempoRatio < IDEAL_TEMPO_MIN then return "Chunk" end
		if tempoRatio > IDEAL_TEMPO_MAX * 1.2 then return "Thin" end
		if followThru < 20 then return "Thin" end
		return "Good"
	end
	-- Good accel (>= 0.80)
	if tempoRatio < IDEAL_TEMPO_MIN then return "Chunk" end
	if tempoRatio > IDEAL_TEMPO_MAX * 1.2 then return "Thin" end
	local ts = _tempoScore(tempoRatio)
	if accelCons >= 0.92 and ts > 0.75 and math.abs(pathOffset) < 0.35 and followThru > 20 then
		return "Perfect"
	end
	return "Good"
end

-- Right-handed shot shape from absolute path direction + absolute face angle.
-- Negative path = club travels left; negative face = closed face.
local function _shotShape(clubPathDeg: number, faceAngleDeg: number, cq: string): string
	if cq == "Mishit" then return "Mishit" end
	local PATH_DEAD = 1.0
	local FACE_DEAD = 1.0
	if math.abs(clubPathDeg) <= PATH_DEAD and math.abs(faceAngleDeg) <= FACE_DEAD then
		return "Straight"
	elseif clubPathDeg < -PATH_DEAD and math.abs(faceAngleDeg) <= FACE_DEAD then
		return "Pull"
	elseif clubPathDeg > PATH_DEAD and math.abs(faceAngleDeg) <= FACE_DEAD then
		return "Push"
	elseif clubPathDeg < -PATH_DEAD and faceAngleDeg < -FACE_DEAD then
		return "Hook"
	elseif clubPathDeg < -PATH_DEAD and faceAngleDeg > FACE_DEAD then
		return "Fade"
	elseif clubPathDeg > PATH_DEAD and faceAngleDeg < -FACE_DEAD then
		return "Draw"
	elseif clubPathDeg > PATH_DEAD and faceAngleDeg > FACE_DEAD then
		return "Slice"
	end
	return "Straight"
end

-- Rotate aimDirection by yawDegrees around Y, then add slight upward arc.
local function _launchDir(aimDir: Vector3, yawDeg: number): Vector3
	local rad = math.rad(yawDeg)
	local c   = math.cos(rad)
	local s   = math.sin(rad)
	local rx  = aimDir.X * c - aimDir.Z * s
	local rz  = aimDir.X * s + aimDir.Z * c
	local base = Vector3.new(rx, aimDir.Y, rz)
	local withArc = base + Vector3.new(0, 0.20, 0)
	if withArc.Magnitude > 0 then
		return withArc.Unit
	end
	return Vector3.new(0, 0.2, -1).Unit
end

local CARRY_MULTIPLIERS: { [string]: number } = {
	Perfect = 1.00,
	Good    = 0.95,
	Thin    = 0.85,
	Chunk   = 0.50,
	Poor    = 0.40,
	Mishit  = 0.30,
}

local ROLL_MULTIPLIERS: { [string]: number } = {
	Perfect = 1.00,
	Good    = 1.00,
	Thin    = 1.40,
	Chunk   = 0.80,
	Poor    = 0.70,
	Mishit  = 0.60,
}

-- Safe numeric read from an `any` table field.
local function _numField(t: any, key: string, default: number): number
	local v = (t :: { [string]: any })[key]
	return if type(v) == "number" then v :: number else default
end

local function _boolField(t: any, key: string, default: boolean): boolean
	local v = (t :: { [string]: any })[key]
	return if type(v) == "boolean" then v :: boolean else default
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Converts raw swing + face data into a SwingResult.
-- rawSwingData: RawSwingData table from SwingInputControllerModule.
-- faceInputData: FaceInputData table from FaceControlControllerModule.
-- aimDirection: camera LookVector at time of release.
function SwingAnalyzerModule:Analyze(rawSwingData: any, faceInputData: any, aimDirection: Vector3): SwingResult
	-- Safe field extraction
	local maxBackswing   = _numField(rawSwingData, "maxBackswingDistance",  0)
	local backswingDur   = _numField(rawSwingData, "backswingDuration",     0.001)
	local downswingDur   = _numField(rawSwingData, "downswingDuration",     0.001)
	local horizOffset    = _numField(rawSwingData, "horizontalOffset",      0)
	local followThru     = _numField(rawSwingData, "followThroughDistance", 0)
	local cancelled      = _boolField(rawSwingData, "cancelled",            false)

	local rawPositions: { Vector2 } = {}
	local rawTimes:     { number }  = {}
	local rawDownIdx    = 0
	local rawStartX     = 0

	local rdAny = rawSwingData :: { [string]: any }
	if type(rdAny["sampledPositions"]) == "table" then
		rawPositions = rdAny["sampledPositions"] :: { Vector2 }
	end
	if type(rdAny["sampledTimes"]) == "table" then
		rawTimes = rdAny["sampledTimes"] :: { number }
	end
	if type(rdAny["downswingStartIndex"]) == "number" then
		rawDownIdx = rdAny["downswingStartIndex"] :: number
	end
	local spField = rdAny["startPosition"]
	if typeof(spField) == "Vector2" then
		rawStartX = (spField :: Vector2).X
	end

	local faceAngleDeg: number = _numField(faceInputData, "faceAngle", 0)

	-- Cancelled swing: return invalid result
	if cancelled then
		local blank: SwingResult = {
			valid                   = false,
			power01                 = 0,
			swingEnergy             = 0,
			shotPower               = 0,
			clubPath                = 0,
			faceAngle               = 0,
			pathOffset              = 0,
			horizontalError         = 0,
			verticalAccuracy        = 0,
			tempoScore              = 0,
			tempoRatio              = 0,
			accelerationConsistency = 0,
			contactQuality          = "Mishit",
			shotShape               = "Mishit",
			launchDirection         = aimDirection.Magnitude > 0
				and (aimDirection + Vector3.new(0, 0.2, 0)).Unit
				or  Vector3.new(0, 0.2, -1).Unit,
			carryMultiplier         = 0,
			rollMultiplier          = 0,
			sideSpinInput           = 0,
			backSpinInput           = 0,
		}
		_lastResult = blank
		return blank
	end

	-- Power
	local power01   = math.clamp(maxBackswing / MAX_BACKSWING_PIXELS, 0, 1)
	local shotPower = MIN_SHOT_POWER + (MAX_SHOT_POWER - MIN_SHOT_POWER) * power01

	-- Path
	local pathOffset   = math.clamp(horizOffset / MAX_PATH_OFFSET_PIXELS, -1, 1)
	local clubPathDeg  = pathOffset * MAX_CLUB_PATH_DEGREES
	local horizError   = math.abs(horizOffset)

	-- Tempo
	local tempoRatio = math.max(backswingDur, 0.001) / math.max(downswingDur, 0.001)
	local tScore     = _tempoScore(tempoRatio)

	-- Smooth sampled positions before quality metrics (raw data preserved in RawSwingData)
	local smoothedPositions = _smooth(rawPositions)

	-- Additional quality metrics use smoothed positions; rawTimes / rawDownIdx index stays valid
	local vertAcc   = _verticalAccuracy(smoothedPositions, rawStartX)
	local accelCons = _accelConsistency(smoothedPositions, rawTimes, rawDownIdx)

	-- Strike quality independent of club: power × tempo. Future BallFlightService
	-- will multiply swingEnergy by club carry factor instead of using shotPower.
	local swingEnergy = power01 * tScore

	-- Contact
	local cq = _contactQuality(tempoRatio, pathOffset, maxBackswing, followThru, accelCons)

	-- Shot shape
	local shape = _shotShape(clubPathDeg, faceAngleDeg, cq)

	-- Launch direction (aim + path offset)
	local aimSafe = if aimDirection.Magnitude > 0
		then aimDirection
		else Vector3.new(0, 0, -1)
	local launchDir = _launchDir(aimSafe, clubPathDeg)

	-- Multipliers from contact
	local carryMult = CARRY_MULTIPLIERS[cq] or 0.9
	local rollMult  = ROLL_MULTIPLIERS[cq] or 1.0

	-- Spin
	local faceToPath   = faceAngleDeg - clubPathDeg
	local sideSpinInput = math.clamp(faceToPath / MAX_FACE_ANGLE, -1, 1)
	local backSpinInput = power01 * 0.5

	local result: SwingResult = {
		valid                   = true,
		power01                 = power01,
		swingEnergy             = swingEnergy,
		shotPower               = shotPower,
		clubPath                = clubPathDeg,
		faceAngle               = faceAngleDeg,
		pathOffset              = pathOffset,
		horizontalError         = horizError,
		verticalAccuracy        = vertAcc,
		tempoScore              = tScore,
		tempoRatio              = tempoRatio,
		accelerationConsistency = accelCons,
		contactQuality          = cq,
		shotShape               = shape,
		launchDirection         = launchDir,
		carryMultiplier         = carryMult,
		rollMultiplier          = rollMult,
		sideSpinInput           = sideSpinInput,
		backSpinInput           = backSpinInput,
	}

	_lastResult = result
	return result
end

function SwingAnalyzerModule:GetLastResult(): SwingResult?
	local r = _lastResult
	if not r then return nil end
	return {
		valid                   = r.valid,
		power01                 = r.power01,
		swingEnergy             = r.swingEnergy,
		shotPower               = r.shotPower,
		clubPath                = r.clubPath,
		faceAngle               = r.faceAngle,
		pathOffset              = r.pathOffset,
		horizontalError         = r.horizontalError,
		verticalAccuracy        = r.verticalAccuracy,
		tempoScore              = r.tempoScore,
		tempoRatio              = r.tempoRatio,
		accelerationConsistency = r.accelerationConsistency,
		contactQuality          = r.contactQuality,
		shotShape               = r.shotShape,
		launchDirection         = r.launchDirection,
		carryMultiplier         = r.carryMultiplier,
		rollMultiplier          = r.rollMultiplier,
		sideSpinInput           = r.sideSpinInput,
		backSpinInput           = r.backSpinInput,
	}
end

function SwingAnalyzerModule:Reset()
	_lastResult = nil
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function SwingAnalyzerModule:Init()
	if _initialized then
		warn("[SwingAnalyzerModule] Init called twice — skipping")
		return
	end
	_initialized = true
	_lastResult  = nil
end

function SwingAnalyzerModule:Update(_dt: number) end

function SwingAnalyzerModule:Destroy()
	_lastResult  = nil
	_initialized = false
end

return SwingAnalyzerModule
