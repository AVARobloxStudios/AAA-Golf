--!strict
-- SwingFeedbackHUDModule — Client singleton (Sprint 34, Milestone 3)
-- Developer overlay: live swing phase + post-swing analysis.
-- Milestone 3: +Club, +Carry, +BallState rows; readable Path/Face labels;
--              richer shot-summary popup replaces path-line overlay.

local Players = game:GetService("Players")

-- ── Constants ─────────────────────────────────────────────────────────────────

local FACE_DISPLAY_MAX:   number = 7.0   -- ±° for face meter range (matches FaceControl MAX_FACE_ANGLE)
local SUMMARY_LIFE:       number = 3.0   -- seconds the shot summary popup stays visible

-- Deadzone thresholds for readable Path / Face labels
local PATH_DEAD:          number = 1.0   -- ±° → "Straight"
local FACE_DEAD:          number = 1.0   -- ±° → "Square"

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean    = false
local _gui:         ScreenGui? = nil
local _summaryGui:  ScreenGui? = nil   -- replaces old _pathGui

local _lblPhase:     TextLabel? = nil
local _lblPower:     TextLabel? = nil
local _lblPath:      TextLabel? = nil
local _lblFace:      TextLabel? = nil
local _lblTempo:     TextLabel? = nil
local _lblContact:   TextLabel? = nil
local _lblShape:     TextLabel? = nil
local _lblAccel:     TextLabel? = nil
local _lblEnergy:    TextLabel? = nil
local _lblClub:      TextLabel? = nil   -- NEW
local _lblCarry:     TextLabel? = nil   -- NEW
local _lblBallState: TextLabel? = nil   -- NEW

local _faceMark:   Frame?     = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local SwingFeedbackHUDModule = {}
SwingFeedbackHUDModule.__index = SwingFeedbackHUDModule

-- ── Private ───────────────────────────────────────────────────────────────────

local function _buildHUD()
	local player = Players.LocalPlayer
	if not player then return end
	local playerGui: PlayerGui = player.PlayerGui

	if _gui and _gui.Parent then _gui:Destroy() end

	local screenGui              = Instance.new("ScreenGui")
	screenGui.Name               = "SwingDebugHUD"
	screenGui.ResetOnSpawn       = false
	screenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder       = 98

	-- 13 text rows (0-12) + face meter section (62 px) = 4 + 13×22 + 62 = 352 px
	local frame                  = Instance.new("Frame")
	frame.BackgroundColor3       = Color3.fromRGB(8, 8, 12)
	frame.BackgroundTransparency = 0.30
	frame.Size                   = UDim2.new(0, 220, 0, 352)
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

	local white  = Color3.fromRGB(200, 200, 200)
	local cyan   = Color3.fromRGB(160, 210, 255)
	local green  = Color3.fromRGB(160, 255, 180)
	local gold   = Color3.fromRGB(255, 200,  50)
	local orange = Color3.fromRGB(255, 180, 80)

	makeRow("[ SWING DEBUG ]",   0, gold)
	_lblPhase    = makeRow("Phase: Idle",    1, white)
	_lblPower    = makeRow("Power: --",      2, white)
	_lblPath     = makeRow("Path: --",       3, white)
	_lblFace     = makeRow("Face: --",       4, white)
	_lblTempo    = makeRow("Tempo: --",      5, white)
	_lblContact  = makeRow("Contact: --",    6, white)
	_lblShape    = makeRow("Shape: --",      7, white)
	_lblAccel    = makeRow("Accel: --",      8, cyan)
	_lblEnergy   = makeRow("Energy: --",     9, green)
	_lblClub     = makeRow("Club: --",      10, orange)    -- NEW
	_lblCarry    = makeRow("Carry est: --", 11, orange)    -- NEW
	_lblBallState= makeRow("Ball: --",      12, Color3.fromRGB(120, 220, 120))  -- NEW

	-- ── Face Meter ────────────────────────────────────────────────────────────
	local meterY = 4 + 13 * 22  -- 290 px from top of frame

	local meterHdr                  = Instance.new("TextLabel")
	meterHdr.BackgroundTransparency = 1
	meterHdr.Size                   = UDim2.new(1, -12, 0, 18)
	meterHdr.Position               = UDim2.new(0, 6, 0, meterY)
	meterHdr.Font                   = Enum.Font.GothamBold
	meterHdr.TextSize               = 11
	meterHdr.TextColor3             = Color3.fromRGB(180, 220, 255)
	meterHdr.TextXAlignment         = Enum.TextXAlignment.Left
	meterHdr.Text                   = "[ FACE METER ]"
	meterHdr.Parent                 = frame

	local barBg                = Instance.new("Frame")
	barBg.Size                 = UDim2.new(1, -24, 0, 8)
	barBg.Position             = UDim2.new(0, 12, 0, meterY + 22)
	barBg.BackgroundColor3     = Color3.fromRGB(45, 45, 55)
	barBg.BorderSizePixel      = 0
	barBg.Parent               = frame

	local centerTick           = Instance.new("Frame")
	centerTick.Size            = UDim2.new(0, 2, 0, 14)
	centerTick.AnchorPoint     = Vector2.new(0.5, 0.5)
	centerTick.Position        = UDim2.new(0.5, 0, 0.5, 0)
	centerTick.BackgroundColor3= Color3.fromRGB(90, 90, 90)
	centerTick.BorderSizePixel = 0
	centerTick.Parent          = barBg

	local mark                 = Instance.new("Frame")
	mark.Size                  = UDim2.new(0, 8, 0, 16)
	mark.AnchorPoint           = Vector2.new(0.5, 0.5)
	mark.Position              = UDim2.new(0.5, 0, 0.5, 0)
	mark.BackgroundColor3      = Color3.fromRGB(80, 220, 80)
	mark.BorderSizePixel       = 0
	mark.Parent                = barBg
	_faceMark = mark

	local lblClosed                  = Instance.new("TextLabel")
	lblClosed.BackgroundTransparency = 1
	lblClosed.Size                   = UDim2.new(0, 58, 0, 14)
	lblClosed.Position               = UDim2.new(0, 6, 0, meterY + 34)
	lblClosed.Font                   = Enum.Font.Gotham
	lblClosed.TextSize               = 10
	lblClosed.TextColor3             = Color3.fromRGB(100, 160, 255)
	lblClosed.TextXAlignment         = Enum.TextXAlignment.Left
	lblClosed.Text                   = "◄ Closed"
	lblClosed.Parent                 = frame

	local lblOpen                  = Instance.new("TextLabel")
	lblOpen.BackgroundTransparency = 1
	lblOpen.Size                   = UDim2.new(0, 58, 0, 14)
	lblOpen.Position               = UDim2.new(1, -64, 0, meterY + 34)
	lblOpen.Font                   = Enum.Font.Gotham
	lblOpen.TextSize               = 10
	lblOpen.TextColor3             = Color3.fromRGB(255, 160, 80)
	lblOpen.TextXAlignment         = Enum.TextXAlignment.Right
	lblOpen.Text                   = "Open ►"
	lblOpen.Parent                 = frame

	screenGui.Parent = playerGui
	_gui = screenGui
