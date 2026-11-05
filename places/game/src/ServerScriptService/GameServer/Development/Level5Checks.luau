--!nonstrict
local Checks={}
function Checks.Run()
 local root=script.Parent.Parent;local Floor=require(root.Floors.Level5Floor);local Slots=require(game.ReplicatedStorage.Game.Shared.Utilities.CabinSlots);local Intro=require(game.ReplicatedStorage.Game.Shared.Utilities.IntroTimeline);local Route=require(game.ReplicatedStorage.Game.Shared.Utilities.RouteGuide);local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
 local results={};local function test(name,fn)local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err)or nil})end
 local function fixture(fn,fail)
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level5:Clone();m.Parent=workspace
  local f=Floor.new(m,5);local defs={};local count=0;local suspended=false
  f:Prepare({RunId='HorrorFixture',IsSuspended=function()return suspended end,RegisterInteraction=function(d)defs[d.interactionId]=d end,RegisterItem=function()end,RegisterSocket=function()end,SetInteractionEnabled=function()end,
   CompleteObjective=function()count+=1;return not fail,'Test'end})
  f:Activate();local ok,err=xpcall(function()fn(f,defs,function()return count end,function(v)suspended=v end)end,debug.traceback);f:Destroy();assert(ok,err)
 end
 local function repair(f,d)assert(d.BW5Isolation.complete());Refs.Get(f.Model,'LinkSocket'):SetAttribute('EHInstalledItem','BW5ReplacementLink');task.wait()end
 test('Cabin slots stay separate for 1, 2 and 4 roster members',function()
  for _,size in {1,2,4}do local roster={101,102,103,104};local frames={}
   for i=1,size do frames[i]=Slots.Frame(CFrame.new(0,20.2,3),roster[i],roster);assert(frames[i].LookVector.Z<-.99)
    for j=1,i-1 do assert((frames[i].Position-frames[j].Position).Magnitude>=5)end
   end
   assert(Slots.Frame(CFrame.new(),104,roster)==Slots.Frame(CFrame.new(),104,roster))
  end
 end)
 test('Solo and every connected member must vote before early opening',function()
  for _,size in {1,2,4}do local p,v={},{};for i=1,size do p[tostring(i)]={connectionState='Connected'}end
   assert(not Intro.AllSkipped(p,v));for i=1,size-1 do v[tostring(i)]=true;assert(not Intro.AllSkipped(p,v))end
   v[tostring(size)]=true;assert(Intro.AllSkipped(p,v));v[tostring(size)]=nil;p[tostring(size)].connectionState='Disconnected';assert(Intro.AllSkipped(p,v)==(size>1))
  end
  assert(not Intro.AllSkipped({},{}));assert(Intro.Cover(0)==1 and Intro.Cover(10)==0 and Intro.Cover(Intro.ImpactAt+.5)==1 and Intro.Cover(Intro.ImpactAt+Intro.BlackHold-.01)==1 and Intro.Cover(Intro.RevealEnd)==0 and Intro.RevealAt-Intro.ImpactAt==Intro.BlackHold)
  assert(Intro.Travel(Intro.ImpactAt)==Intro.Travel(Intro.Duration) and Intro.Speed(Intro.ImpactAt)==0 and Intro.CabinPowered(20) and not Intro.CabinPowered(Intro.ImpactAt+.5))
 end)
 test('Skip tally counts only connected crew and every overlay ends before the doors open',function()
  local p={['1']={connectionState='Connected'},['2']={connectionState='Connected'},['3']={connectionState='Disconnected'}}
  local v,c=Intro.SkipTally(p,{});assert(v==0 and c==2)
  v,c=Intro.SkipTally(p,{['1']=true,['3']=true});assert(v==1 and c==2)
  local last=0;for _,cue in Intro.Captions do last=math.max(last,cue.finish)end
  assert(last<Intro.DoorsAt and Intro.RevealEnd<Intro.DoorsAt and Intro.DoorsAt==Intro.IntroSeconds)
  assert(Intro.Cover(Intro.DoorsAt)==0 and Intro.ImpactAt-Intro.StrainAt<=5.5)
  -- exponential shake: almost nothing halfway, violent at the very end
  assert(Intro.Shake(Intro.StrainAt)==0 and Intro.Shake((Intro.StrainAt+Intro.ImpactAt)/2)<.15 and Intro.Shake(Intro.ImpactAt-.02)>.9)
  -- double blink: open, closed again, open
  assert(Intro.Cover(Intro.RevealAt+2.9)<.4 and Intro.Cover(Intro.RevealAt+3.6)==1 and Intro.Cover(Intro.RevealEnd)==0 and Intro.RevealEnd<Intro.GetUpAt)
  -- the first opening is slow and deliberate: still mostly shut a second in
  assert(Intro.Cover(Intro.RevealAt+1)>.8)
  -- ~7.5 s on the floor, ~3.5 s getting up (long head nod), doors a few seconds after
  local floor=Intro.GetUpAt-Intro.RevealAt;assert(floor>=7 and floor<=8 and Intro.GetUpSeconds>=3 and Intro.GetUpSeconds<=4 and Intro.DoorsAt-Intro.GetUpEnd>=2)
  -- the dialogue and skip panel are gone before the shake starts
  for _,cue in Intro.Captions do assert(cue.afterFault or cue.finish<=Intro.StrainAt-Intro.UiFadeSeconds) end
  assert(Intro.Dazed(Intro.GetUpAt-.1)==1 and Intro.Dazed(Intro.GetUpEnd)>0 and Intro.Dazed(Intro.DoorsAt)==0)
  assert(require(game.ReplicatedStorage.Game.Shared.Config.Level5).IntroSeconds==Intro.IntroSeconds)
 end)
 test('Circuit actions reject premature and repeated input',function()fixture(function(f,d,count)
  assert(not d.BW5SwitchA.complete());assert(d.BW5Isolation.complete());assert(not d.BW5Isolation.complete());assert(not f:TestLift());assert(count()==0)
 end)end)
 test('Installation advances shared task; circuits work in any order; lift test commits once',function()fixture(function(f,d,count)
  repair(f,d);assert(f._stage==3)
  for _,id in {'C','A','B'}do assert(d['BW5Switch'..id].complete());assert(not d['BW5Switch'..id].complete())end
  assert(f._stage==4 and f.Model:GetAttribute('PowerRestored')and count()==0)
  assert(not f:TestLift());assert(not d.BW5TankConfirm.complete());assert(d.BW5TankBleed.complete());assert(d.BW5TankBleed.complete());assert(d.BW5TankConfirm.complete());assert(not d.BW5TankConfirm.complete());assert(d.BW5GateRelease.complete());assert(not d.BW5GateRelease.complete());assert(f:TestLift());assert(f._state=='Completed' and count()==1);assert(not f:TestLift())
 end)end)
 test('Rejected lift completion remains retryable',function()fixture(function(f,d,count)
  repair(f,d);for _,id in {'A','B','C'}do assert(d['BW5Switch'..id].complete())end
  assert(d.BW5TankBleed.complete());assert(d.BW5TankBleed.complete());assert(d.BW5TankConfirm.complete());assert(d.BW5GateRelease.complete());assert(not f:TestLift());assert(f._stage==6 and f._state=='Active' and count()==1)
 end,true)end)
 test('Suspension and cleanup reject late repairs',function()fixture(function(f,d,count,suspend)
  suspend(true);assert(not d.BW5Isolation.complete());suspend(false);assert(d.BW5Isolation.complete());f:Stop();assert(not d.BW5SwitchA.complete())
 end)end)
 test('Task visibility rejects a solid wall even when highlight rendering is inconsistent',function()
  local Visibility=require(game.ReplicatedStorage.Game.Shared.Utilities.ObjectiveVisibility)
  local folder=Instance.new('Folder',workspace);local wall=Instance.new('Part',folder);wall.Anchored=true;wall.Size=Vector3.new(10,10,1);wall.Position=Vector3.new(0,500,5)
  local target=Instance.new('Part',folder);target.Anchored=true;target.Size=Vector3.new(1,1,1);target.Position=Vector3.new(0,500,10)
  local ok,err=pcall(function()assert(not Visibility.Clear(Vector3.new(0,500,0),target,{folder}));wall.Position=Vector3.new(100,500,5);assert(Visibility.Clear(Vector3.new(0,500,0),target,{folder}))end)
  folder:Destroy();assert(ok,err)
 end)
 test('Backup tank requires balance and cannot unlock the gate early',function()fixture(function(f,d)
  assert(not d.BW5TankBleed.complete());repair(f,d);for _,id in {'A','B','C'}do assert(d['BW5Switch'..id].complete())end
  assert(not d.BW5GateRelease.complete());for i=1,10 do assert(d.BW5TankFill.complete())end;assert(f._pressure==6)
  for i=1,3 do assert(d.BW5TankBleed.complete())end;assert(d.BW5TankConfirm.complete());assert(f._stage==5 and f.Model:GetAttribute('TankBalanced'))
 end)end)
 test('Held items stow before switching and settle at both endpoints',function()
  local Motion=require(game.ReplicatedStorage.Game.Shared.Utilities.HeldItemMotion);local state=Motion.New()
  for i=1,20 do Motion.Step(state,'Flashlight',.05)end;assert(state.item=='Flashlight' and state.amount==1)
  Motion.Step(state,'Fuse',.05);assert(state.item=='Flashlight' and state.amount<1)
  for i=1,30 do Motion.Step(state,'Fuse',.05)end;assert(state.item=='Fuse' and state.amount==1)
  for i=1,20 do Motion.Step(state,nil,.05)end;assert(state.item==nil and state.amount==0)
 end)
 test('Every vent opens from both ends and leads somewhere to stand',function()
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level5
  local vents=m:FindFirstChild('Ventilation');assert(vents and #vents:GetChildren()>=4,'expected at least four vent routes')
  for _,route in vents:GetChildren()do
   local id=assert(route:GetAttribute('VentId'));assert(Refs.Get(route,'VentVolume'..id))
   for _,E in {'A','B'}do
    assert(Refs.Get(route,'VentCover'..id..E));assert(Refs.Get(route,'VentMouth'..id..E))
    local f=route:GetAttribute('EntryFrame'..E);assert(typeof(f)=='CFrame','missing EntryFrame'..E..' on '..route.Name)
   end
   -- the two ends face opposite ways along the duct
   assert(route:GetAttribute('EntryFrameA').LookVector:Dot(route:GetAttribute('EntryFrameB').LookVector)<-.99)
  end
 end)
 test('Nothing solid stands in front of a vent opening or inside its mouth',function()
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level5:Clone();m.Parent=workspace
  local ok,err=xpcall(function()
   local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Include;op.FilterDescendantsInstances={m}
   for _,route in m.Ventilation:GetChildren()do
    for _,E in {'A','B'}do
     local f=route:GetAttribute('EntryFrame'..E);local inward=f.LookVector;local lip=f.Position-inward*1.9
     local floorY=lip.Y-6.5
     -- the climb-in corridor in front of the opening (floor to just under the duct)
     local c=CFrame.lookAt(Vector3.new(lip.X,floorY+3.2,lip.Z)-inward*1.8,Vector3.new(lip.X,floorY+3.2,lip.Z)-inward*5)
     for _,p in workspace:GetPartBoundsInBox(c,Vector3.new(3.4,5.6,3.2),op)do
      assert(not p.CanCollide or p:IsDescendantOf(route) or p.Size.Y>8 or p.Position.Y<floorY+.4,'Vent '..route.Name..E..' approach blocked by '..p:GetFullName())
     end
    end
   end
  end,debug.traceback);m:Destroy();assert(ok,err)
 end)
 test('Route follows authored turns and refuses inaccessible destination',function()
  local a,b,c=Vector3.new(0,0,0),Vector3.new(0,0,10),Vector3.new(10,0,10)
  local nodes={A={position=a,links={'B'}},B={position=b,links={'A','C'}},C={position=c,links={'B'}}}
  local visible=function(x,y)return x.X==y.X or x.Z==y.Z end
  assert(Route.Next(nodes,a,c,visible)==b);nodes.B.links={'A'};assert(Route.Next(nodes,a,c,visible)==nil)
 end)
 test('Large loop has grounded recovery, accessible graph and gated return',function()
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level5:Clone();m.Parent=workspace
  local ok,err=xpcall(function()
   assert(require(root.Data.ElevatorPolicy).ValidateMap(m));local bounds=Refs.Get(m,'FloorBounds');assert(bounds.Size.X>=250 and bounds.Size.Z>=220)
   local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include;ray.FilterDescendantsInstances={m};ray.RespectCanCollide=true
   local nav=Refs.Get(m,'Navigation');local gate=Refs.Get(m,'ReturnGate')
   for _,n in nav:GetChildren()do
    local ground=workspace:Raycast(n.Position,Vector3.new(0,-6,0),ray);assert(ground and ground.Normal.Y>.5,'Ungrounded node '..n.Name)
    for _,id in string.split(n:GetAttribute('Links'),',')do local t=assert(nav:FindFirstChild(id));local hit=workspace:Raycast(n.Position,t.Position-n.Position,ray)
     assert(not hit or hit.Instance==gate,'Blocked navigation '..n.Name..' to '..id..(hit and ' by '..hit.Instance.Name or ''))
    end
   end
  end,debug.traceback);m:Destroy();assert(ok,err)
 end)
 return {results=results}
end
return table.freeze(Checks)
