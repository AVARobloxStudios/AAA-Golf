--!strict
-- SoundConfig — Centralized audio asset IDs (Milestone 2B).
-- Replace rbxassetid://0 stubs with purchased or free Creator Store audio.
-- No hardcoded asset IDs should appear outside this file.
--
-- Free Roblox library IDs verified as of 2026:
--   AmbientBirds: rbxassetid://9119713951 — "Summer Birds Ambience"
-- All others are stubs — source from the Creator Marketplace and swap in here.

local SoundConfig = {}

-- ── Club impact sounds ─────────────────────────────────────────────────────────
-- Triggered client-side on swing release, one per club category.
SoundConfig.Impact = {
	Driver = "rbxassetid://0",          -- needs: deep metallic thwack / titanium impact
	Wood   = "rbxassetid://0",          -- needs: slightly lighter wood/metal blend
	Hybrid = "rbxassetid://0",          -- needs: crisp iron-like crack
	Iron   = "rbxassetid://0",          -- needs: clean clicking iron strike
	Wedge  = "rbxassetid://0",          -- needs: short crisp wedge contact
	Putter = "rbxassetid://0",          -- needs: soft mallet click / tap
}

-- ── Ball event sounds ─────────────────────────────────────────────────────────
SoundConfig.BallLanding  = "rbxassetid://0"   -- fairway/rough landing thud
SoundConfig.BallBounce   = "rbxassetid://0"   -- secondary bounce (lighter)
SoundConfig.CupDrop      = "rbxassetid://0"   -- ball drops into cup
SoundConfig.WaterSplash  = "rbxassetid://0"   -- water hazard entry

-- ── Ambient sounds ─────────────────────────────────────────────────────────────
SoundConfig.AmbientBirds = "rbxassetid://9119713951"  -- Summer Birds Ambience (free)
SoundConfig.AmbientWind  = "rbxassetid://0"           -- needs: gentle breeze loop

-- ── UI sounds ─────────────────────────────────────────────────────────────────
SoundConfig.MenuClick    = "rbxassetid://0"   -- button press
SoundConfig.ScoreReveal  = "rbxassetid://0"   -- hole complete fanfare / chime

return SoundConfig
