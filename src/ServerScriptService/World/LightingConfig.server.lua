--!strict
-- LightingConfig — Server Script (Sprint 35)
-- Configures Roblox Lighting for Sunnybrook Meadows: sunny spring afternoon,
-- bright and warm, with Atmosphere, ColorCorrection, SunRays, and Bloom.
-- Runs once at server start; effects replicate to all clients automatically.

local Lighting = game:GetService("Lighting")

-- ── Clear any existing post-effects and atmosphere ───────────────────────────

for _, child in Lighting:GetChildren() do
	if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
		child:Destroy()
	end
end

-- ── Lighting base properties ─────────────────────────────────────────────────

Lighting.Brightness         = 2.2
Lighting.ClockTime          = 14.2        -- 2:12 PM, afternoon sun
Lighting.GeographicLatitude = 41.0        -- mid-latitude sun angle
Lighting.GlobalShadows      = true
Lighting.FogEnd             = 2200
Lighting.FogStart           = 1600
Lighting.FogColor           = Color3.fromRGB(192, 215, 242)
Lighting.Ambient            = Color3.fromRGB(68, 88, 108)
Lighting.OutdoorAmbient     = Color3.fromRGB(108, 128, 148)

-- ── Atmosphere ───────────────────────────────────────────────────────────────

local atmo          = Instance.new("Atmosphere")
atmo.Density        = 0.30     -- slight haze; keeps horizon clean
atmo.Offset         = 0.08
atmo.Color          = Color3.fromRGB(198, 222, 248)
atmo.Decay          = Color3.fromRGB(145, 175, 210)
atmo.Glare          = 0.45
atmo.Haze           = 1.0
atmo.Parent         = Lighting

-- ── ColorCorrection ──────────────────────────────────────────────────────────

local cc            = Instance.new("ColorCorrectionEffect")
cc.Name             = "SpringTone"
cc.Brightness       = 0.02      -- very slightly brighter
cc.Contrast         = 0.05      -- very slightly punchier
cc.Saturation       = 0.18      -- warm, vivid greens
cc.TintColor        = Color3.fromRGB(255, 248, 235)   -- warm ivory tint
cc.Parent           = Lighting

-- ── SunRays ──────────────────────────────────────────────────────────────────

local rays          = Instance.new("SunRaysEffect")
rays.Name           = "AfternoonRays"
rays.Intensity      = 0.06      -- subtle god-rays
rays.Spread         = 0.55
rays.Parent         = Lighting

-- ── Bloom ────────────────────────────────────────────────────────────────────

local bloom         = Instance.new("BloomEffect")
bloom.Name          = "SoftBloom"
bloom.Intensity     = 0.45      -- light bloom on bright surfaces
bloom.Size          = 22
bloom.Threshold     = 0.92
bloom.Parent        = Lighting

print("[LightingConfig] Sunnybrook Meadows lighting applied — 2:12 PM spring afternoon")
