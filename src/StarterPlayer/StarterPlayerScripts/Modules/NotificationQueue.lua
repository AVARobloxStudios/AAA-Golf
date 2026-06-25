-- NotificationQueue — Toast notifications and achievement popups
-- Queues multiple notifications and displays them sequentially
-- Implemented: Sprint 4

local NotificationQueue = {}
NotificationQueue.__index = NotificationQueue

function NotificationQueue:Init(dependencies: table)
end

function NotificationQueue:Update(dt: number)
end

function NotificationQueue:Destroy()
end

-- Adds a toast notification to the queue
function NotificationQueue:PushToast(message: string, duration: number?)
end

-- Adds an achievement popup to the queue
function NotificationQueue:PushAchievement(achievementId: string)
end

function NotificationQueue:_processQueue()
end

return NotificationQueue
