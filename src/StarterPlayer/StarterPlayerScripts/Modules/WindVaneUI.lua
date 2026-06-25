-- WindVaneUI — Wind direction arrow and speed readout widget
-- Driven by WeatherChanged events from server
-- Implemented: Sprint 4

local WindVaneUI = {}
WindVaneUI.__index = WindVaneUI

function WindVaneUI:Init(dependencies: table)
end

function WindVaneUI:Update(dt: number)
end

function WindVaneUI:Destroy()
end

-- Updates the arrow direction and speed text
function WindVaneUI:SetWind(direction: Vector3, speedMPH: number)
end

return WindVaneUI
