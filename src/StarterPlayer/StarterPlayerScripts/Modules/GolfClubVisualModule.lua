--!strict
-- GolfClubVisualModule — Client, Sprint 37.5
--
-- Manages a placeholder golf club Model that is physically attached to the character's
-- right hand via a Motor6D joint. Shaft and Head are welded to Grip, so only the
-- Motor6D.C0 needs updating each frame to animate the swing arc.
--
-- Swap path: replace _buildClubModel() with a version that clones a real asset from
-- ReplicatedStorage, then keep everything else unchanged.
--
-- Swing angle convention  (Rx rotation around HRP.RightVector):
--   shaft direction = -(cos θ · HRP.Up  +  sin θ · HRP.Backward)
--   ADDRESS_PITCH        +15°  → shaft mostly Down, slight Forward lean (head near ground)
--   BACKSWING_PITCH     −135°  → shaft Up and Behind  (full backswing)
--   FOLLOW_THROUGH_PITCH +100° → shaft Forward and Up (over lead shoulder)
--
-- Public API
--   Init()
--   AttachToCharacter(character: Model)
--   Detach()
--   Update(dt: number)
--   Destroy()

local SwingInputControllerModule = require(script.Parent.SwingInputControllerModule)

-- ─── Placement constants (tune these in Studio if positioning looks wrong) ────

