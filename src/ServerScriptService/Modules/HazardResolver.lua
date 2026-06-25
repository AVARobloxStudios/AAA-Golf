-- HazardResolver — Detects ball entry into water/sand/OOB zones
-- Returns surface type and penalty data; used by PhysicsIntegrator landing check
-- Implemented: Sprint 2

local HazardResolver = {}
HazardResolver.__index = HazardResolver

function HazardResolver:Init(dependencies: table)
end

function HazardResolver:Update(dt: number)
end

function HazardResolver:Destroy()
end

-- Returns the SurfaceType enum value for the given world position
-- Checks tagged hazard Parts before defaulting to FAIRWAY
function HazardResolver:GetSurface(position: Vector3): string
end

-- Returns penalty data for the given surface type
function HazardResolver:GetPenalty(surfaceType: string): any
end

function HazardResolver:_buildZoneCache()
end

return HazardResolver
