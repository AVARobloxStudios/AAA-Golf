--!strict
-- LieModifier — Shared, Milestone 2 / extended Milestone 4
-- Maps a lie string → shot-parameter multipliers applied before BallFlightService:Launch.
--
-- power       : effective power fraction          (1.0 = no penalty)
-- spin        : backSpin / sideSpin scale          (1.0 = full spin)
-- accuracy    : shape-offset scale, higher = straighter (1.0 = unmodified)
-- launch      : reserved for future loft scaling  (1.0 = normal)
-- mishitScale : amplifier on power penalty for poor contact
--               1.0 = normal; 1.60 = deep rough doubles the punishment
-- rollMult    : multiplies the per-club rollFrictionScale; ball stops faster
--               1.0 = no effect; 2.20 = sand kills roll quickly
-- loftBoost   : additive degrees added to club loft for "explosion" feel
--               0 = normal; 8 = bunker shot pops steeply upward
-- penalty     : true → Water / OB; caller handles as stroke-and-distance

local LieModifier = {}

export type LieMod = {
	power:       number,
	spin:        number,
	accuracy:    number,
	launch:      number,
	mishitScale: number,
	rollMult:    number,
	loftBoost:   number,
	penalty:     boolean,
}

local _mods: { [string]: LieMod } = {

	-- ── Clean lies — no penalty ───────────────────────────────────────────────
	Tee = {
		power = 1.00, spin = 1.00, accuracy = 1.00, launch = 1.00,
		mishitScale = 1.00, rollMult = 1.00, loftBoost = 0,
		penalty = false,
	},
	Fairway = {
		power = 1.00, spin = 1.00, accuracy = 1.00, launch = 1.00,
		mishitScale = 1.00, rollMult = 1.00, loftBoost = 0,
		penalty = false,
	},
	Green = {
		power = 1.00, spin = 1.00, accuracy = 1.00, launch = 1.00,
		mishitScale = 1.00, rollMult = 1.00, loftBoost = 0,
		penalty = false,
	},

	-- ── First Cut — slight resistance ─────────────────────────────────────────
	FirstCut = {
		power = 0.95, spin = 0.92, accuracy = 0.95, launch = 1.00,
		mishitScale = 1.10, rollMult = 1.15, loftBoost = 0,
		penalty = false,
	},

	-- ── Rough — clear power/spin loss; mishits amplified ─────────────────────
	Rough = {
		power = 0.85, spin = 0.78, accuracy = 0.85, launch = 0.95,
		mishitScale = 1.30, rollMult = 1.35, loftBoost = 0,
		penalty = false,
	},

	-- ── Deep Rough — heavy penalty, chunking dramatically more likely ─────────
	DeepRough = {
		power = 0.68, spin = 0.62, accuracy = 0.72, launch = 0.90,
		mishitScale = 1.60, rollMult = 1.60, loftBoost = 2,
		penalty = false,
	},

	-- ── Bunker / Sand — pops up steeply, short distance, stops fast ──────────
	Bunker = {
		power = 0.58, spin = 0.68, accuracy = 0.78, launch = 0.95,
		mishitScale = 1.45, rollMult = 2.20, loftBoost = 8,
		penalty = false,
	},

	-- ── Water / OB — stroke-and-distance; all other fields irrelevant ────────
	Water = {
		power = 0.00, spin = 0.00, accuracy = 0.00, launch = 0.00,
		mishitScale = 1.00, rollMult = 1.00, loftBoost = 0,
		penalty = true,
	},
}

local _default: LieMod = {
	power = 1.00, spin = 1.00, accuracy = 1.00, launch = 1.00,
	mishitScale = 1.00, rollMult = 1.00, loftBoost = 0,
	penalty = false,
}

function LieModifier.GetModifier(lie: string): LieMod
	return _mods[lie] or _default
end

function LieModifier.GetDisplayName(lie: string): string
	local names: { [string]: string } = {
		Tee       = "Tee Box",
		Fairway   = "Fairway",
		Green     = "Green",
		FirstCut  = "First Cut",
		Rough     = "Rough",
		DeepRough = "Deep Rough",
		Bunker    = "Bunker",
		Water     = "Water (Penalty)",
	}
	return names[lie] or lie
end

return LieModifier
