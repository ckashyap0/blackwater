--!strict
-- Critically damped movement preserves velocity when equip/stow reverses.
-- The old item remains visible until its display has fully lowered.
local CollectionService=game:GetService("CollectionService")
local Motion={}
function Motion.New():any return {item=nil,amount=0,velocity=0}end
function Motion.Step(state:any,wanted:any,dt:number,frequencyOverride:number?):number
 if state.amount==0 and state.item~=wanted then state.item=wanted end
 local target=state.item==wanted and wanted~=nil and 1 or 0
 local t=math.clamp(dt,0,.1);local frequency=frequencyOverride or 16
 local velocity=state.velocity or 0;local displacement=state.amount-target
 local impulse=(velocity+frequency*displacement)*t;local decay=math.exp(-frequency*t)
 local nextAmount=target+(displacement+impulse)*decay
 state.velocity=(velocity-frequency*impulse)*decay
 state.amount=math.clamp(nextAmount,0,1)
 if state.amount==0 and state.velocity<0 then state.velocity=0 end
 if state.amount==1 and state.velocity>0 then state.velocity=0 end
 if math.abs(state.amount-target)<.0005 and math.abs(state.velocity)<.01 then state.amount=target;state.velocity=0 end
 if state.amount==0 and state.item~=wanted then state.item=wanted end
 return math.clamp(state.amount,0,1)
end

-- Keep authored appearance and grip attachments while removing behavior and
-- physical pieces from client/server hand-display copies.
function Motion.CloneDisplayPart(source:BasePart,name:string):BasePart
 local clone=source:Clone()
 clone.Name=name
 local remove={}
 -- Authored detail parts (DisplayDetail) and the welds that hold them stay: a detailed item looks
 -- the same in the hand as on the shelf. Everything else that could act in the world is stripped.
 local keep={}
 for _,node in clone:GetDescendants() do
  if node:IsA("BasePart") and node:GetAttribute("DisplayDetail") then
   keep[node]=true;node.Transparency=node:GetAttribute("DetailTransparency") or 0
   node.Anchored=false;node.CanCollide=false;node.CanQuery=false;node.CanTouch=false;node.Massless=true
  end
 end
 for _,node in clone:GetDescendants() do
  if node:IsA("WeldConstraint") and ((node.Part0==clone or keep[node.Part0]) and (node.Part1==clone or keep[node.Part1])) then keep[node]=true end
 end
 -- (Nov 3) the printing always comes along switched on: the world copy's labels are turned off while it is
 -- hidden (carried), and a copy made then used to be a blank card in the hand
 for _,node in clone:GetDescendants() do
  if node:IsA("SurfaceGui") then node.Enabled=true
  elseif node:IsA("Decal") and node:GetAttribute("BaseT")~=nil then node.Transparency=node:GetAttribute("BaseT") end
 end
 for _,node in clone:GetDescendants() do
  for _,tag in CollectionService:GetTags(node) do CollectionService:RemoveTag(node,tag) end
  for attribute in node:GetAttributes() do node:SetAttribute(attribute,nil) end
  if keep[node] then continue end
  if node:IsA("BasePart") or node:IsA("JointInstance") or node:IsA("Constraint")
   or node:IsA("LuaSourceContainer") or node:IsA("ProximityPrompt")
   or node:IsA("ClickDetector") or node:IsA("BodyMover") or node:IsA("Tool") then
   table.insert(remove,node)
  end
 end
 for _,node in remove do if node.Parent then node:Destroy() end end
 for _,tag in CollectionService:GetTags(clone) do CollectionService:RemoveTag(clone,tag) end
 for attribute in clone:GetAttributes() do clone:SetAttribute(attribute,nil) end
 return clone
end

