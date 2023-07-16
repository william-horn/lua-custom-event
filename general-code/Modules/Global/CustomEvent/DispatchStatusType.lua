
local DispatchStatusType = {
	Disabled = {
		status = "Disabled",
		verbose = "Event is disabled. To re-enable it, call event:enable()"
	},
	
	UnknownRejectionError = {
		status = "UnknownRejectionError",
		verbose = "Event could not fire. Notify the developer if you get this error."
	},
	
	NoConnection = {
		status = "NoConnection",
		verbose = "No handlers have been connected to the event yet, and event.requiresConnection is set to true. Connect a handler to this event or toggle 'requiresConnection' to false in the event settings or headers."
	},
	
	DispatchLimitReached = {
		status = "DispatchLimitReached",
		verbose = "Event has reached maximum dispatch limit set in event settings."
	},
	
	AnscestorDisabled = {
		status = "AnscestorDisabled",
		verbose = "Event cannot fire due to anscestor being disabled. All anscestors of an event must be enabled in order for a descendant event to fire."
	},
	
	OnCooldown = {
		status = "OnCooldown",
		verbose = "Event failed to fire due to cooldown in event settings."
	},
	
	GloballyPaused = {
		status = "GloballyPaused",
		verbose = "Event failed to fire because all connections and/or descendant connections are paused at the highest priority."
	},
	
	LocallyPaused = {
		status = "LocallyPaused",
		verbose = "Event failed to fire because all connections directly on the local event are paused."
	},
	
	DispatchOverride = {
		status = "DispatchOverride",
		verbose = "Event successfully fired. Validation for this dispatch was ignored."
	},
	
	Successful = {
		status = "Successful",
		verbose = "Event successfully fired. All validations were met."
	},
	
	Rejected = {
		status = "Rejected",
		verbose = "Event validation failed."
	}
}

return DispatchStatusType