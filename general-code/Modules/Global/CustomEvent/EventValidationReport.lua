
local EventValidationStatus = require(script.Parent.EventValidationStatus)

local EventValidationReport = {}
EventValidationReport.__index = EventValidationReport

function EventValidationReport:updateStats()
	if (not self.stats) then
		return
	end
	
	local reasons = self.reasons
	
	for index = 1, #reasons do
		local reason = reasons[index]
		if (reason.statType and reason.statValue) then
			self.stats[reason.statType] += reason.statValue
		end
	end
	
	self.stats[self.resultStatType] += self.resultStatValue
end

function EventValidationReport:hasDispatchStatus(dispatchStatusType)
	for index = 1, #self.reasons do
		local reason = self.reasons[index]
		if (reason.dispatchStatusType == dispatchStatusType) then
			return true
		end
	end
	
	return false
end

function EventValidationReport:addReason(dispatchStatusType, statType, statValue)
	self.reasons[#self.reasons + 1] = {
		dispatchStatusType = dispatchStatusType,
		statType = statType,
		statValue = statValue
	}
end

function EventValidationReport:setResult(eventValidationStatus, statType, statValue)
	self.result = eventValidationStatus
	self.resultStatType = statType
	self.resultStatValue = statValue
end

function EventValidationReport.new(stats)
	local evr = setmetatable({}, EventValidationReport)
	
	evr.resultStatType = nil
	evr.resultStatValue = nil
	evr.result = nil
	evr.reasons = {} 
	evr.stats = stats

	return evr
end

return EventValidationReport