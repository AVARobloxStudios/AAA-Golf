--!strict
return function()
-- Sprint18ClientTest — LocalScript
-- Client smoke tests for Sprint 18: NetworkController, EventRouterController,
-- and PlayerStateController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.
-- Tests drive each module via its public API only.
-- No real round or real server response required.
-- Send/Invoke are tested only with invalid names (no actual FireServer calls).

print("[Sprint18ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint18ClientTest]"
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

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — NetworkControllerModule  (checks 1–9)
-- ════════════════════════════════════════════════════════════════════════════

local ncOk, ncResult = safeRequire(
	script.Parent.Parent.Modules.NetworkControllerModule)

if ncOk then

	local NCM: any = ncResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("NCM: module loads successfully", function()
		assert(type(NCM) == "table", "expected table, got " .. type(NCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	-- ReplicatedStorage.Network is present in Play mode (declared in project.json).
	check("NCM: IsReady() is true when Network folder is available", function()
		assert(NCM:IsReady() == true,
			"expected IsReady=true in Play mode (Network folder should exist)")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("NCM: GetRemote('GameBus') returns a non-nil Instance", function()
		local remote = NCM:GetRemote("GameBus")
		assert(remote ~= nil, "expected GameBus remote to exist")
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("NCM: GetRemote('GetCourseData') returns a non-nil Instance", function()
		local remote = NCM:GetRemote("GetCourseData")
		assert(remote ~= nil, "expected GetCourseData RemoteFunction to exist")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("NCM: GetRemote for unknown name returns nil", function()
		assert(NCM:GetRemote("DOES_NOT_EXIST") == nil,
			"expected nil for unknown remote name")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	-- Only tests the rejection path — does NOT fire server.
	check("NCM: Send with unknown event name warns and does not error", function()
		NCM:Send("FAKE_EVENT_XYZ", {})
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	-- Only tests the rejection path — does NOT invoke server.
	check("NCM: Invoke with unknown function name warns and does not error", function()
		local result = NCM:Invoke("FAKE_FUNCTION_XYZ", {})
		assert(result == nil, "expected nil return for unknown function")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("NCM: Destroy resets to not-ready", function()
		NCM:Destroy()
		assert(NCM:IsReady()             == false, "expected not-ready after Destroy")
		assert(NCM:GetRemote("GameBus") == nil,   "expected nil remote after Destroy")
	end)

	-- Restore
	NCM:Init()

	-- 9 ────────────────────────────────────────────────────────────────────
	check("NCM: IsReady and GetRemote work after Init restore", function()
		assert(NCM:IsReady() == true, "expected ready after re-Init")
		assert(NCM:GetRemote("GameBus") ~= nil, "expected GameBus after re-Init")
	end)

end -- ncOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — EventRouterControllerModule  (checks 10–23)
-- ════════════════════════════════════════════════════════════════════════════

local erOk, erResult = safeRequire(
	script.Parent.Parent.Modules.EventRouterControllerModule)

if erOk then

	local ERC: any = erResult

	-- 10 ───────────────────────────────────────────────────────────────────
	check("ERC: module loads successfully", function()
		assert(type(ERC) == "table", "expected table, got " .. type(ERC))
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("ERC: GetHandlerCount for unregistered type is 0", function()
		assert(ERC:GetHandlerCount("TestEvent") == 0,
			"expected 0 handlers initially")
	end)

	-- Shared state for handler call tracking
	local callLog: { string } = {}

	local function handlerA(env: any)
		table.insert(callLog, "A:" .. tostring(env.eventType))
	end
	local function handlerB(env: any)
		table.insert(callLog, "B:" .. tostring(env.eventType))
	end

	-- 12 ───────────────────────────────────────────────────────────────────
	check("ERC: RegisterHandler adds handler", function()
		ERC:RegisterHandler("TestEvent", handlerA)
		assert(ERC:GetHandlerCount("TestEvent") == 1, "expected 1 handler after register")
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("ERC: RouteEvent calls registered handler", function()
		table.clear(callLog)
		ERC:RouteEvent({ eventType = "TestEvent", payload = {} })
		assert(#callLog == 1 and callLog[1] == "A:TestEvent",
			("expected handler called once, got: %s"):format(table.concat(callLog, ", ")))
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("ERC: multiple handlers for same type are all called", function()
		ERC:RegisterHandler("TestEvent", handlerB)
		assert(ERC:GetHandlerCount("TestEvent") == 2, "expected 2 handlers")
		table.clear(callLog)
		ERC:RouteEvent({ eventType = "TestEvent", payload = {} })
		assert(#callLog == 2, ("expected 2 calls, got %d"):format(#callLog))
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("ERC: RouteEvent for unregistered type does not error", function()
		ERC:RouteEvent({ eventType = "UnknownEvent", payload = {} })
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("ERC: UnregisterHandler removes specific handler by identity", function()
		ERC:UnregisterHandler("TestEvent", handlerA)
		assert(ERC:GetHandlerCount("TestEvent") == 1,
			"expected 1 handler after unregister of handlerA")
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("ERC: RouteEvent after unregister does not call removed handler", function()
		table.clear(callLog)
		ERC:RouteEvent({ eventType = "TestEvent", payload = {} })
		assert(#callLog == 1 and callLog[1] == "B:TestEvent",
			"only handlerB should be called after handlerA unregistered")
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("ERC: UnregisterHandler last handler clears the type entry", function()
		ERC:UnregisterHandler("TestEvent", handlerB)
		assert(ERC:GetHandlerCount("TestEvent") == 0,
			"expected 0 handlers after both unregistered")
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("ERC: RegisterHandler for multiple event types works", function()
		ERC:RegisterHandler("StateChanged",  handlerA)
		ERC:RegisterHandler("RoundComplete", handlerB)
		assert(ERC:GetHandlerCount("StateChanged")  == 1, "expected 1 StateChanged handler")
		assert(ERC:GetHandlerCount("RoundComplete") == 1, "expected 1 RoundComplete handler")
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("ERC: ClearHandlers removes all registered handlers", function()
		ERC:ClearHandlers()
		assert(ERC:GetHandlerCount("StateChanged")  == 0, "expected 0 after ClearHandlers")
		assert(ERC:GetHandlerCount("RoundComplete") == 0, "expected 0 after ClearHandlers")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("ERC: RouteEvent with non-table envelope is rejected safely", function()
		ERC:RouteEvent("not a table" :: any)   -- should warn, not throw
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("ERC: RouteEvent with non-string eventType is rejected safely", function()
		ERC:RouteEvent({ eventType = 42 } :: any)   -- should warn, not throw
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("ERC: Destroy resets all handlers", function()
		ERC:RegisterHandler("TestEvent", handlerA)
		ERC:Destroy()
		assert(ERC:GetHandlerCount("TestEvent") == 0,
			"expected 0 handlers after Destroy")
	end)

	-- Restore
	ERC:Init()

	-- 24 ───────────────────────────────────────────────────────────────────  (bonus)
	check("ERC: RegisterHandler and RouteEvent work after Init restore", function()
		table.clear(callLog)
		ERC:RegisterHandler("RestoredEvent", handlerA)
		ERC:RouteEvent({ eventType = "RestoredEvent", payload = "test" })
		assert(#callLog == 1 and callLog[1] == "A:RestoredEvent",
			"expected handlerA called after restore")
		ERC:ClearHandlers()
	end)

end -- erOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — PlayerStateControllerModule  (checks 25–38)
-- ════════════════════════════════════════════════════════════════════════════

local psOk, psResult = safeRequire(
	script.Parent.Parent.Modules.PlayerStateControllerModule)

if psOk then

	local PSC: any = psResult

	-- 25 ───────────────────────────────────────────────────────────────────
	check("PSC: module loads successfully", function()
		assert(type(PSC) == "table", "expected table, got " .. type(PSC))
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("PSC: default gameState is 'LOBBY'", function()
		assert(PSC:GetStateField("gameState") == "LOBBY",
			("expected 'LOBBY', got %q"):format(tostring(PSC:GetStateField("gameState"))))
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("PSC: default holeNumber is 1", function()
		assert(PSC:GetStateField("holeNumber") == 1,
			("expected 1, got %s"):format(tostring(PSC:GetStateField("holeNumber"))))
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("PSC: all 10 default fields are present and correct", function()
		assert(PSC:GetStateField("gameState")      == "LOBBY",    "bad gameState")
		assert(PSC:GetStateField("holeNumber")     == 1,         "bad holeNumber")
		assert(PSC:GetStateField("strokeCount")    == 0,         "bad strokeCount")
		assert(PSC:GetStateField("currentClub")    == "Driver",  "bad currentClub")
		assert(PSC:GetStateField("aimAngle")       == 0,         "bad aimAngle")
		assert(PSC:GetStateField("swingPower")     == 0,         "bad swingPower")
		assert(PSC:GetStateField("coins")          == 0,         "bad coins")
		assert(PSC:GetStateField("xp")             == 0,         "bad xp")
		assert(PSC:GetStateField("selectedCourse") == "course_1","bad selectedCourse")
		assert(PSC:GetStateField("isReady")        == false,     "bad isReady")
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("PSC: SetStateField updates a valid field", function()
		PSC:SetStateField("gameState", "SWING")
		assert(PSC:GetStateField("gameState") == "SWING",
			("expected 'SWING', got %q"):format(tostring(PSC:GetStateField("gameState"))))
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("PSC: SetStateField updates numeric fields", function()
		PSC:SetStateField("strokeCount", 3)
		PSC:SetStateField("coins",       500)
		assert(PSC:GetStateField("strokeCount") == 3,   "wrong strokeCount")
		assert(PSC:GetStateField("coins")       == 500, "wrong coins")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("PSC: SetStateField rejects unknown field names", function()
		PSC:SetStateField("INVALID_FIELD", "bad")
		assert(PSC:GetStateField("INVALID_FIELD") == nil,
			"unknown field must not be set")
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("PSC: GetStateField returns nil for unknown fields", function()
		assert(PSC:GetStateField("NOT_A_FIELD") == nil,
			"expected nil for unknown field")
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("PSC: ApplySnapshot merges valid fields", function()
		PSC:ApplySnapshot({ holeNumber = 5, xp = 200, coins = 1000 })
		assert(PSC:GetStateField("holeNumber") == 5,    "wrong holeNumber after snapshot")
		assert(PSC:GetStateField("xp")         == 200,  "wrong xp after snapshot")
		assert(PSC:GetStateField("coins")      == 1000, "wrong coins after snapshot")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("PSC: ApplySnapshot silently ignores unknown keys", function()
		local before = PSC:GetStateField("gameState")
		PSC:ApplySnapshot({ UNKNOWN_KEY = "bad", gameState = "TEE_OFF" })
		assert(PSC:GetStateField("gameState")    == "TEE_OFF", "known key should apply")
		assert(PSC:GetStateField("UNKNOWN_KEY") == nil,       "unknown key must be ignored")
		-- Restore
		PSC:SetStateField("gameState", before)
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("PSC: GetSnapshot returns all fields", function()
		local snap = PSC:GetSnapshot()
		assert(type(snap) == "table",           "expected table")
		assert(snap["gameState"]  ~= nil,       "expected gameState in snapshot")
		assert(snap["holeNumber"] ~= nil,       "expected holeNumber in snapshot")
		assert(snap["isReady"]    ~= nil,       "expected isReady in snapshot")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("PSC: GetSnapshot returns a copy (mutation does not affect internal)", function()
		local snap = PSC:GetSnapshot()
		snap["gameState"] = "MUTATED"
		assert(PSC:GetStateField("gameState") ~= "MUTATED",
			"mutating snapshot copy must not change internal state")
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("PSC: ResetState restores all fields to defaults", function()
		PSC:ResetState()
		assert(PSC:GetStateField("gameState")      == "LOBBY",    "expected LOBBY")
		assert(PSC:GetStateField("holeNumber")     == 1,         "expected 1")
		assert(PSC:GetStateField("strokeCount")    == 0,         "expected 0")
		assert(PSC:GetStateField("currentClub")    == "Driver",  "expected Driver")
		assert(PSC:GetStateField("coins")          == 0,         "expected 0 coins")
		assert(PSC:GetStateField("isReady")        == false,     "expected false")
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("PSC: Destroy clears all state fields", function()
		PSC:Destroy()
		assert(PSC:GetStateField("gameState") == nil,
			"expected nil gameState after Destroy (field map is cleared)")
	end)

	-- Restore
	PSC:Init()

	-- 39 ───────────────────────────────────────────────────────────────────
	check("PSC: defaults restored after Init restore", function()
		assert(PSC:GetStateField("gameState")   == "LOBBY",   "expected LOBBY after restore")
		assert(PSC:GetStateField("holeNumber")  == 1,        "expected 1 after restore")
		assert(PSC:GetStateField("coins")       == 0,        "expected 0 coins after restore")
		PSC:SetStateField("isReady", true)
		assert(PSC:GetStateField("isReady") == true, "SetStateField should work after restore")
	end)

end -- psOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 18 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
end
