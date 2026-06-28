--!strict
-- SwingFeedbackHUDModule — Client singleton (Sprint 34, updated Sprint 34.75)
-- Developer overlay: live swing phase + post-swing analysis.
-- Sprint 34.75 additions: Accel/Energy rows, Face Meter bar, Swing Path overlay.

local Players = game:GetService("Players")

-- ── Constants ─────────────────────────────────────────────────────────────────

local FACE_DISPLAY_MAX:   number = 10.0  -- ±° for face meter range
local PATH_OVERLAY_LIFE:  number = 3.0   -- seconds before path overlay self-destroys

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean    = false
local _gui:         ScreenGui? = nil
local _pathGui:     ScreenGui? = nil

local _lblPhase:   TextLabel? = nil
local _lblPower:   TextLabel? = nil
local _lblPath:    TextLabel? = nil
local _lblFace:    TextLabel? = nil
local _lblTempo:   TextLabel? = nil
local _lblContact: TextLabel? = nil
local _lblShape:   TextLabel? = nil
local _lblAccel:   TextLabel? = nil
local _lblEnergy:  TextLabel? = nil

local _faceMark:   Frame?     = nil  -- sliding marker on face meter bar

-- ── Module ───────────────────────────────────────────────────────────────────

local SwingFeedbackHUDModule = {}
SwingFeedbackHUDModule.__index = SwingFeedbackHUDModule

-- ── Private ───────────────────────────────────────────────────────────────────

