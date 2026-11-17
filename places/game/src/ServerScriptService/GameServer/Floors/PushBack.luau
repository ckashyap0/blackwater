--!nonstrict
-- R43: drive the crew back to a checkpoint (a failed set piece, e.g. the flood reached the deck). Nobody is hurt.
-- Every client fades to black from EHPushBackAt (SetPieceController), the server moves each character to the
-- checkpoint while the screen is black, and the picture comes back. Characters are set down on the ground
-- found under each slot (moving a character by a part's facing alone can drop it through the floor).
local PushBack={}
PushBack.FadeIn=.45   -- seconds to black
PushBack.Hold=1.1     -- seconds held black (the move happens in the middle)

local function ground(pos,ignore)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=ignore
	params.RespectCanCollide=true
	local hit=workspace:Raycast(pos+Vector3.new(0,6,0),Vector3.new(0,-20,0),params)
	return hit and hit.Position or nil
end

-- checkpoint: a part (its CFrame is where the crew stands, LookVector = the way they face)
function PushBack.Run(players,checkpoint,options)
	options=options or {}
	local now=workspace:GetServerTimeNow()
	for _,p in players do p:SetAttribute('EHPushBackAt',now) end
	task.delay(PushBack.FadeIn+PushBack.Hold*.4,function()
		local ignore={}
		for _,p in players do if p.Character then table.insert(ignore,p.Character) end end
		for i,p in players do
			local c=p.Character;local root=c and c:FindFirstChild('HumanoidRootPart')
			if root and checkpoint and checkpoint.Parent then
				local side=i-(#players+1)/2 -- (the crew stands centred on the checkpoint, 3 studs apart)
				local spot=checkpoint.CFrame*CFrame.new(side*3,0,0)
				local g=ground(spot.Position,ignore)
				if g then
					c:PivotTo(CFrame.lookAt(g+Vector3.new(0,3.1,0),g+Vector3.new(0,3.1,0)+spot.LookVector*Vector3.new(1,0,1)))
					root.AssemblyLinearVelocity=Vector3.zero
					c:SetAttribute('EHFacing',spot.LookVector)
				end
			end
		end
		if options.onMoved then pcall(options.onMoved) end
	end)
	return now
end

return PushBack
