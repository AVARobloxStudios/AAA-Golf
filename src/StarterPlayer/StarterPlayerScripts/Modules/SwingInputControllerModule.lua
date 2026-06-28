--!strict
-- SwingInputControllerModule — Client singleton (Sprint 34)
-- Raw mouse / touch input capture only. No physics, no server calls.
-- Phases: Idle → InputStarted → Backswing → Downswing → Released | Cancelled
-- Screen space: Y increases downward. Dragging down = backswing. Up = downswing.

local MIN_BACKSWING_PIXELS:       number = 40   -- min drag (px) to enter Backswing
local DOWNSWING_DETECT_THRESHOLD: number = 15   -- px back up from peak to enter Downswing
local CANCEL_RADIUS:              number = 28   -- EndInput within this dist of start = cancel (Backswing phase only)
local MAX_SAMPLES:                number = 60   -- cap on sampled positions

-- ── Types ─────────────────────────────────────────────────────────────────────

export type RawSwingData = {
	startPosition:         Vector2,
	currentPosition:       Vector2,
	releasePosition:       Vector2,
	sampledPositions:      { Vector2 },
	sampledTimes:          { number },
	backswingStartTime:    number,
	downswingStartTime:    number,
	releaseTime:           number,
	maxBackswingDistance:  number,   -- pixels dragged down
	followThroughDistance: number,   -- pixels released above start (0 if no follow-through)
	horizontalOffset:      number,   -- avg X deviation during downswing from start X
	totalDuration:         number,   -- seconds from begin to release
	backswingDuration:     number,   -- seconds from backswing start to downswing start
	downswingDuration:     number,   -- seconds from downswing start to release
	cancelled:             boolean,
}

