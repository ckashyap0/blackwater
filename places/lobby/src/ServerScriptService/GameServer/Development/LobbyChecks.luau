--!nonstrict
local Checks={}
function Checks.Run()
	local results={}
	local function check(name,fn)
		local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err)or nil})
	end
	local B=require(game.ServerStorage.GameAssets.EnvironmentBuilder)
	check("Friend admission rejects a replaced party with the same revision",function()
		local m=require(script.Parent.Parent.Data.PartyModel).new()
		assert(m:Join(101,1,true));local old=m:Get(1);assert(m:Leave(101));assert(m:Join(102,1,true))
		local ok,reason=m:Join(103,1,true,old.revision,old.partyId)
		assert(not ok and reason=="PartyChanged" and m:ForUser(103)==nil)
	end)
	local env=B.Lobby(workspace);env.Name="LobbyRegression"
	local character=Instance.new("Model");character.Name="ExitTestCharacter";character.Parent=workspace
	local root=Instance.new("Part");root.Name="HumanoidRootPart";root.Anchored=true;root.Parent=character;character.PrimaryPart=root
	local p={UserId=-777,Character=character}
	local party=require(script.Parent.Parent.Services.PartyService).new()
	party:Init({EnvironmentService={Role="Lobby",Model=env},ProfileService={},SessionService={}})
	check("Exit moves players out of all four bays and clears membership",function()
		for i=1,4 do
			local bay=env["Bay"..i];character:PivotTo(bay.BoardingZone.CFrame)
			assert(party._model:Join(p.UserId,i,true))
			assert(party:_ExitBay(p));assert(party._model:ForUser(p.UserId)==nil)
			assert((root.Position-bay.ExitLanding.Position).Magnitude<.01,"Exit did not move character")
			assert(not party:_Inside(p,i),"Exit still inside boarding trigger")
			assert(party._blocked[p]==i,"Exit must suppress pending admission")
			local gate=workspace.LobbyBarriers and workspace.LobbyBarriers:FindFirstChild("Bay"..i)
			assert(gate and gate.CanCollide and gate.CollisionGroup=="EHPartyBarrier","Missing editable lobby barrier")
		end
	end)
    check("Exiting a shared bay dismisses the entire crew",function()
        assert(party._model:Join(p.UserId,2,true));assert(party._model:Join(-778,2,true))
        assert(party:_ExitBay(p))
        assert(party._model:Get(2)==nil and party._model:ForUser(-778)==nil)
        assert(party._blocked[p]==2)
        assert((root.Position-env.Bay2.ExitLanding.Position).Magnitude<.01)
    end)
    check("Party collision group holds all joined crew behind the barrier",function()
        local physics=game:GetService("PhysicsService")
        assert(physics:CollisionGroupsAreCollidable("EHParty","EHPartyBarrier"))
        assert(not physics:CollisionGroupsAreCollidable("Default","EHPartyBarrier"))
        party:_SetCharacterCollision(p,true);assert(root.CollisionGroup=="EHParty")
        party:_SetCharacterCollision(p,false);assert(root.CollisionGroup=="Default")
    end)
    check("Known place IDs win over the local Studio default",function()
        local config=require(game.ReplicatedStorage.Game.Shared.Config.PlaceConfig)
        assert(config.Resolve(config.GamePlaceId,true,nil)=="Game")
        assert(config.Resolve(config.LobbyPlaceId,true,nil)=="Lobby")
    end)
    check("Denied admission stays blocked across the full boarding trigger",function()
        local zone=env.Bay1.BoardingZone
        character:PivotTo(zone.CFrame*CFrame.new(0,0,2.5));party._blocked[p]=1
        assert(party:_InBoardingZone(p,1)and not party:_Inside(p,1))
        party:_RefreshAdmissionBlock(p);assert(party._blocked[p]==1)
        character:PivotTo(zone.CFrame*CFrame.new(0,0,5))
        party:_RefreshAdmissionBlock(p);assert(party._blocked[p]==nil)
    end)
    check("Ready containment recovers a character below the cabin",function()
        local zone=env.Bay1.BoardingZone
        character:PivotTo(zone.CFrame*CFrame.new(0,-30,0));assert(not party:_Inside(p,1))
        party:_Contain(p,1);assert(party:_Inside(p,1))
    end)
	check("Exit cannot cancel a launching roster",function()
		local crew={p.UserId,-778,-779,-780}
		for _,id in crew do assert(party._model:Join(id,1,true)) end
		for _,id in crew do assert(party._model:Ready(id,true)) end
		assert(party._model:Launch(p.UserId))
		character:PivotTo(env.Bay1.BoardingZone.CFrame);local before=root.Position
		local ok,reason=party:_ExitBay(p);assert(not ok and reason=="Launching")
		assert(root.Position==before and party._model:ForUser(p.UserId)==1)
	end)
	check("Boarding occupancy signs remain clear from the approach",function()
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={env}
		for i=1,4 do
			local bay=env['Bay'..i];local sign=bay.Occupancy
			assert(sign.Lettering.OccupancyText:IsA('TextLabel'))
			local origin=Vector3.new(sign.Position.X,25,0)
			local hit=workspace:Raycast(origin,sign.Position-origin,params)
			assert(not hit or hit.Instance==sign,'Obstructed occupancy sign')
		end
	end)
	party:Destroy();character:Destroy();env:Destroy()
	return {results=results}
end
return table.freeze(Checks)