-- (Nov 3) Resting frame for a flat item (DropFlat, e.g. the keycard) dropped from `from`: on the first solid
-- surface below, lying face up (its Front face, the printed side, towards the sky), its top edge pointing the
-- way `look` points. Shared by the server (InventoryService) and the dropping client's local fall, so both
-- land on the same spot.
local FACE_UP=CFrame.fromMatrix(Vector3.zero,Vector3.new(-1,0,0),Vector3.new(0,0,-1),Vector3.new(0,-1,0))
function Motion.FlatRest(from:Vector3,look:Vector3,size:Vector3,ignore:{Instance}):CFrame?
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances=ignore;params.RespectCanCollide=true
 local hit=workspace:Raycast(from,Vector3.new(0,-14,0),params)
 if not hit or hit.Normal.Y<.5 then return nil end
 look=Vector3.new(look.X,0,look.Z);if look.Magnitude<.05 then look=Vector3.new(0,0,-1) end;look=look.Unit
 local yaw=math.atan2(-look.X,-look.Z)
 return CFrame.new(hit.Position+Vector3.new(0,size.Z/2+.006,0))*CFrame.Angles(0,yaw,0)*FACE_UP
end

function Motion.GetCarryFrame(part:BasePart,handGripFrame:CFrame,fallbackOffset:CFrame):CFrame
 for _,name in {"CarryGrip","Grip","LeftGripAttachment"} do
  local attachment=part:FindFirstChild(name,true)
  if attachment and attachment:IsA("Attachment") then
   return handGripFrame*attachment.CFrame:Inverse()
  end
 end
 return handGripFrame*fallbackOffset
end

-- One authoritative light state. Brief false sprint pulses must not start a redraw.
function Motion.ResolveLight(state:any,allowed:boolean,wanted:boolean,sprinting:boolean,now:number):boolean
 if sprinting then state.resumeAt=now+.22 end
 return allowed and wanted and not sprinting and now>=(state.resumeAt or 0)
end

-- Small monotonic draw/stow, with no spring momentum or locomotion animation.
function Motion.StepSimple(state:any,wanted:boolean,dt:number):number
 local target=wanted and 1 or 0
 if state.target~=target then
  state.target=target;state.from=state.amount or 0;state.elapsed=0
  state.duration=math.max(.06,(wanted and .28 or .22)*math.abs(target-state.from))
 end
 state.elapsed=math.min(state.duration,(state.elapsed or 0)+math.clamp(dt,0,.1))
 local t=state.elapsed/state.duration;local ease=t*t*(3-2*t)
 state.amount=state.from+(target-state.from)*ease
 return state.amount
end

-- Keep the authored size. Frame larger objects farther away, never shrink the mesh.
Motion.HandSpread=.62 -- shared by the left-hand item and the right-hand flashlight
Motion.DesktopCarrySpread=.48 -- on keyboard-and-mouse screens the carried item sits a little further in
function Motion.CarryPose(size:Vector3,aspect:number,fov:number,amount:number,spread:number?):CFrame
 local tangent=math.tan(math.rad(math.clamp(fov,40,100))*.5)
 local horizontal=tangent*math.clamp(aspect,.45,2.5)
 local depth=math.max(2.1,size.X/(.64*horizontal)+size.Z*.5,size.Y/(.5*tangent)+size.Z*.5)
 -- 0.62 of the half-width to the left: the exact mirror of the flashlight on the right
 return CFrame.new(-depth*horizontal*(spread or Motion.HandSpread),-depth*tangent*.56-(1-amount)*(size.Y+2),-depth)
end

-- First-person view models are drawn as small copies just in front of the lens: a copy scaled by
-- Near and placed at Near x the distance covers exactly the same pixels as the full-size object, but
-- nothing in the world can get between it and the eye, so it never clips into walls or props.
Motion.Near=.1
function Motion.Compress(eye:Vector3,frame:CFrame,factor:number?):CFrame
 local f=factor or Motion.Near
 return CFrame.new(eye+(frame.Position-eye)*f)*frame.Rotation
end

return table.freeze(Motion)