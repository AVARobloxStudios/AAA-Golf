--!strict
-- Sprint4Test — Temporary server smoke test for Sprint 4 HazardResolver.
-- Safe to delete after Sprint 4 sign-off.
--
-- What is tested:
--   Module API, Y-floor OOB detection, FAIRWAY default (no zones),
--   zone detection for all 6 SurfaceTypes, priority ordering (OOB > WATER > SAND),
--   destroyed-part resilience, GetPenalty values for every surface.
--
-- No player required. All tests are synchronous. Temporary Parts are created in
-- Workspace, used for detection tests, then destroyed — no persistent side effects.

local CollectionService   = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local HazardResolver = require(ServerScriptService.Modules.HazardResolver)

local TAG = "[Sprint4Test]"

-- ── Helpers ────────────────────────────────────────────────────────────────

local passed = 0
local failed = 0

local function pass(label: string)
	passed += 1
	print(TAG .. " PASS  " .. label)
end

local function fail(label: string, reason: string)
	failed += 1
	warn(TAG .. " FAIL  " .. label .. "  (" .. reason .. ")")
end

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		pass(label)
	else
		fail(label, tostring(err))
	end
end

-- Creates a non-collidable BasePart in Workspace, tags it, and returns it.
-- The caller is responsible for destroying it after the relevant test.
local function makeZonePart(tag: string, pos: Vector3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name        = "TestZone_" .. tag
	part.Size        = size
	part.CFrame      = CFrame.new(pos)
	part.Anchored    = true
	part.CanCollide  = false
	part.Transparency = 1
	part.Parent      = workspace
	CollectionService:AddTag(part, tag)
	return part
end

-- A position is "outside" a zone centred at (1000, 0, 1000) with size (50, 2, 50).
-- Tests that default to FAIRWAY when no zone overlaps use this position.
local OUTSIDE_ALL_ZONES = Vector3.new(0, 10, 0)

-- ── Module-level checks ────────────────────────────────────────────────────

check("HazardResolver: module loads without error", function()
	assert(HazardResolver ~= nil)
end)

check("HazardResolver: GetSurface method exists", function()
	assert(type(HazardResolver.GetSurface) == "function", "GetSurface missing")
end)

check("HazardResolver: GetPenalty method exists", function()
	assert(type(HazardResolver.GetPenalty) == "function", "GetPenalty missing")
end)

check("HazardResolver: _buildZoneCache method exists", function()
	assert(type(HazardResolver._buildZoneCache) == "function", "_buildZoneCache missing")
end)

check("HazardResolver: Init runs without error", function()
	HazardResolver:Init({})
end)

-- ── Y-floor OOB (no zone parts required) ──────────────────────────────────

check("GetSurface: pos.Y < -100 → OOB (fell off the map)", function()
	local surface = HazardResolver:GetSurface(Vector3.new(0, -200, 0))
	assert(surface == "OOB",
		("expected OOB, got %s"):format(surface))
end)

check("GetSurface: pos.Y = -101 → OOB (exactly one below floor)", function()
	local surface = HazardResolver:GetSurface(Vector3.new(0, -101, 0))
	assert(surface == "OOB",
		("expected OOB, got %s"):format(surface))
end)

check("GetSurface: pos.Y = -100 (on floor) → not OOB (zone floor is exclusive)", function()
	-- Y exactly at -100 is NOT below the floor; should fall through to FAIRWAY default.
	local surface = HazardResolver:GetSurface(Vector3.new(0, -100, 0))
	assert(surface ~= "OOB",
		"expected non-OOB at exactly Y=-100 (floor threshold is strictly less-than)")
end)

-- ── FAIRWAY default (no zones present for these positions) ─────────────────

check("GetSurface: no matching zone → FAIRWAY default", function()
	local surface = HazardResolver:GetSurface(OUTSIDE_ALL_ZONES)
	assert(surface == "FAIRWAY",
		("expected FAIRWAY (default), got %s"):format(surface))
end)

-- ── Zone detection — one surface type at a time ────────────────────────────
-- Each sub-section creates a zone part centred at (500, 0, 500) with a
-- 100×2×100 footprint, then tests a position at (500, 10, 500) — well inside
-- the XZ footprint but above the part (Y intentionally different to confirm
-- Y is not used for containment).

local ZONE_CENTER = Vector3.new(500, 0, 500)
local ZONE_SIZE   = Vector3.new(100, 2, 100)
local INSIDE_POS  = Vector3.new(500, 10, 500)   -- inside XZ, above the part
local OUTSIDE_POS = Vector3.new(800, 10, 800)   -- outside XZ footprint

do
	local waterPart = makeZonePart("Zone_WATER", ZONE_CENTER, ZONE_SIZE)

	check("GetSurface: WATER zone — inside XZ → WATER", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "WATER",
			("expected WATER, got %s"):format(surface))
	end)

	check("GetSurface: WATER zone — outside XZ → FAIRWAY", function()
		local surface = HazardResolver:GetSurface(OUTSIDE_POS)
		assert(surface == "FAIRWAY",
			("expected FAIRWAY outside zone, got %s"):format(surface))
	end)

	check("GetSurface: WATER zone — Y above part is still detected (Y ignored)", function()
		-- INSIDE_POS.Y = 10, part top surface Y ≈ 1. Y-only mismatch must not prevent detection.
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "WATER",
			("Y-above detection failed: expected WATER, got %s"):format(surface))
	end)

	waterPart:Destroy()