local BASE_OFFSET_X: number =  1.30   -- right of HRP center  (+X = character's right)
local BASE_OFFSET_Y: number = -0.25   -- below HRP center; lower puts grip at right hip
local BASE_OFFSET_Z: number = -0.10   -- forward of HRP center (-Z = toward hole)

-- Absolute pitch angles for each swing phase.
local ADDRESS_PITCH:        number = math.rad(  8)   -- address pose (less fwd lean → shaft more vertical)
local BACKSWING_PITCH:      number = math.rad(-135)  -- full backswing peak
local FOLLOW_THROUGH_PITCH: number = math.rad( 100)  -- follow-through finish

local FOLLOW_DURATION:  number = 0.45    -- seconds for follow-through animation
local MAX_BACKSWING_PX: number = 260.0   -- mirrors SwingAnalyzerModule.MAX_BACKSWING_PIXELS

-- ─── Club geometry ────────────────────────────────────────────────────────────

-- Grip: short rubber handle.
-- Shaft: Cylinder (Size.X = length along local X; a -90° Z-roll in the Weld aligns
--        the cylinder axis with the down-shaft direction).
-- Head: flat box (X = face width, Y = thin, Z = depth).
local GRIP_SIZE  = Vector3.new(0.22, 0.70, 0.22)
local SHAFT_SIZE = Vector3.new(2.40, 0.09, 0.09)
local HEAD_SIZE  = Vector3.new(0.90, 0.11, 0.42)

local GRIP_HALF:  number = GRIP_SIZE.Y  / 2   -- 0.35
local SHAFT_HALF: number = SHAFT_SIZE.X / 2   -- 1.20
local HEAD_HALF:  number = HEAD_SIZE.Y  / 2   -- 0.055

-- Weld.C0 values (offsets in Grip's local -Y direction, i.e. down the club).
local SHAFT_WELD_C0: CFrame =
	CFrame.new(0, -(GRIP_HALF + SHAFT_HALF), 0)
	* CFrame.Angles(0, 0, -math.pi / 2)        -- -90° Z-roll: cylinder X axis → shaft direction

local HEAD_WELD_C0: CFrame =
	CFrame.new(0.07, -(GRIP_HALF + SHAFT_SIZE.X + HEAD_HALF), 0)

-- ─── Colors ───────────────────────────────────────────────────────────────────

local GRIP_COLOR:  Color3 = Color3.fromRGB(42,  28,  18)   -- dark leather
local SHAFT_COLOR: Color3 = Color3.fromRGB(192, 198, 205)  -- brushed steel
local HEAD_COLOR:  Color3 = Color3.fromRGB(38,  42,  48)   -- dark titanium

-- ─── Module state ─────────────────────────────────────────────────────────────

local _initialized:     boolean               = false
local _hrp:             BasePart?             = nil
local _handPart:        BasePart?             = nil
local _motor:           Motor6D?              = nil
local _clubModel:       Model?               = nil
local _backswingPeak:   number               = 0
local _followProgress:  number               = 0
local _followActive:    boolean              = false
local _pathBias:        number               = 0   -- mouse-X bias this frame (−1=left, +1=right)
local _pathBiasAtPeak:  number               = 0   -- X bias captured at downswing start
local _charConn:        RBXScriptConnection? = nil
local _clubTrail:       Trail?               = nil   -- club-head swing trail

-- ─── Module table ─────────────────────────────────────────────────────────────

local GolfClubVisualModule = {}
GolfClubVisualModule.__index = GolfClubVisualModule

-- ─── Private helpers ──────────────────────────────────────────────────────────

local function _makePart(name: string, size: Vector3, color: Color3): Part
	local p      = Instance.new("Part")
	p.Name       = name
	p.Size       = size
	p.Color      = color
	p.Material   = Enum.Material.SmoothPlastic
	p.Anchored   = false   -- driven by Motor6D + Weld; not free-floating
	p.CanCollide = false
	p.CastShadow = false
	p.Locked     = true
	return p
end

local function _weld(parent: Part, child: Part, c0: CFrame, name: string)
	local w  = Instance.new("Weld")
	w.Name   = name
	w.Part0  = parent
	w.Part1  = child
	w.C0     = c0
	w.C1     = CFrame.new()
	w.Parent = parent
end

--- Builds the GolfClub Model with Grip (PrimaryPart), Shaft, and Head all welded together.
--- To swap in a real asset later, replace only this function.
local function _buildClubModel(): Model
	local model      = Instance.new("Model")
	model.Name       = "GolfClub"

	local grip  = _makePart("Grip",  GRIP_SIZE,  GRIP_COLOR)
	local shaft = _makePart("Shaft", SHAFT_SIZE, SHAFT_COLOR)
	local head  = _makePart("Head",  HEAD_SIZE,  HEAD_COLOR)
	shaft.Shape = Enum.PartType.Cylinder   -- length axis = local X

	grip.Parent  = model
	shaft.Parent = model
	head.Parent  = model
	model.PrimaryPart = grip

	_weld(grip, shaft, SHAFT_WELD_C0, "ShaftWeld")
	_weld(grip, head,  HEAD_WELD_C0,  "HeadWeld")

	-- Swing trail: two attachments span the face width; enabled only during downswing
	local att0           = Instance.new("Attachment")
	att0.Name            = "SwingTrailAtt0"
	att0.Position        = Vector3.new( HEAD_SIZE.X * 0.42, 0, 0)
	att0.Parent          = head

	local att1           = Instance.new("Attachment")
	att1.Name            = "SwingTrailAtt1"
	att1.Position        = Vector3.new(-HEAD_SIZE.X * 0.42, 0, 0)
	att1.Parent          = head

	local swingTrail         = Instance.new("Trail")
	swingTrail.Name          = "ClubSwingTrail"
	swingTrail.Attachment0   = att0
	swingTrail.Attachment1   = att1
	swingTrail.Lifetime      = 0.10
	swingTrail.MinLength     = 0
	swingTrail.MaxLength     = 0
	swingTrail.FaceCamera    = false
	swingTrail.Color         = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(205, 218, 232)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	swingTrail.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.10),
		NumberSequenceKeypoint.new(0.40, 0.55),
		NumberSequenceKeypoint.new(1,    1.00),
	})
	swingTrail.WidthScale    = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	swingTrail.Enabled       = false
	swingTrail.Parent        = head

	return model
end

--- Returns the best hand part to attach to: RightHand (R15), Right Arm (R6), or HRP fallback.
local function _findHandPart(character: Model, hrp: BasePart): BasePart
	return (
		character:FindFirstChild("RightHand") or
		character:FindFirstChild("Right Arm") or
		hrp
	) :: BasePart
end

--- Creates the Motor6D on handPart that drives the Grip. Returns it parented and ready.
--- C0 is set to the address pose; Update() will override it every frame.
local function _attachMotor(handPart: BasePart, hrp: BasePart, grip: Part): Motor6D
	local motor  = Instance.new("Motor6D")
	motor.Name   = "GolfClubJoint"
	motor.Part0  = handPart
	motor.Part1  = grip
	motor.C1     = CFrame.new()   -- attachment at grip center
	motor.C0     = handPart.CFrame:Inverse()
	               * hrp.CFrame
	               * CFrame.new(BASE_OFFSET_X, BASE_OFFSET_Y, BASE_OFFSET_Z)
	               * CFrame.Angles(ADDRESS_PITCH, 0, 0)
	motor.Parent = handPart       -- Motor6D must be a child of Part0
	return motor
