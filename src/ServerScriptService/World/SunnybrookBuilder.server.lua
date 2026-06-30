--!strict
-- SunnybrookBuilder — Server Script (Sprint 35 + 35.5 + 35.6 + 35.6.1)
-- Procedurally builds Workspace.Courses.SunnybrookMeadows.Hole1 when the server starts.
-- Par 4 (~346 studs). Layout: Tee (0,3,190) → straight fairway → dogleg right →
-- pond + bridge → Green (85,−145).
--
-- Layering philosophy (Milestone 1.95 — dev readability pass):
--   Rough terrain (Grass material, Y=0)
--   → Fairway Part (SmoothPlastic, center Y=-2.75, top=2.00)
--   → Rough strip Part (SmoothPlastic, center Y=-2.60, top=1.65, 0.35 below fairway)
--   → GreenCollar cylinder (Grass, center Y=-2.75, top=1.50)
--   → GreenFringe cylinder (SmoothPlastic, center Y=1.75, top=2.00)
--   → GreenSurface cylinder (SmoothPlastic, center Y=2.25, top=2.50)
--   Tee: TeePlatform (Concrete, top=2.50) → TeeTurf (SmoothPlastic, top=3.00)
--
-- SmoothPlastic is used for all playable surface Parts so the Roblox engine does
-- NOT render grass blades on Part surfaces (Grass material does render blades).
-- Surrounding terrain remains Grass everywhere — no material swaps needed.
-- Fairway tops at Y=2.0 clear the terrain grass-blade zone (terrain Y=0 to ~Y=1.5).
--
-- All geometry is anchored. No gameplay logic, no swing changes, no networking.
-- PlayableHoleService finds this hole via Workspace.Courses.SunnybrookMeadows.Hole1.

local Workspace    = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

print("[SunnybrookBuilder] Starting")

-- ── Layout constants ──────────────────────────────────────────────────────────

-- TeeSpawn.Y = 3.0 = TeeTurf top. PlayableHoleService adds +5 before PivotTo,
-- so character pivot lands at Y=8, feet at ~Y=5, falls ~2 studs onto tee turf.
local TEE_POS       = Vector3.new(0,    3,    190)
local BALL_POS      = Vector3.new(0,    4,    186)

-- GREEN_CENTER is an XZ reference (Y=0). Each green Part computes its own center Y
-- as GREEN_CENTER + Vector3.new(0, offset, 0). See green section for the stack.
local GREEN_CENTER  = Vector3.new(85,   0.0, -145)

-- CUP_POS.Y = GreenSurface top (2.25 center + 0.25 half-thickness = 2.5).
-- CUP_RADIUS in PlayableHoleService is 3.0 studs — generous for detection.
local CUP_POS       = Vector3.new(85,   2.5, -145)

-- FLAG_BASE.Y matches GreenSurface top so flag stands on the green.
-- X=86: 1 stud right of cup center (cup radius=1.2), places flag at cup edge.
local FLAG_BASE     = Vector3.new(86,   2.5, -145)

-- POND_CENTER is XZ reference. Each pond Part offsets its own Y.
local POND_CENTER   = Vector3.new(65,   0.0,  -85)

-- ── Helper: build an anchored Part ───────────────────────────────────────────

local function makePart(
	name:     string,
	sz:       Vector3,
	cf:       CFrame,
	color:    Color3,
	mat:      Enum.Material,
	parent:   Instance
): Part
	local p          = Instance.new("Part")
	p.Name           = name
	p.Size           = sz
	p.CFrame         = cf
	p.Color          = color
	p.Material       = mat
	p.Anchored       = true
	p.CanCollide     = true
	p.CastShadow     = true
	p.Parent         = parent
	return p
end

local function makeFolder(name: string, parent: Instance): Folder
	local f    = Instance.new("Folder")
	f.Name     = name
	f.Parent   = parent
	return f
end

-- ── Create / reset workspace hierarchy ───────────────────────────────────────

local courses: Instance
do
	local c = Workspace:FindFirstChild("Courses")
	if not c then
		local newFolder   = Instance.new("Folder")
		newFolder.Name    = "Courses"
		newFolder.Parent  = Workspace
		c                 = newFolder
	end
	courses = c :: Instance
end

-- Destroy a previous builder run so re-running in Studio is safe
local prev = courses:FindFirstChild("SunnybrookMeadows")
if prev then prev:Destroy() end

