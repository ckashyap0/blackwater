-- Clutter scatter (edit-time tool, Nov 11): drops small clutter into the open middle of rooms and halls.
return function(level,start,folder,opt)
 local flood=loadstring(game.ServerStorage.ArtTools.WalkFlood.Source)()
 local A=workspace.BlackwaterAuthoring
 local kit=game.ServerStorage.BW_ModelKitF4
 local r=flood(level,start,{})
 local step=2 local set={}
 local function key(x,z) return math.floor(x/step+.5)..','..math.floor(z/step+.5) end
 for _,p in r.cells do set[key(p.X,p.Z)]=p end
 local open={}
 for _,p in r.cells do local ok=true for dx=-4,4,2 do for dz=-4,4,2 do if not set[key(p.X+dx,p.Z+dz)] then ok=false end end end if ok then open[#open+1]=p end end
 local rng=Random.new(opt.seed or 5)
 for i=#open,2,-1 do local j=rng:NextInteger(1,i) open[i],open[j]=open[j],open[i] end
 local inter={} for _,f in {level:FindFirstChild('Interactables'),level:FindFirstChild('Anchors')} do if f then for _,p in f:GetDescendants() do if p:IsA('BasePart') then inter[#inter+1]=p.Position end end end end
 local picks={}
 for _,p in open do local ok=true
  for _,q in picks do if (q-p).Magnitude<(opt.spacing or 16) then ok=false break end end
  if ok then for _,q in inter do if (Vector3.new(q.X,p.Y,q.Z)-p).Magnitude<6 then ok=false break end end end
  if ok and (p-start).Magnitude<10 then ok=false end
  if ok then picks[#picks+1]=p end
 end
 -- make hidden parts visible to queries while we test
 local saved={} for _,p in level:GetDescendants() do if p:IsA('BasePart') and not p.CanQuery and p.Transparency<1 then saved[p]=true p.CanQuery=true end end
 local function corners(m) local t={} for _,p in m:GetDescendants() do if p:IsA('BasePart') then local c=p.CFrame local s=p.Size/2 for _,a in {-1,1} do for _,b in {-1,1} do for _,cc in {-1,1} do t[#t+1]=c:PointToWorldSpace(Vector3.new(a*s.X,b*s.Y,cc*s.Z)) end end end end end return t end
 local function clash(m)
  local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Exclude op.FilterDescendantsInstances={m,level.Architecture,level:FindFirstChild('Anchors')}
  for _,p in m:GetDescendants() do if p:IsA('BasePart') then for _,h in workspace:GetPartBoundsInBox(p.CFrame,p.Size*.9,op) do if h.Transparency<1 then return h end end end end
 end
 local function find(name) return kit:FindFirstChild(name) or A.Level5.PropCollections:FindFirstChild(name,true) end
 local function settle(m,y) local mn=1e9 for _,w in corners(m) do mn=math.min(mn,w.Y) end m:PivotTo(m:GetPivot()+Vector3.new(0,y-mn+.01,0)) end
 local function drop(name,p,tipped,collide)
  local s=find(name) if not s then return end
  local m=s:Clone() m.Name='Clutter_'..name
  local cf,sz=m:GetBoundingBox() local rel=cf:ToObjectSpace(m:GetPivot())
  local rot=CFrame.Angles(0,rng:NextNumber(0,math.pi*2),0)*(tipped and CFrame.Angles(math.pi/2,0,rng:NextNumber(-.2,.2)) or CFrame.identity)
  m:PivotTo(CFrame.new(p+Vector3.new(0,3,0))*rot*rel) m.Parent=folder
  settle(m,p.Y)
  for _,d in m:GetDescendants() do if d:IsA('BasePart') then d.Anchored=true d.CanCollide=collide or false d.CanTouch=false elseif d:IsA('LuaSourceContainer') or d:IsA('ProximityPrompt') then d:Destroy() end end
  if clash(m) then m:Destroy() return end
  return m
 end
 local ceil=opt.ceil
 local function wires(p)
  local s=A.Level5.PropCollections:FindFirstChild('DanglingWires',true) if not s then return end
  local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances={} rp.RespectCanCollide=false
  local up=workspace:Spherecast(p+Vector3.new(0,7,0),.9,Vector3.new(0,ceil-p.Y-8.2,0),rp)
  if up then return end
  local m=s:Clone() m.Name='Clutter_DanglingWires'
  for _,d in m:GetDescendants() do if d:IsA('BasePart') then d.Anchored=true d.CanCollide=false d.CanTouch=false end end
  local cf,sz=m:GetBoundingBox() local rel=cf:ToObjectSpace(m:GetPivot())
  m:PivotTo(CFrame.new(p.X,ceil-sz.Y/2,p.Z)*CFrame.Angles(0,rng:NextNumber(0,6.28),0)*rel) m.Parent=folder
  if clash(m) then m:Destroy() return end
  return m
 end
 local kinds=opt.kinds
 local count={}
 for i,p in picks do
  local k=kinds[(i-1)%#kinds+1]
  local m
  if k=='wires' then m=wires(p) if not m then k='paper' end end
  if k=='paper' then m=drop('F4PaperSheets3',p) if m then drop('F4PaperBalls3',p+Vector3.new(rng:NextNumber(-2,2),0,rng:NextNumber(-2,2))) end
  elseif k=='chair' then m=drop(opt.chair or 'F4StackChair',p,true,true)
  elseif k=='cone' then m=drop('HazardCone',p,true)
  elseif k=='cans' then m=drop('F4Cans',p) if m then drop('F4Bottle',p+Vector3.new(1.6,0,.8),true) end
  elseif k=='bottle' then m=drop('F4Bottle',p,true) drop('F4PaperBalls3',p+Vector3.new(-1.2,0,1))
  elseif k=='boxes' then m=drop('F4ArchiveBoxes',p,false,true) end
  if m then count[k]=(count[k] or 0)+1 end
 end
 for p in saved do p.CanQuery=false end
 local r2=flood(level,start,{})
 local t={} for k,v in count do t[#t+1]=k..'='..v end
 return string.format('open %d picks %d placed: %s | reach %d -> %d',#open,#picks,table.concat(t,' '),r.count,r2.count)
end
