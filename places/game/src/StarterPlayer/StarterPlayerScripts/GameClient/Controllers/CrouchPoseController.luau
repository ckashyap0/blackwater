--!nonstrict
-- Crouch pose for EVERY character, driven by the server-replicated EHCrouching player attribute
-- (the server confirms BeginCrouch/EndCrouch and broadcasts the state to all clients).
--  * Local player: Humanoid.HipHeight lowers with the camera's crouch spring. The character is
--    owner-simulated, so the lowered body replicates physically to every other client.
--  * All characters (local and remote): the legs fold and the torso leans through the rig's
--    joint Transforms (AnimationConstraint or Motor6D), applied after the Animator each frame,
--    so walking animations keep playing on top of the crouch and every client shows the same pose.
--  * Remote characters fold their legs by how far their root ACTUALLY sits below standing height
--    (measured from the floor under them), not by the crouch attribute alone. The lowered root
--    replicates physically from the owner on every platform (PC, mobile, console), so the fold
--    always matches it: a friend's character can never sink into the floor, even if the attribute
--    arrives late, is missed, or the avatar has different body proportions. Joints are re-resolved
--    until the whole rig has streamed in.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Crouch=require(Shared.Utilities.CrouchState)
local Crawl=require(Shared.Utilities.CrawlState)
local DROP=1.1          -- studs the hips lower at full crouch
local SPRING=13         -- matches the camera crouch spring
local Controller={};Controller.__index=Controller
function Controller.new(player)return setmetatable({Name='CrouchPoseController',Dependencies={'CameraController'},_player=player,_state={}},Controller)end
function Controller:Init()self._scope=Scope.new()end
local JOINTS={LeftHip='LeftUpperLeg',RightHip='RightUpperLeg',LeftKnee='LeftLowerLeg',RightKnee='RightLowerLeg',LeftAnkle='LeftFoot',RightAnkle='RightFoot',Waist='UpperTorso'}
local function rig(character)
 local j={}
 for name,partName in JOINTS do
  local part=character:FindFirstChild(partName)
  local joint=part and (part:FindFirstChild(name))
  if joint and (joint:IsA('Motor6D') or joint:IsA('AnimationConstraint')) then j[name]=joint end
 end
 return j
end
local floorParams=RaycastParams.new();floorParams.FilterType=Enum.RaycastFilterType.Exclude;floorParams.RespectCanCollide=true
-- How crouched a remote character really is: drop of its replicated root below standing height.
local function measured(c,root,base)
 local list={};for _,p in Players:GetPlayers()do if p.Character then table.insert(list,p.Character)end end
 floorParams.FilterDescendantsInstances=list
 local hit=workspace:Raycast(root.Position,Vector3.new(0,-(base+root.Size.Y/2+3),0),floorParams)
 if not hit then return nil end
 local standing=hit.Position.Y+base+root.Size.Y/2
 return math.clamp((standing-root.Position.Y)/DROP,0,1)
end
local function springStep(s,target,dt)
 local x,v=s.x or 0,s.v or 0
 local steps=math.max(1,math.ceil(dt*120));local h=dt/steps
 for _=1,steps do v+=(SPRING*SPRING*(target-x)-2*SPRING*v)*h;x+=v*h end
 if math.abs(target-x)<1e-4 and math.abs(v)<1e-3 then x,v=target,0 end
 s.x,s.v=x,v;return math.clamp(x,0,1)
end
function Controller:_Pose(player,dt)
 local c=player.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if not h or h.Health<=0 then self._state[player]=nil;return end
 local s=self._state[player]
 if not s or s.character~=c then
  s={character=c,joints=rig(c),base=h:GetAttribute('EHStandingHipHeight') or h.HipHeight,x=0,v=0,resolved=os.clock()}
  if player==self._player then h:SetAttribute('EHStandingHipHeight',s.base) end
  self._state[player]=s
 end
 -- remote rigs stream in part by part: keep re-resolving until all seven joints are present
 local count=0;for _ in s.joints do count+=1 end
 if count<7 and os.clock()-s.resolved>.5 then s.joints=rig(c);s.resolved=os.clock()end
 local a
 if player==self._player then a=Crouch.amount or 0 -- the camera's spring: body and eye move together
 else
  local root=c:FindFirstChild('HumanoidRootPart')
  local m=root and measured(c,root,s.base)
  local target=m or (player:GetAttribute('EHCrouching')==true and 1 or 0)
  if m and m<.08 then target=0 end -- ignore replication jitter while standing
  -- the measured drop IS the replicated body position, so it is applied directly (no lag that
  -- could let the hips drop before the knees bend); the attribute fallback is spring-smoothed
  if m then s.x,s.v=target,0;a=target else a=springStep(s,target,dt)end
 end
 -- lying down (a duct, or crawling with Left Ctrl) the HazardController owns the hip height
 -- and the whole pose, so don't fight it
 local lying=player:GetAttribute('EHInVent')~=nil or (player==self._player and Crawl.state=='Vent')
 if player==self._player and not lying then
  local target=s.base-DROP*a
  if math.abs(h.HipHeight-target)>1e-3 then h.HipHeight=target end
 end
 if a<.001 then return end
 -- lying prone in a duct (and climbing in/out of one) the HazardController poses the whole body:
 -- no crouch fold on top of it, or the knees and feet kick up into the duct roof
 if lying then return end
 -- Leg fold that matches the hip drop: thighs swing forward by t, shins back by 2t, feet stay flat.
 local legLength=math.max(s.base,1.5)
 local t=math.acos(math.clamp((legLength-DROP*a)/legLength,0,1))
 local j=s.joints
 local function apply(joint,cf)if joint and joint.Parent then local ok=pcall(function()joint.Transform=joint.Transform*cf end)end end
 apply(j.LeftHip,CFrame.Angles(t,0,0));apply(j.RightHip,CFrame.Angles(t,0,0))
 apply(j.LeftKnee,CFrame.Angles(-2*t,0,0));apply(j.RightKnee,CFrame.Angles(-2*t,0,0))
 apply(j.LeftAnkle,CFrame.Angles(t,0,0));apply(j.RightAnkle,CFrame.Angles(t,0,0))
 apply(j.Waist,CFrame.Angles(math.rad(-14)*a,0,0))
end
function Controller:Start()
 -- PreSimulation runs after the Animator has written this frame's joint transforms.
 self._scope:Add(RunService.PreSimulation:Connect(function(dt)
  dt=math.clamp(dt,0,.1)
  for _,p in Players:GetPlayers()do local ok,err=pcall(self._Pose,self,p,dt);if not ok then self._state[p]=nil end end
  for p in self._state do if p.Parent~=Players then self._state[p]=nil end end
 end))
end
function Controller:Destroy()
 local s=self._state[self._player];local h=s and s.character and s.character:FindFirstChildOfClass('Humanoid')
 if h then h.HipHeight=s.base end
 if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
