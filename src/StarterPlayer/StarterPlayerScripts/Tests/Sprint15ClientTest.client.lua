--!strict
-- Sprint15ClientTest — LocalScript
-- Client smoke tests for Sprint 15: LobbyController, MatchmakingController,
-- and PartyController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.  Tests drive
-- each module via its public API.  No real multiplayer, no real golf round.

print("[Sprint15ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint15ClientTest]"
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
-- Section 1 — LobbyControllerModule  (checks 1–13)
-- ════════════════════════════════════════════════════════════════════════════

local lcOk, lcResult = safeRequire(
	script.Parent.Parent.Modules.LobbyControllerModule)

if lcOk then

	local LCM: any = lcResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("LCM: module loads successfully", function()
		assert(type(LCM) == "table", "expected table, got " .. type(LCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("LCM: IsVisible is false initially", function()
		assert(LCM:IsVisible() == false, "lobby must start hidden")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("LCM: GetLobbyState is 'Idle' initially", function()
		assert(LCM:GetLobbyState() == "Idle",
			("expected 'Idle', got %q"):format(LCM:GetLobbyState()))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("LCM: GetSelectedCourse is 'course_1' initially", function()
		assert(LCM:GetSelectedCourse() == "course_1",
			("expected 'course_1', got %q"):format(LCM:GetSelectedCourse()))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("LCM: OpenLobby sets IsVisible true", function()
		LCM:OpenLobby()
		assert(LCM:IsVisible() == true, "expected visible after OpenLobby")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("LCM: CloseLobby sets IsVisible false", function()
		LCM:CloseLobby()
		assert(LCM:IsVisible() == false, "expected hidden after CloseLobby")
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("LCM: SetLobbyState('ReadyCheck') updates GetLobbyState", function()
		LCM:SetLobbyState("ReadyCheck")
		assert(LCM:GetLobbyState() == "ReadyCheck",
			("expected 'ReadyCheck', got %q"):format(LCM:GetLobbyState()))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("LCM: SetLobbyState with invalid name is rejected", function()
		local before = LCM:GetLobbyState()
		LCM:SetLobbyState("WarpZone")
		assert(LCM:GetLobbyState() == before,
			"invalid SetLobbyState should leave state unchanged")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("LCM: all 5 valid lobby states are accepted", function()
		local VALID = {
			"Idle", "SelectingCourse", "ReadyCheck", "MatchStarting", "InMatch",
		}
		for _, s in ipairs(VALID) do
			LCM:SetLobbyState(s)
			assert(LCM:GetLobbyState() == s,
				("SetLobbyState failed for %q"):format(s))
		end
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("LCM: SetSelectedCourse('course_3') updates GetSelectedCourse", function()
		LCM:SetSelectedCourse("course_3")
		assert(LCM:GetSelectedCourse() == "course_3",
			("expected 'course_3', got %q"):format(LCM:GetSelectedCourse()))
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("LCM: OpenLobby / CloseLobby toggle correctly", function()
		LCM:OpenLobby()
		assert(LCM:IsVisible() == true,  "expected open")
		LCM:CloseLobby()
		assert(LCM:IsVisible() == false, "expected closed")
		LCM:OpenLobby()
		assert(LCM:IsVisible() == true,  "expected re-opened")
		LCM:CloseLobby()
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("LCM: Destroy resets all state", function()
		LCM:OpenLobby()
		LCM:SetLobbyState("InMatch")
		LCM:SetSelectedCourse("course_5")
		LCM:Destroy()
		assert(LCM:IsVisible()         == false, "expected hidden after Destroy")
		assert(LCM:GetLobbyState()     == "",    "expected empty state after Destroy")
		assert(LCM:GetSelectedCourse() == "",    "expected empty course after Destroy")
	end)

	-- Restore
	LCM:Init()

	-- 13 ───────────────────────────────────────────────────────────────────
	check("LCM: defaults restored after Init restore", function()
		assert(LCM:GetLobbyState()     == "Idle",     "expected 'Idle' after re-Init")
		assert(LCM:GetSelectedCourse() == "course_1", "expected 'course_1' after re-Init")
		assert(LCM:IsVisible()         == false,      "expected hidden after re-Init")
		LCM:OpenLobby()
		assert(LCM:IsVisible() == true, "OpenLobby should work after re-Init")
		LCM:CloseLobby()
	end)

end -- lcOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — MatchmakingControllerModule  (checks 14–25)
-- ════════════════════════════════════════════════════════════════════════════

local mcOk, mcResult = safeRequire(
	script.Parent.Parent.Modules.MatchmakingControllerModule)

if mcOk then

	local MCM: any = mcResult

	-- 14 ───────────────────────────────────────────────────────────────────
	check("MCM: module loads successfully", function()
		assert(type(MCM) == "table", "expected table, got " .. type(MCM))
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("MCM: IsQueued is false initially", function()
		assert(MCM:IsQueued() == false, "should not be queued initially")
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("MCM: GetMode is '' initially", function()
		assert(MCM:GetMode() == "",
			("expected '', got %q"):format(MCM:GetMode()))
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("MCM: GetEstimatedWait is 0 initially", function()
		assert(MCM:GetEstimatedWait() == 0,
			("expected 0, got %d"):format(MCM:GetEstimatedWait()))
	end)

	-- 18 ───────────────────────────────────────────────────────────────────
	check("MCM: GetMatchFound is nil initially", function()
		assert(MCM:GetMatchFound() == nil, "expected nil initially")
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("MCM: StartQueue('Solo') sets IsQueued and GetMode", function()
		MCM:StartQueue("Solo")
		assert(MCM:IsQueued() == true,   "expected queued after StartQueue")
		assert(MCM:GetMode()  == "Solo", ("expected 'Solo', got %q"):format(MCM:GetMode()))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("MCM: StartQueue with invalid mode is rejected", function()
		MCM:CancelQueue()
		MCM:StartQueue("BattleRoyale")
		assert(MCM:IsQueued() == false,
			"invalid mode should not start queue")
		assert(MCM:GetMode() == "",
			"mode should remain empty after rejected StartQueue")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("MCM: all 4 valid modes are accepted by StartQueue", function()
		for _, m in ipairs({ "Solo", "Duo", "Squad", "Private" }) do
			MCM:StartQueue(m)
			assert(MCM:IsQueued() == true and MCM:GetMode() == m,
				("StartQueue failed for mode %q"):format(m))
			MCM:CancelQueue()
		end
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("MCM: SetEstimatedWait / GetEstimatedWait", function()
		MCM:StartQueue("Duo")
		MCM:SetEstimatedWait(45)
		assert(MCM:GetEstimatedWait() == 45,
			("expected 45, got %d"):format(MCM:GetEstimatedWait()))
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("MCM: SetMatchFound / GetMatchFound returns correct data", function()
		MCM:SetMatchFound({ matchId = "MATCH_001", courseId = "course_2" })
		local data = MCM:GetMatchFound()
		assert(data ~= nil, "expected match data")
		assert(data["matchId"]  == "MATCH_001", "wrong matchId")
		assert(data["courseId"] == "course_2",  "wrong courseId")
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("MCM: GetMatchFound returns a copy (mutation does not affect internal)", function()
		local copy = MCM:GetMatchFound()
		assert(copy ~= nil, "expected copy to exist")
		copy["matchId"] = "MUTATED"
		local fresh = MCM:GetMatchFound()
		assert(fresh ~= nil and fresh["matchId"] == "MATCH_001",
			"mutating returned copy must not change internal match data")
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("MCM: CancelQueue resets all matchmaking state", function()
		MCM:CancelQueue()
		assert(MCM:IsQueued()         == false, "expected not queued after CancelQueue")
		assert(MCM:GetMode()          == "",    "expected empty mode after CancelQueue")
		assert(MCM:GetEstimatedWait() == 0,     "expected 0 wait after CancelQueue")
		assert(MCM:GetMatchFound()    == nil,   "expected nil match after CancelQueue")
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("MCM: Destroy resets all state", function()
		MCM:StartQueue("Squad")
		MCM:SetEstimatedWait(30)
		MCM:Destroy()
		assert(MCM:IsQueued()         == false, "expected not queued after Destroy")
		assert(MCM:GetMode()          == "",    "expected empty mode after Destroy")
		assert(MCM:GetEstimatedWait() == 0,     "expected 0 wait after Destroy")
		assert(MCM:GetMatchFound()    == nil,   "expected nil match after Destroy")
	end)

	-- Restore
	MCM:Init()

	-- 27 ───────────────────────────────────────────────────────────────────  (bonus)
	check("MCM: StartQueue works after Init restore", function()
		MCM:StartQueue("Private")
		assert(MCM:IsQueued() == true,      "expected queued after restore")
		assert(MCM:GetMode()  == "Private", "expected 'Private' after restore")
		MCM:CancelQueue()
	end)

end -- mcOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — PartyControllerModule  (checks 28–44)
-- ════════════════════════════════════════════════════════════════════════════

local pcOk, pcResult = safeRequire(
	script.Parent.Parent.Modules.PartyControllerModule)

if pcOk then

	local PCM: any = pcResult

	local ALICE: any = { userId = 1001, displayName = "Alice",   isReady = false, handicap = 5  }
	local BOB:   any = { userId = 1002, displayName = "Bob",     isReady = true,  handicap = 10 }
	local CAROL: any = { userId = 1003, displayName = "Carol",   isReady = false, handicap = 2  }

	-- 28 ───────────────────────────────────────────────────────────────────
	check("PCM: module loads successfully", function()
		assert(type(PCM) == "table", "expected table, got " .. type(PCM))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("PCM: GetMembers returns empty table initially", function()
		local m = PCM:GetMembers()
		assert(type(m) == "table" and #m == 0,
			("expected empty table, got %d members"):format(#m))
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("PCM: GetPartySize is 0 initially", function()
		assert(PCM:GetPartySize() == 0,
			("expected 0, got %d"):format(PCM:GetPartySize()))
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("PCM: AddMember adds one member correctly", function()
		PCM:AddMember(ALICE)
		assert(PCM:GetPartySize() == 1,
			("expected 1 member, got %d"):format(PCM:GetPartySize()))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("PCM: GetMember returns correct data", function()
		local m = PCM:GetMember(1001)
		assert(m ~= nil,                     "expected Alice to exist")
		assert(m.displayName == "Alice",     "wrong displayName")
		assert(m.userId      == 1001,        "wrong userId")
		assert(m.isReady     == false,       "wrong isReady")
		assert(m.handicap    == 5,           "wrong handicap")
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("PCM: GetMember returns nil for unknown userId", function()
		assert(PCM:GetMember(9999) == nil, "expected nil for unknown userId")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("PCM: IsReady returns false for member that has not readied up", function()
		assert(PCM:IsReady(1001) == false, "expected not ready initially")
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("PCM: SetReady(1001, true) sets IsReady true", function()
		PCM:SetReady(1001, true)
		assert(PCM:IsReady(1001) == true, "expected ready after SetReady")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("PCM: SetReady(1001, false) sets IsReady false", function()
		PCM:SetReady(1001, false)
		assert(PCM:IsReady(1001) == false, "expected not ready after SetReady(false)")
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("PCM: SetReady for absent userId warns but does not error", function()
		PCM:SetReady(8888, true)  -- no error; warns internally
		assert(PCM:IsReady(8888) == false, "absent member should not be marked ready")
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("PCM: AddMember with missing userId is rejected", function()
		local before = PCM:GetPartySize()
		PCM:AddMember({ displayName = "Ghost" } :: any)   -- no userId
		assert(PCM:GetPartySize() == before, "invalid AddMember should not grow party")
	end)

	-- 39 ───────────────────────────────────────────────────────────────────
	check("PCM: AddMember with empty displayName is rejected", function()
		local before = PCM:GetPartySize()
		PCM:AddMember({ userId = 2001, displayName = "" } :: any)
		assert(PCM:GetPartySize() == before, "empty displayName should be rejected")
	end)

	-- 40 ───────────────────────────────────────────────────────────────────
	check("PCM: RemoveMember removes by userId", function()
		PCM:RemoveMember(1001)
		assert(PCM:GetPartySize()  == 0,   "expected 0 after RemoveMember")
		assert(PCM:GetMember(1001) == nil, "Alice should be gone after RemoveMember")
	end)

	-- 41 ───────────────────────────────────────────────────────────────────
	check("PCM: SetMembers replaces roster", function()
		PCM:SetMembers({ ALICE, BOB, CAROL } :: any)
		assert(PCM:GetPartySize() == 3,
			("expected 3 members after SetMembers, got %d"):format(PCM:GetPartySize()))
		assert(PCM:GetMember(1002) ~= nil, "expected Bob")
		assert(PCM:GetMember(1003) ~= nil, "expected Carol")
	end)

	-- 42 ───────────────────────────────────────────────────────────────────
	check("PCM: GetMembers returns copy (mutation does not affect internal)", function()
		local copy = PCM:GetMembers()
		copy[1].displayName = "MUTATED"
		local fresh = PCM:GetMembers()
		for _, m in ipairs(fresh) do
			assert(m.displayName ~= "MUTATED",
				"mutating returned copy must not affect internal roster")
		end
	end)

	-- 43 ───────────────────────────────────────────────────────────────────
	check("PCM: GetMembers is sorted ascending by userId", function()
		local members = PCM:GetMembers()
		assert(#members == 3, "expected 3 members")
		assert(members[1].userId == 1001, "expected Alice first (userId 1001)")
		assert(members[2].userId == 1002, "expected Bob second (userId 1002)")
		assert(members[3].userId == 1003, "expected Carol third (userId 1003)")
	end)

	-- 44 ───────────────────────────────────────────────────────────────────
	check("PCM: ClearParty empties the roster", function()
		PCM:ClearParty()
		assert(PCM:GetPartySize() == 0, "expected empty after ClearParty")
	end)

	-- 45 ───────────────────────────────────────────────────────────────────
	check("PCM: Destroy resets all state", function()
		PCM:AddMember(ALICE)
		PCM:Destroy()
		assert(PCM:GetPartySize() == 0, "expected empty after Destroy")
	end)

	-- Restore
	PCM:Init()

	-- 46 ───────────────────────────────────────────────────────────────────
	check("PCM: AddMember and GetMember work after Init restore", function()
		PCM:AddMember(BOB)
		assert(PCM:GetPartySize() == 1,    "expected 1 member after restore")
		local m = PCM:GetMember(1002)
		assert(m ~= nil,                   "expected Bob after restore")
		assert(m.displayName == "Bob",     "wrong displayName after restore")
		assert(m.isReady     == true,      "wrong isReady for Bob")
		assert(m.handicap    == 10,        "wrong handicap for Bob")
		PCM:ClearParty()
	end)

end -- pcOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 15 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