end

--- Returns Motor6D.C0 for the current swing state.
--- Internally computes the desired grip CFrame in HRP local space, then converts to
--- hand-local space: grip world CFrame = handPart.CFrame * C0 = hrp.CFrame * gripLocalCF.
local function _computeSwingC0(
	phase:      string,
	backswingT: number,   -- 0–1, real-time backswing progress
	downswingT: number,   -- 0–1, downswing progress (0 until downswing begins)
	followT:    number    -- 0–1, follow-through animation progress
): CFrame
	local hrp      = _hrp      :: BasePart
	local handPart = _handPart :: BasePart

	local px = BASE_OFFSET_X
	local py = BASE_OFFSET_Y
	local pz = BASE_OFFSET_Z
	local pitch: number
	local yaw:   number = 0

	if phase == "Backswing" then
		-- Interpolate from ADDRESS_PITCH to BACKSWING_PITCH as the drag grows.
		-- Mouse-X path bias adds a visible yaw that mirrors the draw/fade tendency.
		-- Grip also drifts back slightly (pz+) as the hands go back — more physical.
		pitch = ADDRESS_PITCH + backswingT * (BACKSWING_PITCH - ADDRESS_PITCH)
		yaw   = backswingT * math.rad(12) + _pathBias * backswingT * math.rad(7)
		py    = py + backswingT * 0.35
		pz    = pz + backswingT * 0.20   -- hands drift back with the club

	elseif phase == "Downswing" then
		-- Interpolate from the captured peak back to address.
		-- Path bias uses the frozen value from peak so downswing stays consistent.
		local peakPitch = ADDRESS_PITCH + _backswingPeak * (BACKSWING_PITCH - ADDRESS_PITCH)
		pitch = peakPitch + (ADDRESS_PITCH - peakPitch) * downswingT
		yaw   = _backswingPeak * math.rad(12) * (1 - downswingT)
		      + _pathBiasAtPeak * _backswingPeak * math.rad(7) * (1 - downswingT)
		py    = py + _backswingPeak * 0.35 * (1 - downswingT)
		pz    = pz + _backswingPeak * 0.20 * (1 - downswingT)   -- returns to address Z

	elseif phase == "Released" and followT < 1 then
		-- Interpolate from address to follow-through finish.
		pitch = ADDRESS_PITCH + followT * (FOLLOW_THROUGH_PITCH - ADDRESS_PITCH)
		yaw   = followT * math.rad(-25)   -- body unwinds left through impact
		px    = px - followT * 0.18       -- arm sweeps across body
		py    = py + followT * 0.40       -- hands finish high

	else
		pitch = ADDRESS_PITCH
	end

	local gripLocalCF = CFrame.new(px, py, pz) * CFrame.Angles(pitch, yaw, 0)
	return handPart.CFrame:Inverse() * hrp.CFrame * gripLocalCF
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function GolfClubVisualModule:Init()
	if _initialized then
		warn("[GolfClubVisual] Init called twice — skipping")
		return
	end
	_initialized    = true
	_backswingPeak  = 0
	_followProgress = 0
	_followActive   = false
	print("[GolfClubVisual] ready")
end

function GolfClubVisualModule:AttachToCharacter(character: Model)
	if not _initialized then return end
	GolfClubVisualModule:Detach()

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		warn("[GolfClubVisual] AttachToCharacter: HumanoidRootPart not found")
		return
	end

	local handPart = _findHandPart(character, hrp)
	local model    = _buildClubModel()
	local grip     = model.PrimaryPart :: Part
	local motor    = _attachMotor(handPart, hrp, grip)

	model.Parent = character

	_hrp       = hrp
	_handPart  = handPart
	_motor     = motor
	_clubModel = model

	local trailInst = model:FindFirstChild("ClubSwingTrail", true)
	_clubTrail = if trailInst and trailInst:IsA("Trail") then trailInst :: Trail else nil

	_charConn = character.AncestryChanged:Connect(function()
		if not character.Parent then GolfClubVisualModule:Detach() end
	end)

	print("[GolfClubVisual] attached to " .. character.Name .. " via " .. handPart.Name)
end

