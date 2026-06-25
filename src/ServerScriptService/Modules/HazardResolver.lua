--!strict
-- HazardResolver — Server-only ModuleScript
-- Classifies the surface type at a world position by inspecting CollectionService-
-- tagged zone BaseParts. Zone parts must carry one of the "Zone_<TYPE>" tags and
-- define ground-level hazard areas. The canonical tag list and priority ordering
-- are the contract between HazardResolver and the course design team.
--
-- Zone priority (checked in order, first match wins):
--   OOB > WATER > SAND > GREEN > FAIRWAY > ROUGH
-- Y-floor fallback: pos.Y < OOB_Y_FLOOR always returns OOB (ball off the map).
-- No-zone fallback: returns FAIRWAY.
--
-- Usage: require this module in PhysicsService and call
--   HazardResolver:Init({}) once, then
--   HazardResolver:GetSurface(pos) on each ball landing.
-- TDD §4.2 (referenced as landing-surface dependency of PhysicsService).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Enums        = require(ReplicatedStorage.Shared.Modules.Enums)
local ScoringRules = require(ReplicatedStorage.Shared.Modules.ScoringRules)

-- ── Zone tag constants ─────────────────────────────────────────────────────
-- Course designers apply these tags to non-collidable BaseParts placed inside
-- each hole's Hazards (or Fairway) folder. Size and CFrame define the zone's
-- ground footprint; Y-extent is ignored (see _isInsideZone).

local TAG_OOB     = "Zone_OOB"
local TAG_WATER   = "Zone_WATER"
local TAG_SAND    = "Zone_SAND"
local TAG_GREEN   = "Zone_GREEN"
local TAG_FAIRWAY = "Zone_FAIRWAY"
local TAG_ROUGH   = "Zone_ROUGH"

-- Balls that land below this altitude are OOB (fell off the map).
local OOB_Y_FLOOR: number = -100

-- Priority table: checked top-to-bottom; first match wins.
-- Adding a new surface type here is the only change needed for new zone kinds.
type PriorityEntry = { tag: string, surface: string }
local PRIORITY: { PriorityEntry } = {
	{ tag = TAG_OOB,     surface = Enums.SurfaceType.OOB     },
	{ tag = TAG_WATER,   surface = Enums.SurfaceType.WATER   },
	{ tag = TAG_SAND,    surface = Enums.SurfaceType.SAND    },
	{ tag = TAG_GREEN,   surface = Enums.SurfaceType.GREEN   },
	{ tag = TAG_FAIRWAY, surface = Enums.SurfaceType.FAIRWAY },
	{ tag = TAG_ROUGH,   surface = Enums.SurfaceType.ROUGH   },
}

-- ── Module state ───────────────────────────────────────────────────────────

type ZoneEntry = { surface: string, part: BasePart }

-- Flat list of (surface, part) pairs, sorted by priority (OOB entries first).
local _zoneCache: { ZoneEntry } = {}

local _initialized = false

-- ── Module ─────────────────────────────────────────────────────────────────

local HazardResolver = {}
HazardResolver.__index = HazardResolver

-- ── Private ────────────────────────────────────────────────────────────────

-- XZ-only containment check using the part's local coordinate space.
-- Y is intentionally excluded: zone parts define 2D ground areas and terrain
-- height variation would cause false negatives with purely 3D AABB tests.
-- Rotated zone parts are handled correctly via :PointToObjectSpace.
local function _isInsideZone(part: BasePart, pos: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(pos)
	local half     = part.Size * 0.5
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Z) <= half.Z
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

-- Rebuilds the zone list from CollectionService. Inserts entries in PRIORITY
-- order so GetSurface can return the first match without a secondary sort.
-- Public so tests can force a rebuild after programmatically creating zones.
function HazardResolver:_buildZoneCache()
	table.clear(_zoneCache)
	for _, entry in ipairs(PRIORITY) do
		for _, inst in ipairs(CollectionService:GetTagged(entry.tag)) do
			if inst:IsA("BasePart") then
				table.insert(_zoneCache, {
					surface = entry.surface,
					part    = inst :: BasePart,
				})
			end
		end
	end
end

-- Returns the SurfaceType string for a world position.
-- Y-floor OOB check → live CollectionService scan in priority order → FAIRWAY default.
-- CollectionService:GetTagged is a synchronous data query (not an event) so it always
-- reflects the current tagged-part set without any caching or signal dependency.
function HazardResolver:GetSurface(pos: Vector3): string
	if pos.Y < OOB_Y_FLOOR then
		return Enums.SurfaceType.OOB
	end

	for _, entry in ipairs(PRIORITY) do
		for _, inst in ipairs(CollectionService:GetTagged(entry.tag)) do
			if inst:IsA("BasePart") then
				local part = inst :: BasePart
				-- Parts unparented without Destroy keep their tags; skip them.
				if not part.Parent then
					continue
				end
				if _isInsideZone(part, pos) then
					return entry.surface
				end
			end
		end
	end

	return Enums.SurfaceType.FAIRWAY
end

-- Returns stroke-penalty data for a surface type.
-- Mirrors ScoringRules.PENALTY_STROKES; dropBack signals the ball must be
-- replayed from its previous lie (used by GameService drop logic, Sprint 4+).
function HazardResolver:GetPenalty(surfaceType: string): { strokes: number, dropBack: boolean }
	local strokes: number = (ScoringRules.PENALTY_STROKES :: any)[surfaceType] or 0
	return {
		strokes  = strokes,
		dropBack = strokes > 0,
	}
end

function HazardResolver:Init(_dependencies: { [string]: any })
	if _initialized then
		return
	end
	_initialized = true
	-- GetSurface queries CollectionService:GetTagged live on every call, so no
	-- signal-based cache invalidation is needed. _buildZoneCache exists for
	-- callers that want an explicit snapshot (e.g. diagnostic tools).
	self:_buildZoneCache()
end

function HazardResolver:Update(_dt: number) end

function HazardResolver:Destroy()
	table.clear(_zoneCache)
	_initialized = false
end

return HazardResolver
