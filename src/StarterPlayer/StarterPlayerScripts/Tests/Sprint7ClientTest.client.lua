--!strict
-- Sprint7ClientTest — LocalScript
-- Client smoke tests for PredictionControllerModule (Sprint 7).
-- Run in Play mode; all output appears in the Roblox Studio Output window.
-- Does NOT call Init() — tests drive the module through semi-public methods
-- so that no live RemoteEvent or RunService connections are created.

print("[Sprint7ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint7ClientTest]"
local passed = 0
local failed = 0

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(TAG .. " PASS: " .. label)
	else
		failed += 1
		warn(TAG .. " FAIL: " .. label .. " — " .. tostring(err))
	end
end

-- pcall-wrapped require so module load errors surface as FATAL output
-- rather than silently killing the test script.
local function safeRequire(path: Instance): (boolean, any)
	local ok, result = pcall(require, path :: any)
	if not ok then
		warn(TAG .. " FATAL: require failed — " .. tostring(result))
	end
	return ok, result
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — PredictionControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local pcmOk, pcmResult = safeRequire(
	script.Parent.Parent.Modules.PredictionControllerModule)

if pcmOk then

	local PCM: any = pcmResult

	-- Fake ball data -------------------------------------------------------
	local BALL_ID   = "ball_12345"
	local FAKE_POS  = Vector3.new(10, 5, -30)
	local FAKE_VEL  = Vector3.new(2, 1, -8)
	local FAKE_POS2 = Vector3.new(50, 3, -100)

	local function storeSnap()
		PCM:_onBallPositionUpdate({
			ballId = BALL_ID,
			pos    = FAKE_POS,
			vel    = FAKE_VEL,
		})
	end

	-- 1 ────────────────────────────────────────────────────────────────────
	check("PCM: module loads successfully", function()
		assert(type(PCM) == "table", "expected table, got " .. type(PCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("PCM: GetSnapshot returns nil for unknown ballId", function()
		local snap = PCM:GetSnapshot("ball_unknown_xyz")
		assert(snap == nil, "expected nil")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("PCM: _onBallPositionUpdate stores a snapshot", function()
		storeSnap()
		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap ~= nil, "snapshot should not be nil")
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("PCM: stored snapshot has correct ballId", function()
		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap ~= nil, "snapshot is nil")
		assert(snap.ballId == BALL_ID,
			("expected %q, got %q"):format(BALL_ID, tostring(snap.ballId)))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("PCM: stored snapshot has correct pos", function()
		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap ~= nil, "snapshot is nil")
		assert(snap.pos == FAKE_POS,
			("expected %s, got %s"):format(tostring(FAKE_POS), tostring(snap.pos)))
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("PCM: stored snapshot has correct vel", function()
		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap ~= nil, "snapshot is nil")
		assert(snap.vel == FAKE_VEL,
			("expected %s, got %s"):format(tostring(FAKE_VEL), tostring(snap.vel)))
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("PCM: stored snapshot receivedAt is a positive number", function()
		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap ~= nil, "snapshot is nil")
		assert(type(snap.receivedAt) == "number", "receivedAt must be a number")
		assert(snap.receivedAt > 0, "receivedAt must be positive")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("PCM: _onBallPositionUpdate without vel defaults vel to Vector3.zero", function()
		local noVelId = "ball_novelbid"
		PCM:_onBallPositionUpdate({
			ballId = noVelId,
			pos    = FAKE_POS2,
			-- vel intentionally omitted
		})
		local snap = PCM:GetSnapshot(noVelId)
		assert(snap ~= nil, "snapshot is nil")
		assert(snap.vel == Vector3.zero,
			"expected Vector3.zero, got " .. tostring(snap.vel))
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("PCM: _onBallPositionUpdate with non-table payload is ignored", function()
		local before = PCM:GetSnapshot("ball_garbage")
		PCM:_onBallPositionUpdate("this is a string")
		local after = PCM:GetSnapshot("ball_garbage")
		assert(before == after, "snapshot should be unchanged")
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("PCM: _onBallPositionUpdate with missing ballId is ignored", function()
		-- Store a known-good snap for BALL_ID first, so we can verify nothing
		-- unrelated changes.
		PCM:_onBallPositionUpdate({ pos = FAKE_POS, vel = FAKE_VEL })  -- no ballId
		-- No assert needed if it didn't error; BALL_ID snapshot still equals FAKE_POS
		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap ~= nil, "existing snapshot should not be touched")
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("PCM: _onBallPositionUpdate with non-Vector3 pos is ignored", function()
		local badId = "ball_badpos"
		PCM:_onBallPositionUpdate({ ballId = badId, pos = "not a vector", vel = FAKE_VEL })
		local snap = PCM:GetSnapshot(badId)
		assert(snap == nil, "snapshot should not be created for invalid pos")
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("PCM: _onGameBusEvent BallResolved clears snapshot", function()
		-- Ensure there is a snapshot to clear.
		PCM:_onBallPositionUpdate({ ballId = BALL_ID, pos = FAKE_POS, vel = FAKE_VEL })
		assert(PCM:GetSnapshot(BALL_ID) ~= nil, "snapshot must exist before BallResolved")

		PCM:_onGameBusEvent({
			eventType = "BallResolved",
			payload   = {
				ballId         = BALL_ID,
				trajectory     = { FAKE_POS, FAKE_POS2 },
				landingPos     = FAKE_POS2,
				landingSurface = "FAIRWAY",
			},
			timestamp = os.time(),
		})

		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap == nil, "snapshot should be nil after BallResolved")
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("PCM: _onGameBusEvent non-BallResolved eventType does not clear snapshots", function()
		-- Store a fresh snapshot.
		PCM:_onBallPositionUpdate({ ballId = BALL_ID, pos = FAKE_POS, vel = FAKE_VEL })

		PCM:_onGameBusEvent({
			eventType = "StateChanged",
			payload   = { state = "SWING", playerId = 99999 },
			timestamp = os.time(),
		})

		local snap = PCM:GetSnapshot(BALL_ID)
		assert(snap ~= nil, "unrelated event should not clear snapshot")
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("PCM: _onGameBusEvent with invalid envelope is ignored", function()
		PCM:_onGameBusEvent("not a table")
		PCM:_onGameBusEvent(nil)
		-- Just asserting no error was raised (pcall in check() catches any throw).
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("PCM: multiple ballIds are stored independently", function()
		local idA = "ball_111"
		local idB = "ball_222"
		local posA = Vector3.new(1, 0, 0)
		local posB = Vector3.new(0, 0, 1)

		PCM:_onBallPositionUpdate({ ballId = idA, pos = posA, vel = Vector3.zero })
		PCM:_onBallPositionUpdate({ ballId = idB, pos = posB, vel = Vector3.zero })

		local snapA = PCM:GetSnapshot(idA)
		local snapB = PCM:GetSnapshot(idB)
		assert(snapA ~= nil, "snapshot A should exist")
		assert(snapB ~= nil, "snapshot B should exist")
		assert(snapA.pos == posA, "snapshot A pos mismatch")
		assert(snapB.pos == posB, "snapshot B pos mismatch")
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("PCM: Destroy clears all snapshots", function()
		PCM:_onBallPositionUpdate({ ballId = "ball_d1", pos = FAKE_POS, vel = FAKE_VEL })
		PCM:_onBallPositionUpdate({ ballId = "ball_d2", pos = FAKE_POS, vel = FAKE_VEL })
		assert(PCM:GetSnapshot("ball_d1") ~= nil, "snapshot d1 should exist before Destroy")
		assert(PCM:GetSnapshot("ball_d2") ~= nil, "snapshot d2 should exist before Destroy")

		PCM:Destroy()

		assert(PCM:GetSnapshot("ball_d1") == nil, "snapshot d1 should be nil after Destroy")
		assert(PCM:GetSnapshot("ball_d2") == nil, "snapshot d2 should be nil after Destroy")
	end)

	-- Destroy() above disconnected the live BallPositionStream.OnClientEvent listener
	-- that PredictionController.client.lua established. Re-init restores it so the
	-- server's 60 Hz position stream has a listener for the remainder of the session.
	PCM:Init()

end -- pcmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 7 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
