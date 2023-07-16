--[[
	@author: 
		William J. Horn
		ScriptGuider @ROBLOX.com
		
	@description:
		The CustomEvent library allows you to create and manage your own pseudo events in Lua. It comes
		packaged with a powerful API that lets you manipulate event connections, use different connection
		priorities, create event chains, etc.
		
		Note: Note: This program was designed to run in the ROBLOX environment with ROBLOX's modified version of Lua.
		
	@last-updated:
		07/16/2023
		
	@help:
		If you have any questions or concerns, please email me at: williamjosephhorn@gmail.com
]]

-----------------------
--- ROBLOX services ---
-----------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------------------
--- External project files ---
------------------------------
local Modules = ReplicatedStorage.Modules

---------------
--- Imports ---
---------------
-- External imports
local uuid = require(Modules.Global.UUID)
local Debug__Package = require(Modules.Global.Debug)
local Debug, DebugPriorityLevel = Debug__Package.Debug, Debug__Package.DebugPriorityLevel
local GameConfig = require(ReplicatedStorage.GameConfig):getConfigForMachine()
local Analytics = require(Modules.Global.Analytics)

-- Internal imports
local Enum = require(Modules.Global.EnumExtension)
local DispatchStatusType = require(script.DispatchStatusType)
local EventValidationStatus = require(script.EventValidationStatus)
local EventStateType = require(script.EventStateType)

local Priority__Package = require(script.Priority)
local PriorityType, PriorityRegion = Priority__Package.PriorityType, Priority__Package.PriorityRegion

local Dispatcher = require(script.Dispatcher)
local EventValidationReport = require(script.EventValidationReport)
local ConnectionInstance = require(script.ConnectionInstance)

-------------------------
--- Localized globals ---
-------------------------
local unpack = unpack

-------------------------
--- Utility functions ---
-------------------------

--[[
	validateSearchQuery(search<table>, against<table>): <boolean>
		@params search:
			The table containing the keys/values to include in the search over
			the object.
		@params against:
			The object being searched.
			
	Used for searching event connections by their given options.
]]
local function validateSearchQuery(search, against)
	for k, v in next, search do
		if (v ~= against[k]) then
			return false
		end
	end

	return true
end

local function getDefaultOptions(options)
	options = options or {}
	options.priority = options.priority or PriorityType.Base
	
	return options
end

