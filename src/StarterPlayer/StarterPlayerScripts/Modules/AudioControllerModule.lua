--!strict
-- AudioControllerModule — Client singleton (Sprint 17)
-- Tracks volume levels and the currently playing music track.
-- Placeholder registry only — no real SoundService calls, no asset IDs.
--
-- Volume values are clamped to [0, 1] on every Set call.
-- PlaySFX / StopSFX track "active" state without wiring real Sound instances.
-- PlayMusic / StopMusic track the current track name.
--
-- Valid SFX names (placeholder):
--   Swing | BallHit | HoleSink | BirdieChime | EagleChime | BogeyGroan |
--   WindAmbient | MenuClick | MenuHover | CoinsCollect
--
-- Valid music tracks (placeholder):
--   LobbyTheme | CourseAmbient | RoundComplete | Victory
--
-- Public API
--   SetMasterVolume(value)  — clamped [0,1]
--   GetMasterVolume()       → number
--   SetMusicVolume(value)   — clamped [0,1]
--   GetMusicVolume()        → number
--   SetSFXVolume(value)     — clamped [0,1]
--   GetSFXVolume()          → number
--   PlaySFX(soundName)      — warns on unknown names
--   StopSFX(soundName)      — warns on unknown names
--   PlayMusic(trackName)    — warns on unknown tracks
--   StopMusic()             — clears current track
--   GetCurrentMusic()       → string  ("" when stopped)
--
-- AudioController.client.lua is the thin runner.

-- ── Sound registries (placeholder — no asset IDs yet) ─────────────────────────

local VALID_SFX: { [string]: boolean } = {
	Swing        = true,
	BallHit      = true,
	HoleSink     = true,
	BirdieChime  = true,
	EagleChime   = true,
	BogeyGroan   = true,
	WindAmbient  = true,
	MenuClick    = true,
	MenuHover    = true,
	CoinsCollect = true,
}

local VALID_MUSIC: { [string]: boolean } = {
	LobbyTheme    = true,
	CourseAmbient = true,
	RoundComplete = true,
	Victory       = true,
}

-- ── Default volume levels ─────────────────────────────────────────────────────

local DEFAULT_MASTER = 1.0
local DEFAULT_MUSIC  = 0.7
local DEFAULT_SFX    = 1.0

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean              = false
local _masterVolume:  number               = DEFAULT_MASTER
local _musicVolume:   number               = DEFAULT_MUSIC
local _sfxVolume:     number               = DEFAULT_SFX
local _currentMusic:  string               = ""
local _activeSFX:     { [string]: boolean } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local AudioControllerModule = {}
AudioControllerModule.__index = AudioControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

function AudioControllerModule:SetMasterVolume(value: number)
	_masterVolume = math.clamp(value, 0, 1)
end

function AudioControllerModule:GetMasterVolume(): number
	return _masterVolume
end

function AudioControllerModule:SetMusicVolume(value: number)
	_musicVolume = math.clamp(value, 0, 1)
end

function AudioControllerModule:GetMusicVolume(): number
	return _musicVolume
end

function AudioControllerModule:SetSFXVolume(value: number)
	_sfxVolume = math.clamp(value, 0, 1)
end

function AudioControllerModule:GetSFXVolume(): number
	return _sfxVolume
end

-- Marks the SFX as playing (placeholder — no real Sound instance).
function AudioControllerModule:PlaySFX(soundName: string)
	if not VALID_SFX[soundName] then
		warn(("[AudioController] PlaySFX: unknown sound %q"):format(
			tostring(soundName)))
		return
	end
	_activeSFX[soundName] = true
end

-- Marks the SFX as stopped.
function AudioControllerModule:StopSFX(soundName: string)
	if not VALID_SFX[soundName] then
		warn(("[AudioController] StopSFX: unknown sound %q"):format(
			tostring(soundName)))
		return
	end
	_activeSFX[soundName] = nil
end

-- Sets the active music track (placeholder — no real AudioPlayer).
function AudioControllerModule:PlayMusic(trackName: string)
	if not VALID_MUSIC[trackName] then
		warn(("[AudioController] PlayMusic: unknown track %q"):format(
			tostring(trackName)))
		return
	end
	_currentMusic = trackName
end

function AudioControllerModule:StopMusic()
	_currentMusic = ""
end

function AudioControllerModule:GetCurrentMusic(): string
	return _currentMusic
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function AudioControllerModule:Init()
	if _initialized then
		warn("[AudioController] Init called twice — skipping")
		return
	end
	_initialized  = true
	_masterVolume = DEFAULT_MASTER
	_musicVolume  = DEFAULT_MUSIC
	_sfxVolume    = DEFAULT_SFX
	_currentMusic = ""
	table.clear(_activeSFX)

	print("[AudioController] ready")
end

function AudioControllerModule:Update(_dt: number) end

function AudioControllerModule:Destroy()
	table.clear(_activeSFX)
	_masterVolume = DEFAULT_MASTER
	_musicVolume  = DEFAULT_MUSIC
	_sfxVolume    = DEFAULT_SFX
	_currentMusic = ""
	_initialized  = false
end

return AudioControllerModule
