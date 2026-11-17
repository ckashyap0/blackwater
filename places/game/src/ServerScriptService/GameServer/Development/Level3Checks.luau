--!nonstrict
-- Development checks for Level 3 (Filtration). Studio only; run with Workspace.RunDevChecks = true.
-- They use a copy of the Level 3 template and a stand-in floor context, never the live run.
local Checks={}
function Checks.Run()
 local root=script.Parent.Parent
 local Floor=require(root.Floors.Level3Floor)
 local Config=require(game.ReplicatedStorage.Game.Shared.Config.Level3)
 local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
 local Contract=require(game.ReplicatedStorage.Game.Shared.Contracts.FloorContract)
 local CS=game:GetService('CollectionService')
 local results={};local function test(name,fn)local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err)or nil})end
 local function fixture(fn)
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level3:Clone();m.Parent=workspace
  local f=Floor.new(m,3);local defs={};local count=0;local enabled={}
  f:Prepare({RunId='HorrorFixture',IsSuspended=function()return false end,RegisterInteraction=function(d)defs[d.interactionId]=d end,
   RegisterItem=function()end,RegisterSocket=function()end,SetInteractionEnabled=function(id,on)enabled[id]=on end,SetStatus=function()end,
   GetPlayers=function()return {}end,DrainStamina=function()return true end,SetSpeedModifier=function()return true end,
   CompleteObjective=function()count+=1;return true,'Test'end})
  f:Activate()
  local ok,err=xpcall(function()fn(f,defs,m,function()return count end,enabled)end,debug.traceback);f:Destroy();assert(ok,err)
 end
 local function oneSentence(text)
  local _,n=string.gsub(text,'[%.%?!]%s','');local last=string.sub(text,-1)
  return #text<=90 and n==0 and (last=='.' or last=='?' or last=='!')
 end
 test('Level 3 template has its anchors and every part the floor looks up',function()
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level3
  Contract.ValidateTemplate(m)
  local names={'FumeZone','FanStarter','DosingSwitch1','DosingSwitch2','HallEntryZone','HeaderConsole','HeaderZone','ChamberMonitor','BypassKey','ChamberHatch','ChamberLadder',
   'ChamberZone','LadderTop','LadderBottom','WheelStand','BypassWheel','ChamberLamp','BoothBulb','BoothWindow','Intercom_Chamber','Intercom_Header','GalleryKnock','HB3','HB5'}
  for i=1,6 do table.insert(names,'FilterConsole'..i);table.insert(names,'BedWater'..i) end
  for _,n in names do assert(Refs.Find(m,n),'Missing Ref: '..n) end
  local bounds=Refs.Find(m,'FloorBounds');local lo=bounds.Position.Y-bounds.Size.Y/2
  assert(Refs.Find(m,'LadderBottom').Position.Y>lo,'the bypass chamber is below FloorBounds')
 end)
 test('Every Marty, hint and intercom line is one sentence of 90 characters or less',function()
  for group,list in {Marty=Config.Marty,Hints=Config.Hints,Radio=Config.Radio} do
   for key,entry in list do
    local text=type(entry)=='table' and entry.text or entry
    assert(oneSentence(text),group..'.'..key..': '..text)
   end
  end
 end)
 test('Every reach has a path, one film part per gap and a rest inside its reach',function()
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level3;local n=0
  for _,f in CS:GetTagged('BlackWaterReach')do
   if f:IsDescendantOf(m) then
    n+=1
    local pts=0;for _ in string.gmatch(f:GetAttribute('Points') or '','[^;]+')do pts+=1 end
    local segs=0;for _,s in f:GetChildren()do if s:IsA('BasePart') then segs+=1 end end
    assert(pts>=3 and segs==pts-1,f.Name..': '..pts..' points, '..segs..' film parts')
    assert((f:GetAttribute('RestLength') or 0)<=(f:GetAttribute('MaxLength') or 0),f.Name..': rest beyond its reach')
   end
  end
  assert(n==8,'expected 8 reaches, found '..n)
 end)
 test('Marty never stands within 8 studs of black water',function()
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level3
  for _,mk in m.MartyMarkers:GetChildren()do
   local stand=mk:FindFirstChild('MartyStand')
   if stand then
    for _,f in CS:GetTagged('BlackWaterReach')do
     if f:IsDescendantOf(m) then
      for _,s in f:GetChildren()do if s:IsA('BasePart') then
       local d=stand.Position-s.Position
       assert(Vector3.new(d.X,0,d.Z).Magnitude>=8 or math.abs(d.Y)>9,mk.Name..' is too close to '..f.Name)
      end end
     end
    end
   end
  end
 end)
 test('Fan, pumps and six inlets lead to the bypass stage without finishing the floor',function()
  fixture(function(f,defs,m,count)
   assert(m:GetAttribute('Stage')=='Fumes' and m:GetAttribute('FumesActive')==true)
   assert(not defs.BW3Pump1.canUse(),'pumps before the fan')
   assert(defs.BW3Fan.complete());assert(m:GetAttribute('Stage')=='Dosing' and m:GetAttribute('ExtractFanAt'))
   assert(defs.BW3Pump1.complete());assert(not defs.BW3Inlet1.canUse(),'inlets before both pumps')
   assert(defs.BW3Pump2.complete());assert(m:GetAttribute('Stage')=='Inlets')
   for i=1,6 do assert(defs['BW3Inlet'..i].complete());assert(not defs['BW3Inlet'..i].canUse(),'an inlet closes once') end
   assert(m:GetAttribute('Stage')=='Bypass' and m:GetAttribute('InletsClosed')==6 and count()==0)
   assert(m:GetAttribute('TaskText')==Config.Text.KeyOnHook)
  end)
 end)
 test('Each closed inlet lets its bed reach further',function()
  fixture(function(f,defs,m)
   defs.BW3Fan.complete();defs.BW3Pump1.complete();defs.BW3Pump2.complete()
   local reach=m['07_BlackWater'].Reach2
   local before=reach:GetAttribute('RestLength')
   defs.BW3Inlet2.complete()
   assert(reach:GetAttribute('RestLength')==Config.Light.InletRest and Config.Light.InletRest>before)
  end)
 end)
 test('The wheel will not turn without the key, an occupant and header pressure',function()
  fixture(function(f,defs,m,count)
   defs.BW3Fan.complete();defs.BW3Pump1.complete();defs.BW3Pump2.complete();for i=1,6 do defs['BW3Inlet'..i].complete() end
   local ok=defs.BW3Wheel.canUse(nil);assert(not ok,'wheel with no key in the stand')
   assert(not defs.BW3HatchDown.canUse({UserId=1}),'the hatch without the key')
   assert(defs.BW3Header.complete());assert(m:GetAttribute('HeaderStartedAt') and m:GetAttribute('HeaderLatched')==true,'a crew of none or one latches the header')
   assert(count()==0)
  end)
 end)
 return {results=results}
end
return Checks
