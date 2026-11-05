--!nonstrict
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
local Contract={}
Contract.Contexts={
	Lobby={movement=true,sprint=true,camera="ThirdPerson",group="Lobby"},
	Intro={movement=false,sprint=false,camera="Sequence",group="None"},
	ActiveFloor={movement=true,sprint=true,camera="FirstPerson",group="Gameplay"},
	Transit={movement=true,sprint=false,camera="FirstPerson",group="Cabin"},
	Downed={movement=false,sprint=false,camera="FirstPerson",group="Help"},
	Dead={movement=false,sprint=false,camera="Spectator",group="Spectator"},
	Results={movement=false,sprint=false,camera="Results",group="Results"},
}
function Contract.ContextFor(view,life)
	if view and (view.phase=="Resolving" or view.phase=="Completed" or view.phase=="Failed" or view.phase=="Closing") then return "Results" end
	if life=="Dead" then return "Dead" end
	if life=="Downed" then return "Downed" end
	if not view or view.phase=="Initializing" or view.phase=="WaitingForRoster" then return "Lobby" end
	if view.phase=="PreparingFloor" and view.completedFloors and #view.completedFloors>0 then return "Transit" end
	if view.phase=="Intro" or view.phase=="PreparingFloor" then return "Intro" end
	if view.phase=="Transit" or view.phase=="Departing" then return "Transit" end
	return "ActiveFloor"
end
return Freeze(Contract)
