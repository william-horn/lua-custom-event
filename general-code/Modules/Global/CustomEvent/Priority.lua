
local PriorityType = {
	Base = 0,
	Medium = 100,
	High = 200,
	Max = math.huge
}

local PriorityRegion = {
	Global = 0,
	Local = 1
}

return {
	PriorityType = PriorityType,
	PriorityRegion = PriorityRegion
}
