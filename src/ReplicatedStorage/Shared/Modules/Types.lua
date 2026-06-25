-- Types — Shared Luau type definitions for cross-boundary data structures
-- Import this module wherever type annotations are needed

local Types = {}

-- Ball physics state passed through integrator steps
export type BallPhysState = {
	pos: Vector3,
	vel: Vector3,
	spin: Vector3,
}

-- Swing intent payload sent from client to server via GameBus
export type SwingIntent = {
	eventType: string,       -- "SwingIntent"
	aimVector: Vector3,
	power: number,           -- 0.0–1.0
	accuracy: number,        -- -1.0 (slice) to 1.0 (hook)
	clubId: string,          -- Enums.ClubType value
	timestamp: number,
}

-- Server → client ball resolution payload
export type BallResolved = {
	ballId: string,
	trajectory: { Vector3 },
	landingPos: Vector3,
	landingSurface: string,
}

-- Server → client stroke confirmation
export type StrokeCommitted = {
	strokes: number,
	par: number,
	scoreTier: string,
	coinDelta: number,
	xpDelta: number,
}

-- Profile schema top-level shape (subset used by client)
export type ClientProfile = {
	userId: number,
	displayName: string,
	level: number,
	coins: number,
	xp: number,
	unlockedCourses: { string },
}

-- Per-hole score entry
export type HoleScore = {
	holeNumber: number,
	par: number,
	strokes: number,
	scoreTier: string,
	coins: number,
	xp: number,
}

-- Round summary passed to RoundSummary screen
export type RoundSummary = {
	courseId: string,
	holes: { HoleScore },
	totalStrokes: number,
	totalPar: number,
	totalCoins: number,
	totalXP: number,
}

-- GameBus payload envelope
export type GameBusEnvelope = {
	eventType: string,
	payload: any,
	timestamp: number,
}

return Types
