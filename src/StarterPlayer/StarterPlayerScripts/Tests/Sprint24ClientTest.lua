--!strict
return function()
-- Sprint24ClientTest — ModuleScript
-- Client smoke tests for Sprint 24: ClientAckIntegrationControllerModule.
-- Run via TestRunner.client.lua; output appears in the Roblox Studio Output window.
--
-- Covers (17 checks):
--   CAIC — module loading, DispatchAllAndTrack, DispatchActionAndTrack,
--     GetLastDispatchCount, SAC tracking, GetLastAckStatus (Pending/Accepted/Unknown),
--     simulated ack via EventRouter, Reset, Destroy/re-Init.
--
-- Thin runners call Module:Init() before this script loads.
-- Section resets all five dependencies for test isolation.
-- ER (EventRouter) is NOT reset — that would wipe other modules' handlers.
-- ABC is Destroy()d to unregister its handlers, then re-Init()d so RouteEvent works.

print("[Sprint24ClientTest] Script started")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local TAG    = "[Sprint24ClientTest]"
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

local function safeRequire(path: Instance): (boolean, any)
	local ok, result = pcall(require, path :: any)
	if not ok then
		warn(TAG .. " FATAL: require failed — " .. tostring(result))
	end
	return ok, result
end

-- ── Shared dependencies ───────────────────────────────────────────────────────

local cacOk, cacResult = safeRequire(script.Parent.Parent.Modules.ClientActionControllerModule)
local adcOk, adcResult = safeRequire(script.Parent.Parent.Modules.ActionDispatchControllerModule)
local sacOk, sacResult = safeRequire(script.Parent.Parent.Modules.ServerAckControllerModule)
local abcOk, abcResult = safeRequire(script.Parent.Parent.Modules.AckBridgeControllerModule)
local erOk,  erResult  = safeRequire(script.Parent.Parent.Modules.EventRouterControllerModule)

-- ════════════════════════════════════════════════════════════════════════════
-- Section — ClientAckIntegrationControllerModule  (checks 1–17)
-- ════════════════════════════════════════════════════════════════════════════

local caicOk, caicResult = safeRequire(
	script.Parent.Parent.Modules.ClientAckIntegrationControllerModule)

