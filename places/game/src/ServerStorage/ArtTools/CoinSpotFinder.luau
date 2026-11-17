--!nonstrict
-- (Nov 16) EDIT-TIME TOOL: finds hidden spots for coin stashes on an authored floor and writes them as
-- invisible marker parts (Level<n>.CoinSpots.CoinSpot01..). Run once per floor from the command bar:
--   require(game.ServerStorage.ArtTools.CoinSpotFinder).Run(workspace.BlackwaterAuthoring.Level5,30)
-- A spot is: the top of a floor / shelf / low surface, free of anything solid, boxed in on most sides
-- (corners, behind crates, under desks and stairs), away from the lift and the task machines, and
-- reachable on foot from the lift (PathfindingService). The markers can be moved or deleted by hand.
local PS=game:GetService('PathfindingService')
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local M={}
local DIRS={} for i=0,7 do local a=i/8*math.pi*2 DIRS[i+1]=Vector3.new(math.cos(a),0,math.sin(a)) end
function M.Run(model,want,opts)
 opts=opts or {}
 local step=opts.step or 2
 local bounds=Refs.Get(model,'FloorBounds');local dock=Refs.Get(model,'ElevatorDock')
 local floorY=dock.Position.Y
 local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={model};rp.RespectCanCollide=true
 local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Include;op.FilterDescendantsInstances={model}
 -- keep-outs: the lift, every task control, vents, spills
 local avoid={}
 for _,d in model:GetDescendants()do
  if d:IsA('BasePart') then
   local inter=d:GetAttribute('Ref') and d:IsDescendantOf(model:FindFirstChild('Interactables') or model)
   if (d:GetAttribute('Ref') and (d.Parent and (d:FindFirstAncestor('Interactables')~=nil))) or d:GetAttribute('SlipHazard') or d.Name:find('^VentVolume') or d.Name:find('^VentMouth') then table.insert(avoid,d) end
  end
 end
 local function nearAvoid(p)
  if (p-dock.Position).Magnitude<16 then return true end
  for _,a in avoid do local l=a.CFrame:PointToObjectSpace(p);local h=a.Size/2+Vector3.new(3,3,3);if math.abs(l.X)<h.X and math.abs(l.Y)<h.Y and math.abs(l.Z)<h.Z then return true end end
  return false
 end
 local function solid(r)return r and r.Instance.Transparency<.9 end
 local cands={}
 local c=bounds.CFrame;local s=bounds.Size
 local top=floorY+7
 for x=-s.X/2,s.X/2,step do for z=-s.Z/2,s.Z/2,step do
  local w=c*Vector3.new(x,0,z);local o=Vector3.new(w.X,top,w.Z)
  local r=workspace:Raycast(o,Vector3.new(0,-9,0),rp)
  if r and r.Normal.Y>.9 and solid(r) then
   local P=r.Position;local rise=P.Y-floorY
   if rise>-1 and rise<4.2 then
    local inBox=#workspace:GetPartBoundsInBox(CFrame.new(P+Vector3.new(0,.42,0)),Vector3.new(1.4,.7,1.4),op)==0
    if inBox and not workspace:Raycast(P+Vector3.new(0,.1,0),Vector3.new(0,1.3,0),rp) then
     local k,openDir,openLen=0,nil,0
     for _,d in DIRS do local h=workspace:Raycast(P+Vector3.new(0,.4,0),d*3.2,rp);if h and solid(h) then k+=1 else local far=workspace:Raycast(P+Vector3.new(0,.4,0),d*8,rp);local len=far and far.Distance or 8;if len>openLen then openLen=len;openDir=d end end end
     local up=workspace:Raycast(P+Vector3.new(0,1.4,0),Vector3.new(0,5.5,0),rp)
     local covered=up and solid(up) and (up.Position.Y-P.Y)<6 and not up.Instance.Name:lower():find('ceil') and (up.Position.Y-floorY)<6.5
     if k>=3 and openDir and not nearAvoid(P) then
      table.insert(cands,{p=P,k=k,cov=covered,rise=rise,open=openDir,score=k+(covered and 3 or 0)+(rise>1.2 and 1 or 0)+math.random()*.5})
     end
    end
   end
  end
 end end
 table.sort(cands,function(a,b)return a.score>b.score end)
 local start=Refs.Get(model,'PlayerRecovery').Position
 local sr=workspace:Raycast(start+Vector3.new(0,2,0),Vector3.new(0,-10,0),rp);start=(sr and sr.Position or start)+Vector3.new(0,1,0)
 local function reachable(cd)
  for _,dist in {3,2,4.5} do
   local stand=cd.p+cd.open*dist
   local g=workspace:Raycast(stand+Vector3.new(0,3,0),Vector3.new(0,-6,0),rp)
   if g and g.Normal.Y>.7 then
    local eye=g.Position+Vector3.new(0,1.6,0)
    local los=workspace:Raycast(eye,(cd.p+Vector3.new(0,.3,0))-eye,rp)
    if not los or (los.Position-(cd.p+Vector3.new(0,.3,0))).Magnitude<.6 then
     local path=PS:CreatePath({AgentRadius=1,AgentHeight=4.5,AgentCanJump=true,WaypointSpacing=10})
     local ok=pcall(function()path:ComputeAsync(start,g.Position+Vector3.new(0,1,0))end)
     if ok and path.Status==Enum.PathStatus.Success then return true end
    end
   end
  end
  return false
 end
 local picked={}
 for _,sep in {opts.sep or 14,10,7} do
  for _,cd in cands do
   if #picked>=want then break end
   if not cd.used then
    local fine=true;for _,q in picked do if (q.p-cd.p).Magnitude<sep then fine=false;break end end
    if fine and reachable(cd) then cd.used=true;table.insert(picked,cd) end
   end
  end
  if #picked>=want then break end
 end
 local folder=model:FindFirstChild('CoinSpots');if folder then folder:Destroy() end
 folder=Instance.new('Folder');folder.Name='CoinSpots'
 folder:SetAttribute('Note','(Nov 16) hidden coin stash spots. Each run CoinStashes picks 4-5 of these at random. Move, add or delete markers freely (any Part named CoinSpot.. in here counts; it sits on the surface, the stash faces its -Z).')
 for i,cd in picked do
  local p=Instance.new('Part');p.Name=string.format('CoinSpot%02d',i);p.Size=Vector3.new(.4,.1,.4);p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Transparency=1
  p.CFrame=CFrame.lookAt(cd.p+Vector3.new(0,.05,0),cd.p+Vector3.new(0,.05,0)+cd.open)*CFrame.Angles(0,math.rad(math.random(-35,35)),0)
  p:SetAttribute('CoinSpot',true);p:SetAttribute('Enclosed',cd.k);p:SetAttribute('Covered',cd.cov==true)
  p.Parent=folder
 end
 folder.Parent=model
 return #picked,#cands
end
return M
