--!strict
-- Sprint4Test — Temporary server smoke test for Sprint 4 modules.
-- Safe to delete after Sprint 4 sign-off.
--
-- Modules tested:
--   HazardResolver (32 checks): module API, Y-floor OOB, FAIRWAY default,
--     zone detection for all 6 SurfaceTypes, priority ordering, destroyed-part
--     resilience, nil-Parent safety net, GetPenalty for every surface.
--   CourseLoader (23 checks): module API, ActivateHole priority assignments,
--     first/last hole boundary behaviour, transitions, DeactivateHole,
--     GetHoleFolder, error paths.
--
-- No player required. All tests are synchronous.
-- HazardResolver tests create temporary Parts (destroyed after use).
-- CourseLoader tests set StreamingPriority attributes on existing Workspace
-- hole folders — minor side effects, no impact on gameplay in Studio.

local CollectionService   = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local HazardResolver = require(ServerScriptService.Modules.HazardResolver)
local CourseLoader   = require(ServerScriptService.Modules.CourseLoader)

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

-- ════════════════════════════════════════════════════════════════════════════
-- CourseLoader smoke tests
-- ════════════════════════════════════════════════════════════════════════════

-- The Workspace folder name for the only course in the Vertical Slice.
local COURSE_ID = "Course_1_SunnybrookMeadows"

-- Helper: reads the StreamingPriority attribute from a hole folder.
-- Returns -1 if the folder is missing or the attribute is not yet set.
local function getPriority(holeId: string): number
	local folder = CourseLoader:GetHoleFolder(COURSE_ID, holeId)
	if not folder then
		return -1
	end
	local val = folder:GetAttribute("StreamingPriority")
	if type(val) == "number" then
		return val
	end
	return -1
end

-- ── Module API ─────────────────────────────────────────────────────────────

check("CourseLoader: module loads without error", function()
	assert(CourseLoader ~= nil)
end)

check("CourseLoader: Init runs without error (and is idempotent)", function()
	CourseLoader:Init({})
	CourseLoader:Init({})  -- second call must be a no-op, not an error
end)

check("CourseLoader: ActivateHole method exists", function()
	assert(type(CourseLoader.ActivateHole) == "function", "ActivateHole missing")
end)

check("CourseLoader: DeactivateHole method exists", function()
	assert(type(CourseLoader.DeactivateHole) == "function", "DeactivateHole missing")
end)

check("CourseLoader: GetHoleFolder method exists", function()
	assert(type(CourseLoader.GetHoleFolder) == "function", "GetHoleFolder missing")
end)

-- ── GetHoleFolder ──────────────────────────────────────────────────────────

check("GetHoleFolder: valid holeId returns non-nil", function()
	local folder = CourseLoader:GetHoleFolder(COURSE_ID, "Hole_01")
	assert(folder ~= nil, "expected Hole_01 folder to exist in Workspace")
end)

check("GetHoleFolder: non-existent hole returns nil (no error)", function()
	local folder = CourseLoader:GetHoleFolder(COURSE_ID, "Hole_99")
	assert(folder == nil, "expected nil for Hole_99 (not in Workspace)")
end)

-- ── ActivateHole — first hole (Hole_01) ───────────────────────────────────
-- Hole_01 has no previous hole; Hole_02 is pre-fetched.

check("ActivateHole Hole_01: current hole gets StreamingPriority 10", function()
	CourseLoader:ActivateHole(COURSE_ID, "Hole_01")
	local p = getPriority("Hole_01")
	assert(p == 10, ("expected 10, got %d"):format(p))
end)

check("ActivateHole Hole_01: next hole (Hole_02) gets StreamingPriority 5", function()
	local p = getPriority("Hole_02")
	assert(p == 5, ("expected 5, got %d"):format(p))
end)

check("ActivateHole Hole_01: no previous hole — no error (Hole_00 absent)", function()
	-- If ActivateHole errored on missing prev, the test above would have failed.
	-- Explicitly verify Hole_00 doesn't exist and GetHoleFolder agrees.
	local folder = CourseLoader:GetHoleFolder(COURSE_ID, "Hole_00")
	assert(folder == nil, "Hole_00 should not exist")
end)