if caicOk and cacOk and adcOk and sacOk and abcOk and erOk then

	local CAIC: any = caicResult
	local CAC:  any = cacResult
	local ADC:  any = adcResult
	local SAC:  any = sacResult
	local ABC:  any = abcResult
	local ER:   any = erResult

	-- Reset for test isolation.
	-- ABC:Destroy() unregisters its 3 EventRouter handlers.
	-- ER is NOT reset — that would wipe handlers from other modules.
	CAIC:Destroy()
	ADC:Destroy()
	ABC:Destroy()
	SAC:Destroy()
	CAC:Destroy()

	CAC:Init()
	ADC:Init()
	SAC:Init()
	ABC:Init()     -- re-registers 3 handlers with ER
	CAIC:Init()

	-- 1 ─────────────────────────────────────────────────────────────────────
	check("CAIC: module loads successfully", function()
		assert(type(CAIC) == "table", "expected table, got " .. type(CAIC))
	end)

	-- 2 ─────────────────────────────────────────────────────────────────────
	check("CAIC: GetLastDispatchCount() is 0 initially", function()
		assert(CAIC:GetLastDispatchCount() == 0,
			("expected 0, got %d"):format(CAIC:GetLastDispatchCount()))
	end)

	-- 3 ─────────────────────────────────────────────────────────────────────
	check("CAIC: DispatchAllAndTrack with empty queue → lastDispatchCount = 0", function()
		CAC:ClearActions()
		ADC:ResetDispatchedCount()
		CAIC:DispatchAllAndTrack()
		assert(CAIC:GetLastDispatchCount() == 0,
			("expected 0, got %d"):format(CAIC:GetLastDispatchCount()))
	end)

	-- 4 ─────────────────────────────────────────────────────────────────────
	local swingId: string = ""
	check("CAIC: DispatchAllAndTrack with one queued action → lastDispatchCount = 1", function()
		CAC:ClearActions()
		ADC:ResetDispatchedCount()
		local id = CAC:QueueAction("SwingIntent", { power = 0.75 })
		assert(type(id) == "string" and id ~= "", "CAC:QueueAction failed")
		swingId = id :: string
		CAIC:DispatchAllAndTrack()
		assert(CAIC:GetLastDispatchCount() == 1,
			("expected 1, got %d"):format(CAIC:GetLastDispatchCount()))
	end)

	-- 5 ─────────────────────────────────────────────────────────────────────
	check("CAIC: SAC has a Pending entry after DispatchAllAndTrack", function()
		assert(SAC:GetPendingCount() == 1,
			("expected 1 pending entry in SAC, got %d"):format(SAC:GetPendingCount()))
		local ack = SAC:GetAck(swingId)
		assert(type(ack) == "table", "expected AckEntry, got nil")
	end)

	-- 6 ─────────────────────────────────────────────────────────────────────
	check("CAIC: GetLastAckStatus returns 'Pending' for tracked action", function()
		local status = CAIC:GetLastAckStatus(swingId)
		assert(status == "Pending",
			("expected 'Pending', got %q"):format(status))
	end)

	-- 7 ─────────────────────────────────────────────────────────────────────
	check("CAIC: GetLastAckStatus returns 'Unknown' for untracked actionId", function()
		local status = CAIC:GetLastAckStatus("not_a_real_action_id")
		assert(status == "Unknown",
			("expected 'Unknown', got %q"):format(status))
	end)

	-- 8 ─────────────────────────────────────────────────────────────────────
	check("CAIC: second DispatchAllAndTrack skips already-sent action → lastDispatchCount = 0", function()
		CAIC:DispatchAllAndTrack()
		assert(CAIC:GetLastDispatchCount() == 0,
			("expected 0 for already-sent queue, got %d"):format(
				CAIC:GetLastDispatchCount()))
	end)

	-- 9 ─────────────────────────────────────────────────────────────────────
	-- Route a RequestAck through EventRouter → AckBridgeController fires →
	-- SAC:ReceiveAck updates the entry status to "Accepted".
	check("CAIC: simulated RequestAck via EventRouter routes through AckBridge to SAC", function()
		ER:RouteEvent({
			eventType = "RequestAck",
			payload   = { requestId = swingId, status = "Accepted" },
			timestamp = os.clock(),
		})
		local ack = SAC:GetAck(swingId)
		assert(type(ack) == "table", "expected AckEntry after ack")
		assert(ack.status == "Accepted",
			("expected 'Accepted' in SAC after RouteEvent, got %q"):format(
				tostring(ack.status)))
	end)

	-- 10 ─────────────────────────────────────────────────────────────────────
	check("CAIC: GetLastAckStatus returns 'Accepted' after ack is received", function()
		local status = CAIC:GetLastAckStatus(swingId)
		assert(status == "Accepted",
			("expected 'Accepted', got %q"):format(status))
	end)

	-- 11 ─────────────────────────────────────────────────────────────────────
	local readyId: string = ""
	check("CAIC: DispatchActionAndTrack dispatches and tracks one action", function()
		CAC:ClearActions()
		ADC:ResetDispatchedCount()
		local id = CAC:QueueAction("SetReady", { isReady = true })
		assert(type(id) == "string" and id ~= "", "CAC:QueueAction failed")
		readyId = id :: string
		CAIC:DispatchActionAndTrack(readyId)
		assert(ADC:GetDispatchedCount() == 1,
			("expected ADC dispatchedCount 1, got %d"):format(ADC:GetDispatchedCount()))
		local ack = SAC:GetAck(readyId)
		assert(type(ack) == "table", "expected AckEntry in SAC after DispatchActionAndTrack")
		assert(ack.status == "Pending",
			("expected 'Pending', got %q"):format(tostring(ack.status)))
	end)

	-- 12 ─────────────────────────────────────────────────────────────────────
	check("CAIC: DispatchActionAndTrack → lastDispatchCount = 1", function()
		assert(CAIC:GetLastDispatchCount() == 1,
			("expected 1, got %d"):format(CAIC:GetLastDispatchCount()))
	end)

	-- 13 ─────────────────────────────────────────────────────────────────────
	check("CAIC: DispatchActionAndTrack with unknown actionId → lastDispatchCount = 0", function()
		CAIC:DispatchActionAndTrack("no_such_action_id_s24")
		assert(CAIC:GetLastDispatchCount() == 0,
			("expected 0, got %d"):format(CAIC:GetLastDispatchCount()))
	end)

	-- 14 ─────────────────────────────────────────────────────────────────────
	check("CAIC: Reset() clears lastDispatchCount to 0", function()
		-- Set it to something non-zero first.
		CAC:ClearActions()
		local tmpId = CAC:QueueAction("HoleReady", {})
		CAIC:DispatchAllAndTrack()
		assert(CAIC:GetLastDispatchCount() == 1, "pre-condition: count should be 1")
		CAIC:Reset()
		assert(CAIC:GetLastDispatchCount() == 0,
			("expected 0 after Reset(), got %d"):format(CAIC:GetLastDispatchCount()))
		-- SAC entry for tmpId should still exist (Reset only clears CAIC state).
		assert(SAC:GetAck(tmpId :: string) ~= nil,
			"SAC entry must survive CAIC:Reset()")
	end)

	-- 15 ─────────────────────────────────────────────────────────────────────
	check("CAIC: Update(0) does not error", function()
		CAIC:Update(0)
	end)

	-- 16 ─────────────────────────────────────────────────────────────────────
	check("CAIC: Destroy resets lastDispatchCount to 0", function()
		-- Ensure count is non-zero before Destroy.
		CAC:ClearActions()
		CAC:QueueAction("HoleReady", {})
		CAIC:DispatchAllAndTrack()
		assert(CAIC:GetLastDispatchCount() == 1, "pre-condition: count should be 1")
		CAIC:Destroy()
		assert(CAIC:GetLastDispatchCount() == 0,
			("expected 0 after Destroy, got %d"):format(CAIC:GetLastDispatchCount()))
	end)

	-- 17 ─────────────────────────────────────────────────────────────────────
	check("CAIC: re-Init after Destroy works — DispatchAllAndTrack functional", function()
		CAIC:Init()
		CAC:ClearActions()
		ADC:ResetDispatchedCount()
		CAC:QueueAction("QueueMatchmaking", {})
		CAIC:DispatchAllAndTrack()
		assert(CAIC:GetLastDispatchCount() == 1,
			("expected 1 after re-Init DispatchAllAndTrack, got %d"):format(
				CAIC:GetLastDispatchCount()))
	end)

	-- ── Teardown ─────────────────────────────────────────────────────────────
	CAIC:Destroy()

else
	warn(TAG .. " SKIP: ClientAckIntegrationControllerModule section — require failed")
end

-- ── Summary ───────────────────────────────────────────────────────────────────

print(TAG .. (" COMPLETE — %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	warn(TAG .. " Some checks failed — see output above")
end

end
