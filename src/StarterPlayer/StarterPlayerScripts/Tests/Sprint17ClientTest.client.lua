--!strict
-- Sprint17ClientTest — LocalScript
-- Client smoke tests for Sprint 17: AudioController, VFXController,
-- and FeedbackController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.
-- Tests drive each module via its public API only.
-- No real audio assets or VFX assets required.

print("[Sprint17ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint17ClientTest]"
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
-- Section 1 — AudioControllerModule  (checks 1–16)
-- ════════════════════════════════════════════════════════════════════════════

local acOk, acResult = safeRequire(
	script.Parent.Parent.Modules.AudioControllerModule)

if acOk then

	local ACM: any = acResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("ACM: module loads successfully", function()
		assert(type(ACM) == "table", "expected table, got " .. type(ACM))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("ACM: GetMasterVolume is 1.0 initially", function()
		assert(ACM:GetMasterVolume() == 1.0,
			("expected 1.0, got %s"):format(tostring(ACM:GetMasterVolume())))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("ACM: GetMusicVolume is 0.7 initially", function()
		assert(ACM:GetMusicVolume() == 0.7,
			("expected 0.7, got %s"):format(tostring(ACM:GetMusicVolume())))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("ACM: GetSFXVolume is 1.0 initially", function()
		assert(ACM:GetSFXVolume() == 1.0,
			("expected 1.0, got %s"):format(tostring(ACM:GetSFXVolume())))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("ACM: GetCurrentMusic is '' initially", function()
		assert(ACM:GetCurrentMusic() == "",
			("expected '', got %q"):format(ACM:GetCurrentMusic()))
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("ACM: SetMasterVolume / GetMasterVolume round-trip", function()
		ACM:SetMasterVolume(0.5)
		assert(ACM:GetMasterVolume() == 0.5,
			("expected 0.5, got %s"):format(tostring(ACM:GetMasterVolume())))
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("ACM: SetMusicVolume / GetMusicVolume round-trip", function()
		ACM:SetMusicVolume(0.3)
		assert(ACM:GetMusicVolume() == 0.3,
			("expected 0.3, got %s"):format(tostring(ACM:GetMusicVolume())))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	check("ACM: SetSFXVolume / GetSFXVolume round-trip", function()
		ACM:SetSFXVolume(0.8)
		assert(ACM:GetSFXVolume() == 0.8,
			("expected 0.8, got %s"):format(tostring(ACM:GetSFXVolume())))
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("ACM: Volume clamped to 1 when value > 1", function()
		ACM:SetMasterVolume(5.0)
		assert(ACM:GetMasterVolume() == 1.0,
			("expected 1.0 after clamp, got %s"):format(tostring(ACM:GetMasterVolume())))
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("ACM: Volume clamped to 0 when value < 0", function()
		ACM:SetMasterVolume(-3.0)
		assert(ACM:GetMasterVolume() == 0.0,
			("expected 0.0 after clamp, got %s"):format(tostring(ACM:GetMasterVolume())))
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("ACM: PlaySFX valid name does not error", function()
		ACM:PlaySFX("Swing")   -- placeholder; no real sound fired
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("ACM: StopSFX valid name does not error", function()
		ACM:StopSFX("Swing")
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("ACM: PlaySFX invalid name is rejected without error", function()
		ACM:PlaySFX("LaserBlast")  -- should warn, not throw
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("ACM: PlayMusic sets GetCurrentMusic", function()
		ACM:PlayMusic("LobbyTheme")
		assert(ACM:GetCurrentMusic() == "LobbyTheme",
			("expected 'LobbyTheme', got %q"):format(ACM:GetCurrentMusic()))
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("ACM: StopMusic clears GetCurrentMusic", function()
		ACM:StopMusic()
		assert(ACM:GetCurrentMusic() == "",
			("expected '', got %q"):format(ACM:GetCurrentMusic()))
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("ACM: PlayMusic invalid track is rejected without error", function()
		ACM:PlayMusic("HeavyMetal")   -- should warn, not throw
		assert(ACM:GetCurrentMusic() == "",
			"invalid PlayMusic must not change current music")
	end)

	-- 17 ───────────────────────────────────────────────────────────────────
	check("ACM: Destroy resets state to defaults", function()
		ACM:SetMasterVolume(0.2)
		ACM:PlayMusic("Victory")
		ACM:Destroy()
		assert(ACM:GetMasterVolume()  == 1.0, "expected master=1.0 after Destroy")
		assert(ACM:GetMusicVolume()   == 0.7, "expected music=0.7 after Destroy")
		assert(ACM:GetSFXVolume()     == 1.0, "expected sfx=1.0 after Destroy")
		assert(ACM:GetCurrentMusic()  == "",  "expected no music after Destroy")
	end)

	-- Restore
	ACM:Init()

	-- 18 ───────────────────────────────────────────────────────────────────
	check("ACM: PlayMusic and SetMasterVolume work after Init restore", function()
		ACM:SetMasterVolume(0.6)
		assert(ACM:GetMasterVolume() == 0.6, "expected 0.6 after restore set")
		ACM:PlayMusic("CourseAmbient")
		assert(ACM:GetCurrentMusic() == "CourseAmbient", "expected CourseAmbient")
		ACM:StopMusic()
	end)

end -- acOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — VFXControllerModule  (checks 19–30)
-- ════════════════════════════════════════════════════════════════════════════

local vfxOk, vfxResult = safeRequire(
	script.Parent.Parent.Modules.VFXControllerModule)

if vfxOk then

	local VFX: any = vfxResult

	-- 19 ───────────────────────────────────────────────────────────────────
	check("VFX: module loads successfully", function()
		assert(type(VFX) == "table", "expected table, got " .. type(VFX))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("VFX: GetActiveEffects returns empty table initially", function()
		local effects = VFX:GetActiveEffects()
		assert(type(effects) == "table" and #effects == 0,
			("expected 0 active effects, got %d"):format(#effects))
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	check("VFX: IsEffectActive is false for any effect initially", function()
		assert(VFX:IsEffectActive("SwingTrail") == false,
			"SwingTrail should not be active initially")
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("VFX: PlayEffect sets IsEffectActive true", function()
		VFX:PlayEffect("SwingTrail", {})
		assert(VFX:IsEffectActive("SwingTrail") == true,
			"expected SwingTrail active after PlayEffect")
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("VFX: GetActiveEffects includes the active effect", function()
		local effects = VFX:GetActiveEffects()
		local found = false
		for _, name in ipairs(effects) do
			if name == "SwingTrail" then found = true end
		end
		assert(found, "GetActiveEffects should include SwingTrail")
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("VFX: GetActiveEffects returns a copy (mutation does not affect internal)", function()
		local copy = VFX:GetActiveEffects()
		table.clear(copy)
		assert(VFX:IsEffectActive("SwingTrail") == true,
			"clearing the returned copy must not deactivate SwingTrail")
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("VFX: StopEffect sets IsEffectActive false", function()
		VFX:StopEffect("SwingTrail")
		assert(VFX:IsEffectActive("SwingTrail") == false,
			"expected SwingTrail inactive after StopEffect")
	end)

	-- 26 ───────────────────────────────────────────────────────────────────
	check("VFX: PlayEffect with invalid name is rejected", function()
		VFX:PlayEffect("Explosion", {})   -- invalid; should warn, not throw
		assert(VFX:IsEffectActive("Explosion") == false,
			"invalid effect must not be marked active")
	end)

	-- 27 ───────────────────────────────────────────────────────────────────
	check("VFX: all 7 valid effect names accepted by PlayEffect", function()
		local EFFECTS = {
			"SwingTrail", "BallImpact", "PerfectShot", "CoinBurst",
			"XPGlow", "UnlockSparkle", "Confetti",
		}
		for _, name in ipairs(EFFECTS) do
			VFX:PlayEffect(name, nil)
			assert(VFX:IsEffectActive(name) == true,
				("PlayEffect failed for %q"):format(name))
		end
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("VFX: ClearEffects deactivates all effects", function()
		VFX:ClearEffects()
		local effects = VFX:GetActiveEffects()
		assert(#effects == 0,
			("expected 0 active effects after ClearEffects, got %d"):format(#effects))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("VFX: Destroy resets all state", function()
		VFX:PlayEffect("CoinBurst", {})
		VFX:Destroy()
		assert(VFX:IsEffectActive("CoinBurst") == false,
			"CoinBurst must not be active after Destroy")
		assert(#VFX:GetActiveEffects() == 0,
			"expected no active effects after Destroy")
	end)

	-- Restore
	VFX:Init()

	-- 30 ───────────────────────────────────────────────────────────────────
	check("VFX: PlayEffect and ClearEffects work after Init restore", function()
		VFX:PlayEffect("Confetti", {})
		assert(VFX:IsEffectActive("Confetti") == true, "expected Confetti active")
		VFX:ClearEffects()
		assert(#VFX:GetActiveEffects() == 0, "expected empty after ClearEffects")
	end)

end -- vfxOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — FeedbackControllerModule  (checks 31–42)
-- ════════════════════════════════════════════════════════════════════════════

local fcOk, fcResult = safeRequire(
	script.Parent.Parent.Modules.FeedbackControllerModule)

if fcOk then

	local FCM: any = fcResult

	-- 31 ───────────────────────────────────────────────────────────────────
	check("FCM: module loads successfully", function()
		assert(type(FCM) == "table", "expected table, got " .. type(FCM))
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("FCM: IsVisible is false initially", function()
		assert(FCM:IsVisible() == false, "expected hidden initially")
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("FCM: GetMessage is '' initially", function()
		assert(FCM:GetMessage() == "",
			("expected '', got %q"):format(FCM:GetMessage()))
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("FCM: GetMessageType is '' initially", function()
		assert(FCM:GetMessageType() == "",
			("expected '', got %q"):format(FCM:GetMessageType()))
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("FCM: ShowMessage sets message, type, and IsVisible", function()
		FCM:ShowMessage("Birdie!", "Success")
		assert(FCM:IsVisible()        == true,      "expected visible after ShowMessage")
		assert(FCM:GetMessage()       == "Birdie!",  "wrong message")
		assert(FCM:GetMessageType()   == "Success",  "wrong type")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("FCM: ClearMessage hides and empties", function()
		FCM:ClearMessage()
		assert(FCM:IsVisible()      == false, "expected hidden after ClearMessage")
		assert(FCM:GetMessage()     == "",    "expected '' after ClearMessage")
		assert(FCM:GetMessageType() == "",    "expected '' type after ClearMessage")
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("FCM: ShowMessage with invalid type is rejected", function()
		FCM:ShowMessage("Oops", "Critical")   -- invalid type
		assert(FCM:IsVisible()    == false, "invalid type must not show message")
		assert(FCM:GetMessage()   == "",    "message must not be set for invalid type")
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("FCM: all 5 valid message types accepted", function()
		local TYPES = { "Info", "Success", "Warning", "Error", "Reward" }
		for _, t in ipairs(TYPES) do
			FCM:ShowMessage("test", t)
			assert(FCM:IsVisible()      == true, ("expected visible for type %q"):format(t))
			assert(FCM:GetMessageType() == t,    ("wrong type for %q"):format(t))
			FCM:ClearMessage()
		end
	end)

	-- 39 ───────────────────────────────────────────────────────────────────
	check("FCM: ShowMessage 'Reward' type works (Reward = gold accent)", function()
		FCM:ShowMessage("Hole in one!", "Reward")
		assert(FCM:GetMessage()     == "Hole in one!", "wrong message")
		assert(FCM:GetMessageType() == "Reward",       "wrong type")
		assert(FCM:IsVisible()      == true,           "expected visible")
		FCM:ClearMessage()
	end)

	-- 40 ───────────────────────────────────────────────────────────────────
	check("FCM: ShowMessage overwrites previous message", function()
		FCM:ShowMessage("First",  "Info")
		FCM:ShowMessage("Second", "Warning")
		assert(FCM:GetMessage()     == "Second",  "expected overwritten message")
		assert(FCM:GetMessageType() == "Warning", "expected overwritten type")
		FCM:ClearMessage()
	end)

	-- 41 ───────────────────────────────────────────────────────────────────
	check("FCM: Destroy resets all state", function()
		FCM:ShowMessage("Hi", "Info")
		FCM:Destroy()
		assert(FCM:IsVisible()      == false, "expected hidden after Destroy")
		assert(FCM:GetMessage()     == "",    "expected '' after Destroy")
		assert(FCM:GetMessageType() == "",    "expected '' type after Destroy")
	end)

	-- Restore
	FCM:Init()

	-- 42 ───────────────────────────────────────────────────────────────────
	check("FCM: ShowMessage and ClearMessage work after Init restore", function()
		FCM:ShowMessage("Eagle!", "Reward")
		assert(FCM:IsVisible()      == true,    "expected visible after restore")
		assert(FCM:GetMessage()     == "Eagle!", "wrong message after restore")
		assert(FCM:GetMessageType() == "Reward", "wrong type after restore")
		FCM:ClearMessage()
		assert(FCM:IsVisible() == false, "expected hidden after ClearMessage restore")
	end)

end -- fcOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 17 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
