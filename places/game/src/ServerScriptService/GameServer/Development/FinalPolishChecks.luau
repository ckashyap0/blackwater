--!nonstrict
local Checks={}
function Checks.Run()
 local u=game.ReplicatedStorage.Game.Shared.Utilities
 local Motion=require(u.HeldItemMotion);local Layout=require(u.MobileLayout)
 local results={}
 local function test(name,fn)local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err)or nil})end
 test('Sprint-stop chatter produces one stable flashlight return',function()
  local s={};local now=0
  assert(Motion.ResolveLight(s,true,true,false,now))
  assert(not Motion.ResolveLight(s,true,true,true,now))
  for _,sprint in {false,true,false,true,false}do
   now+=.04;assert(not Motion.ResolveLight(s,true,true,sprint,now))
  end
  now+=.23;assert(Motion.ResolveLight(s,true,true,false,now))
  for i=1,60 do now+=1/60;assert(Motion.ResolveLight(s,true,true,false,now))end
 end)
 test('Sprint release preserves off choice and restrictions',function()
  local s={};Motion.ResolveLight(s,true,true,true,0)
  assert(not Motion.ResolveLight(s,true,false,false,1))
  assert(not Motion.ResolveLight(s,false,true,false,1))
  assert(Motion.ResolveLight(s,true,true,false,1))
 end)
 test('Simple draw reverses once without spring rebound at every target rate',function()
  for _,fps in {30,60,120}do
   local s=Motion.New();local prior=0
   for i=1,math.floor(.15*fps)do local a=Motion.StepSimple(s,true,1/fps);assert(a>=prior);prior=a end
   for i=1,math.floor(.1*fps)do local a=Motion.StepSimple(s,false,1/fps);assert(a<=prior);prior=a end
   for i=1,fps do local a=Motion.StepSimple(s,true,1/fps);assert(a>=prior);prior=a end
   assert(s.amount==1)
  end
 end)
 test('Objective display retains original dimensions mesh and skin-free appearance',function()
  local p=Instance.new('Part');p.Size=Vector3.new(2.1,.6,.75)
  local mesh=Instance.new('SpecialMesh',p);mesh.MeshType=Enum.MeshType.FileMesh;mesh.Scale=Vector3.new(2,3,4)
  local clone=Motion.CloneDisplayPart(p,'HeldObjective')
  assert(clone.Size==p.Size and clone:FindFirstChildOfClass('SpecialMesh').Scale==mesh.Scale)
  clone:Destroy();p:Destroy()
 end)
 test('Large objective is framed farther away without rescaling on narrow screens',function()
  local small=Motion.CarryPose(Vector3.new(.4,.4,.4),1.78,70,1)
  local large=Motion.CarryPose(Vector3.new(2.1,.6,.75),1.78,70,1)
  local phone=Motion.CarryPose(Vector3.new(2.1,.6,.75),.6,70,1)
  assert(large.Z<small.Z and phone.Z<large.Z)
 end)
 test('Flashlight draws and stows monotonically at 30, 60 and 120 FPS',function()
  for _,fps in {30,60,120}do local s=Motion.New();local previous=0
   for i=1,fps do local a=Motion.Step(s,'Flashlight',1/fps);assert(a>=previous and a<=1);previous=a end;assert(previous==1)
   for i=1,fps do local a=Motion.Step(s,nil,1/fps);assert(a<=previous and a>=0);previous=a end;assert(previous==0 and s.item==nil)
  end
 end)
 test('Phone controls fit small iPhone, notched iPhone and tablet safe areas',function()
  for _,size in {Vector2.new(667,317),Vector2.new(749,310),Vector2.new(852,335),Vector2.new(1024,710),Vector2.new(375,609)}do
   local l=Layout.Get(size.X,size.Y);local radius=l.diameter/2
   for _,name in {'Flashlight','Sprint','Crouch','Interact','DropObjectiveItem'}do local p=l[name];assert(p.X-radius>=0 and p.X+radius<=size.X and p.Y-radius>=0 and p.Y+radius<=size.Y)end
   assert((l.Flashlight-l.Sprint).Magnitude>l.diameter and (l.Sprint-l.Crouch).Magnitude>l.diameter)
   -- The wide Interact (TAKE/FIT) prompt must not overlap any round button, especially Drop.
   local iw,ih=math.min(260,size.X*.55)/2,28
   for _,name in {'Flashlight','Sprint','Crouch','DropObjectiveItem'}do local p=l[name];assert(math.abs(p.X-l.Interact.X)>=iw+radius or math.abs(p.Y-l.Interact.Y)>=ih+radius,name..' overlaps Interact')end
   for _,a in {'Flashlight','Sprint','Crouch'}do assert((l[a]-l.DropObjectiveItem).Magnitude>l.diameter,a..' overlaps Drop')end
  end
 end)
 test('Interrupted draw preserves pose and reaches the final request at all target rates',function()
  for _,fps in {30,60,120}do
   local s=Motion.New()
   for i=1,math.floor(fps*.12)do Motion.Step(s,'Flashlight',1/fps)end
   local before=s.amount;local after=Motion.Step(s,nil,1/fps)
   assert(math.abs(after-before)<.3,'Reversal snapped')
   for i=1,fps do Motion.Step(s,'Flashlight',1/fps)end
   assert(s.item=='Flashlight'and s.amount==1)
   for i=1,fps do Motion.Step(s,nil,1/fps)end
   assert(s.item==nil and s.amount==0)
  end
 end)
 test('Desired flashlight packets accept false and reject invalid state',function()
  local net=require(game.ReplicatedStorage.Game.Shared.Contracts.NetworkContract)
  local version=require(game.ReplicatedStorage.Game.Shared.Constants).SchemaVersion
  for _,on in {true,false}do assert(net.ValidateAction({schemaVersion=version,requestId=1,action='ToggleFlashlight',payload={characterEpoch=1,on=on}}))end
  assert(not net.ValidateAction({schemaVersion=version,requestId=1,action='ToggleFlashlight',payload={characterEpoch=1,on='yes'}}))
 end)
 return {results=results}
end
return table.freeze(Checks)