local function _buildHUD()
	local player = Players.LocalPlayer
	if not player then return end
	local playerGui: PlayerGui = player.PlayerGui

	if _gui and _gui.Parent then
		_gui:Destroy()
	end

	local screenGui              = Instance.new("ScreenGui")
	screenGui.Name               = "SwingDebugHUD"
	screenGui.ResetOnSpawn       = false
	screenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder       = 98

	-- 10 text rows + face meter section (58 px) = 4 + 10×22 + 58 = 282 px
	local frame                  = Instance.new("Frame")
	frame.BackgroundColor3       = Color3.fromRGB(8, 8, 12)
	frame.BackgroundTransparency = 0.30
	frame.Size                   = UDim2.new(0, 220, 0, 286)
	frame.Position               = UDim2.new(1, -228, 0, 10)
	frame.AnchorPoint            = Vector2.new(0, 0)
	frame.BorderSizePixel        = 0
	frame.Parent                 = screenGui

	local function makeRow(text: string, row: number, color: Color3): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size           = UDim2.new(1, -12, 0, 20)
		lbl.Position       = UDim2.new(0, 6, 0, 4 + row * 22)
		lbl.Font           = Enum.Font.Gotham
		lbl.TextSize       = 12
		lbl.TextColor3     = color
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate   = Enum.TextTruncate.AtEnd
		lbl.Text           = text
		lbl.Parent         = frame
		return lbl
	end

	local white = Color3.fromRGB(200, 200, 200)
	makeRow("[ SWING DEBUG ]",    0, Color3.fromRGB(255, 200,  50))
	_lblPhase   = makeRow("Phase: Idle",   1, white)
	_lblPower   = makeRow("Power: --",     2, white)
	_lblPath    = makeRow("Path: --",      3, white)
	_lblFace    = makeRow("Face: --",      4, white)
	_lblTempo   = makeRow("Tempo: --",     5, white)
	_lblContact = makeRow("Contact: --",   6, white)
	_lblShape   = makeRow("Shape: --",     7, white)
	_lblAccel   = makeRow("Accel: --",     8, Color3.fromRGB(160, 210, 255))
	_lblEnergy  = makeRow("Energy: --",    9, Color3.fromRGB(160, 255, 180))

	-- ── Face Meter (below text rows) ──────────────────────────────────────────
	local meterY = 4 + 10 * 22  -- 224 px from top of frame

	local meterHdr = Instance.new("TextLabel")
	meterHdr.BackgroundTransparency = 1
	meterHdr.Size           = UDim2.new(1, -12, 0, 18)
	meterHdr.Position       = UDim2.new(0, 6, 0, meterY)
	meterHdr.Font           = Enum.Font.GothamBold
	meterHdr.TextSize       = 11
	meterHdr.TextColor3     = Color3.fromRGB(180, 220, 255)
	meterHdr.TextXAlignment = Enum.TextXAlignment.Left
	meterHdr.Text           = "[ FACE METER ]"
	meterHdr.Parent         = frame

	-- Bar background
	local barBg = Instance.new("Frame")
	barBg.Size             = UDim2.new(1, -24, 0, 8)
	barBg.Position         = UDim2.new(0, 12, 0, meterY + 22)
	barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	barBg.BorderSizePixel  = 0
	barBg.Parent           = frame

	-- Center tick at 0° (square face reference)
	local centerTick = Instance.new("Frame")
	centerTick.Size             = UDim2.new(0, 2, 0, 14)
	centerTick.AnchorPoint      = Vector2.new(0.5, 0.5)
	centerTick.Position         = UDim2.new(0.5, 0, 0.5, 0)
	centerTick.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
	centerTick.BorderSizePixel  = 0
	centerTick.Parent           = barBg

	-- Sliding marker — moves left (closed) or right (open)
	local mark = Instance.new("Frame")
	mark.Size             = UDim2.new(0, 8, 0, 16)
	mark.AnchorPoint      = Vector2.new(0.5, 0.5)
	mark.Position         = UDim2.new(0.5, 0, 0.5, 0)  -- center = 0°
	mark.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	mark.BorderSizePixel  = 0
	mark.Parent           = barBg
	_faceMark = mark

	-- "◄ Closed" label
	local lblClosed = Instance.new("TextLabel")
	lblClosed.BackgroundTransparency = 1
	lblClosed.Size           = UDim2.new(0, 58, 0, 14)
	lblClosed.Position       = UDim2.new(0, 6, 0, meterY + 34)
	lblClosed.Font           = Enum.Font.Gotham
	lblClosed.TextSize       = 10
	lblClosed.TextColor3     = Color3.fromRGB(100, 160, 255)
	lblClosed.TextXAlignment = Enum.TextXAlignment.Left
	lblClosed.Text           = "◄ Closed"
	lblClosed.Parent         = frame

	-- "Open ►" label
	local lblOpen = Instance.new("TextLabel")
	lblOpen.BackgroundTransparency = 1
	lblOpen.Size           = UDim2.new(0, 58, 0, 14)
	lblOpen.Position       = UDim2.new(1, -64, 0, meterY + 34)
	lblOpen.Font           = Enum.Font.Gotham
	lblOpen.TextSize       = 10
	lblOpen.TextColor3     = Color3.fromRGB(255, 160, 80)
	lblOpen.TextXAlignment = Enum.TextXAlignment.Right
	lblOpen.Text           = "Open ►"
	lblOpen.Parent         = frame

	screenGui.Parent = playerGui
	_gui = screenGui
end

-- Reposition and recolor the face meter marker based on current faceAngle.
local function _updateFaceMeter(faceAngle: number)
	if not _faceMark then return end
	local t = math.clamp((faceAngle + FACE_DISPLAY_MAX) / (FACE_DISPLAY_MAX * 2), 0, 1)
	_faceMark.Position = UDim2.new(t, 0, 0.5, 0)
	if faceAngle < -1 then
		_faceMark.BackgroundColor3 = Color3.fromRGB(100, 150, 255)  -- blue = closed
	elseif faceAngle > 1 then
		_faceMark.BackgroundColor3 = Color3.fromRGB(255, 150, 60)   -- orange = open
	else
		_faceMark.BackgroundColor3 = Color3.fromRGB(80, 220, 80)    -- green = square
	end