end

do
	local sandPart = makeZonePart("Zone_SAND", ZONE_CENTER, ZONE_SIZE)

	check("GetSurface: SAND zone → SAND", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "SAND",
			("expected SAND, got %s"):format(surface))
	end)

	sandPart:Destroy()
end

do
	local greenPart = makeZonePart("Zone_GREEN", ZONE_CENTER, ZONE_SIZE)

	check("GetSurface: GREEN zone → GREEN", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "GREEN",
			("expected GREEN, got %s"):format(surface))
	end)

	greenPart:Destroy()
end

do
	local fairwayPart = makeZonePart("Zone_FAIRWAY", ZONE_CENTER, ZONE_SIZE)

	check("GetSurface: explicit FAIRWAY zone → FAIRWAY", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "FAIRWAY",
			("expected FAIRWAY, got %s"):format(surface))
	end)

	fairwayPart:Destroy()
end

do
	local roughPart = makeZonePart("Zone_ROUGH", ZONE_CENTER, ZONE_SIZE)

	check("GetSurface: ROUGH zone → ROUGH", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "ROUGH",
			("expected ROUGH, got %s"):format(surface))
	end)

	roughPart:Destroy()
end

do
	local oobPart = makeZonePart("Zone_OOB", ZONE_CENTER, ZONE_SIZE)

	check("GetSurface: OOB zone → OOB", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "OOB",
			("expected OOB, got %s"):format(surface))
	end)

	oobPart:Destroy()
end

-- ── Priority ordering ──────────────────────────────────────────────────────
-- Overlapping zones must resolve to the highest-priority surface type.

do
	-- OOB and WATER both cover INSIDE_POS — OOB must win.
	local oobPart   = makeZonePart("Zone_OOB",   ZONE_CENTER, ZONE_SIZE)
	local waterPart = makeZonePart("Zone_WATER",  ZONE_CENTER, ZONE_SIZE)

	check("Priority: OOB beats WATER when both zones overlap", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "OOB",
			("expected OOB (higher priority), got %s"):format(surface))
	end)

	oobPart:Destroy()
	waterPart:Destroy()
end

do
	-- WATER and SAND both cover INSIDE_POS — WATER must win.
	local waterPart = makeZonePart("Zone_WATER", ZONE_CENTER, ZONE_SIZE)
	local sandPart  = makeZonePart("Zone_SAND",  ZONE_CENTER, ZONE_SIZE)

	check("Priority: WATER beats SAND when both zones overlap", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "WATER",
			("expected WATER (higher priority), got %s"):format(surface))
	end)

	waterPart:Destroy()
	sandPart:Destroy()
end

do
	-- SAND and GREEN overlap — SAND must win.
	local sandPart  = makeZonePart("Zone_SAND",  ZONE_CENTER, ZONE_SIZE)
	local greenPart = makeZonePart("Zone_GREEN", ZONE_CENTER, ZONE_SIZE)

	check("Priority: SAND beats GREEN when both zones overlap", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "SAND",
			("expected SAND (higher priority), got %s"):format(surface))
	end)

	sandPart:Destroy()
	greenPart:Destroy()
end

-- ── Rotated zone part ──────────────────────────────────────────────────────
-- A zone part rotated 45° should still detect points inside its local footprint.

do
	local rotatedPart = makeZonePart("Zone_WATER", ZONE_CENTER, ZONE_SIZE)
	rotatedPart.CFrame = CFrame.new(ZONE_CENTER) * CFrame.Angles(0, math.rad(45), 0)

	-- The rotated zone still covers ZONE_CENTER itself (centre point is always inside).
	check("GetSurface: rotated zone part — centre of zone still detected", function()
		local surface = HazardResolver:GetSurface(ZONE_CENTER)
		assert(surface == "WATER",
			("expected WATER (rotated zone), got %s"):format(surface))
	end)

	rotatedPart:Destroy()
