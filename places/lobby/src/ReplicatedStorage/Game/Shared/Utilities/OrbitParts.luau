--!nonstrict
-- Moving pieces on flashlight models (same file in the Lobby and Game places). Any BasePart with an
-- Orbit attribute (rad/s) turns about:
--   OrbitAxis   (Vector3 in the model's own space; default Z = the flashlight's long axis)
--   OrbitCenter (Vector3 in the model's own space; default the model's pivot)
-- Collect once (after any ScaleTo), then Step every frame; the model itself can move freely in between.
-- Used by the shop cards, the locker preview and the flashlight in your hand.
local O={}
function O.Collect(root)
	local list={}
	for _,p in root:GetDescendants() do
		local speed=p:IsA("BasePart") and p:GetAttribute("Orbit")
		local owner=speed and p:FindFirstAncestorWhichIsA("Model")
		if owner then
			local pivot=owner:GetPivot()
			local c,axis=p:GetAttribute("OrbitCenter"),p:GetAttribute("OrbitAxis")
			table.insert(list,{part=p,owner=owner,rel=pivot:ToObjectSpace(p.CFrame),speed=speed,
				center=(typeof(c)=="Vector3" and c or Vector3.zero)*owner:GetScale(),
				axis=(typeof(axis)=="Vector3" and axis.Magnitude>0) and axis.Unit or Vector3.zAxis})
		end
	end
	return list
end
function O.Step(list,t)
	for _,o in list do
		if o.part.Parent then
			o.part.CFrame=o.owner:GetPivot()*CFrame.new(o.center)*CFrame.fromAxisAngle(o.axis,t*o.speed)*CFrame.new(-o.center)*o.rel
		end
	end
end
return O