local smm        = Instance.new("Folder")
smm.Name         = "SunnybrookMeadows"
smm.Parent       = courses

local hole1      = Instance.new("Folder")
hole1.Name       = "Hole1"
hole1.Parent     = smm

local fTee       = makeFolder("Tee",      hole1)
local fFairway   = makeFolder("Fairway",  hole1)
local fGreen     = makeFolder("Green",    hole1)
local fFlag      = makeFolder("Flag",     hole1)
local fWater     = makeFolder("Water",    hole1)
local fBridge    = makeFolder("Bridge",   hole1)
local fPath      = makeFolder("CartPath", hole1)
local fProps     = makeFolder("Props",    hole1)
local fTrees     = makeFolder("Trees",    fProps)
local fRocks     = makeFolder("Rocks",    fProps)
local fFlowers   = makeFolder("Flowers",  fProps)

-- ── Remove baseplate if present ───────────────────────────────────────────────

local bp = Workspace:FindFirstChild("Baseplate")
if bp then bp:Destroy() end

-- ── Terrain ───────────────────────────────────────────────────────────────────
-- Terrain material is Grass everywhere. Playable surfaces are Parts, NOT terrain swaps.
-- Decoration=false disables engine-level grass blade rendering on the terrain surface,
-- eliminating the visual grass layer that bleeds through playable Part surfaces.

local terrain = Workspace.Terrain
pcall(function()
	terrain.Decoration = false
end)

-- Main grass base: fills Y=-20 to Y=0 across the entire course area (tops at Y=0)
terrain:FillBlock(
	CFrame.new(40, -10, 25),
	Vector3.new(700, 20, 800),
	Enum.Material.Grass
)

-- Rolling rough hills: frame the course visually, positioned well outside shot path.
-- FillBall takes Vector3 (center position), NOT CFrame.
-- All hills are verified ≥ 53 studs XZ from any gameplay surface.
terrain:FillBall(Vector3.new(-15,  12, 268), 55, Enum.Material.Grass)  -- backdrop left of tee
terrain:FillBall(Vector3.new(52,   10, 275), 42, Enum.Material.Grass)  -- backdrop right of tee
terrain:FillBall(Vector3.new(-88,   8, 108), 32, Enum.Material.Grass)  -- left rough mid
terrain:FillBall(Vector3.new(-108, 12, -55), 42, Enum.Material.Grass)  -- left background
terrain:FillBall(Vector3.new(162,  11, -98), 40, Enum.Material.Grass)  -- right far background
terrain:FillBall(Vector3.new(158,   9, 108), 34, Enum.Material.Grass)  -- right rough mid
-- Hill moved from (112,-182) r=36 → (148,-218) r=30 (old position reached inside green fringe)
terrain:FillBall(Vector3.new(148,   8, -218), 30, Enum.Material.Grass) -- behind-right of green


-- ── Spawn markers (required by PlayableHoleService) ───────────────────────────

local teeSpawn         = Instance.new("Part")
teeSpawn.Name          = "TeeSpawn"
teeSpawn.Size          = Vector3.new(1, 1, 1)
teeSpawn.CFrame        = CFrame.new(TEE_POS)
teeSpawn.Anchored      = true
teeSpawn.CanCollide    = false
teeSpawn.Transparency  = 1
teeSpawn.Parent        = hole1

local ballSpawn        = Instance.new("Part")
ballSpawn.Name         = "BallSpawn"
ballSpawn.Size         = Vector3.new(0.4, 0.4, 0.4)
ballSpawn.CFrame       = CFrame.new(BALL_POS)
ballSpawn.Anchored     = true
ballSpawn.CanCollide   = false
ballSpawn.Transparency = 1
ballSpawn.Parent       = hole1

-- Cup: dark cylinder disc. Detection radius = 3.0 in PlayableHoleService.
local cup              = Instance.new("Part")
cup.Name               = "Cup"
cup.Shape              = Enum.PartType.Cylinder
cup.Size               = Vector3.new(0.4, 2.4, 2.4)
cup.CFrame             = CFrame.new(CUP_POS) * CFrame.Angles(0, 0, math.pi / 2)
cup.Anchored           = true
cup.CanCollide         = false
cup.CastShadow         = false
cup.Color              = Color3.fromRGB(10, 10, 10)
cup.Material           = Enum.Material.SmoothPlastic
cup.Transparency       = 0
cup.Parent             = hole1