end

-- ── Destroyed-part resilience ──────────────────────────────────────────────
-- If a zone part is destroyed after the cache was built, GetSurface must skip
-- it gracefully (via nil Parent check) and fall through to the next match or default.

do
	local zombiePart = makeZonePart("Zone_WATER", ZONE_CENTER, ZONE_SIZE)

	check("Destroyed-part setup: WATER detected before destroy", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "WATER",
			("setup check failed: expected WATER, got %s"):format(surface))
	end)

	-- Destroy removes the CS tag; GetTagged will no longer return this part.
	zombiePart:Destroy()

	check("Destroyed-part: GetSurface returns FAIRWAY after zone is destroyed", function()
		-- GetTagged no longer includes the destroyed part → no match → FAIRWAY.
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "FAIRWAY",
			("expected FAIRWAY after zone destroy, got %s"):format(surface))
	end)
end

-- ── nil-Parent safety net ──────────────────────────────────────────────────
-- Setting Parent = nil without Destroy does NOT remove the CS tag, so GetTagged
-- still returns the part. GetSurface must check part.Parent and skip it.
do
	local unparentedPart = makeZonePart("Zone_WATER", ZONE_CENTER, ZONE_SIZE)

	check("nil-Parent setup: WATER detected before unparent", function()
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "WATER",
			("setup check failed: expected WATER, got %s"):format(surface))
	end)

	-- Unparent without Destroy: tag stays on instance, GetTagged still returns it.
	unparentedPart.Parent = nil

	check("nil-Parent: GetSurface skips unparented part and returns FAIRWAY", function()
		-- GetTagged returns the part (tag intact), but part.Parent == nil → skipped.
		local surface = HazardResolver:GetSurface(INSIDE_POS)
		assert(surface == "FAIRWAY",
			("expected FAIRWAY (nil-Parent skip), got %s"):format(surface))
	end)

	-- Cleanup: remove the tag then destroy the orphaned part.
	CollectionService:RemoveTag(unparentedPart, "Zone_WATER")
	unparentedPart:Destroy()
end

-- ── GetPenalty ─────────────────────────────────────────────────────────────

check("GetPenalty: WATER → 1 stroke, dropBack = true", function()
	local p = HazardResolver:GetPenalty("WATER")
	assert(p.strokes == 1,   ("expected strokes=1, got %d"):format(p.strokes))
	assert(p.dropBack == true, "expected dropBack=true for WATER")
end)

check("GetPenalty: OOB → 1 stroke, dropBack = true", function()
	local p = HazardResolver:GetPenalty("OOB")
	assert(p.strokes == 1,   ("expected strokes=1, got %d"):format(p.strokes))
	assert(p.dropBack == true, "expected dropBack=true for OOB")
end)

check("GetPenalty: SAND → 0 strokes, dropBack = false (lie penalty only)", function()
	local p = HazardResolver:GetPenalty("SAND")
	assert(p.strokes == 0,    ("expected strokes=0, got %d"):format(p.strokes))
	assert(p.dropBack == false, "expected dropBack=false for SAND")
end)

check("GetPenalty: FAIRWAY → 0 strokes, dropBack = false", function()
	local p = HazardResolver:GetPenalty("FAIRWAY")
	assert(p.strokes == 0,    ("expected strokes=0, got %d"):format(p.strokes))
	assert(p.dropBack == false, "expected dropBack=false for FAIRWAY")
end)

check("GetPenalty: GREEN → 0 strokes, dropBack = false", function()
	local p = HazardResolver:GetPenalty("GREEN")
	assert(p.strokes == 0,    ("expected strokes=0, got %d"):format(p.strokes))
	assert(p.dropBack == false, "expected dropBack=false for GREEN")
end)

check("GetPenalty: ROUGH → 0 strokes, dropBack = false", function()
	local p = HazardResolver:GetPenalty("ROUGH")
	assert(p.strokes == 0,    ("expected strokes=0, got %d"):format(p.strokes))
	assert(p.dropBack == false, "expected dropBack=false for ROUGH")
end)

check("GetPenalty: unknown surface → 0 strokes, dropBack = false (safe default)", function()
	local p = HazardResolver:GetPenalty("UNKNOWN")
	assert(p.strokes == 0,    ("expected strokes=0, got %d"):format(p.strokes))
	assert(p.dropBack == false, "expected dropBack=false for unknown surface")
end)

-- ── Summary ────────────────────────────────────────────────────────────────

print(TAG .. " ─────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 4 smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
