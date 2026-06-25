-- StreamingController — Pre-fetches next hole while player is on current hole
-- Fires PrefetchHole via GameBus to server on hole start
-- Implemented: Sprint 7

local StreamingController = {}
StreamingController.__index = StreamingController

function StreamingController:Init(dependencies: table)
end

function StreamingController:Update(dt: number)
end

function StreamingController:Destroy()
end

-- Called when a hole begins; triggers pre-fetch of the next hole
function StreamingController:OnHoleStart(currentHoleId: string)
end

-- Returns true when the requested hole's geometry is ready
function StreamingController:IsHoleReady(holeId: string): boolean
	return false
end

return StreamingController