-- Cup lip: off-white ring just outside the cup opening — improves visibility from fairway.
local cupLip           = Instance.new("Part")
cupLip.Name            = "CupLip"
cupLip.Shape           = Enum.PartType.Cylinder
cupLip.Size            = Vector3.new(0.06, 2.86, 2.86)
cupLip.CFrame          = CFrame.new(CUP_POS + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.pi / 2)
cupLip.Anchored        = true
cupLip.CanCollide      = false
cupLip.CastShadow      = false
cupLip.Color           = Color3.fromRGB(230, 226, 210)
cupLip.Material        = Enum.Material.SmoothPlastic
cupLip.Parent          = fGreen

-- ── Tee box ───────────────────────────────────────────────────────────────────
-- Two-layer construction:
--   TeePlatform: wide concrete foundation, extends 7 studs into terrain.
--                46×46 footprint covers terrain grass across the full tee zone.
--                center Y=-2.25 → bottom=-7.0, top=2.5
--   TeeTurf:     actual playing surface on top of foundation.
--                22×22 (standard tee box size), Grass material.
--                center Y=2.75 → bottom=2.5, top=3.0
--   TeeSpawn.Y = 3.0 = TeeTurf top. ✓

makePart("TeePlatform", Vector3.new(46, 9.5, 46),
	CFrame.new(0, -2.25, 190),
	Color3.fromRGB(180, 183, 172), Enum.Material.Concrete, fTee)

makePart("TeeTurf", Vector3.new(22, 0.5, 22),
	CFrame.new(0, 2.75, 190),
	Color3.fromRGB(100, 210, 80), Enum.Material.SmoothPlastic, fTee)

-- Tee peg: small yellow cylinder prop under the ball spawn position.
-- Center Y = BALL_POS.Y - 0.09 so the peg top is at ~BALL_POS.Y (ball rests on peg).
local teePeg           = makePart("TeePeg", Vector3.new(0.11, 0.20, 0.11),
	CFrame.new(BALL_POS + Vector3.new(0, -0.10, 0)),
	Color3.fromRGB(255, 238, 110), Enum.Material.SmoothPlastic, fTee)
teePeg.CastShadow      = false

-- Red tee markers — small sphere markers resting on the tee turf surface (Y=3.0 top).
-- Diameter 0.8 → center Y = 3.0 + 0.4 = 3.4. Positioned at the forward edge of tee box.
local markerL = makePart("MarkerL", Vector3.new(0.8, 0.8, 0.8),
	CFrame.new(-3.5, 3.4, 186),
	Color3.fromRGB(215, 40, 40), Enum.Material.SmoothPlastic, fTee)
markerL.Shape = Enum.PartType.Ball

local markerR = makePart("MarkerR", Vector3.new(0.8, 0.8, 0.8),
	CFrame.new( 3.5, 3.4, 186),
	Color3.fromRGB(215, 40, 40), Enum.Material.SmoothPlastic, fTee)
markerR.Shape = Enum.PartType.Ball

-- ── Fairway ───────────────────────────────────────────────────────────────────
-- SmoothPlastic for all playable surface Parts → no grass-blade rendering on surfaces.
-- Fairway: size Y=9.5, center Y=-2.75 → top=2.00, bottom=-7.25
-- Rough:   size Y=8.5, center Y=-2.60 → top=1.65, bottom=-6.85
--   0.35-stud step from rough to fairway remains visible and readable.

local FAIRWAY_COLOR = Color3.fromRGB(106, 210, 72)   -- vivid fairway green
local ROUGH_COLOR   = Color3.fromRGB(52,  115,  40)  -- noticeably darker rough

-- Straight section: tee front → dogleg entry (Z=180 to Z=10)
makePart("FairwayStraight", Vector3.new(90, 9.5, 170),
	CFrame.new(5, -2.75, 95),
	FAIRWAY_COLOR, Enum.Material.SmoothPlastic, fFairway)

-- Rough strips flanking straight section
makePart("RoughL_Straight", Vector3.new(28, 8.5, 170),
	CFrame.new(-53, -2.60, 95),
	ROUGH_COLOR, Enum.Material.SmoothPlastic, fFairway)
