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

local GRIP_COLOR:  Color3 = Color3.fromRGB(32,  20,  12)   -- dark rubber grip
local SHAFT_COLOR: Color3 = Color3.fromRGB(188, 196, 206)  -- brushed steel
-- HEAD_COLOR/HEAD_SIZE/HEAD_HALF/HEAD_WELD_C0 superseded by _headProfile() below.

-- ─── Per-category head geometry ───────────────────────────────────────────────
-- Returns (headSize, headColor, headMaterial, headReflectance,
--          headOffsetX, headOffsetZ, headAngleX, hasHosel, hasCrown, crownSize?)
-- Category values match ClubData: Driver | Wood | Hybrid | Iron | Wedge | Putter
local function _headProfile(category: string)

	if category == "Driver" then
		return Vector3.new(1.40, 0.85, 1.12),
			Color3.fromRGB(34, 38, 46), Enum.Material.Metal, 0.40,
			0.10, 0.0, 0,
			false, true, Vector3.new(1.26, 0.07, 0.98)

	elseif category == "Wood" then
		return Vector3.new(1.15, 0.70, 0.95),
			Color3.fromRGB(38, 42, 52), Enum.Material.Metal, 0.36,
			0.08, 0.0, 0,
			false, true, Vector3.new(1.04, 0.07, 0.84)

	elseif category == "Hybrid" then
		return Vector3.new(0.95, 0.55, 0.80),
			Color3.fromRGB(46, 50, 60), Enum.Material.Metal, 0.34,
			0.06, 0.0, math.rad(2),
			true, false, nil

	elseif category == "Wedge" then
		return Vector3.new(0.72, 0.40, 0.58),
			Color3.fromRGB(178, 184, 192), Enum.Material.Metal, 0.44,
			0.04, 0.05, math.rad(4),
			true, false, nil

	elseif category == "Putter" then
		return Vector3.new(1.12, 0.20, 0.46),
			Color3.fromRGB(30, 32, 38), Enum.Material.Metal, 0.18,
			0.0, 0.0, 0,
			false, false, nil

	else  -- Iron (IRON_4 through IRON_9)
		return Vector3.new(0.78, 0.28, 0.52),
			Color3.fromRGB(192, 198, 206), Enum.Material.Metal, 0.48,
			0.04, 0.05, math.rad(3),
			true, false, nil
	end
end

-- ─── Module state ─────────────────────────────────────────────────────────────

local _clubCategory:    string                = "Driver"   -- updated via SetClub()
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