type SwingState = {
	phase:               string,
	enabled:             boolean,
	startPosition:       Vector2,
	currentPosition:     Vector2,
	maxBackswingDistance: number,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:        boolean  = false
local _enabled:            boolean  = true
local _phase:              string   = "Idle"

local _startPos:           Vector2  = Vector2.zero
local _currentPos:         Vector2  = Vector2.zero
local _releasePos:         Vector2  = Vector2.zero
local _peakBackswingPos:   Vector2  = Vector2.zero

local _inputStartTime:     number   = 0
local _backswingStartTime: number   = 0
local _downswingStartTime: number   = 0
local _releaseTime:        number   = 0

local _maxBackswingDistance: number = 0
local _downswingStartIndex:  number = 0  -- index in _sampledPositions where downswing began

local _sampledPositions: { Vector2 } = {}
local _sampledTimes:     { number }  = {}

local _lastRawData: RawSwingData?    = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local SwingInputControllerModule = {}
SwingInputControllerModule.__index = SwingInputControllerModule

-- ── Private ───────────────────────────────────────────────────────────────────

local function _resetState()
	_phase               = "Idle"
	_startPos            = Vector2.zero
	_currentPos          = Vector2.zero
	_releasePos          = Vector2.zero
	_peakBackswingPos    = Vector2.zero
	_inputStartTime      = 0
	_backswingStartTime  = 0
	_downswingStartTime  = 0
	_releaseTime         = 0
	_maxBackswingDistance  = 0
	_downswingStartIndex   = 0
	table.clear(_sampledPositions)
	table.clear(_sampledTimes)
end

local function _appendSample(pos: Vector2)
	if #_sampledPositions >= MAX_SAMPLES then return end
	table.insert(_sampledPositions, pos)
	table.insert(_sampledTimes, os.clock())
end

local function _computeHorizontalOffset(): number
	local startIdx = _downswingStartIndex
	if startIdx == 0 or startIdx > #_sampledPositions then
		return _releasePos.X - _startPos.X
	end
	local sum   = 0
	local count = 0
	for i = startIdx, #_sampledPositions do
		sum   += _sampledPositions[i].X - _startPos.X
		count += 1
	end
	return if count > 0 then sum / count else 0
end

local function _buildRawSwingData(cancelled: boolean): RawSwingData
	local backswingDur = math.max(0, _downswingStartTime - _backswingStartTime)
	local downswingDur = math.max(0.001, _releaseTime - _downswingStartTime)
	local totalDur     = math.max(0.001, _releaseTime - _inputStartTime)
	local followThru   = math.max(0, _startPos.Y - _releasePos.Y)  -- px above start

	local posCopy: { Vector2 } = {}
	local timCopy: { number }  = {}
	for i, p in ipairs(_sampledPositions) do
		posCopy[i] = p
		timCopy[i] = _sampledTimes[i]
	end

	return {
		startPosition         = _startPos,
		currentPosition       = _currentPos,
		releasePosition       = _releasePos,
		sampledPositions      = posCopy,
		sampledTimes          = timCopy,
		backswingStartTime    = _backswingStartTime,
		downswingStartTime    = _downswingStartTime,
		releaseTime           = _releaseTime,
		maxBackswingDistance  = _maxBackswingDistance,
		followThroughDistance = followThru,
		horizontalOffset      = if cancelled then 0 else _computeHorizontalOffset(),
		totalDuration         = totalDur,
		backswingDuration     = backswingDur,
		downswingDuration     = downswingDur,
		cancelled             = cancelled,
	}
end

-- ── Public API ────────────────────────────────────────────────────────────────

function SwingInputControllerModule:SetEnabled(enabled: boolean)
	_enabled = enabled
	if not enabled then
		SwingInputControllerModule:CancelInput()
	end
end

-- Call when mouse/touch press begins.
function SwingInputControllerModule:BeginInput(screenPosition: Vector2)
	if not _initialized or not _enabled then return end
	_resetState()
	_phase              = "InputStarted"
	_startPos           = screenPosition
	_currentPos         = screenPosition
	_peakBackswingPos   = screenPosition
	_inputStartTime     = os.clock()
	_backswingStartTime = _inputStartTime
	_appendSample(screenPosition)
end

-- Call every frame/event while mouse/touch is held.
function SwingInputControllerModule:UpdateInput(screenPosition: Vector2)
	if not _initialized then return end
	if _phase == "Idle" or _phase == "Released" or _phase == "Cancelled" then return end

	_currentPos = screenPosition
	_appendSample(screenPosition)

	local deltaY = screenPosition.Y - _startPos.Y  -- positive = dragged DOWN

	if _phase == "InputStarted" then
		if deltaY >= MIN_BACKSWING_PIXELS then
			_phase              = "Backswing"
			_backswingStartTime = os.clock()
			_peakBackswingPos   = screenPosition
			_maxBackswingDistance = deltaY
		end

	elseif _phase == "Backswing" then
		if screenPosition.Y > _peakBackswingPos.Y then
			_peakBackswingPos     = screenPosition
			_maxBackswingDistance = screenPosition.Y - _startPos.Y
		end
		local pixelsBack = _peakBackswingPos.Y - screenPosition.Y
		if pixelsBack >= DOWNSWING_DETECT_THRESHOLD then
			_phase              = "Downswing"
			_downswingStartTime = os.clock()
			_downswingStartIndex = #_sampledPositions
		end
	end
	-- Downswing: positions tracked via _appendSample; EndInput finalizes
end

-- Call when mouse/touch is released.
function SwingInputControllerModule:EndInput(screenPosition: Vector2)
	if not _initialized then return end
	if _phase == "Idle" or _phase == "Released" or _phase == "Cancelled" then return end

	_releasePos  = screenPosition
	_releaseTime = os.clock()
	_appendSample(screenPosition)

	local cancelled: boolean
	if _phase == "InputStarted" then
		cancelled = true  -- never reached backswing
	elseif _phase == "Backswing" then
		-- cancel if released near start (swing aborted before downswing)
		local dist = (screenPosition - _startPos).Magnitude
		cancelled  = dist < CANCEL_RADIUS
	else
		cancelled = false  -- Downswing completed → valid shot
	end

	_phase       = if cancelled then "Cancelled" else "Released"
	_lastRawData = _buildRawSwingData(cancelled)
end

-- Force-cancel any in-progress swing.
function SwingInputControllerModule:CancelInput()
	if _phase == "Idle" or _phase == "Released" or _phase == "Cancelled" then return end
	_releasePos  = _currentPos
	_releaseTime = os.clock()
	_phase       = "Cancelled"
	_lastRawData = _buildRawSwingData(true)
end

function SwingInputControllerModule:GetSwingState(): SwingState
	return {
		phase                = _phase,
		enabled              = _enabled,
		startPosition        = _startPos,
		currentPosition      = _currentPos,
		maxBackswingDistance = _maxBackswingDistance,
	}
end

-- Returns the RawSwingData from the most recently completed swing (Released or Cancelled).
function SwingInputControllerModule:GetRawSwingData(): RawSwingData?
	return _lastRawData
end

function SwingInputControllerModule:GetLastSwingResult(): RawSwingData?
	return _lastRawData
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function SwingInputControllerModule:Init()
	if _initialized then
		warn("[SwingInputControllerModule] Init called twice — skipping")
		return
	end
	_initialized = true
	_enabled     = true
	_resetState()
	_lastRawData = nil
end

function SwingInputControllerModule:Update(_dt: number) end

function SwingInputControllerModule:Destroy()
	_resetState()
	_lastRawData = nil
	_enabled     = true
	_initialized = false
end

return SwingInputControllerModule