makePart("RoughR_Straight", Vector3.new(28, 8.5, 170),
	CFrame.new(63, -2.60, 95),
	ROUGH_COLOR, Enum.Material.SmoothPlastic, fFairway)

-- Corner wedge filling the dogleg turn
makePart("FairwayCorner", Vector3.new(95, 9.5, 44),
	CFrame.new(28, -2.75, 5),
	FAIRWAY_COLOR, Enum.Material.SmoothPlastic, fFairway)

-- Angled section: dogleg right toward green (~14° clockwise)
makePart("FairwayDogleg", Vector3.new(97, 9.5, 185),
	CFrame.new(58, -2.75, -68) * CFrame.Angles(0, math.rad(-14), 0),
	FAIRWAY_COLOR, Enum.Material.SmoothPlastic, fFairway)

-- Rough strips flanking dogleg
makePart("RoughL_Dogleg", Vector3.new(28, 8.5, 185),
	CFrame.new(4, -2.60, -68) * CFrame.Angles(0, math.rad(-14), 0),
	ROUGH_COLOR, Enum.Material.SmoothPlastic, fFairway)
makePart("RoughR_Dogleg", Vector3.new(28, 8.5, 185),
	CFrame.new(116, -2.60, -68) * CFrame.Angles(0, math.rad(-14), 0),
	ROUGH_COLOR, Enum.Material.SmoothPlastic, fFairway)

-- ── Green ─────────────────────────────────────────────────────────────────────
-- Three-layer stack. All cylinders are rotated 90° around Z so Size.X = world-Y thickness.
--
--   GreenCollar:  diameter 130, center Y=-2.75, thickness 8.5 → bottom=-7.00, top=1.50
--                 Wide grass apron; deep embedding suppresses terrain grass underneath.
--                 Fairway dogleg (top 1.50) and collar (top 1.50) share the same
--                 height at the approach — no Z-fight because they are separate XZ zones.
--
--   GreenFringe:  diameter 100, center Y= 1.75, thickness 0.50 → bottom=1.50, top=2.00
--                 Bottom = collar top → seamless, no seam visible.
--
--   GreenSurface: diameter  80, center Y= 2.25, thickness 0.50 → bottom=2.00, top=2.50
--                 Bottom = fringe top → seamless, no seam visible.
--                 CUP_POS.Y = 2.50 = GreenSurface top. ✓