end

local function _updateFaceMeter(faceAngle: number)
	if not _faceMark then return end
	local t = math.clamp((faceAngle + FACE_DISPLAY_MAX) / (FACE_DISPLAY_MAX * 2), 0, 1)
	_faceMark.Position = UDim2.new(t, 0, 0.5, 0)
	if faceAngle < -FACE_DEAD then
		_faceMark.BackgroundColor3 = Color3.fromRGB(100, 150, 255)  -- blue = closed
	elseif faceAngle > FACE_DEAD then
		_faceMark.BackgroundColor3 = Color3.fromRGB(255, 150, 60)   -- orange = open
	else
		_faceMark.BackgroundColor3 = Color3.fromRGB(80, 220, 80)    -- green = square
	end
end

-- Shot summary popup: shows readable labels for contact, path, face, shape.
-- Appears centre-screen and auto-destroys after SUMMARY_LIFE seconds.
local function _showShotSummary(contact: string, clubPath: number, faceAngle: number, shape: string)
	local player = Players.LocalPlayer
	if not player then return end

	if _summaryGui and _summaryGui.Parent then
		_summaryGui:Destroy()
		_summaryGui = nil
	end

	-- Readable labels
	local pathLabel: string = if clubPath > PATH_DEAD then "Right"
		elseif clubPath < -PATH_DEAD then "Left"
		else "Straight"

	local faceLabel: string = if faceAngle > FACE_DEAD then "Open"
		elseif faceAngle < -FACE_DEAD then "Closed"
		else "Square"

	-- Contact quality colour
	local contactColor: Color3
	if contact == "Perfect" then
		contactColor = Color3.fromRGB(255, 215,  0)
	elseif contact == "Good" then
		contactColor = Color3.fromRGB(100, 230, 110)
	elseif contact == "Thin" then
		contactColor = Color3.fromRGB(255, 230,  55)
	elseif contact == "Chunk" then
		contactColor = Color3.fromRGB(255, 140,  45)
	elseif contact == "Poor" then
		contactColor = Color3.fromRGB(255, 155,  80)
	else
		contactColor = Color3.fromRGB(255, 80, 80)
	end

	local sg            = Instance.new("ScreenGui")
	sg.Name             = "ShotSummary"
	sg.ResetOnSpawn     = false
	sg.DisplayOrder     = 97

	local panel                    = Instance.new("Frame")
	panel.Size                     = UDim2.new(0, 200, 0, 110)
	panel.AnchorPoint              = Vector2.new(0.5, 0)
	panel.Position                 = UDim2.new(0.5, 0, 0, 70)
	panel.BackgroundColor3         = Color3.fromRGB(8, 8, 12)
	panel.BackgroundTransparency   = 0.25
	panel.BorderSizePixel          = 0
	panel.Parent                   = sg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	-- Contact quality (large)
	local lblContact                    = Instance.new("TextLabel")
	lblContact.BackgroundTransparency   = 1
	lblContact.Size                     = UDim2.new(1, -8, 0, 36)
	lblContact.Position                 = UDim2.new(0, 4, 0, 6)
	lblContact.Font                     = Enum.Font.GothamBold
	lblContact.TextSize                 = 22
	lblContact.TextColor3               = contactColor
	lblContact.TextXAlignment           = Enum.TextXAlignment.Center
	lblContact.TextStrokeTransparency   = 0.4
	lblContact.TextStrokeColor3         = Color3.fromRGB(0, 0, 0)
	lblContact.Text                     = contact:upper()
	lblContact.Parent                   = panel

	-- Path / Face row
	local lblPathFace                   = Instance.new("TextLabel")
	lblPathFace.BackgroundTransparency  = 1
	lblPathFace.Size                    = UDim2.new(1, -8, 0, 22)
	lblPathFace.Position                = UDim2.new(0, 4, 0, 44)
	lblPathFace.Font                    = Enum.Font.Gotham
	lblPathFace.TextSize                = 13
	lblPathFace.TextColor3              = Color3.fromRGB(200, 200, 200)
	lblPathFace.TextXAlignment          = Enum.TextXAlignment.Center
	lblPathFace.Text                    = ("Path: %s  ·  Face: %s"):format(pathLabel, faceLabel)
	lblPathFace.Parent                  = panel

	-- Shape row
	local shapeColor: Color3
	if shape == "Draw" then
		shapeColor = Color3.fromRGB(100, 200, 255)
	elseif shape == "Fade" then
		shapeColor = Color3.fromRGB(255, 200, 100)
	elseif shape == "Hook" then
		shapeColor = Color3.fromRGB(60, 140, 255)
	elseif shape == "Slice" then
		shapeColor = Color3.fromRGB(255, 120, 60)
	elseif shape == "Straight" or shape == "Push" or shape == "Pull" then
		shapeColor = Color3.fromRGB(160, 255, 160)
	else
		shapeColor = Color3.fromRGB(255, 80, 80)
	end

	local lblShape                   = Instance.new("TextLabel")
	lblShape.BackgroundTransparency  = 1
	lblShape.Size                    = UDim2.new(1, -8, 0, 22)
	lblShape.Position                = UDim2.new(0, 4, 0, 68)
	lblShape.Font                    = Enum.Font.GothamBold
	lblShape.TextSize                = 14
	lblShape.TextColor3              = shapeColor
	lblShape.TextXAlignment          = Enum.TextXAlignment.Center
	lblShape.Text                    = shape:upper()
	lblShape.Parent                  = panel

	sg.Parent    = player.PlayerGui
	_summaryGui  = sg

	-- Fade out and self-destroy
	local captured = sg
	local conn: RBXScriptConnection?
	local elapsed  = 0
	local HOLD     = SUMMARY_LIFE - 0.5
	local FADE     = 0.5
	conn = game:GetService("RunService").RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= HOLD then
			local alpha = math.min((elapsed - HOLD) / FADE, 1)
			if panel.Parent then panel.BackgroundTransparency = 0.25 + alpha * 0.75 end
			for _, child in ipairs(panel:GetChildren()) do
				if child:IsA("TextLabel") then
					(child :: TextLabel).TextTransparency = alpha
				end
			end
		end
		if elapsed >= HOLD + FADE then
			if conn then conn:Disconnect() end
			if _summaryGui == captured and captured.Parent then
				captured:Destroy()
				_summaryGui = nil
			end
		end
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function SwingFeedbackHUDModule:UpdatePhase(phase: string)
	if _lblPhase then _lblPhase.Text = "Phase: " .. phase end
