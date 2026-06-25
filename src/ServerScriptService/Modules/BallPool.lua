-- BallPool — Pre-allocates 10 ball Model instances at server start
-- Lease/Release pattern; never instantiates or destroys during gameplay
-- Implemented: Sprint 2

local BallPool = {}
BallPool.__index = BallPool

function BallPool:Init(dependencies: table)
end

function BallPool:Update(dt: number)
end

function BallPool:Destroy()
end

-- Returns an available BallModel from the pool; errors if pool exhausted
function BallPool:Lease()
end

-- Returns a ball to the pool and resets its state to IDLE
function BallPool:Release(ball: any)
end

function BallPool:_createBallModel(index: number)
end

return BallPool