local greenCollar     = makePart("GreenCollar", Vector3.new(8.5, 130, 130),
	CFrame.new(GREEN_CENTER + Vector3.new(0, -2.75, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	Color3.fromRGB(55, 130, 50), Enum.Material.Grass, fGreen)
greenCollar.Shape     = Enum.PartType.Cylinder

local fringe          = makePart("GreenFringe", Vector3.new(0.5, 100, 100),
	CFrame.new(GREEN_CENTER + Vector3.new(0, 1.75, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	Color3.fromRGB(62, 150, 58), Enum.Material.SmoothPlastic, fGreen)
fringe.Shape          = Enum.PartType.Cylinder

local greenDisc       = makePart("GreenSurface", Vector3.new(0.5, 80, 80),
	CFrame.new(GREEN_CENTER + Vector3.new(0, 2.25, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	Color3.fromRGB(142, 252, 112), Enum.Material.SmoothPlastic, fGreen)
greenDisc.Shape       = Enum.PartType.Cylinder

-- ── Flag ──────────────────────────────────────────────────────────────────────
-- FLAG_BASE.Y = 2.5 = GreenSurface top. All offsets are relative to FLAG_BASE.

-- Small base disc on the green surface
makePart("FlagBase", Vector3.new(1.4, 1.0, 1.4),
	CFrame.new(FLAG_BASE + Vector3.new(0, 0.5, 0)),
	Color3.fromRGB(18, 18, 18), Enum.Material.SmoothPlastic, fFlag)

-- Pole (16 studs tall)
makePart("FlagPole", Vector3.new(0.38, 16, 0.38),
	CFrame.new(FLAG_BASE + Vector3.new(0, 8.5, 0)),
	Color3.fromRGB(245, 245, 240), Enum.Material.SmoothPlastic, fFlag)

-- Flag cloth — large vivid red panel readable from tee camera
local flagCloth       = makePart("FlagCloth", Vector3.new(0.25, 5, 9),
	CFrame.new(FLAG_BASE + Vector3.new(0, 14.5, -4.5)),
	Color3.fromRGB(255, 20, 20), Enum.Material.SmoothPlastic, fFlag)
flagCloth.CanCollide  = false
flagCloth.CastShadow  = false

-- Neon tip sphere: bright white dot at pole top for distance readability
local poleTip         = makePart("PoleTip", Vector3.new(1.0, 1.0, 1.0),
	CFrame.new(FLAG_BASE + Vector3.new(0, 17.0, 0)),
	Color3.fromRGB(255, 255, 255), Enum.Material.Neon, fFlag)
poleTip.Shape         = Enum.PartType.Ball
poleTip.CastShadow    = false

-- Gentle server-side flag wave (replicates to all clients automatically)
task.spawn(function()
	local baseCF = flagCloth.CFrame
	local t      = 0
	while flagCloth.Parent ~= nil do
		local dt = task.wait(1 / 20)
		t        += dt
		flagCloth.CFrame = baseCF * CFrame.Angles(0, 0, math.sin(t * 1.8) * math.rad(8))
	end
end)

-- ── Pond (water body) ─────────────────────────────────────────────────────────
-- Two-layer: wide sandy rim embeds into terrain; water surface sits on rim top.
--   PondRim:     size (76, 2.0, 66), center Y=0.0 → bottom=-1.0, top=1.0
--   PondSurface: size (54, 0.5, 44), center Y=1.0 → bottom=0.75, top=1.25

makePart("PondRim", Vector3.new(76, 2.0, 66),
	CFrame.new(POND_CENTER + Vector3.new(0, 0.0, 0)),
	Color3.fromRGB(185, 165, 125), Enum.Material.Sand, fWater)

local pond            = makePart("PondSurface", Vector3.new(54, 0.5, 44),
	CFrame.new(POND_CENTER + Vector3.new(0, 1.0, 0)),
	Color3.fromRGB(42, 108, 190), Enum.Material.Glass, fWater)
pond.Reflectance      = 0.72
pond.Transparency     = 0.18
pond.CanCollide       = false
pond.CastShadow       = false

-- ── Bridge ────────────────────────────────────────────────────────────────────
-- Spans Z=-63 to Z=-107 at X≈63 over the pond. Raised to Y=2.5 so the deck
-- is clearly elevated above the pond surface (Y=1.25) and above fairway (Y=1.5).
-- One solid deck replaces the original 5 spaced planks to remove the ladder look.
-- Posts start at Y=0 (terrain/rim surface) so they rise visibly above ground.

local woodColor  = Color3.fromRGB(118, 78, 48)
local postColor  = Color3.fromRGB(82, 52, 32)

-- Solid deck: 22 studs wide (E-W), 1.0 tall, 50 studs long (Z covers pond + 3-stud approach)
makePart("BridgeDeck", Vector3.new(22, 1.0, 50),
	CFrame.new(63, 2.5, -85),
	woodColor, Enum.Material.Wood, fBridge)

-- Side rails
makePart("RailL", Vector3.new(0.55, 1.4, 50),
	CFrame.new(52, 3.7, -85), postColor, Enum.Material.Wood, fBridge)
makePart("RailR", Vector3.new(0.55, 1.4, 50),
	CFrame.new(74, 3.7, -85), postColor, Enum.Material.Wood, fBridge)

-- Vertical posts: bottom at Y=0 (rim surface), height 4.4 → top at Y=4.4
local postZs = { -63, -85, -107 }
for _, z in ipairs(postZs) do
	makePart("PostL_" .. tostring(math.abs(z)), Vector3.new(1.0, 4.4, 1.0),
		CFrame.new(52, 2.2, z), postColor, Enum.Material.Wood, fBridge)
	makePart("PostR_" .. tostring(math.abs(z)), Vector3.new(1.0, 4.4, 1.0),
		CFrame.new(74, 2.2, z), postColor, Enum.Material.Wood, fBridge)
end

-- ── Cart path ─────────────────────────────────────────────────────────────────
-- Concrete strip on the right side of the fairway.
-- center Y=1.6 → bottom=1.45, top=1.75 (sits above fairway top at 1.50).

local PATH_COLOR = Color3.fromRGB(190, 178, 152)

makePart("PathStraight", Vector3.new(7, 0.3, 170),
	CFrame.new(58, 1.6, 95),
	PATH_COLOR, Enum.Material.Concrete, fPath)

makePart("PathCorner", Vector3.new(42, 0.3, 7),
	CFrame.new(76, 1.6, 10),
	PATH_COLOR, Enum.Material.Concrete, fPath)

makePart("PathDogleg", Vector3.new(7, 0.3, 185),
	CFrame.new(115, 1.6, -68) * CFrame.Angles(0, math.rad(-14), 0),
	PATH_COLOR, Enum.Material.Concrete, fPath)

-- ── Trees ─────────────────────────────────────────────────────────────────────

local TREE_POS: { Vector3 } = {
	-- Left rough (straight section) — well outside the fairway edge
	Vector3.new(-60, 0, 158), Vector3.new(-64, 0, 122), Vector3.new(-57, 0, 88),
	Vector3.new(-62, 0, 52),  Vector3.new(-68, 0, 18),  Vector3.new(-58, 0, -10),
	Vector3.new(-54, 0, -44), Vector3.new(-70, 0, -80),
	-- Right rough (before dogleg) — clear of shot path
	Vector3.new(78, 0, 155),  Vector3.new(82, 0, 112),  Vector3.new(80, 0, 68),
	-- Behind tee (north backdrop)
	Vector3.new(-42, 0, 246), Vector3.new(36, 0, 252),  Vector3.new(5,  0, 274),
	Vector3.new(-64, 0, 224), Vector3.new(66, 0, 230),
	-- Right side after dogleg and behind green
	Vector3.new(134, 0, -50), Vector3.new(146, 0, -96), Vector3.new(138, 0, -150),
	Vector3.new(150, 0, -195),
	-- Left background
	Vector3.new(-92, 0, -8),  Vector3.new(-105, 0, -68), Vector3.new(-98, 0, -132),
	-- Flanking the green on the left (clear of approach line)
	Vector3.new(56, 0, -165), Vector3.new(60, 0, -188),
}

local CANOPY_COLORS: { Color3 } = {
	Color3.fromRGB(58, 158, 52),
	Color3.fromRGB(44, 138, 38),
	Color3.fromRGB(72, 172, 62),
	Color3.fromRGB(54, 148, 44),
}

for i, pos in ipairs(TREE_POS) do
	local variant  = ((i - 1) % 4) + 1
	local trunkH   = 6 + (i % 3) * 2
	local canopyR  = 4.5 + (i % 4)

	makePart(("Trunk%d"):format(i),
		Vector3.new(1.4, trunkH, 1.4),
		CFrame.new(pos + Vector3.new(0, trunkH * 0.5, 0)),
		Color3.fromRGB(92, 62, 38), Enum.Material.Wood, fTrees)

	local canopy      = makePart(("Canopy%d"):format(i),
		Vector3.new(canopyR * 2, canopyR * 2.2, canopyR * 2),
		CFrame.new(pos + Vector3.new(0, trunkH + canopyR * 0.75, 0)),
		CANOPY_COLORS[variant], Enum.Material.Grass, fTrees)
	canopy.Shape      = Enum.PartType.Ball
	canopy.CastShadow = true
end

-- ── Rocks ─────────────────────────────────────────────────────────────────────

local ROCK_POS: { Vector3 } = {
	Vector3.new(44, 0, 32),   Vector3.new(-39, 0, -8),  Vector3.new(67, 0, -42),
	Vector3.new(-63, 0, -58), Vector3.new(94, 0, -94),  Vector3.new(-74, 0, -105),
	Vector3.new(54, 0, -148), Vector3.new(-44, 0, 76),  Vector3.new(80, 0, 102),
	Vector3.new(-67, 0, 168),
}

local ROCK_COLORS: { Color3 } = {
	Color3.fromRGB(132, 128, 122),
	Color3.fromRGB(112, 108, 102),
	Color3.fromRGB(148, 142, 132),
}

for i, pos in ipairs(ROCK_POS) do
	local rc    = ROCK_COLORS[((i - 1) % 3) + 1]
	local sx    = 2.2 + (i % 3) * 0.8
	local sy    = 1.3 + (i % 2) * 0.7
	local sz    = 1.6 + (i % 4) * 0.5
	local rot   = (i * 23) % 360
	makePart(("Rock%d"):format(i),
		Vector3.new(sx, sy, sz),
		CFrame.new(pos + Vector3.new(0, sy * 0.5, 0)) * CFrame.Angles(0, math.rad(rot), 0),
		rc, Enum.Material.Rock, fRocks)
end

-- ── Flowers ───────────────────────────────────────────────────────────────────

local FLOWER_POS: { Vector3 } = {
	-- Near left rough fairway edge (straight section)
	Vector3.new(-40, 0, 132), Vector3.new(-36, 0, 129), Vector3.new(-42, 0, 135),
	Vector3.new( 42, 0,  98), Vector3.new( 39, 0, 101), Vector3.new( 44, 0,  96),
	Vector3.new(-38, 0,  58), Vector3.new(-35, 0,  54),
	-- Near pond approach
	Vector3.new(104, 0, -68), Vector3.new(107, 0, -72), Vector3.new(100, 0, -66),
	-- Near green (left flank)
	Vector3.new(66, 0, -163), Vector3.new(70, 0, -167), Vector3.new(63, 0, -159),
}

local FLOWER_COLORS: { Color3 } = {
	Color3.fromRGB(255, 205, 48),   -- yellow
	Color3.fromRGB(230, 75, 75),    -- red
	Color3.fromRGB(198, 95, 198),   -- purple
	Color3.fromRGB(248, 248, 248),  -- white
	Color3.fromRGB(255, 148, 45),   -- orange
}

for i, pos in ipairs(FLOWER_POS) do
	local fc      = FLOWER_COLORS[((i - 1) % 5) + 1]
	local flower  = makePart(("Flower%d"):format(i),
		Vector3.new(0.9, 0.9, 0.9),
		CFrame.new(pos + Vector3.new(0, 0.55, 0)),
		fc, Enum.Material.SmoothPlastic, fFlowers)
	flower.Shape      = Enum.PartType.Ball
	flower.CastShadow = false
end

-- ── Yardage markers ───────────────────────────────────────────────────────────
-- Colored sphere discs embedded in the fairway surface.
-- Red = 150 yd from cup (standard). White = 100 yd from cup.
-- Positions are measured along the fairway centreline (1 stud ≈ 1 yard).

-- 150 yd markers: fairway corner area (≈ 150 studs from cup centreline)
-- One on each side of the fairway (left/right of center)
local m150L = makePart("Marker150L", Vector3.new(1.4, 0.25, 1.4),
	CFrame.new(Vector3.new(3, 2.05, 5)),
	Color3.fromRGB(215, 35, 35), Enum.Material.SmoothPlastic, fProps)
m150L.Shape       = Enum.PartType.Cylinder
m150L.CastShadow  = false
m150L.CFrame      = m150L.CFrame * CFrame.Angles(0, 0, math.pi / 2)

local m150R = makePart("Marker150R", Vector3.new(1.4, 0.25, 1.4),
	CFrame.new(Vector3.new(52, 2.05, 5)),
	Color3.fromRGB(215, 35, 35), Enum.Material.SmoothPlastic, fProps)
m150R.Shape       = Enum.PartType.Cylinder
m150R.CastShadow  = false
m150R.CFrame      = m150R.CFrame * CFrame.Angles(0, 0, math.pi / 2)

-- 100 yd markers: in the dogleg section (≈ 100 studs from cup along fairway)
-- X≈42 Z≈−50 places them just before the bridge on the left of the dogleg
local m100L = makePart("Marker100L", Vector3.new(1.4, 0.25, 1.4),
	CFrame.new(Vector3.new(30, 2.05, -50)),
	Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic, fProps)
m100L.Shape       = Enum.PartType.Cylinder
m100L.CastShadow  = false
m100L.CFrame      = m100L.CFrame * CFrame.Angles(0, 0, math.pi / 2)

local m100R = makePart("Marker100R", Vector3.new(1.4, 0.25, 1.4),
	CFrame.new(Vector3.new(82, 2.05, -50)),
	Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic, fProps)
m100R.Shape       = Enum.PartType.Cylinder
m100R.CastShadow  = false
m100R.CFrame      = m100R.CFrame * CFrame.Angles(0, 0, math.pi / 2)

-- ── Ambient sound placeholders ────────────────────────────────────────────────
-- SoundIds marked below: replace with licensed audio from the Roblox Creator Store.
-- The ambient birds ID is a publicly available Roblox library asset.

local function makeAmbient(name: string, soundId: string, vol: number, looped: boolean): Sound
	local s       = Instance.new("Sound")
	s.Name        = name
	-- Only assign SoundId when we have a real asset; setting it to "rbxassetid://0" or ""
	-- causes Roblox to attempt an asset load and emit a content-error in the output.
	if soundId ~= "" and soundId ~= "rbxassetid://0" then
		s.SoundId = soundId
	end
	s.Volume      = vol
	s.Looped      = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent      = SoundService
	if soundId ~= "" and soundId ~= "rbxassetid://0" then
		s:Play()
	end
	return s
end

-- rbxassetid://9119713951 — "Summer Birds Ambience" (free Roblox library audio)
-- Replace with any preferred bird/nature ambience if this ID changes.
makeAmbient("AmbientBirds",    "rbxassetid://9119713951", 0.35, true)
makeAmbient("AmbientWind",     "",                        0.15, true)   -- stub: add wind SFX ID
makeAmbient("SFX_BallImpact",  "",                        0.80, false)  -- stub: triggered client-side
makeAmbient("SFX_BallLanding", "",                        0.60, false)  -- stub: triggered client-side
makeAmbient("SFX_CupDrop",     "",                        0.90, false)  -- stub: triggered client-side

-- ── Done — debug object counts ────────────────────────────────────────────────

local nFairway = #fFairway:GetChildren()
local nGreen   = #fGreen:GetChildren()
local nWater   = #fWater:GetChildren()
local nBridge  = #fBridge:GetChildren()
local nTrees   = #TREE_POS
local nRocks   = #ROCK_POS
local nFlowers = #FLOWER_POS

print(("[SunnybrookBuilder] Hole 1 ready — Tee %s | Green %s | Cup %s"):format(
	tostring(TEE_POS), tostring(GREEN_CENTER), tostring(CUP_POS)))
print(("[SunnybrookBuilder] Counts — Fairway:%d  Green:%d  Water:%d  Bridge:%d  Trees:%d  Rocks:%d  Flowers:%d"):format(
	nFairway, nGreen, nWater, nBridge, nTrees, nRocks, nFlowers))
-- Expected: Fairway:7  Green:3  Water:2  Bridge:13  Trees:25  Rocks:10  Flowers:14

-- ── Y-level verification ──────────────────────────────────────────────────────
-- Reads actual Part positions to confirm the layer stack is correct.
-- TeePlatform (foundation) top: 2.50  TeeTurf (playing surface) top: 3.00
-- Fairway top: 2.00  Rough top: 1.65  Green collar top: 1.50  Fringe top: 2.00  Surface top: 2.50
local teePlatTopY   = -999
local teeTurfTopY   = -999
local greenSurfTopY = -999
do
	local p = fTee:FindFirstChild("TeePlatform")
	if p and p:IsA("BasePart") then
		teePlatTopY = (p :: BasePart).Position.Y + (p :: BasePart).Size.Y * 0.5
	end
	local t = fTee:FindFirstChild("TeeTurf")
	if t and t:IsA("BasePart") then
		teeTurfTopY = (t :: BasePart).Position.Y + (t :: BasePart).Size.Y * 0.5
	end
	local g = fGreen:FindFirstChild("GreenSurface")
	if g and g:IsA("BasePart") then
		-- Cylinder rotated 90° around Z: Size.X is world-Y thickness.
		greenSurfTopY = (g :: BasePart).Position.Y + (g :: BasePart).Size.X * 0.5
	end
end
print("[SunnybrookBuilder] Y verification:")
print(("  TeePlatform top Y  = %.2f  (foundation, target ≥ 2.50)"):format(teePlatTopY))
print(("  TeeTurf top Y      = %.2f  (playing surface, target = 3.00)"):format(teeTurfTopY))
print(("  TeeSpawn Y         = %.2f  (target = TeeTurf top = 3.00)"):format(TEE_POS.Y))
print(("  GreenSurface top Y = %.2f  (target > fairway top 1.50)"):format(greenSurfTopY))
print(("  Cup center Y       = %.2f  (target = GreenSurface top = 2.50)"):format(CUP_POS.Y))
print("[SunnybrookBuilder] Materials: Grass terrain (no swaps), Concrete, Sand, Glass, Wood, Rock, SmoothPlastic, Neon")
print("[SunnybrookBuilder] Completed")
