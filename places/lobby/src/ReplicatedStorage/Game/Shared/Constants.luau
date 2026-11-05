--!strict
local Freeze = require(script.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	SchemaVersion = 5,
	BuildVersion = "0.9.2-triage",
	ImplementedChunk = 9,
	OwnershipTag = "ElevatorHorror",
	FoundationPhase = "FoundationReady",
	RemoteNames = { "ClientAction", "ClientReady", "StateSnapshot", "PresentationEvent" },
	RunPhases = {
		"Initializing", "WaitingForRoster", "Intro", "PreparingFloor", "FloorActive",
		"Departing", "Transit", "FinaleActive", "Resolving", "Completed", "Failed", "Closing",
	},
	LifeStates = { "Alive", "Downed", "Dead", "Escaped" },
	ConnectionStates = { "Connected", "Disconnected", "Abandoned" },
	PlannedActions = {
		"Ready", "StartParty", "Interact", "DropObjectiveItem", "BeginSprint", "EndSprint",
		"ToggleFlashlight", "BeginRevival", "CancelRevival", "RequestDeparture",
	},
})
