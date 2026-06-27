--!strict
return function()
-- Sprint10ClientTest — LocalScript
-- Client smoke tests for Sprint 10: MenuController, PauseController,
-- SettingsController, and LoadingController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Each thin runner (MenuController.client.lua, etc.) calls Module:Init()
-- before this script loads, so safeRequire() returns already-initialised
-- singletons — exactly the same pattern as Sprints 7, 8, and 9.
-- Tests exercise each module through its public API and verify internal
-- state via getters.  No live round, network, or UI interaction required.

print("[Sprint10ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint10ClientTest]"
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
-- Section 1 — MenuControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local mcmOk, mcmResult = safeRequire(
	script.Parent.Parent.Modules.MenuControllerModule)

if mcmOk then

	local MCM: any = mcmResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("MCM: module loads successfully", function()
		assert(type(MCM) == "table", "expected table, got " .. type(MCM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("MCM: initial IsVisible is false", function()
		assert(MCM:IsVisible() == false, "menu must start hidden")
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("MCM: initial GetActiveMenu is empty string", function()
		assert(MCM:GetActiveMenu() == "",
			("expected empty, got %q"):format(MCM:GetActiveMenu()))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("MCM: OpenMenu makes IsVisible true", function()
		MCM:OpenMenu("MainMenu")
		assert(MCM:IsVisible() == true, "expected IsVisible true after OpenMenu")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("MCM: GetActiveMenu returns 'MainMenu' after OpenMenu", function()
		assert(MCM:GetActiveMenu() == "MainMenu",
			("expected 'MainMenu', got %q"):format(MCM:GetActiveMenu()))
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("MCM: OpenMenu switches active panel", function()
		MCM:OpenMenu("CourseSelect")
		assert(MCM:GetActiveMenu() == "CourseSelect",
			("expected 'CourseSelect', got %q"):format(MCM:GetActiveMenu()))
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("MCM: IsVisible stays true after panel switch", function()
		assert(MCM:IsVisible() == true, "expected still visible after panel switch")
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("MCM: CloseMenu sets IsVisible false", function()
		MCM:CloseMenu()
		assert(MCM:IsVisible() == false, "expected IsVisible false after CloseMenu")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("MCM: GetActiveMenu is empty after CloseMenu", function()
		assert(MCM:GetActiveMenu() == "",
			("expected empty, got %q"):format(MCM:GetActiveMenu()))
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("MCM: Destroy resets IsVisible and GetActiveMenu", function()
		MCM:OpenMenu("FriendsPanel")
		assert(MCM:GetActiveMenu() == "FriendsPanel", "state should be FriendsPanel before Destroy")

		MCM:Destroy()

		assert(MCM:IsVisible() == false,
			"expected IsVisible false after Destroy")
		assert(MCM:GetActiveMenu() == "",
			("expected empty active menu after Destroy, got %q"):format(MCM:GetActiveMenu()))
	end)

	-- Restore the live connection that Destroy() cleared.
	MCM:Init()

end -- mcmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — PauseControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local pcmOk, pcmResult = safeRequire(
	script.Parent.Parent.Modules.PauseControllerModule)

if pcmOk then

	local PCM: any = pcmResult

	-- 11 ───────────────────────────────────────────────────────────────────
	check("PCM: module loads successfully", function()
		assert(type(PCM) == "table", "expected table, got " .. type(PCM))
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("PCM: initial IsPaused is false", function()
		assert(PCM:IsPaused() == false, "game must start unpaused")
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("PCM: TogglePause sets IsPaused true", function()
		PCM:TogglePause()
		assert(PCM:IsPaused() == true, "expected IsPaused true after first toggle")
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("PCM: TogglePause again sets IsPaused false", function()
		PCM:TogglePause()
		assert(PCM:IsPaused() == false, "expected IsPaused false after second toggle")
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("PCM: Resume after TogglePause clears pause", function()
		PCM:TogglePause()
		assert(PCM:IsPaused() == true, "expected paused before Resume")
		PCM:Resume()
		assert(PCM:IsPaused() == false, "expected IsPaused false after Resume")
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("PCM: Resume when not paused does not error", function()
		assert(PCM:IsPaused() == false, "should already be unpaused")
		PCM:Resume()  -- must not throw
		assert(PCM:IsPaused() == false, "still unpaused")
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("PCM: Destroy resets IsPaused to false", function()
		PCM:TogglePause()
		assert(PCM:IsPaused() == true, "should be paused before Destroy")
		PCM:Destroy()
		assert(PCM:IsPaused() == false, "expected false after Destroy")
	end)

	-- Restore PauseOverlay and live state before the final check.
	PCM:Init()

	-- 18 ───────────────────────────────────────────────────────────────────
	check("PCM: TogglePause and Resume work after Init restore", function()
		PCM:TogglePause()
		assert(PCM:IsPaused() == true, "should be paused")
		PCM:Resume()
		assert(PCM:IsPaused() == false, "should be unpaused after Resume")
	end)

end -- pcmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — SettingsControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local scmOk, scmResult = safeRequire(
	script.Parent.Parent.Modules.SettingsControllerModule)

if scmOk then

	local SCM: any = scmResult

	-- 19 ───────────────────────────────────────────────────────────────────
	check("SCM: module loads successfully", function()
		assert(type(SCM) == "table", "expected table, got " .. type(SCM))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("SCM: default AudioVolume is 1.0", function()
		assert(SCM:GetSetting("AudioVolume") == 1.0,
			("expected 1.0, got %s"):format(tostring(SCM:GetSetting("AudioVolume"))))
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("SCM: default MusicVolume is 0.7", function()
		assert(SCM:GetSetting("MusicVolume") == 0.7,
			("expected 0.7, got %s"):format(tostring(SCM:GetSetting("MusicVolume"))))
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("SCM: default GraphicsQuality is 'High'", function()
		assert(SCM:GetSetting("GraphicsQuality") == "High",
			("expected 'High', got %q"):format(tostring(SCM:GetSetting("GraphicsQuality"))))
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("SCM: GetSetting on unknown key returns nil", function()
		assert(SCM:GetSetting("NonExistentKey") == nil,
			"unknown key must return nil")
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("SCM: SetSetting updates a value", function()
		SCM:SetSetting("AudioVolume", 0.5)
		assert(SCM:GetSetting("AudioVolume") == 0.5,
			("expected 0.5, got %s"):format(tostring(SCM:GetSetting("AudioVolume"))))
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("SCM: SetSetting can store a new key", function()
		SCM:SetSetting("CustomKey", "CustomValue")
		assert(SCM:GetSetting("CustomKey") == "CustomValue",
			"custom key/value pair must be stored")
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("SCM: GetAllSettings returns table containing AudioVolume", function()
		local all = SCM:GetAllSettings()
		assert(type(all) == "table", "expected table from GetAllSettings")
		assert(all["AudioVolume"] ~= nil, "AudioVolume must be present in GetAllSettings")
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("SCM: GetAllSettings is a copy — mutating it does not affect state", function()
		local all = SCM:GetAllSettings()
		all["AudioVolume"] = 9999
		assert(SCM:GetSetting("AudioVolume") == 0.5,
			"mutating the copy must not change internal state")
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("SCM: Destroy clears settings (GetSetting returns nil)", function()
		SCM:Destroy()
		assert(SCM:GetSetting("AudioVolume") == nil,
			"settings must be nil after Destroy")
	end)

	-- Restore defaults via Init() before the final check.
	SCM:Init()

	-- 29 ───────────────────────────────────────────────────────────────────
	check("SCM: Init after Destroy restores AudioVolume default", function()
		assert(SCM:GetSetting("AudioVolume") == 1.0,
			("expected 1.0 after Init restore, got %s"):format(
				tostring(SCM:GetSetting("AudioVolume"))))
	end)

end -- scmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 4 — LoadingControllerModule
-- ════════════════════════════════════════════════════════════════════════════

local lcmOk, lcmResult = safeRequire(
	script.Parent.Parent.Modules.LoadingControllerModule)

if lcmOk then

	local LCM: any = lcmResult

	-- 30 ───────────────────────────────────────────────────────────────────
	check("LCM: module loads successfully", function()
		assert(type(LCM) == "table", "expected table, got " .. type(LCM))
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("LCM: initial IsLoading is false", function()
		assert(LCM:IsLoading() == false, "loading screen must start hidden")
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("LCM: initial GetMessage is empty string", function()
		assert(LCM:GetMessage() == "",
			("expected empty, got %q"):format(LCM:GetMessage()))
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("LCM: ShowLoading sets IsLoading true", function()
		LCM:ShowLoading("Connecting to server…")
		assert(LCM:IsLoading() == true, "expected IsLoading true after ShowLoading")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("LCM: GetMessage returns the provided message", function()
		assert(LCM:GetMessage() == "Connecting to server…",
			("expected 'Connecting to server…', got %q"):format(LCM:GetMessage()))
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("LCM: ShowLoading updates the message", function()
		LCM:ShowLoading("Loading course…")
		assert(LCM:GetMessage() == "Loading course…",
			("expected 'Loading course…', got %q"):format(LCM:GetMessage()))
		assert(LCM:IsLoading() == true, "still loading after message update")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("LCM: HideLoading sets IsLoading false", function()
		LCM:HideLoading()
		assert(LCM:IsLoading() == false, "expected IsLoading false after HideLoading")
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("LCM: Destroy resets IsLoading and GetMessage", function()
		LCM:ShowLoading("Teardown test")
		assert(LCM:IsLoading() == true, "should be loading before Destroy")

		LCM:Destroy()

		assert(LCM:IsLoading() == false,
			"expected IsLoading false after Destroy")
		assert(LCM:GetMessage() == "",
			("expected empty message after Destroy, got %q"):format(LCM:GetMessage()))
	end)

	-- Restore the loading screen connection that Destroy() cleared.
	LCM:Init()

	-- 38 ───────────────────────────────────────────────────────────────────
	check("LCM: ShowLoading and HideLoading work after Init restore", function()
		LCM:ShowLoading("Post-restore test")
		assert(LCM:IsLoading() == true, "should be loading")
		LCM:HideLoading()
		assert(LCM:IsLoading() == false, "should not be loading after HideLoading")
	end)

end -- lcmOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 10 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
end
