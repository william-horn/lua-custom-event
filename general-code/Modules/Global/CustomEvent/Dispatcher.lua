
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules

local Debug__Package = require(Modules.Global.Debug)
local Debug, DebugPriorityLevel = Debug__Package.Debug, Debug__Package.DebugPriorityLevel

local EventValidationStatus = require(script.Parent.EventValidationStatus) 
local DispatchStatusType = require(script.Parent.DispatchStatusType)

local Dispatcher = {}
Dispatcher.__index = Dispatcher

function Dispatcher:execute(payload__local, settings__localEvent, eventValidationReport)
	local eventBlacklist = self.eventBlacklist 

	-- payload metadata
	local event = payload__local.event
	local args = payload__local.args or {}

	-- event data
	local stats = event.stats
	local parentEvent = event._parentEvent
	local childEvents = event._childEvents
	local connections = event._connections
	local linkedEvents = settings__localEvent.linkedEvents
	
	self.blacklist[event] = true

	local function runEventHandlers()
		if (settings__localEvent.dispatchSelf) then
			for index = 1, #connections do
				local connection = connections[index]

				if connection:isActive() and self.catalyst._propagating then

					-- TODO: add a staticArgs table to send back to the handler function which contains
					-- the catalyst event, along with more verbose information
					if (settings__localEvent.async or connection.async) then
						task.defer(
							connection.handler,
							self.catalyst,
							unpack(args)
						)
					else
						connection.handler(self.catalyst, unpack(args))
					end
				end
			end
		end
	end

	local function runDescendantEventHandlers()
		if (settings__localEvent.dispatchDescendants and #childEvents > 0) then
			for index = 1, #childEvents do
				local childEvent = childEvents[index]

				self:fire({ 
					event = childEvent,
					args = args,
				})
			end
		end
	end
	
	local function runAscendantEventHandlers()
		if (settings__localEvent.dispatchAscendants and parentEvent and self.catalyst._propagating) then
			self:fire({
				event = parentEvent,
				args = args,
				headers = {
					dispatchDescendants = false,
				}
			})
		end
	end
	
	local function runLinkedEventHandlers()
		if (settings__localEvent.dispatchLinked and #linkedEvents > 0) then
			for index = 1, #linkedEvents do
				local linkedEvent = linkedEvents[index]
				self:fire({
					event = linkedEvent,
					args = args
				})
			end
		end
	end

	-- fire end of dispatch callbacks. these will run before the dispatch handlers
	if eventValidationReport.result == EventValidationStatus.Successful then
		event:executeDispatchSuccess(eventValidationReport.reasons, event)
		runEventHandlers()
		runLinkedEventHandlers()

	elseif eventValidationReport.result == EventValidationStatus.Rejected then
		event:executeDispatchFailed(eventValidationReport.reasons, event)
	end

	-- run dispatch handlers
	-- TODO: add dispatch execution order option?
	if not eventValidationReport:hasDispatchStatus(DispatchStatusType.GloballyPaused) then
		runAscendantEventHandlers()
		runDescendantEventHandlers()
	end

	-- update time last dispatched to now
	stats.timeLastDispatched = tick()
end

function Dispatcher:fire(payload__local, initialDispatch)
	if (self.blacklist[payload__local.event]) then
		Debug.error("Cyclic event detected. Make sure your events are properly connected.") 
		return
	end
	
	local settings__localEvent = payload__local.event:getSettingsWithHeaders(self.headers__original)
	
	-- on all dispatches that are not the original dispatch (such as recursive dispatches), use the
	-- headers that are provided in the local payload.
	if (payload__local.headers and not initialDispatch) then
		for key, value in next, payload__local.headers do
			settings__localEvent[key] = value
		end
	end
	
	-- validate the event dispatch and update dispatch stats
	local eventValidationReport = payload__local.event:validateDispatch(settings__localEvent) 
	eventValidationReport:updateStats()
	
	-- execute the dispatch 
	self:execute(payload__local, settings__localEvent, eventValidationReport)

	return eventValidationReport
end

function Dispatcher.new(payload__original)
	local dispatcher = setmetatable({}, Dispatcher)

	dispatcher.blacklist = {}
	dispatcher.catalyst = payload__original.event
	dispatcher.headers__original = payload__original.headers

	return dispatcher
end

function Dispatcher.onDispatchFailed(dispatchStatus, event)
	Debug.warn(
		DebugPriorityLevel.High,
		"Dispatch rejected for event ["..event.name.."]: ", dispatchStatus
	)
end

function Dispatcher.onDispatchSuccess(dispatchStatus, event)
	Debug.print(
		DebugPriorityLevel.High,
		"Dispatch succeeded for event ["..event.name.."]: ", dispatchStatus
	)
end

return Dispatcher