function GolfClubVisualModule:Detach()
	if _charConn   then _charConn:Disconnect(); _charConn = nil end
	if _motor      and _motor.Parent      then _motor:Destroy()     end
	if _clubModel  and _clubModel.Parent  then _clubModel:Destroy() end
	_motor          = nil
	_clubModel      = nil
	_hrp            = nil
	_handPart       = nil
	_clubTrail      = nil
	_backswingPeak  = 0
	_followProgress = 0
	_followActive   = false
	_pathBias       = 0
	_pathBiasAtPeak = 0
end

function GolfClubVisualModule:Update(dt: number)
	local hrp      = _hrp
	local handPart = _handPart
	local motor    = _motor
	if not hrp      or not hrp.Parent      then return end
	if not handPart or not handPart.Parent then return end
	if not motor    or not motor.Parent    then return end

	-- ── Read swing state ────────────────────────────────────────────────────────
	local swingState  = SwingInputControllerModule:GetSwingState()
	local phase       = swingState.phase
	local maxBackDist = swingState.maxBackswingDistance

	local backswingT: number
	if phase == "Backswing" then
		local delta = swingState.currentPosition.Y - swingState.startPosition.Y
		backswingT  = math.clamp(delta / MAX_BACKSWING_PX, 0, 1)
	else
		backswingT = math.clamp(maxBackDist / MAX_BACKSWING_PX, 0, 1)
	end

	-- ── Path bias from mouse X movement ────────────────────────────────────────
	-- Only meaningful during active swing; reset otherwise so idle pose is neutral.
	if phase == "Backswing" or phase == "Downswing" then
		local xDelta = swingState.currentPosition.X - swingState.startPosition.X
		_pathBias = math.clamp(xDelta / 90, -1, 1)
	else
		_pathBias = 0
	end

	-- ── Track backswing peak (captured once when downswing starts) ──────────────
	if phase == "Downswing" and _backswingPeak == 0 then
		_backswingPeak    = backswingT
		_pathBiasAtPeak   = _pathBias   -- freeze X bias at the transition
	end
	if phase == "Backswing" then
		_backswingPeak    = 0
		_pathBiasAtPeak   = 0
	end

	-- ── Downswing progress ──────────────────────────────────────────────────────
	local downswingT: number = 0
	if phase == "Downswing" and _backswingPeak > 0 then
		local peakDist = _backswingPeak * MAX_BACKSWING_PX
		local delta    = swingState.currentPosition.Y - swingState.startPosition.Y
		downswingT     = math.clamp(1 - delta / peakDist, 0, 1)
	end

	-- ── Follow-through timer ────────────────────────────────────────────────────
	-- Guard: only start if progress < 1. When the engine is stopped externally,
	-- phase stays "Released" permanently. Keeping progress at 1.0 on completion
	-- prevents the restart condition from firing every frame after the swing ends.
	if phase == "Released" and not _followActive and _followProgress < 1 then
		_followActive   = true
		_followProgress = 0
	elseif phase ~= "Released" then
		if _followActive then
			_followActive  = false
			_backswingPeak = 0
		end
		-- Reset when a new swing begins so follow-through works next shot.
		if phase == "Backswing" then
			_followProgress = 0
		end
	end

	if _followActive then
		_followProgress = math.min(_followProgress + dt / FOLLOW_DURATION, 1)
		if _followProgress >= 1 then
			_followActive  = false
			-- Stay at 1.0: keeps followT ≥ 1 so _computeSwingC0 falls through
			-- to the address pose (else branch), not the follow-through branch.
			_backswingPeak = 0
		end
	end

	-- ── Club-head trail: visible during downswing and early follow-through ──────
	if _clubTrail then
		_clubTrail.Enabled = (phase == "Downswing")
			or (phase == "Released" and _followProgress < 0.55)
	end

	-- ── Drive Motor6D ───────────────────────────────────────────────────────────
	-- During active swing: direct 1:1 mapping so the club mirrors the mouse.
	-- During return to address: gentle lerp so the club eases back smoothly.
	local targetC0 = _computeSwingC0(phase, backswingT, downswingT, _followProgress)
	local isActive = (phase == "Backswing")
		or (phase == "Downswing")
		or (phase == "Released" and _followProgress < 1.0)
	if isActive then
		motor.C0 = targetC0
	else
		motor.C0 = motor.C0:Lerp(targetC0, math.min(dt * 7, 1))
	end
end

function GolfClubVisualModule:Destroy()
	GolfClubVisualModule:Detach()
	_initialized = false
end

return GolfClubVisualModule
