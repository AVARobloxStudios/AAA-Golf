--!strict
-- VFXControllerModule — Client singleton (Sprint 17)
-- Tracks which visual effects are currently active by name.
-- Placeholder only — no particle systems, no real VFX assets yet.
--
-- Each PlayEffect call records the effect as active.  Callers can query
-- IsEffectActive() to gate logic that depends on VFX state.
-- GetActiveEffects() returns an array copy of currently active names.
--
-- Valid effects:
--   SwingTrail | BallImpact | PerfectShot | CoinBurst |
--   XPGlow | UnlockSparkle | Confetti
--
-- Public API
--   PlayEffect(effectName, payload)   — activate; warns on unknown names
--   StopEffect(effectName)            — deactivate; warns on unknown names
--   IsEffectActive(effectName)        → boolean
--   GetActiveEffects()                → { string }  (array copy)
--   ClearEffects()                    — deactivate all
--
-- VFXController.client.lua is the thin runner.

-- ── Effect catalogue (placeholder) ───────────────────────────────────────────

local VALID_EFFECTS: { [string]: boolean } = {
	SwingTrail    = true,
	BallImpact    = true,
	PerfectShot   = true,
	CoinBurst     = true,
	XPGlow        = true,
	UnlockSparkle = true,
	Confetti      = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean               = false
local _activeEffects: { [string]: boolean } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local VFXControllerModule = {}
VFXControllerModule.__index = VFXControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Activates an effect.  `payload` is accepted for future use but ignored now.
function VFXControllerModule:PlayEffect(effectName: string, _payload: any)
	if not VALID_EFFECTS[effectName] then
		warn(("[VFXController] PlayEffect: unknown effect %q"):format(
			tostring(effectName)))
		return
	end
	_activeEffects[effectName] = true
end

function VFXControllerModule:StopEffect(effectName: string)
	if not VALID_EFFECTS[effectName] then
		warn(("[VFXController] StopEffect: unknown effect %q"):format(
			tostring(effectName)))
		return
	end
	_activeEffects[effectName] = nil
end

function VFXControllerModule:IsEffectActive(effectName: string): boolean
	return _activeEffects[effectName] == true
end

-- Returns an array copy of currently active effect names.
-- Order is non-deterministic (depends on hash iteration).
function VFXControllerModule:GetActiveEffects(): { string }
	local arr: { string } = {}
	for name in pairs(_activeEffects) do
		table.insert(arr, name)
	end
	return arr
end

function VFXControllerModule:ClearEffects()
	table.clear(_activeEffects)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function VFXControllerModule:Init()
	if _initialized then
		warn("[VFXController] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_activeEffects)

	print("[VFXController] ready")
end

function VFXControllerModule:Update(_dt: number) end

function VFXControllerModule:Destroy()
	table.clear(_activeEffects)
	_initialized = false
end

return VFXControllerModule