--- Builds a GolfClub Model shaped for the given club category.
--- Grip is PrimaryPart; Shaft, Head, and optional Hosel/Crown are welded to it.
--- Swap in real assets later by replacing only this function.
local function _buildClubModel(category: string): Model
	local headSize, headColor, headMat, headRef,
	      headOffX, headOffZ, headAngX,
	      hasHosel, hasCrown, crownSize = _headProfile(category)

	local model   = Instance.new("Model")
	model.Name    = "GolfClub"

	-- ── Grip ──────────────────────────────────────────────────────────────────
	local grip          = _makePart("Grip", GRIP_SIZE, GRIP_COLOR)
	grip.Reflectance    = 0.05
	-- Grip cap: wider butt-end band for realistic proportions
	local gripCap       = _makePart("GripCap", Vector3.new(0.27, 0.16, 0.27),
		Color3.fromRGB(24, 14, 8))
	gripCap.Reflectance = 0.04

	-- ── Shaft ─────────────────────────────────────────────────────────────────
	local shaft         = _makePart("Shaft", SHAFT_SIZE, SHAFT_COLOR)
	shaft.Shape         = Enum.PartType.Cylinder
	shaft.Material      = Enum.Material.Metal
	shaft.Reflectance   = 0.55

	-- ── Head ──────────────────────────────────────────────────────────────────
	local headHalf    = headSize.Y / 2
	local headCenterY = -(GRIP_HALF + SHAFT_SIZE.X + headHalf)

	local head          = _makePart("Head", headSize, headColor)
	head.Material       = headMat
	head.Reflectance    = headRef

	-- ── Parent all primary parts ──────────────────────────────────────────────
	grip.Parent    = model
	gripCap.Parent = model
	shaft.Parent   = model
	head.Parent    = model
	model.PrimaryPart = grip

	-- ── Welds ─────────────────────────────────────────────────────────────────
	_weld(grip, shaft,   SHAFT_WELD_C0, "ShaftWeld")
	_weld(grip, gripCap, CFrame.new(0, GRIP_HALF - 0.06, 0), "GripCapWeld")
	_weld(grip, head,
		CFrame.new(headOffX, headCenterY, headOffZ) * CFrame.Angles(headAngX, 0, 0),
		"HeadWeld")

	-- ── Optional hosel: iron / wedge / hybrid ─────────────────────────────────
	-- Thin neck cylinder at the shaft-to-head junction.
	if hasHosel then
		local hosel       = _makePart("Hosel", Vector3.new(0.26, 0.11, 0.11), SHAFT_COLOR)
		hosel.Shape       = Enum.PartType.Cylinder
		hosel.Material    = Enum.Material.Metal
		hosel.Reflectance = 0.50
		hosel.Parent      = model
		_weld(grip, hosel,
			CFrame.new(headOffX * 0.5, -(GRIP_HALF + SHAFT_SIZE.X) - 0.13, headOffZ * 0.3)
			* CFrame.Angles(0, 0, -math.pi / 2),
			"HoselWeld")
	end

	-- ── Optional crown: driver / wood ─────────────────────────────────────────
	-- Flat plate on top of the head — the key visual of a modern driver.
	if hasCrown and crownSize then
		local cs          = crownSize :: Vector3
		local crown       = _makePart("Crown", cs, Color3.fromRGB(26, 28, 34))
		crown.Material    = Enum.Material.Metal
		crown.Reflectance = 0.22
		crown.Parent      = model
		_weld(grip, crown,
			CFrame.new(headOffX * 0.8, -(GRIP_HALF + SHAFT_SIZE.X) + cs.Y * 0.5, headOffZ - cs.Z * 0.04),
			"CrownWeld")
	end

	-- ── Putter sight lines ────────────────────────────────────────────────────
	-- Two thin white stripes on top of the blade help with aim.
	if category == "Putter" then
		local topY = -(GRIP_HALF + SHAFT_SIZE.X) + 0.015
		for i, zOff in ipairs({ -0.08, 0.08 }) do
			local sl        = _makePart("SightLine" .. i,
				Vector3.new(0.86, 0.025, 0.045), Color3.fromRGB(230, 230, 230))
			sl.Material     = Enum.Material.SmoothPlastic
			sl.Reflectance  = 0.08
			sl.Parent       = model
			_weld(grip, sl, CFrame.new(headOffX, topY, zOff), "SightLineWeld" .. i)
		end
	end

	-- ── Swing trail ───────────────────────────────────────────────────────────
	-- Two attachments span the face; enabled only during downswing.
	local trailSpan = headSize.X * 0.42

	local att0       = Instance.new("Attachment")
	att0.Name        = "SwingTrailAtt0"
	att0.Position    = Vector3.new( trailSpan, 0, 0)
	att0.Parent      = head

	local att1       = Instance.new("Attachment")
	att1.Name        = "SwingTrailAtt1"
	att1.Position    = Vector3.new(-trailSpan, 0, 0)
	att1.Parent      = head

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
	local model    = _buildClubModel(_clubCategory)
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

--- Rebuilds the club model for a new category without touching swing state.
--- Pass ClubData.category values: Driver | Wood | Hybrid | Iron | Wedge | Putter
function GolfClubVisualModule:SetClub(category: string)
	_clubCategory = category
	if not _initialized or not _hrp or not (_hrp :: BasePart).Parent then return end
	local handPart = _handPart
	if not handPart or not (handPart :: BasePart).Parent then return end
	-- Destroy existing model (keeps Motor6D parent alive long enough to nil _motor first)
	if _motor     and _motor.Parent     then _motor:Destroy() end
	if _clubModel and _clubModel.Parent then _clubModel:Destroy() end
	_motor     = nil
	_clubModel = nil
	_clubTrail = nil
	-- Rebuild for new category
	local hrp   = _hrp :: BasePart
	local model = _buildClubModel(_clubCategory)
	local grip  = model.PrimaryPart :: Part
	local motor = _attachMotor(handPart :: BasePart, hrp, grip)
	model.Parent = hrp.Parent   -- the character Model
	_motor     = motor
	_clubModel = model
	local trailInst = model:FindFirstChild("ClubSwingTrail", true)
	_clubTrail = if trailInst and trailInst:IsA("Trail") then trailInst :: Trail else nil
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
		-- Idle sway: gentle sine-wave oscillation at address makes the club feel alive.
		local t         = tick()
		local swayYaw   = math.sin(t * 0.65) * math.rad(1.0)
		local swayPitch = ADDRESS_PITCH + math.sin(t * 0.45) * math.rad(0.8)
		local swayCF    = CFrame.new(BASE_OFFSET_X, BASE_OFFSET_Y, BASE_OFFSET_Z)
			* CFrame.Angles(swayPitch, swayYaw, 0)
		local idleC0    = (handPart :: BasePart).CFrame:Inverse() * hrp.CFrame * swayCF
		motor.C0        = motor.C0:Lerp(idleC0, math.min(dt * 4.5, 1))
	end
end

function GolfClubVisualModule:Destroy()
	GolfClubVisualModule:Detach()
	_initialized = false
end

return GolfClubVisualModule
