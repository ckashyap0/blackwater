--!strict
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local P={}
function P.InCabin(position:Vector3):boolean
	return math.abs(position.X)<7.6 and position.Z> -5.6 and position.Z<7.2 and position.Y>20 and position.Y<32
end
function P.InThreshold(position:Vector3):boolean
	return math.abs(position.X)<9 and math.abs(position.Z+8)<2.4 and position.Y>19 and position.Y<33
end
function P.CanDepart(snapshot:any,positions:any,suspended:boolean):(boolean,string)
	if not snapshot or snapshot.phase~="FloorActive" then return false,"WrongPhase" end
	if snapshot.objectiveSnapshot.status~="Completed" then return false,"ObjectiveIncomplete" end
	if suspended then return false,"AwaitingReconnect" end
	local standing=0
	for _,p in snapshot.participants do
		if p.connectionState=="Connected" then
			if p.lifeState=="Downed" then return false,"RescueRequired" end
			if p.lifeState=="Alive" then
				standing+=1
				local position=positions[p.userId]
				if not position or not P.InCabin(position) then return false,"CrewOutside" end
			end
		end
	end
	return standing>0,standing>0 and "Ready" or "NoStandingCrew"
end
function P.ValidateMap(model:Model):(boolean,string)
	for _,name in {"ElevatorDock","PlayerRecovery","ObjectiveRecovery","FloorBounds"} do
		local a=Refs.Find(model,name)
		if not a or not a:IsA("BasePart") or not a.Anchored then return false,"MissingAnchor:"..name end
	end
	local dock=Refs.Find(model,"ElevatorDock")::BasePart
	if (dock.Position-Vector3.new(0,20,-8)).Magnitude>.1 then return false,"MisalignedDock" end
	local bounds=Refs.Find(model,"FloorBounds")::BasePart
	for _,name in {"PlayerRecovery","ObjectiveRecovery"} do
		local a=Refs.Find(model,name)::BasePart
		local p=bounds.CFrame:PointToObjectSpace(a.Position)
		local b=bounds.Size/2
		if math.abs(p.X)>=b.X or math.abs(p.Y)>=b.Y or math.abs(p.Z)>=b.Z then return false,"RecoveryOutsideBounds" end
	end
	return true,"Ready"
end
return table.freeze(P)