-- ── ActivateHole — mid-hole transition (Hole_01 → Hole_02) ───────────────

check("ActivateHole Hole_02: current hole gets StreamingPriority 10", function()
	CourseLoader:ActivateHole(COURSE_ID, "Hole_02")
	local p = getPriority("Hole_02")
	assert(p == 10, ("expected 10, got %d"):format(p))
end)

check("ActivateHole Hole_02: previous hole (Hole_01) gets StreamingPriority 0", function()
	local p = getPriority("Hole_01")
	assert(p == 0, ("expected 0 (released), got %d"):format(p))
end)

check("ActivateHole Hole_02: next hole (Hole_03) gets StreamingPriority 5", function()
	local p = getPriority("Hole_03")
	assert(p == 5, ("expected 5, got %d"):format(p))
end)

-- ── ActivateHole — last hole (Hole_09) ────────────────────────────────────
-- Hole_09 has no next hole; Hole_08 is released.

check("ActivateHole Hole_09: current hole gets StreamingPriority 10", function()
	CourseLoader:ActivateHole(COURSE_ID, "Hole_09")
	local p = getPriority("Hole_09")
	assert(p == 10, ("expected 10, got %d"):format(p))
end)

check("ActivateHole Hole_09: previous hole (Hole_08) gets StreamingPriority 0", function()
	local p = getPriority("Hole_08")
	assert(p == 0, ("expected 0 (released), got %d"):format(p))
end)

check("ActivateHole Hole_09: no next hole — no error (Hole_10 absent)", function()
	local folder = CourseLoader:GetHoleFolder(COURSE_ID, "Hole_10")
	assert(folder == nil, "Hole_10 should not exist")
end)

-- ── ActivateHole — idempotent on same hole ─────────────────────────────────

check("ActivateHole: calling twice on same hole does not error, priority stays 10", function()
	CourseLoader:ActivateHole(COURSE_ID, "Hole_05")
	CourseLoader:ActivateHole(COURSE_ID, "Hole_05")
	local p = getPriority("Hole_05")
	assert(p == 10, ("expected 10, got %d"):format(p))
end)

-- ── DeactivateHole ─────────────────────────────────────────────────────────

check("DeactivateHole: sets StreamingPriority to 0", function()
	CourseLoader:ActivateHole(COURSE_ID, "Hole_06")  -- sets Hole_06 → 10
	local before = getPriority("Hole_06")
	assert(before == 10, ("setup failed: expected 10, got %d"):format(before))
	CourseLoader:DeactivateHole(COURSE_ID, "Hole_06")
	local after = getPriority("Hole_06")
	assert(after == 0, ("expected 0 after DeactivateHole, got %d"):format(after))
end)

check("DeactivateHole: deactivating already-zero hole is a no-op (no error)", function()
	-- Hole_01 was left at 0 after the Hole_02 activation above.
	CourseLoader:DeactivateHole(COURSE_ID, "Hole_01")
	local p = getPriority("Hole_01")
	assert(p == 0, ("expected 0, got %d"):format(p))
end)

-- ── Error paths ────────────────────────────────────────────────────────────

check("ActivateHole: invalid courseId → error", function()
	local ok = pcall(function()
		CourseLoader:ActivateHole("Course_Invalid", "Hole_01")
	end)
	assert(not ok, "expected error for non-existent courseId")
end)

check("ActivateHole: non-existent holeId (Hole_99) → error", function()
	local ok = pcall(function()
		CourseLoader:ActivateHole(COURSE_ID, "Hole_99")
	end)
	assert(not ok, "expected error for non-existent hole")
end)

check("ActivateHole: malformed holeId → error", function()
	local ok = pcall(function()
		CourseLoader:ActivateHole(COURSE_ID, "InvalidHoleName")
	end)
	assert(not ok, "expected error for malformed holeId (not Hole_NN format)")
end)

check("DeactivateHole: non-existent holeId → error", function()
	local ok = pcall(function()
		CourseLoader:DeactivateHole(COURSE_ID, "Hole_99")
	end)
	assert(not ok, "expected error for non-existent hole")
end)

-- ── Summary ────────────────────────────────────────────────────────────────

print(TAG .. " ─────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 4 smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