end

-- Called immediately after SwingAnalyzer:Analyze(). Updates debug panel + shows shot summary.
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

	local power01    = num("power01")
	local clubPath   = num("clubPath")
	local faceAngle  = num("faceAngle")
	local tempoScore = num("tempoScore")
	local accelCons  = num("accelerationConsistency")
	local swingEnergy= num("swingEnergy")
	local contact    = str("contactQuality")
	local shape      = str("shotShape")

	-- Readable path/face labels for debug panel
	local pathLabel: string = if clubPath > PATH_DEAD then "Right"
		elseif clubPath < -PATH_DEAD then "Left"
		else "Straight"
	local faceLabel: string = if faceAngle > FACE_DEAD then "Open"
		elseif faceAngle < -FACE_DEAD then "Closed"
		else "Square"

	if _lblPhase   then _lblPhase.Text   = "Phase: Released" end
	if _lblPower   then _lblPower.Text   = ("Power: %.0f%%"):format(power01 * 100) end
	if _lblPath    then _lblPath.Text    = ("Path: %s (%+.1f°)"):format(pathLabel, clubPath) end
	if _lblFace    then _lblFace.Text    = ("Face: %s (%+.1f°)"):format(faceLabel, faceAngle) end
	if _lblTempo   then _lblTempo.Text   = ("Tempo: %.2f"):format(tempoScore) end
	if _lblContact then _lblContact.Text = "Contact: " .. contact end
	if _lblShape   then _lblShape.Text   = "Shape: " .. shape end
	if _lblAccel   then _lblAccel.Text   = ("Accel: %.2f"):format(accelCons) end
	if _lblEnergy  then _lblEnergy.Text  = ("Energy: %.2f"):format(swingEnergy) end

	_updateFaceMeter(faceAngle)
	_showShotSummary(contact, clubPath, faceAngle, shape)
