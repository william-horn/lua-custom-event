
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules

local Debug__Package = require(Modules.Global.Debug)
local Debug, DebugPriorityLevel = Debug__Package.Debug, Debug__Package.DebugPriorityLevel

local EventValidationStatus = require(script.Parent.EventValidationStatus) 
local DispatchStatusType = require(script.Parent.DispatchStatusType)

local Dispatcher = {}
Dispatcher.__index = Dispatcher

function Dispatcher:execute(payload__local, settings__localEvent, eventValidationReport)
	-- if catalyst event is no longer propagating, exit the event cycle
	local eventBlacklist = self.eventBlacklist 

	-- payload metadata
	local event = payload__local.event
	local args = payload__local.args

	-- event data
	local analytics = event.analytics
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
		if (#childEvents == 0) or (not self.catalyst._propagating) then
			return
		end
		
		if (settings__localEvent.dispatchChildren) then
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
		if (not parentEvent) or (not self.catalyst._propagating) then
			return
		end
		
		if (settings__localEvent.dispatchParent) then
			self:fire({
				event = parentEvent,
				args = args,
				headers__local = {
					dispatchDescendants = false,
					dispatchChildren = false 
				}
			})
		end
	end
	
	local function runLinkedEventHandlers()
		if (#linkedEvents == 0) or (not self.catalyst._propagating) then
			return
		end
		
		if (settings__localEvent.dispatchLinked) then
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
	analytics.timeLastDispatched = tick()
end

function Dispatcher:fire(payload__local)
	local event = payload__local.event
	--local initialDispatch = event == self.catalyst
	
	-- debounce blacklisted events to avoid cyclic occurances
	if (self.blacklist[event]) then
		Debug.error("Cyclic event detected. Make sure your events are properly connected.") 
		return
	end
	
	local settings__localEvent = table.clone(event.settings)
	payload__local.args = payload__local.args or {}
	
	-- apply global headers, if any
	if (self.headers__global) then
		for key, value in next, self.headers__global do
			settings__localEvent[key] = value
		end
	end
	
	-- apply local headers, if any
	if (payload__local.headers__local) then
		for key, value in next, payload__local.headers__local do
			settings__localEvent[key] = value
		end
	end
	
	-- validate the event dispatch and update dispatch stats
	local eventValidationReport = event:validateDispatch(settings__localEvent)
	
	--------------------------------------
	--- TODO: UPDATE ANALYTICS HERE!!! ---
	
	--------------------------------------
	
	-- execute the dispatch 
	self:execute(payload__local, settings__localEvent, eventValidationReport)

	return eventValidationReport
end

function Dispatcher.new(payload__original)
	local dispatcher = setmetatable({}, Dispatcher)
	
	dispatcher.blacklist = {}
	dispatcher.catalyst = payload__original.event
	dispatcher.headers__global = payload__original.headers__global
 
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
