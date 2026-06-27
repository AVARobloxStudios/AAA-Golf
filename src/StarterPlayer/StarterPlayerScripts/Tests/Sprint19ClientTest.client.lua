--!strict
-- Sprint19ClientTest — LocalScript
-- Client smoke tests for Sprint 19: GameBusBridgeController,
-- StateSyncController, and ControllerBridgeController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.
-- No real round or real server response required.
-- GameBus events are simulated via _simulateEvent().
-- ERC event routing is driven directly via RouteEvent().

print("[Sprint19ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint19ClientTest]"
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

-- Pre-load Sprint 18 singletons used as scaffolding in multiple sections.
local Players = game:GetService("Players")
local LocalUserId = Players.LocalPlayer.UserId

local _ercOk, ErcRaw = safeRequire(script.Parent.Parent.Modules.EventRouterControllerModule)
local _pscOk, PscRaw = safeRequire(script.Parent.Parent.Modules.PlayerStateControllerModule)

local ERC: any = ErcRaw
local PSC: any = PscRaw

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — GameBusBridgeControllerModule  (checks 1–11)
-- ════════════════════════════════════════════════════════════════════════════

local gbbOk, gbbResult = safeRequire(
	script.Parent.Parent.Modules.GameBusBridgeControllerModule)

if gbbOk and _ercOk then

	local GBB: any = gbbResult

	-- Ensure ERC is in a clean state for this section.
	ERC:ClearHandlers()

	-- 1 ────────────────────────────────────────────────────────────────────
	check("GBB: module loads successfully", function()
		assert(type(GBB) == "table", "expected table, got " .. type(GBB))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	-- GameBus remote exists in Play mode (declared in default.project.json).
	check("GBB: IsConnected() is true in Play mode", function()
		assert(GBB:IsConnected() == true,
			"expected connected=true in Play mode (GameBus remote should exist)")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("GBB: GetRoutedCount() starts at 0", function()
		assert(GBB:GetRoutedCount() == 0,
			("expected 0, got %d"):format(GBB:GetRoutedCount()))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("GBB: _simulateEvent with non-table envelope is ignored", function()
		local before = GBB:GetRoutedCount()
		GBB:_simulateEvent("not a table" :: any)
		assert(GBB:GetRoutedCount() == before,
			"invalid envelope must not increment routedCount")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	-- Register a test handler so we can confirm ERC dispatch fires.
	local routedPayload: any = nil
	ERC:RegisterHandler("GBBTestEvent", function(env: any)
		routedPayload = env.payload
	end)

	check("GBB: _simulateEvent with valid envelope increments routedCount", function()
		GBB:_simulateEvent({ eventType = "GBBTestEvent", payload = { v = 7 } })
		assert(GBB:GetRoutedCount() == 1,
			("expected routedCount=1, got %d"):format(GBB:GetRoutedCount()))
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("GBB: valid envelope is forwarded to EventRouter handlers", function()
		assert(routedPayload ~= nil,    "expected handler to receive payload")
		assert(routedPayload.v == 7,    "expected payload.v == 7")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("GBB: second simulate increments routedCount to 2", function()
		GBB:_simulateEvent({ eventType = "GBBTestEvent", payload = { v = 8 } })
		assert(GBB:GetRoutedCount() == 2,
			("expected 2, got %d"):format(GBB:GetRoutedCount()))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("GBB: Disconnect() sets IsConnected() false", function()
		GBB:Disconnect()
		assert(GBB:IsConnected() == false,
			"expected IsConnected=false after Disconnect()")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("GBB: _simulateEvent after Disconnect() does not increment count", function()
		local before = GBB:GetRoutedCount()
		GBB:_simulateEvent({ eventType = "GBBTestEvent", payload = {} })
		assert(GBB:GetRoutedCount() == before,
			"routedCount must not change when disconnected")
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("GBB: Destroy() resets count and connected state", function()
		GBB:Destroy()
		assert(GBB:IsConnected()     == false, "expected disconnected after Destroy")
		assert(GBB:GetRoutedCount()  == 0,     "expected count=0 after Destroy")
	end)

	-- Restore
	ERC:ClearHandlers()
	GBB:Init()

	-- 11 ───────────────────────────────────────────────────────────────────
	check("GBB: IsConnected and _simulateEvent work after Init restore", function()
		assert(GBB:IsConnected() == true, "expected connected after re-Init")
		local before = GBB:GetRoutedCount()
		GBB:_simulateEvent({ eventType = "NoHandlerEvent", payload = {} })
		-- routedCount should increment (envelope is valid and connection is up)
		assert(GBB:GetRoutedCount() == before + 1,
			"expected routedCount to increment after restore")
	end)

end -- gbbOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — StateSyncControllerModule  (checks 12–23)
-- ════════════════════════════════════════════════════════════════════════════

local sscOk, sscResult = safeRequire(
	script.Parent.Parent.Modules.StateSyncControllerModule)

if sscOk and _ercOk and _pscOk then

	local SSC: any = sscResult

	-- Reset both singletons to a known baseline before testing.
	PSC:ResetState()
	SSC:ResetSyncCount()

	-- 12 ───────────────────────────────────────────────────────────────────
	check("SSC: module loads successfully", function()
		assert(type(SSC) == "table", "expected table, got " .. type(SSC))
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("SSC: GetSyncedEventCount() is 0 after reset", function()
		assert(SSC:GetSyncedEventCount() == 0,
			("expected 0, got %d"):format(SSC:GetSyncedEventCount()))
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("SSC: ERC has StateChanged handler registered", function()
		assert(ERC:GetHandlerCount("StateChanged") >= 1,
			"expected at least 1 StateChanged handler registered by SSC")
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("SSC: StateChanged updates PSC.gameState for local player", function()
		ERC:RouteEvent({
			eventType = "StateChanged",
			payload   = { playerId = LocalUserId, state = "SWING" },
		})
		assert(PSC:GetStateField("gameState") == "SWING",
			("expected 'SWING', got %q"):format(
				tostring(PSC:GetStateField("gameState"))))
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("SSC: StateChanged for other player is ignored", function()
		ERC:RouteEvent({
			eventType = "StateChanged",
			payload   = { playerId = LocalUserId + 9999, state = "OTHER_PLAYER" },
		})
		assert(PSC:GetStateField("gameState") == "SWING",
			"other-player StateChanged must not update local gameState")
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("SSC: StrokeCommitted updates strokeCount, coins, xp", function()
		ERC:RouteEvent({
			eventType = "StrokeCommitted",
			payload   = { strokeCount = 3, coins = 50, xp = 10 },
		})
		assert(PSC:GetStateField("strokeCount") == 3,  "wrong strokeCount")
		assert(PSC:GetStateField("coins")       == 50, "wrong coins")
		assert(PSC:GetStateField("xp")          == 10, "wrong xp")
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("SSC: HoleComplete advances holeNumber and resets strokeCount", function()
		ERC:RouteEvent({
			eventType = "HoleComplete",
			payload   = { holeNumber = 2 },
		})
		assert(PSC:GetStateField("holeNumber")  == 2, "expected holeNumber=2")
		assert(PSC:GetStateField("strokeCount") == 0, "strokeCount should reset on HoleComplete")
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("SSC: RoundComplete sets gameState to 'ROUND_COMPLETE'", function()
		ERC:RouteEvent({ eventType = "RoundComplete", payload = {} })
		assert(PSC:GetStateField("gameState") == "ROUND_COMPLETE",
			("expected 'ROUND_COMPLETE', got %q"):format(
				tostring(PSC:GetStateField("gameState"))))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("SSC: MatchComplete also sets gameState to 'ROUND_COMPLETE'", function()
		PSC:SetStateField("gameState", "LOBBY")  -- reset to confirm MatchComplete fires
		ERC:RouteEvent({ eventType = "MatchComplete", payload = {} })
		assert(PSC:GetStateField("gameState") == "ROUND_COMPLETE",
			"expected 'ROUND_COMPLETE' after MatchComplete")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("SSC: GetSyncedEventCount reflects processed event count", function()
		-- 5 events processed (checks 15, 17, 18, 19, 20); check 16 was ignored
		assert(SSC:GetSyncedEventCount() >= 5,
			("expected ≥5 synced events, got %d"):format(SSC:GetSyncedEventCount()))
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("SSC: ResetSyncCount resets counter to 0", function()
		SSC:ResetSyncCount()
		assert(SSC:GetSyncedEventCount() == 0,
			("expected 0 after reset, got %d"):format(SSC:GetSyncedEventCount()))
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("SSC: Destroy() unregisters handlers — StateChanged no longer updates PSC", function()
		SSC:Destroy()
		PSC:ResetState()   -- puts gameState back to "LOBBY"
		ERC:RouteEvent({
			eventType = "StateChanged",
			payload   = { playerId = LocalUserId, state = "DESTROYED_STATE" },
		})
		assert(PSC:GetStateField("gameState") == "LOBBY",
			"handler must be unregistered after Destroy — PSC must not update")
	end)

	-- Restore
	SSC:Init()
	PSC:ResetState()

	-- 24 ───────────────────────────────────────────────────────────────────  (bonus)
	check("SSC: StateChanged works again after Init restore", function()
		ERC:RouteEvent({
			eventType = "StateChanged",
			payload   = { playerId = LocalUserId, state = "TEE_OFF" },
		})
		assert(PSC:GetStateField("gameState") == "TEE_OFF",
			"expected 'TEE_OFF' after restore")
	end)

end -- sscOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — ControllerBridgeControllerModule  (checks 25–35)
-- ════════════════════════════════════════════════════════════════════════════

local cbOk, cbResult = safeRequire(
	script.Parent.Parent.Modules.ControllerBridgeControllerModule)

if cbOk then

	local CBM: any = cbResult

	-- 25 ───────────────────────────────────────────────────────────────────
	check("CBM: module loads successfully", function()
		assert(type(CBM) == "table", "expected table, got " .. type(CBM))
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("CBM: IsReady() is true after Init", function()
		assert(CBM:IsReady() == true, "expected ready=true after Init")
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("CBM: GetRegisteredBridgeCount() is 0 initially", function()
		assert(CBM:GetRegisteredBridgeCount() == 0,
			("expected 0, got %d"):format(CBM:GetRegisteredBridgeCount()))
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("CBM: RegisterBridge adds a named bridge", function()
		CBM:RegisterBridge("double", function(payload: any): any
			return payload.value * 2
		end)
		assert(CBM:GetRegisteredBridgeCount() == 1,
			("expected 1 bridge, got %d"):format(CBM:GetRegisteredBridgeCount()))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("CBM: RunBridge calls the callback and returns result", function()
		local result = CBM:RunBridge("double", { value = 6 })
		assert(result == 12, ("expected 12, got %s"):format(tostring(result)))
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("CBM: RegisterBridge overwrites bridge with same name", function()
		CBM:RegisterBridge("double", function(payload: any): any
			return payload.value + 100
		end)
		local result = CBM:RunBridge("double", { value = 5 })
		assert(result == 105, ("expected 105, got %s"):format(tostring(result)))
		assert(CBM:GetRegisteredBridgeCount() == 1, "overwrite must not add a second entry")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("CBM: RunBridge with unknown name warns and returns nil", function()
		local result = CBM:RunBridge("NONEXISTENT", {})
		assert(result == nil, "expected nil for unknown bridge")
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("CBM: RegisterBridge rejects empty name", function()
		local before = CBM:GetRegisteredBridgeCount()
		CBM:RegisterBridge("", function() return nil end)
		assert(CBM:GetRegisteredBridgeCount() == before,
			"empty name must not register a bridge")
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("CBM: RegisterBridge rejects non-function callback", function()
		local before = CBM:GetRegisteredBridgeCount()
		CBM:RegisterBridge("bad", "notAFunction" :: any)
		assert(CBM:GetRegisteredBridgeCount() == before,
			"non-function callback must not register a bridge")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("CBM: multiple bridges coexist independently", function()
		CBM:RegisterBridge("negate", function(payload: any): any
			return -payload.value
		end)
		assert(CBM:GetRegisteredBridgeCount() == 2, "expected 2 bridges")
		assert(CBM:RunBridge("negate",  { value = 10 }) == -10, "wrong negate result")
		assert(CBM:RunBridge("double",  { value =  5 }) == 105,  "wrong double result")
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("CBM: ClearBridges removes all bridges", function()
		CBM:ClearBridges()
		assert(CBM:GetRegisteredBridgeCount() == 0,
			"expected 0 bridges after ClearBridges")
		assert(CBM:RunBridge("double", {}) == nil,
			"RunBridge must return nil after ClearBridges")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("CBM: Destroy() resets IsReady and clears bridges", function()
		CBM:RegisterBridge("temp", function() return 1 end)
		CBM:Destroy()
		assert(CBM:IsReady()                    == false, "expected not-ready after Destroy")
		assert(CBM:GetRegisteredBridgeCount()   == 0,     "expected 0 bridges after Destroy")
	end)

	-- Restore
	CBM:Init()

	-- 37 ───────────────────────────────────────────────────────────────────
	check("CBM: IsReady and RegisterBridge work after Init restore", function()
		assert(CBM:IsReady() == true, "expected ready after re-Init")
		CBM:RegisterBridge("afterRestore", function(p: any): any return p.x end)
		assert(CBM:RunBridge("afterRestore", { x = 42 }) == 42,
			"expected 42 from bridge after restore")
		CBM:ClearBridges()
	end)

end -- cbOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 19 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
