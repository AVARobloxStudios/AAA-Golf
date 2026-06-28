--!strict
-- Sprint34ClientTest — Client ModuleScript smoke tests for Sprint 34.
-- Invoked by TestRunner.client.lua.  No server calls, no RemoteEvents needed.
--
-- Covers:
--   SwingInputControllerModule: loads, Init, SetEnabled, BeginInput, Backswing,
--     Downswing, cancel gesture, valid EndInput, GetSwingState copy, Destroy+re-Init
--   SwingAnalyzerModule: loads, straight shot, power range, left/right path,
--     closed/open face shapes, Chunk/Thin/Mishit from bad tempo/path, copy, Destroy+re-Init
--   FaceControlControllerModule: loads, no-input default, early/perfect/late,
--     duplicate press, Reset, Destroy+re-Init
--   SwingFeedbackHUDModule: loads, Init, UpdatePhase, ShowResult, Update, Destroy
--   PlayableHoleControllerModule backward compat: Shoot(), power, aimDirection,
--     sub-modules accessible, Destroy tears down

return function()
	local StarterPlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts

	local PHCM = require(StarterPlayerScripts.Modules.PlayableHoleControllerModule)
	local SICM = require(StarterPlayerScripts.Modules.SwingInputControllerModule)
	local SAM  = require(StarterPlayerScripts.Modules.SwingAnalyzerModule)
	local FCCM = require(StarterPlayerScripts.Modules.FaceControlControllerModule)
	local SFHM = require(StarterPlayerScripts.Modules.SwingFeedbackHUDModule)

	local TAG = "[Sprint34ClientTest]"
	local passed = 0
	local failed = 0

	local function check(label: string, fn: () -> ())
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			print(TAG .. " PASS  " .. label)
		else
			failed += 1
			warn(TAG .. " FAIL  " .. label .. "  (" .. tostring(err) .. ")")
		end
	end

	-- ── Isolation ─────────────────────────────────────────────────────────────
	-- PHCM:Destroy() also tears down all swing sub-modules.
	PHCM:Destroy()

	-- ═══════════════════════════════════════════════════════════════════════════
	-- SwingInputControllerModule
	-- ═══════════════════════════════════════════════════════════════════════════

	SICM:Init()

	check("SICM: module loads", function()
		assert(type(SICM) == "table")
	end)

	check("SICM: Init — phase=Idle, enabled=true", function()
		local s = SICM:GetSwingState()
		assert(s.phase == "Idle", ("expected Idle, got %q"):format(s.phase))
		assert(s.enabled == true)
	end)

	check("SICM: SetEnabled(false) blocks BeginInput", function()
		SICM:SetEnabled(false)
		SICM:BeginInput(Vector2.new(400, 300))
		local s = SICM:GetSwingState()
		assert(s.phase == "Idle", ("expected Idle when disabled, got %q"):format(s.phase))
		SICM:SetEnabled(true)
	end)

	check("SICM: BeginInput → InputStarted", function()
		SICM:BeginInput(Vector2.new(400, 300))
		local s = SICM:GetSwingState()
		assert(s.phase == "InputStarted",
			("expected InputStarted, got %q"):format(s.phase))
	end)

	check("SICM: 45px downward drag → Backswing", function()
		SICM:BeginInput(Vector2.new(400, 300))
		SICM:UpdateInput(Vector2.new(400, 345))   -- 45px > 40px threshold
		local s = SICM:GetSwingState()
		assert(s.phase == "Backswing",
			("expected Backswing, got %q"):format(s.phase))
		assert(s.maxBackswingDistance >= 40)
	end)

	check("SICM: 17px back up from peak → Downswing", function()
		SICM:BeginInput(Vector2.new(400, 300))
		SICM:UpdateInput(Vector2.new(400, 345))   -- peak at Y=345
		SICM:UpdateInput(Vector2.new(400, 328))   -- 17px back up > 15px threshold
		local s = SICM:GetSwingState()
		assert(s.phase == "Downswing",
			("expected Downswing, got %q"):format(s.phase))
	end)

	check("SICM: release near start in Backswing → cancelled raw data", function()
		SICM:BeginInput(Vector2.new(400, 300))
		SICM:UpdateInput(Vector2.new(400, 345))   -- Backswing
		-- Release 4.5 pixels from start (< 28 CANCEL_RADIUS) while in Backswing
		SICM:EndInput(Vector2.new(402, 304))
		local raw = SICM:GetRawSwingData()
		assert(raw ~= nil, "expected raw data to be set")
		assert(raw.cancelled == true, "expected cancelled=true (reset gesture)")
	end)

	check("SICM: valid EndInput → non-cancelled raw swing data", function()
		SICM:BeginInput(Vector2.new(400, 300))
		SICM:UpdateInput(Vector2.new(400, 345))   -- Backswing
		SICM:UpdateInput(Vector2.new(400, 328))   -- Downswing
		SICM:EndInput(Vector2.new(400, 260))      -- release well above start (not cancelled)
		local raw = SICM:GetRawSwingData()
		assert(raw ~= nil, "expected raw data")
		assert(raw.cancelled == false, "expected not cancelled")
		assert(raw.maxBackswingDistance > 0)
		assert(type(raw.totalDuration) == "number" and raw.totalDuration >= 0)
		assert(type(raw.backswingDuration) == "number")
		assert(type(raw.downswingDuration) == "number")
		assert(typeof(raw.startPosition) == "Vector2")
		assert(typeof(raw.releasePosition) == "Vector2")
	end)

	check("SICM: GetSwingState returns independent copy", function()
		SICM:BeginInput(Vector2.new(400, 300))
		local s1 = SICM:GetSwingState()
		local origPhase = s1.phase
		s1.phase = "MUTATED"
		local s2 = SICM:GetSwingState()
		assert(s2.phase == origPhase,
			("internal phase should be %q, not mutated"):format(origPhase))
	end)

	check("SICM: CancelInput → cancelled raw data", function()
		SICM:BeginInput(Vector2.new(400, 300))
		SICM:UpdateInput(Vector2.new(400, 345))
		SICM:CancelInput()
		local raw = SICM:GetRawSwingData()
		assert(raw ~= nil and raw.cancelled == true)
	end)

	check("SICM: Destroy + re-Init → Idle", function()
		SICM:Destroy()
		SICM:Init()
		local s = SICM:GetSwingState()
		assert(s.phase == "Idle")
	end)

	-- ═══════════════════════════════════════════════════════════════════════════
	-- SwingAnalyzerModule
	-- ═══════════════════════════════════════════════════════════════════════════

	SAM:Destroy()
	SAM:Init()

	-- Synthetic data builders
	local function makeRaw(
		maxBackswing: number,
		backswingDur: number,
		downswingDur: number,
		horizOffset:  number,
		followThru:   number
	): any
		return {
			maxBackswingDistance  = maxBackswing,
			backswingDuration     = backswingDur,
			downswingDuration     = downswingDur,
			horizontalOffset      = horizOffset,
			followThroughDistance = followThru,
			startPosition         = Vector2.new(400, 300),
			currentPosition       = Vector2.new(400, 260),
			releasePosition       = Vector2.new(400, 260),
			sampledPositions      = {
				Vector2.new(400, 300),
				Vector2.new(400, 345),
				Vector2.new(400, 310),
				Vector2.new(400, 265),
			},
			sampledTimes          = { 0, backswingDur * 0.5, backswingDur, backswingDur + downswingDur * 0.5 },
			downswingStartIndex   = 2,
			backswingStartTime    = 0,
			downswingStartTime    = backswingDur,
			releaseTime           = backswingDur + downswingDur,
			totalDuration         = backswingDur + downswingDur,
			cancelled             = false,
		}
	end

	local function makeFace(angle: number): any
		return {
			faceAngle    = angle,
			noInput      = (angle == 0),
			timedPerfect = (angle == 0),
			timedEarly   = (angle < 0),
			timedLate    = (angle > 0),
		}
	end

	check("SAM: module loads", function()
		assert(type(SAM) == "table")
	end)

	check("SAM: straight vertical swing → Straight/near-straight shape, valid=true", function()
		-- Good tempo (ratio 3.0 = 0.6/0.2), no path offset, square face
		local raw    = makeRaw(160, 0.60, 0.20, 0, 40)
		local result = SAM:Analyze(raw, makeFace(0), Vector3.new(0, 0, -1))
		assert(result.valid == true, "expected valid")
		local ok = result.shotShape == "Straight"
			or result.shotShape == "Push"
			or result.shotShape == "Pull"
		assert(ok, ("expected near-straight, got %q"):format(result.shotShape))
	end)

	check("SAM: short backswing → lower power than long backswing", function()
		local shortResult = SAM:Analyze(makeRaw(50, 0.60, 0.20, 0, 40), makeFace(0), Vector3.new(0, 0, -1))
		local longResult  = SAM:Analyze(makeRaw(220, 0.60, 0.20, 0, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(shortResult.power01 < longResult.power01,
			("expected short power01 %f < long %f"):format(shortResult.power01, longResult.power01))
		assert(shortResult.shotPower < longResult.shotPower,
			("expected short shotPower %f < long %f"):format(shortResult.shotPower, longResult.shotPower))
	end)

	check("SAM: long backswing → high power01", function()
		local result = SAM:Analyze(makeRaw(240, 0.60, 0.20, 0, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.power01 > 0.7, ("expected power01 > 0.7, got %f"):format(result.power01))
	end)

	check("SAM: right horizontal offset → positive pathOffset and clubPath", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, 80, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.pathOffset > 0,
			("expected pathOffset > 0, got %f"):format(result.pathOffset))
		assert(result.clubPath > 0,
			("expected clubPath > 0, got %f"):format(result.clubPath))
	end)

	check("SAM: left horizontal offset → negative pathOffset", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, -80, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.pathOffset < 0,
			("expected pathOffset < 0, got %f"):format(result.pathOffset))
	end)

	check("SAM: right path + closed face (-8°) → Draw shotShape", function()
		-- horizOffset=70 → positive clubPath; closed face → Draw
		local faceData = { faceAngle = -8, noInput = false, timedPerfect = false, timedEarly = true, timedLate = false }
		local result   = SAM:Analyze(makeRaw(160, 0.60, 0.20, 70, 40), faceData, Vector3.new(0, 0, -1))
		assert(result.shotShape == "Draw", ("expected Draw, got %q"):format(result.shotShape))
		assert(result.sideSpinInput < 0, "closed face → negative sideSpinInput (draw tendency)")
	end)

	check("SAM: right path + open face (+8°) → Slice shotShape", function()
		-- horizOffset=70 → positive clubPath; open face → Slice
		local faceData = { faceAngle = 8, noInput = false, timedPerfect = false, timedEarly = false, timedLate = true }
		local result   = SAM:Analyze(makeRaw(160, 0.60, 0.20, 70, 40), faceData, Vector3.new(0, 0, -1))
		assert(result.shotShape == "Slice", ("expected Slice, got %q"):format(result.shotShape))
		assert(result.sideSpinInput > 0, "open face → positive sideSpinInput (fade tendency)")
	end)

	check("SAM: low tempoRatio (1.0) → Chunk contact quality", function()
		-- tempoRatio = 0.5 / 0.5 = 1.0 < IDEAL_TEMPO_MIN (2.2) → Chunk
		local result = SAM:Analyze(makeRaw(160, 0.50, 0.50, 0, 5), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.contactQuality == "Chunk",
			("expected Chunk, got %q"):format(result.contactQuality))
	end)

	check("SAM: high tempoRatio (10.0) → Thin contact quality", function()
		-- tempoRatio = 0.6 / 0.06 = 10.0 > IDEAL_TEMPO_MAX*1.2 (4.32) → Thin
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.06, 0, 5), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.contactQuality == "Thin",
			("expected Thin, got %q"):format(result.contactQuality))
	end)

	check("SAM: extreme horizontal offset (130px) → Mishit", function()
		-- pathOffset = 130/140 ≈ 0.928 > 0.88 → Mishit
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, 130, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.contactQuality == "Mishit",
			("expected Mishit contact, got %q"):format(result.contactQuality))
		assert(result.shotShape == "Mishit",
			("expected Mishit shape, got %q"):format(result.shotShape))
	end)

	-- ── Right-handed shot shape mapping (all 7 shapes) ──────────────────────────
	-- horizOffset=70 → clubPath≈+7.5° (right); horizOffset=-70 → clubPath≈-7.5° (left)

	check("SAM: left path + closed face → Hook", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, -70, 40),
			{ faceAngle = -8, noInput = false, timedPerfect = false, timedEarly = true, timedLate = false },
			Vector3.new(0, 0, -1))
		assert(result.shotShape == "Hook", ("expected Hook, got %q"):format(result.shotShape))
	end)

	check("SAM: left path + open face → Fade", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, -70, 40),
			{ faceAngle = 8, noInput = false, timedPerfect = false, timedEarly = false, timedLate = true },
			Vector3.new(0, 0, -1))
		assert(result.shotShape == "Fade", ("expected Fade, got %q"):format(result.shotShape))
	end)

	check("SAM: right path + closed face → Draw", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, 70, 40),
			{ faceAngle = -8, noInput = false, timedPerfect = false, timedEarly = true, timedLate = false },
			Vector3.new(0, 0, -1))
		assert(result.shotShape == "Draw", ("expected Draw, got %q"):format(result.shotShape))
	end)

	check("SAM: right path + open face → Slice", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, 70, 40),
			{ faceAngle = 8, noInput = false, timedPerfect = false, timedEarly = false, timedLate = true },
			Vector3.new(0, 0, -1))
		assert(result.shotShape == "Slice", ("expected Slice, got %q"):format(result.shotShape))
	end)

	check("SAM: left path + square face → Pull", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, -70, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.shotShape == "Pull", ("expected Pull, got %q"):format(result.shotShape))
	end)

	check("SAM: right path + square face → Push", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, 70, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.shotShape == "Push", ("expected Push, got %q"):format(result.shotShape))
	end)

	check("SAM: zero path + zero face → Straight", function()
		local result = SAM:Analyze(makeRaw(160, 0.60, 0.20, 0, 40), makeFace(0), Vector3.new(0, 0, -1))
		assert(result.shotShape == "Straight", ("expected Straight, got %q"):format(result.shotShape))
	end)

	check("SAM: mildly decelerating downswing → Poor contact (accelCons 0.35–0.60)", function()
		-- Positions that yield accelCons ≈ 0.558 after smoothing (< 0.60 → Poor)
		local poorRaw: any = {
			maxBackswingDistance  = 160,
			backswingDuration     = 0.60,
			downswingDuration     = 0.20,
			horizontalOffset      = 0,
			followThroughDistance = 30,
			startPosition         = Vector2.new(400, 300),
			currentPosition       = Vector2.new(400, 303),
			releasePosition       = Vector2.new(400, 303),
			sampledPositions      = {
				Vector2.new(400, 300),
				Vector2.new(400, 365),
				Vector2.new(400, 335),
				Vector2.new(400, 315),
				Vector2.new(400, 307),
				Vector2.new(400, 303),
			},
			sampledTimes          = { 0, 0.30, 0.50, 0.70, 0.90, 1.10 },
			downswingStartIndex   = 2,
			backswingStartTime    = 0,
			downswingStartTime    = 0.30,
			releaseTime           = 1.10,
			totalDuration         = 1.10,
			cancelled             = false,
		}
		local result = SAM:Analyze(poorRaw, makeFace(0), Vector3.new(0, 0, -1))
		assert(result.contactQuality == "Poor",
			("expected Poor contact, got %q"):format(result.contactQuality))
	end)

	check("SAM: strongly decelerating downswing → Mishit contact (accelCons < 0.35)", function()
		-- Fast start, then almost stopped: after smoothing, avgB/avgA ≈ 0.55 → accelCons ≈ 0.28 < 0.35
		local decRaw: any = {
			maxBackswingDistance  = 160,
			backswingDuration     = 0.60,
			downswingDuration     = 0.80,
			horizontalOffset      = 0,
			followThroughDistance = 40,
			startPosition         = Vector2.new(400, 300),
			currentPosition       = Vector2.new(400, 293),
			releasePosition       = Vector2.new(400, 293),
			sampledPositions      = {
				Vector2.new(400, 300),
				Vector2.new(400, 360),  -- peak: downswingStartIndex=2
				Vector2.new(400, 320),  -- fast first-half (40px up)
				Vector2.new(400, 300),  -- slowing
				Vector2.new(400, 295),  -- nearly stopped
				Vector2.new(400, 293),  -- almost no movement
			},
			sampledTimes          = { 0, 0.30, 0.50, 0.70, 0.90, 1.10 },
			downswingStartIndex   = 2,
			backswingStartTime    = 0,
			downswingStartTime    = 0.30,
			releaseTime           = 1.10,
			totalDuration         = 1.10,
			cancelled             = false,
		}
		local result = SAM:Analyze(decRaw, makeFace(0), Vector3.new(0, 0, -1))
		assert(result.contactQuality == "Mishit",
			("expected Mishit from deceleration, got %q"):format(result.contactQuality))
	end)

	check("SAM: cancelled raw data → valid=false", function()
		local cancelled: any = {
			cancelled             = true,
			maxBackswingDistance  = 0,
			backswingDuration     = 0,
			downswingDuration     = 0,
			horizontalOffset      = 0,
			followThroughDistance = 0,
			totalDuration         = 0,
			startPosition         = Vector2.zero,
			currentPosition       = Vector2.zero,
			releasePosition       = Vector2.zero,
			sampledPositions      = {},
			sampledTimes          = {},
			backswingStartTime    = 0,
			downswingStartTime    = 0,
			releaseTime           = 0,
		}
		local result = SAM:Analyze(cancelled, makeFace(0), Vector3.new(0, 0, -1))
		assert(result.valid == false, "cancelled swing should produce valid=false")
	end)

	check("SAM: GetLastResult returns independent copy", function()
		SAM:Analyze(makeRaw(160, 0.60, 0.20, 0, 40), makeFace(0), Vector3.new(0, 0, -1))
		local r1 = SAM:GetLastResult()
		if r1 then
			r1.shotPower = 99999
			local r2 = SAM:GetLastResult()
			assert(r2 ~= nil and r2.shotPower ~= 99999,
				"GetLastResult should return independent copy")
		end
	end)

	check("SAM: Destroy + re-Init clears last result", function()
		SAM:Destroy()
		SAM:Init()
		assert(SAM:GetLastResult() == nil, "expected nil after re-Init")
	end)

	-- ═══════════════════════════════════════════════════════════════════════════
	-- FaceControlControllerModule
	-- ═══════════════════════════════════════════════════════════════════════════

	FCCM:Destroy()
	FCCM:Init()

	-- Reference time for deterministic timing tests (avoids task.wait())
	local t0: number = 0

	check("FCCM: module loads", function()
		assert(type(FCCM) == "table")
	end)

	check("FCCM: no-input → open face (>0°), noInput=true", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:EndFaceWindow()
		local d = FCCM:GetFaceInputData()
		assert(d.noInput == true, "expected noInput=true")
		assert(d.faceAngle > 0, ("expected open face angle >0°, got %f"):format(d.faceAngle))
	end)

	check("FCCM: early input (0.01s) → faceAngle<0, timedEarly=true", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:RegisterFaceInput(t0 + 0.01)   -- ideal at t0+0.15 → early by 0.14s
		local d = FCCM:GetFaceInputData()
		assert(d.timedEarly == true, "expected timedEarly")
		assert(d.faceAngle < 0, ("expected closed face angle, got %f°"):format(d.faceAngle))
	end)

	check("FCCM: perfect input (0.15s) → faceAngle=0, timedPerfect=true", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:RegisterFaceInput(t0 + 0.15)   -- exactly at ideal impact time
		local d = FCCM:GetFaceInputData()
		assert(d.timedPerfect == true, "expected timedPerfect")
		assert(d.faceAngle == 0, ("expected 0° for perfect timing, got %f°"):format(d.faceAngle))
	end)

	check("FCCM: late input (0.50s) → faceAngle>0, timedLate=true", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:RegisterFaceInput(t0 + 0.50)   -- 0.35s after ideal → beyond PERFECT_WINDOW → clamped to +10°
		local d = FCCM:GetFaceInputData()
		assert(d.timedLate == true, "expected timedLate")
		assert(d.faceAngle > 0, ("expected open face angle, got %f°"):format(d.faceAngle))
	end)

	check("FCCM: second RegisterFaceInput is ignored (only first press counts)", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:RegisterFaceInput(t0 + 0.50)   -- late → open face
		local firstAngle = FCCM:GetFaceInputData().faceAngle
		FCCM:RegisterFaceInput(t0 + 0.15)   -- second press at ideal — should be ignored
		local secondAngle = FCCM:GetFaceInputData().faceAngle
		assert(firstAngle == secondAngle,
			("expected first angle %f unchanged, got %f"):format(firstAngle, secondAngle))
	end)

	check("FCCM: Reset clears registered input → noInput=true, open face", function()
		FCCM:Reset()
		local d = FCCM:GetFaceInputData()
		assert(d.noInput == true, "expected noInput=true after Reset")
		assert(d.faceAngle > 0, ("expected open face >0° after Reset, got %f"):format(d.faceAngle))
	end)

	check("FCCM: Destroy + re-Init → noInput, open face default", function()
		FCCM:Destroy()
		FCCM:Init()
		local d = FCCM:GetFaceInputData()
		assert(d.noInput == true, "expected noInput after re-Init")
		assert(d.faceAngle > 0, ("expected open face >0° after re-Init, got %f"):format(d.faceAngle))
	end)

	-- ── Continuous face angle tests (Sprint 34.75) ────────────────────────────
	-- FACE_SENSITIVITY=80 deg/s, MAX_FACE_ANGLE=10°, IDEAL_IMPACT_DELAY=0.15s

	check("FCCM: small early error (0.03s early) → small negative angle (−4° to 0°)", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:RegisterFaceInput(t0 + 0.12)  -- delta = 0.12-0.15 = -0.03s → -2.4°
		local d = FCCM:GetFaceInputData()
		assert(d.faceAngle < 0,  ("expected faceAngle < 0, got %f"):format(d.faceAngle))
		assert(d.faceAngle > -4, ("expected faceAngle > -4°, got %f"):format(d.faceAngle))
	end)

	check("FCCM: large late error (0.25s late) → clamped to +MAX_FACE_ANGLE", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:RegisterFaceInput(t0 + 0.40)  -- delta = 0.40-0.15 = +0.25s → +20° → clamped to +10°
		local d = FCCM:GetFaceInputData()
		assert(d.faceAngle == 10.0,
			("expected +10° (MAX), got %f"):format(d.faceAngle))
	end)

	check("FCCM: large early error (0.15s early) → clamped to -MAX_FACE_ANGLE", function()
		FCCM:Reset()
		FCCM:StartFaceWindow(t0)
		FCCM:RegisterFaceInput(t0 + 0.00)  -- delta = 0.00-0.15 = -0.15s → -12° → clamped to -10°
		local d = FCCM:GetFaceInputData()
		assert(d.faceAngle == -10.0,
			("expected -10° (MAX), got %f"):format(d.faceAngle))
	end)

	-- ═══════════════════════════════════════════════════════════════════════════
	-- SwingFeedbackHUDModule
	-- ═══════════════════════════════════════════════════════════════════════════

	SFHM:Destroy()
	SFHM:Init()

	check("SFHM: module loads", function()
		assert(type(SFHM) == "table")
	end)

	check("SFHM: Init guard — double Init warns and skips", function()
		SFHM:Init()  -- second call; guard should prevent crash
	end)

	check("SFHM: UpdatePhase — no error", function()
		SFHM:UpdatePhase("InputStarted")
		SFHM:UpdatePhase("Backswing")
		SFHM:UpdatePhase("Downswing")
		SFHM:UpdatePhase("Released")
		SFHM:UpdatePhase("Idle")
	end)

	check("SFHM: ShowResult — all fields (Accel/Energy/face meter), no error", function()
		SFHM:ShowResult({
			power01                 = 0.75,
			clubPath                = 3.2,
			faceAngle               = -1.5,
			tempoScore              = 0.87,
			contactQuality          = "Good",
			shotShape               = "Draw",
			accelerationConsistency = 0.88,
			swingEnergy             = 0.73,
		})
	end)

	check("SFHM: ShowResult open face → face meter moves right, no error", function()
		SFHM:ShowResult({
			power01                 = 0.60,
			clubPath                = 4.0,
			faceAngle               = 7.5,  -- open face → marker right of center
			tempoScore              = 0.82,
			contactQuality          = "Good",
			shotShape               = "Slice",
			accelerationConsistency = 0.81,
			swingEnergy             = 0.65,
		})
	end)

	check("SFHM: ShowResult missing optional fields defaults gracefully", function()
		SFHM:ShowResult({})  -- all fields absent → defaults to 0 / "--"
	end)

	check("SFHM: ResetDisplay — no error", function()
		SFHM:ResetDisplay()
	end)

	check("SFHM: Update(0) — no error", function()
		SFHM:Update(0)
	end)

	check("SFHM: Destroy — no error", function()
		SFHM:Destroy()
	end)

	-- ═══════════════════════════════════════════════════════════════════════════
	-- PlayableHoleControllerModule — Sprint 33 backward compatibility
	-- ═══════════════════════════════════════════════════════════════════════════

	PHCM:Destroy()
	PHCM:Init()

	check("PHCM: Sprint33 compat — Shoot() sets lastInput='Shoot'", function()
		pcall(function() PHCM:Shoot() end)
		local s = PHCM:GetState()
		assert(s.lastInput == "Shoot",
			("expected 'Shoot', got %q"):format(s.lastInput))
	end)

	check("PHCM: Sprint33 compat — GetState().power > 0", function()
		local s = PHCM:GetState()
		assert(type(s.power) == "number" and s.power > 0,
			("expected power > 0, got %s"):format(tostring(s.power)))
	end)

	check("PHCM: Sprint33 compat — GetState().aimDirection is Vector3", function()
		local s = PHCM:GetState()
		assert(typeof(s.aimDirection) == "Vector3")
	end)

	check("PHCM: swing sub-modules initialized after Init()", function()
		-- Each sub-module should be in Idle / ready state after PHCM:Init()
		local swingState = SICM:GetSwingState()
		assert(swingState.enabled == true, "SICM should be enabled")
		assert(swingState.phase == "Idle" or type(swingState.phase) == "string")
	end)

	check("PHCM: SwingInput can receive Begin/Update/End after PHCM:Init()", function()
		SICM:BeginInput(Vector2.new(400, 300))
		SICM:UpdateInput(Vector2.new(400, 345))
		SICM:UpdateInput(Vector2.new(400, 328))
		SICM:EndInput(Vector2.new(400, 260))
		local raw = SICM:GetRawSwingData()
		assert(raw ~= nil, "expected raw swing data after manual input sequence")
		assert(raw.cancelled == false)
	end)

	check("PHCM: SAM can analyze a manual swing from SICM output", function()
		SICM:BeginInput(Vector2.new(400, 300))
		SICM:UpdateInput(Vector2.new(400, 345))
		SICM:UpdateInput(Vector2.new(400, 328))
		SICM:EndInput(Vector2.new(400, 260))
		local raw      = SICM:GetRawSwingData()
		local faceData = FCCM:GetFaceInputData()
		assert(raw ~= nil, "no raw data")
		local result = SAM:Analyze(raw, faceData, Vector3.new(0, 0, -1))
		assert(type(result.valid) == "boolean")
		assert(type(result.contactQuality) == "string")
		assert(type(result.shotShape) == "string")
		assert(typeof(result.launchDirection) == "Vector3")
	end)

	check("PHCM: Destroy tears down sub-modules (SICM returns to Idle)", function()
		PHCM:Destroy()
		-- SICM was destroyed; BeginInput should be no-op
		SICM:BeginInput(Vector2.new(400, 300))
		local s = SICM:GetSwingState()
		assert(s.phase == "Idle",
			("SICM should be in Idle after PHCM:Destroy(), got %q"):format(s.phase))
	end)

	-- ── Summary ───────────────────────────────────────────────────────────────
	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 34 client tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end