function dispatchEvent(payload__original)
	local dispatcher = Dispatcher.new(payload__original)
	local event = payload__original.event
	
	-- initiate event propagation state
	event._propagating = true
	
	-- fire custom internal dispatcher
	dispatcher:fire(payload__original)
	
	-- fire roblox wait signal
	event._rbxYieldSignal:Fire(unpack(payload__original.args or {}))
	
	-- cancel any yielding threads for event:wait(), if any
	local yieldTasks = event._yieldTasks
	
	if (#yieldTasks > 0) then
		for index = 1, #yieldTasks do
			local yieldTask = yieldTasks[index]
			task.cancel(yieldTask)
			yieldTasks[index] = nil
		end
	end
	
	-- conclude event propagation state
	event:stopPropagating()
	return event
end

-------------------------
--- CustomEvent API ---
-------------------------
local Event = {}
Event.__index = Event

function Event:getPriorityList(region)
	local uniquePriority
	local priorityList

	if (region == PriorityRegion.Global) then
		uniquePriority = self._uniqueGlobalPriorities
		priorityList = self._globalPriorities

	elseif (region == PriorityRegion.Local) then
		uniquePriority = self._uniqueLocalPriorities
		priorityList = self._localPriorities
	end

	return priorityList, uniquePriority
end

function Event:validateDispatch(headers)
	local settings = headers or self.settings
	local analytics = self.analytics
	
	local report = EventValidationReport.new(EventValidationStatus.Rejected)
	
	-- special case event overrides
	if (not settings.withValidation) then
		report:addReason(DispatchStatusType.DispatchOverride)
	end
	
	if (#report.reasons > 0) then
		report:setResult(EventValidationStatus.Successful)
		return report
	end
	
	-- event dispatch validation
	if self:isDisabled() then
		report:addReason(DispatchStatusType.Disabled)
	end
		
	if self._anscestorsDisabled > 0 then
		report:addReason(DispatchStatusType.AnscestorDisabled)
	end
	
	if #self._connections == 0 and settings.requiresConnection then
		report:addReason(DispatchStatusType.NoConnection)
	end
	
	if (self._pausePriority >= self:getHighestGlobalPriority()) then
		report:addReason(DispatchStatusType.GloballyPaused) 
		
	elseif (self._pausePriority >= self:getHighestLocalPriority()) then
		report:addReason(DispatchStatusType.LocallyPaused)
	end
	
	if (analytics:isActive() and analytics.dispatchesSuccessful >= settings.dispatchLimit) then
		report:addReason(DispatchStatusType.DispatchLimitReached)
	end
	
	-- update final dispatch report
	if (#report.reasons == 0) then
		report:addReason(DispatchStatusType.Successful)
		report:setResult(EventValidationStatus.Successful)
	end
	
	return report
end

-- TODO: optimize addPriority function
function Event:addPriority(region, priority)
	local priorityList, uniquePriority = self:getPriorityList(region)
	
	if (uniquePriority[priority]) then
		return
	end
	
	-- add the new priority number to the global priority list
	--uniquePriority[priority] = true
	priorityList[#priorityList + 1] = priority
	local numPriorityList = #priorityList
	
	uniquePriority[priority] = numPriorityList
	
	-- sort the new unique priority number
	if (numPriorityList > 1) then
		for i = numPriorityList, 2, -1 do
			local prev = i - 1
			if (priorityList[i] < priorityList[prev]) then
				priorityList[prev], priorityList[i] = priorityList[i], priorityList[prev]
				uniquePriority[priorityList[prev]] = prev
				uniquePriority[priorityList[i]] = i
			else
				break
			end
		end
	else
		uniquePriority[priorityList[numPriorityList]] = numPriorityList
	end
	
	-- bubble up the event chain
	if (self._parentEvent and region == PriorityRegion.Global) then
		self._parentEvent:addPriority(PriorityRegion.Global, priority)
	end
end

-- TODO: optimize removePriority function
function Event:removePriority(region, priority)
	local priorityList, uniquePriority = self:getPriorityList(region)
	local priorityIndex = uniquePriority[priority]
	
	if (not uniquePriority[priority]) then
		return
	end
	
	-- remove the priorities less than or equal to the given priority from the priority list
	for i = priorityIndex, 1, -1 do
		uniquePriority[priorityList[i]] = nil
		table.remove(priorityList, i)
	end
	
	-- update the unique priority list indicies
	for i = 1, #priorityList do
		local priorityItem = priorityList[i]
		uniquePriority[priorityItem] = i
	end
	
	-- bubble up the event chain
	if (self._parentEvent and region == PriorityRegion.Global) then
		self._parentEvent:removePriority(PriorityRegion.Global, priority)
	end
end

function Event:getHighestGlobalPriority()
	return self._globalPriorities[#self._globalPriorities] or PriorityType.Base
end

function Event:getHighestLocalPriority()
	return self._localPriorities[#self._localPriorities] or PriorityType.Base
end

function Event:connect(options)
	options = getDefaultOptions(options)
	
	local connections = self._connections
	local connection = ConnectionInstance.new(options)
	connections[#connections + 1] = connection
	
	-- TODO: optimize method priorities are added/removed. connecting/disconnecting events is
	-- currently the largest source of overhead in the program.
	self:addPriority(PriorityRegion.Local, options.priority)
	self:addPriority(PriorityRegion.Global, options.priority)
	
	return connection
end

function Event:connectAsync(options)
	options.async = true
	self:connect(options)
end

function Event:dispatch(options)
	options.event = self
	dispatchEvent(options)
end

function Event:fire(...) 
	self:dispatch({
		args = {...}
	})
end

function Event:fireAll(...)
	self:dispatch({
		args = {...},
		headers__global = {
			dispatchChildren = true
		}
	})
end

function Event:fireAsync(...)
	self:dispatch({
		args = {...},
		headers__local = {
			async = true
		}
	})
end

function Event:fireDescendantsOnly(...)
	self:dispatch({
		args = {...},
		headers__local = {
			dispatchSelf = false,
		},
		headers__global = {
			dispatchChildren = true
		}
	})
end

function Event:getSettingsWithHeaders(headers)
	if headers then
		local settings = table.clone(self.settings)
		
		for key, value in next, headers do
			settings[key] = value
		end
		
		return settings
	end

	return self.settings
end

function Event:stopPropagating() 
	self._propagating = false
end

function Event:executeDispatchSuccess(...)
	if (self.onDispatchSuccess) then
		self.onDispatchSuccess(...)
	else
		Dispatcher.onDispatchSuccess(...) 
	end
end
 
function Event:executeDispatchFailed(...)
	if (self.onDispatchFailed) then
		self.onDispatchFailed(...)
	else
		Dispatcher.onDispatchFailed(...)
	end
end

function Event:queryDescendantEvents(callback)
	local function searchChildren(_event)
		callback(_event)

		if (#_event._childEvents > 0) then
			for i = 1, #_event._childEvents do
				searchChildren(_event._childEvents[i]) 
			end
		end
	end

	searchChildren(self)
end

function Event:queryEventConnections(options, callback)
	options = table.clone(getDefaultOptions(options))
	local priority = options.priority

	local connections = self._connections
	options.priority = nil

	for index = #connections, 1, -1 do
		local connection = connections[index]
		if (validateSearchQuery(options, connection) and connection.priority <= priority) then
			callback(connections, index, connection)
		end
	end
end

function Event:pause(options)
	options = getDefaultOptions(options)
	
	if (options.priority > self._pausePriority) then
		self._pausePriority = options.priority
	end
	
	self:queryEventConnections(options, function(connections, index, connection)
		connection:pause()
	end)
end

function Event:resume(options)
	options = getDefaultOptions(options)
	
	if (options.priority >= self._pausePriority) then
		self._pausePriority = -1
	end
	
	self:queryEventConnections(options, function(connections, index, connection)
		connection:resume()
	end)
end

function Event:pauseAll(options)
	options = getDefaultOptions(options)
	
	self:queryDescendantEvents(function(event)
		event:pause(options)
	end)
end

function Event:resumeAll(options)
	options = getDefaultOptions(options)
	
	self:queryDescendantEvents(function(event)
		event:resume(options)
	end)
end

function Event:disconnect(options)
	options = getDefaultOptions(options)
	
	self:queryEventConnections(options, function(connections, index, connection)
		table.remove(connections, index)
	end)
	
	self:removePriority(PriorityRegion.Local, options.priority)
	self:removePriority(PriorityRegion.Global, options.priority)
end

function Event:disconnectAll(options)
	options = getDefaultOptions(options)
	
	self:queryDescendantEvents(function(event)
		event:disconnect(options)
	end)
end

function Event:wait(timeout)
	local now = tick()

	if timeout then
		local yieldTask = task.delay(timeout, function()
			self._rbxYieldSignal:Fire()
			
			Debug.warn(
				DebugPriorityLevel.High,
				"Event timed out after "..tostring(tick() - now).." seconds."
			)
		end)
		
		self._yieldTasks[#self._yieldTasks + 1] = yieldTask
	end

	local args = { self._rbxYieldSignal.Event:Wait() }
	return tick() - now, unpack(args)
end

function Event:isDisabled()
	return self._state == EventStateType.Disabled
end

function Event:isEnabled()
	return not (self._state == EventStateType.Disabled)
end

function Event:isActive()
	local report = self:validateDispatch()
	return report.result == EventValidationStatus.Successful
end

function Event:disable()
	if (self._state == EventStateType.Disabled) then
		Debug.warn(
			DebugPriorityLevel.Medium,
			"Attempted to disable event ["..self._id.."] when event is already disabled."
		)
		return
	else
		local prevState = self._state

		self:queryDescendantEvents(function(event) 
			event._prevState = prevState
			event._state = EventStateType.Disabled
			event._inheritAnscestorsDisabled += 1
			
			if (event ~= self) then
				event._anscestorsDisabled += 1 
			end
		end)
	end
end

function Event:enable()
	if (self._state ~= EventStateType.Disabled) then
		Debug.warn(
			DebugPriorityLevel.Medium,
			"Attempted to enable event ["..self._id.."] when event is already enabled."
		)
		return
	end
	
	local prevState = self._prevState
	
	self:queryDescendantEvents(function(event)
		event._state = prevState
		event._inheritAnscestorsDisabled -= 1
		
		if (event ~= self) then
			event._anscestorsDisabled -= 1
		end
	end)
end

--[[
args: { parent = Event (optional), settings = {} (optional) }
]]
function Event.new(options)
	options = options or {
		parent = nil,
		settings = {},
		metadata = {},
		childEvents = {},
		eventMap = {},
		scope = {},
		eventMapReference = nil
	}
	
	local parentEvent = options.parent
	local settings = options.settings or {}
	local metadata = options.metadata or {}
	local childEvents = options.childEvents or {}
	local eventMap = options.eventMap or {}
	
	local event = setmetatable({}, Event)
	
	event._anscestorsDisabled = 0
	event._inheritAnscestorsDisabled = 0
	event._pausePriority = -1
	event._childEvents = childEvents
	event._uniqueGlobalPriorities = {}
	event._uniqueLocalPriorities = {}
	event._globalPriorities = {}
	event._localPriorities = {}
	event._id = uuid()
	event._customType = Enum.CustomTypes.CustomEventInstance
	event._propagating = false
	event._parentEvent = parentEvent
	event._prevState = EventStateType.Listening 
	event._state = EventStateType.Listening
	event._connections = {}
	event._rbxYieldSignal = Instance.new("BindableEvent")
	event._yieldTasks = {}
	
	-- event dispatch callbacks
	-- event.onDispatchFailed
	-- event.onDispatchSuccess
	
	event.name = options.name or event._id 
	event.eventMap = eventMap
	event.eventMapReference = options.eventMapReference
	event.scope = options.scope or {}
	
	-----------------------------------------------------------------------
	--- !! Analytics are inactive until the analytics module is complete !!
	-----------------------------------------------------------------------
	
	event.analytics = Analytics.new({
		--validationKey = 'recordCustomEventAnalytics', 
	}, {
		timeLastDispatched = Analytics.stat(0),
		
		dispatches = Analytics.category({
			displayName = "Dispatches", 
			autoIncrementTotal = true,
			
			stats = {
				whileDisabled = Analytics.stat(0),
				whileAnscestorDisabled = Analytics.stat(0),
				withoutValidation = Analytics.stat(0),
				whileGloballyPaused = Analytics.stat(0),
				whileLocallyPaused = Analytics.stat(0),
				withNoConnection = Analytics.stat(0),
				whileLimitReached = Analytics.stat(0),
				failed = Analytics.stat(0),
				successful = Analytics.stat(0),
			}
		})
	})
	
	event.settings = {
		linkedEvents = {},
		
		cooldown = {
			interval = 0,
			duration = 1,
			reset = 0
		},
		
		dispatchLimit = math.huge,
		
		dispatchLinked = true,			-- determins whether or not linked events will fire
		dispatchParent = false,			-- NEW (untested) determins whether the parent exclusively fires
		dispatchChildren = false,		-- NEW (untested) determins whether the children excluviely fires
		dispatchSelf = true, 			-- determins whether or not the direct connections to this event will fire when triggered
		requiresConnection = true, 		-- determines whether or not the event needs a connection to be triggered
		withValidation = true, 			-- if event handlers should meet conditions to be executed
		--async = nil, 					-- if event handlers should be run asynchonously or not
	}
	
	-- update default settings with instantiated settings
	for key, value in next, settings do
		event.settings[key] = value
	end
	
	-- if child events are given during instantiation then update child event parent
	if (#childEvents > 0) then
		for index = 1, #childEvents do
			local child = childEvents[index]
			child._parentEvent = event
		end
	end
	
	-- create root node chain
	if (parentEvent) then
		parentEvent._childEvents[#parentEvent._childEvents + 1] = event
		event._rootNode = parentEvent._rootNode or parentEvent
		
		event._anscestorsDisabled = parentEvent._inheritAnscestorsDisabled
		event._inheritAnscestorsDisabled = parentEvent._inheritAnscestorsDisabled
		event._pausePriority = parentEvent._pausePriority
		event._prevState = parentEvent._prevState
		event._state = parentEvent._state
		 
		if (options.eventMapReference) then
			parentEvent.eventMap[options.eventMapReference] = event
		end
	else
		event._rootNode = event
	end
	
	return event
end

return {
	Event = Event,
	DispatchStatusType = DispatchStatusType,
	EventPriority = PriorityType,
	EventValidationReport = EventValidationReport,
	EventValidationStatus = EventValidationStatus
}