end

--- Update the Club row. Call from PlayableHoleControllerModule after each swing.
function SwingFeedbackHUDModule:SetClub(name: string)
	if _lblClub then _lblClub.Text = "Club: " .. name end
end

--- Update the Carry estimate row. Call from PlayableHoleControllerModule after each swing.
function SwingFeedbackHUDModule:SetCarryEstimate(yards: number)
	if _lblCarry then
		_lblCarry.Text = if yards > 0
			then ("Carry est: %d yds"):format(yards)
			else "Carry est: --"
	end
end

--- Update the Ball State row. Call from PlayableHoleControllerModule on DevPlayState events.
function SwingFeedbackHUDModule:SetBallState(state: string)
	if _lblBallState then _lblBallState.Text = "Ball: " .. state end
end

function SwingFeedbackHUDModule:ResetDisplay()
	if _lblPhase    then _lblPhase.Text    = "Phase: Idle" end
	if _lblPower    then _lblPower.Text    = "Power: --" end
	if _lblPath     then _lblPath.Text     = "Path: --" end
	if _lblFace     then _lblFace.Text     = "Face: --" end
	if _lblTempo    then _lblTempo.Text    = "Tempo: --" end
	if _lblContact  then _lblContact.Text  = "Contact: --" end
	if _lblShape    then _lblShape.Text    = "Shape: --" end
	if _lblAccel    then _lblAccel.Text    = "Accel: --" end
	if _lblEnergy   then _lblEnergy.Text   = "Energy: --" end
	if _faceMark then
		_faceMark.Position         = UDim2.new(0.5, 0, 0.5, 0)
		_faceMark.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	end
	if _summaryGui and _summaryGui.Parent then
		_summaryGui:Destroy()
		_summaryGui = nil
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
		print("[SwingFeedbackHUDModule] SwingDebugHUD ready (Milestone 3)")
	end
end

function SwingFeedbackHUDModule:Update(_dt: number) end

function SwingFeedbackHUDModule:Destroy()
	if _gui and _gui.Parent then _gui:Destroy() end
	if _summaryGui and _summaryGui.Parent then _summaryGui:Destroy() end
	_gui         = nil
	_summaryGui  = nil
	_lblPhase    = nil
	_lblPower    = nil
	_lblPath     = nil
	_lblFace     = nil
	_lblTempo    = nil
	_lblContact  = nil
	_lblShape    = nil
	_lblAccel    = nil
	_lblEnergy   = nil
	_lblClub     = nil
	_lblCarry    = nil
	_lblBallState= nil
	_faceMark    = nil
	_initialized = false
end

return SwingFeedbackHUDModule
