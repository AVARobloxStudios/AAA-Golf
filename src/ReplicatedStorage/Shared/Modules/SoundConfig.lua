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
	Driver = "",          -- needs: deep metallic thwack / titanium impact
	Wood   = "",          -- needs: slightly lighter wood/metal blend
	Hybrid = "",          -- needs: crisp iron-like crack
	Iron   = "",          -- needs: clean clicking iron strike
	Wedge  = "",          -- needs: short crisp wedge contact
	Putter = "",          -- needs: soft mallet click / tap
}

-- ── Ball event sounds ─────────────────────────────────────────────────────────
SoundConfig.BallLanding  = ""   -- fairway/rough landing thud
SoundConfig.BallBounce   = ""   -- secondary bounce (lighter)
SoundConfig.CupDrop      = ""   -- ball drops into cup
SoundConfig.WaterSplash  = ""   -- water hazard entry

-- ── Ambient sounds ─────────────────────────────────────────────────────────────
SoundConfig.AmbientBirds = "rbxassetid://9119713951"  -- Summer Birds Ambience (free)
SoundConfig.AmbientWind  = ""           -- needs: gentle breeze loop

-- ── UI sounds ─────────────────────────────────────────────────────────────────
SoundConfig.MenuClick    = ""   -- button press
SoundConfig.ScoreReveal  = ""   -- hole complete fanfare / chime

return SoundConfig
