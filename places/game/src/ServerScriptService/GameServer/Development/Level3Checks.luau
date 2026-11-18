--!nonstrict
-- Development checks for Level 3 (Filtration, R43 rebuild). Studio only; run with Workspace.RunDevChecks = true.
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
  local f=Floor.new(m,3);local defs={};local count=0;local enabled={};local work={}
  f:Prepare({RunId='HorrorFixture',IsSuspended=function()return false end,RegisterInteraction=function(d)defs[d.interactionId]=d end,
   RegisterItem=function()end,RegisterSocket=function()end,SetInteractionEnabled=function(id,on)enabled[id]=on end,SetStatus=function()end,
   GetPlayers=function()return {}end,DrainStamina=function()return true end,SetSpeedModifier=function()return true end,
   GetInteractionProgress=function(id)local d=defs[id];return work[id] or 0,d and d.work or 1 end,
   SetInteractionProgress=function(id,v)work[id]=v;return true end,
   CompleteObjective=function()count+=1;return true,'Test'end})
  f:Activate()
  local ok,err=xpcall(function()fn(f,defs,m,function()return count end,enabled,work)end,debug.traceback);f:Destroy();assert(ok,err)
 end
 local function oneSentence(text)
  local _,n=string.gsub(text,'[%.%?!]%s','');local last=string.sub(text,-1)
  return #text<=90 and n==0 and (last=='.' or last=='?' or last=='!')
 end
 test('Level 3 template has its anchors and every part the floor looks up',function()
  local m=game.ServerStorage.GameAssets.FloorTemplates.Level3
  Contract.ValidateTemplate(m)
  local names={'FumeZone','FanStarter','FanLever','BundValve','BundValveWheel','DrumLeak','DosingBeacon1','DosingBeacon2','DosingPlacard','ServiceBoard',
   'F4HandWheel','F4Wheel','L3Checkpoint','ClearWater','MimicPanel','HallEntryZone','HeaderConsole','HeaderZone','ChamberMonitor','BypassKey','ChamberHatch','ChamberLadder',
   'ChamberZone','LadderTop','LadderBottom','WheelStand','BypassWheel','ChamberLamp','BoothBulb','BoothWindow','Intercom_Chamber','Intercom_Header','GalleryKnock','HB3','HB5'}
  for i=1,6 do table.insert(names,'FilterConsole'..i);table.insert(names,'BedWater'..i) end
  for i=1,3 do table.insert(names,'IsoValve'..i);table.insert(names,'IsoWheel'..i);table.insert(names,'ValveTag'..i) end
  for _,n in names do assert(Refs.Find(m,n),'Missing Ref: '..n) end
  local bounds=Refs.Find(m,'FloorBounds');local lo=bounds.Position.Y-bounds.Size.Y/2
  assert(Refs.Find(m,'LadderBottom').Position.Y>lo,'the bypass chamber is below FloorBounds')
  local flood=0;for _,f in CS:GetTagged('BWRisingWater') do if f:IsDescendantOf(m) then flood+=1;assert(f:FindFirstChild('Volume'),'flood has no Volume') end end
  assert(flood==1,'expected one flood zone, found '..flood)
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
 test('Leak, isolation and the beds lead to Filter 4 without finishing the floor',function()
  fixture(function(f,defs,m,count)
   assert(m:GetAttribute('Stage')=='Leak' and m:GetAttribute('FumesActive')==false)
   assert(not defs.BW3FanLever.canUse(),'fan before the drum valve')
   assert(defs.BW3BundValve.complete());assert(defs.BW3FanLever.complete())
   assert(m:GetAttribute('Stage')=='Isolate' and m:GetAttribute('ExtractFanAt'))
   local wrong=f._ferric%3+1
   assert(defs['BW3Iso'..wrong].complete());assert(m:GetAttribute('Stage')=='Isolate','the wrong valve isolated the line')
   assert(m:GetAttribute('FumesActive')==true,'the wrong valve did not gas the room')
   assert(defs['BW3Iso'..f._ferric].complete());assert(m:GetAttribute('Stage')=='Beds')
   local order=f._order;assert(#order==5 and not table.find(order,4),'board order')
   local label=Refs.Find(m,'ServiceBoard'):FindFirstChild('Label',true);assert(label.Text:find('Filter '..order[1]),'board not written')
   assert(defs['BW3Bed'..order[2]].complete());assert(m:GetAttribute('InletsClosed')==0,'a bed closed out of order')
   for _,i in order do assert(defs['BW3Bed'..i].complete()) end
   assert(m:GetAttribute('InletsClosed')==5 and m:GetAttribute('Stage')=='Filter4' and count()==0)
   assert(m:GetAttribute('Beat_Filter4Surge') and m:GetAttribute('CineId')=='Filter4','no Filter 4 cut')
   assert(defs.BW3F4Wheel.complete());assert(m:GetAttribute('F4ShutAt'),'Filter 4 not shut')
  end)
 end)
 test('Each closed bed lets its reach go further',function()
  fixture(function(f,defs,m)
   defs.BW3BundValve.complete();defs.BW3FanLever.complete();defs['BW3Iso'..f._ferric].complete()
   local i=f._order[1];local reach=m['07_BlackWater']['Reach'..i]
   local before=reach:GetAttribute('RestLength')
   defs['BW3Bed'..i].complete()
   assert(reach:GetAttribute('RestLength')==Config.Light.InletRest and Config.Light.InletRest>before)
  end)
 end)
 test('The flood rises in stages and the wheel will not turn without the key or pressure',function()
  fixture(function(f,defs,m,count,enabled,work)
   assert(f._flood,'no flood')
   f:Debug('Stage=Filter4');assert(f._floodStage==2,'flood did not start')
   assert(f._flood.Folder:GetAttribute('ToRise')==f._flood.Stages[2])
   f:Debug('Stage=Bypass')
   assert(not defs.BW3Wheel.canUse(nil),'wheel with no key in the stand')
   assert(not defs.BW3HatchDown.canUse({UserId=1}),'the hatch without the key')
   assert(defs.BW3Wheel.rate({})==0,'the wheel turns without pressure')
   assert(count()==0)
  end)
 end)
 return {results=results}
end
return Checks
