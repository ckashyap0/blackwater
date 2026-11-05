--!nonstrict
-- Actions without a registered consumer stay unbound and have no visible button.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	-- Crouch: C toggles, R3 on gamepad, button on touch.
	Crouch={key=Enum.KeyCode.C,pad=Enum.KeyCode.ButtonR3,label="Crouch",groups={Lobby=true,Gameplay=true,Cabin=true}},
	-- CrouchHold: Left Ctrl is a plain crouch while held (no crawl key: lying down only happens in vents).
	CrouchHold={key=Enum.KeyCode.LeftControl,pad=Enum.KeyCode.ButtonB,label="Crouch",groups={Gameplay=true,Cabin=true}},
	Interact={key=Enum.KeyCode.E,pad=Enum.KeyCode.ButtonX,label="Interact",groups={Lobby=true,Gameplay=true,Cabin=true}},
	Sprint={key=Enum.KeyCode.LeftShift,pad=Enum.KeyCode.ButtonL3,label="Sprint",groups={Lobby=true,Gameplay=true}},
	Flashlight={key=Enum.KeyCode.F,pad=Enum.KeyCode.ButtonY,label="Flashlight",groups={Gameplay=true,Cabin=true}},
	DropObjectiveItem={key=Enum.KeyCode.X,pad=Enum.KeyCode.DPadDown,label="Drop",groups={Gameplay=true,Cabin=true}},
	Ping={key=Enum.KeyCode.Q,pad=Enum.KeyCode.DPadUp,label="Help",groups={Gameplay=true,Cabin=true,Help=true}},
	SpectateNext={key=Enum.KeyCode.E,pad=Enum.KeyCode.ButtonR1,label="Next",groups={Spectator=true}},
	SpectatePrevious={key=Enum.KeyCode.Q,pad=Enum.KeyCode.ButtonL1,label="Previous",groups={Spectator=true}},
	Confirm={key=Enum.KeyCode.Return,pad=Enum.KeyCode.ButtonA,label="Confirm",groups={Lobby=true,Results=true}},
	Cancel={key=Enum.KeyCode.Backspace,pad=Enum.KeyCode.ButtonB,label="Back",groups={Lobby=true,Results=true}},
})
