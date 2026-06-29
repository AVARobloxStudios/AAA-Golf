--!strict
-- SFXPlayer — Client, Milestone 2B.
-- Thin wrapper: looks up asset IDs from SoundConfig and plays them via SoundService.
-- Caches Sound instances so repeated calls don't spawn new objects.
-- Stubs (rbxassetid://0) are silently skipped — no error, no log spam.
--
-- Public API
--   PlayImpact(category)  — club category string matching SoundConfig.Impact keys
--   PlayLanding()         — ball landing on fairway / rough
--   PlayCupDrop()         — ball drops into cup

local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Defensive load: SoundConfig is a new file from Milestone 2B; if Rojo hasn't synced
-- it yet the module would throw and break the entire client script chain.
local _STUB_IMPACT = { Driver="rbxassetid://0", Wood="rbxassetid://0", Hybrid="rbxassetid://0",
	Iron="rbxassetid://0", Wedge="rbxassetid://0", Putter="rbxassetid://0" }
local _ok, _cfg = pcall(function()
	return require(ReplicatedStorage.Shared.Modules.SoundConfig)
end)
if not _ok then
	warn("[SFXPlayer] SoundConfig not found — all sounds will be silent until synced:", _cfg)
end
local SoundConfig: any = if _ok then _cfg else {
	Impact = _STUB_IMPACT, BallLanding = "rbxassetid://0",
	CupDrop = "rbxassetid://0", AmbientBirds = "rbxassetid://0", AmbientWind = "rbxassetid://0",
}

local SFXPlayer = {}

local _cache: { [string]: Sound } = {}

-- Returns a cached Sound instance for (name, soundId). Returns nil for stubs.
local function _getSound(name: string, soundId: string): Sound?
	if soundId == "rbxassetid://0" then return nil end
	local s = _cache[name]
	if s and s.Parent then return s end
	s          = Instance.new("Sound")
	s.Name     = name
	s.SoundId  = soundId
	s.Volume   = 0.85
	s.Parent   = SoundService
	_cache[name] = s
	return s
end

-- Plays the club impact sound for the given ClubData category.
function SFXPlayer:PlayImpact(category: string)
	local idTable = SoundConfig.Impact :: { [string]: string }
	local id: string = (idTable :: any)[category] or idTable.Iron
	local s = _getSound("Impact_" .. category, id)
	if s then s:Play() end
end

-- Plays the ball landing sound.
function SFXPlayer:PlayLanding()
	local s = _getSound("BallLanding", SoundConfig.BallLanding)
	if s then s:Play() end
end

-- Plays the cup-drop sound.
function SFXPlayer:PlayCupDrop()
	local s = _getSound("CupDrop", SoundConfig.CupDrop)
	if s then s:Play() end
end

return SFXPlayer