end

-- Show a brief path overlay (ideal vs actual swing path) that auto-destroys after PATH_OVERLAY_LIFE s.
local function _showPathOverlay(clubPath: number, shape: string)
	local player = Players.LocalPlayer
	if not player then return end

	-- Remove any previous overlay
	if _pathGui and _pathGui.Parent then
		_pathGui:Destroy()
		_pathGui = nil
	end

	local sg = Instance.new("ScreenGui")
	sg.Name           = "SwingPathOverlay"
	sg.ResetOnSpawn   = false
	sg.DisplayOrder   = 97

	local panel = Instance.new("Frame")
	panel.Size                = UDim2.new(0, 140, 0, 118)
	panel.Position            = UDim2.new(0.5, -70, 0, 10)
	panel.BackgroundColor3    = Color3.fromRGB(8, 8, 12)
	panel.BackgroundTransparency = 0.30
	panel.BorderSizePixel     = 0
	panel.Parent              = sg

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size           = UDim2.new(1, -8, 0, 18)
	header.Position       = UDim2.new(0, 4, 0, 4)
	header.Font           = Enum.Font.GothamBold
	header.TextSize       = 11
	header.TextColor3     = Color3.fromRGB(255, 200, 50)
	header.TextXAlignment = Enum.TextXAlignment.Center
	header.Text           = "[ SWING PATH ]"
	header.Parent         = panel

	-- Line drawing area (centered in panel)
	local lineArea = Instance.new("Frame")
	lineArea.Size                = UDim2.new(0, 100, 0, 72)
	lineArea.Position            = UDim2.new(0.5, -50, 0, 26)
	lineArea.BackgroundTransparency = 1
	lineArea.Parent              = panel

	-- Ideal path: thin vertical white/gray line
	local idealLine = Instance.new("Frame")
	idealLine.Size             = UDim2.new(0, 2, 0, 72)
	idealLine.Position         = UDim2.new(0.5, -1, 0, 0)
	idealLine.BackgroundColor3 = Color3.fromRGB(140, 140, 140)
	idealLine.BorderSizePixel  = 0
	idealLine.Parent           = lineArea

	-- Actual path: same size, rotated by clubPath to visualize deviation
	local pathColor: Color3
	if clubPath > 1 then
		pathColor = Color3.fromRGB(255, 120, 60)   -- orange = right path
	elseif clubPath < -1 then
		pathColor = Color3.fromRGB(80, 140, 255)   -- blue   = left path
	else
		pathColor = Color3.fromRGB(80, 220, 80)    -- green  = straight
	end

	local actualLine = Instance.new("Frame")
	actualLine.Size             = UDim2.new(0, 2, 0, 72)
	actualLine.AnchorPoint      = Vector2.new(0.5, 0.5)
	actualLine.Position         = UDim2.new(0.5, 0, 0.5, 0)
	actualLine.Rotation         = -clubPath * 2.5  -- visual tilt; right path tilts right
	actualLine.BackgroundColor3 = pathColor
	actualLine.BorderSizePixel  = 0
	actualLine.Parent           = lineArea

	-- Path + shape info label
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Size           = UDim2.new(1, -8, 0, 18)
	info.Position       = UDim2.new(0, 4, 1, -22)
	info.Font           = Enum.Font.Gotham
	info.TextSize       = 11
	info.TextColor3     = Color3.fromRGB(200, 200, 200)
	info.TextXAlignment = Enum.TextXAlignment.Center
	info.Text           = ("%+.1f°  %s"):format(clubPath, shape)
	info.Parent         = panel

	sg.Parent = player.PlayerGui
	_pathGui  = sg

	local captured = sg
	task.delay(PATH_OVERLAY_LIFE, function()
		if _pathGui == captured and captured.Parent then
			captured:Destroy()
			_pathGui = nil
		end
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function SwingFeedbackHUDModule:UpdatePhase(phase: string)
	if _lblPhase then
		_lblPhase.Text = "Phase: " .. phase
	end
end

function SwingFeedbackHUDModule:ShowResult(swingResult: any)
	if not _initialized then return end
	local sr = swingResult :: { [string]: any }

	local function num(key: string): number
		local v = sr[key]
		return if type(v) == "number" then v :: number else 0
	end
	local function str(key: string): string
		local v = sr[key]
		return if type(v) == "string" then v :: string else "--"
	end

	local power01     = num("power01")
	local clubPath    = num("clubPath")
	local faceAngle   = num("faceAngle")
	local tempoScore  = num("tempoScore")
	local accelCons   = num("accelerationConsistency")
	local swingEnergy = num("swingEnergy")
	local contact     = str("contactQuality")
	local shape       = str("shotShape")

	if _lblPhase   then _lblPhase.Text   = "Phase: Released" end
	if _lblPower   then _lblPower.Text   = ("Power: %.0f%%"):format(power01 * 100) end
	if _lblPath    then _lblPath.Text    = ("Path: %+.1f°"):format(clubPath) end
	if _lblFace    then _lblFace.Text    = ("Face: %+.1f°"):format(faceAngle) end
	if _lblTempo   then _lblTempo.Text   = ("Tempo: %.2f"):format(tempoScore) end
	if _lblContact then _lblContact.Text = "Contact: " .. contact end
	if _lblShape   then _lblShape.Text   = "Shape: " .. shape end
	if _lblAccel   then _lblAccel.Text   = ("Accel: %.2f"):format(accelCons) end
	if _lblEnergy  then _lblEnergy.Text  = ("Energy: %.2f"):format(swingEnergy) end

	_updateFaceMeter(faceAngle)
	_showPathOverlay(clubPath, shape)
end

function SwingFeedbackHUDModule:ResetDisplay()
	if _lblPhase   then _lblPhase.Text   = "Phase: Idle" end
	if _lblPower   then _lblPower.Text   = "Power: --" end
	if _lblPath    then _lblPath.Text    = "Path: --" end
	if _lblFace    then _lblFace.Text    = "Face: --" end
	if _lblTempo   then _lblTempo.Text   = "Tempo: --" end
	if _lblContact then _lblContact.Text = "Contact: --" end
	if _lblShape   then _lblShape.Text   = "Shape: --" end
	if _lblAccel   then _lblAccel.Text   = "Accel: --" end
	if _lblEnergy  then _lblEnergy.Text  = "Energy: --" end
	if _faceMark then
		_faceMark.Position         = UDim2.new(0.5, 0, 0.5, 0)
		_faceMark.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	end
	if _pathGui and _pathGui.Parent then
		_pathGui:Destroy()
		_pathGui = nil
	end
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function SwingFeedbackHUDModule:Init()
	if _initialized then
		warn("[SwingFeedbackHUDModule] Init called twice — skipping")
		return
	end
	_initialized = true
	local ok, err = pcall(_buildHUD)
	if not ok then
		warn("[SwingFeedbackHUDModule] HUD build failed: " .. tostring(err))
	else
		print("[SwingFeedbackHUDModule] SwingDebugHUD ready")
	end
end

function SwingFeedbackHUDModule:Update(_dt: number) end

function SwingFeedbackHUDModule:Destroy()
	if _gui and _gui.Parent then
		_gui:Destroy()
	end
	if _pathGui and _pathGui.Parent then
		_pathGui:Destroy()
	end
	_gui        = nil
	_pathGui    = nil
	_lblPhase   = nil
	_lblPower   = nil
	_lblPath    = nil
	_lblFace    = nil
	_lblTempo   = nil
	_lblContact = nil
	_lblShape   = nil
	_lblAccel   = nil
	_lblEnergy  = nil
	_faceMark   = nil
	_initialized = false
end

return SwingFeedbackHUDModule
