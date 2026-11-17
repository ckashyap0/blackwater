--!nonstrict
-- LEVEL 3: black water and fumes (server side). Used by Level3Floor.
--  * A REACH is one authored path of black water along a floor drain: a Folder tagged BlackWaterReach
--    under the floor, with the path in its Points attribute (in-game coordinates, about 4 studs apart)
--    and one flat film part per gap (Seg1..SegN). The server keeps one number per reach, Head: the
--    wet length in studs from the source. Clients draw the film up to Head (FiltrationController).
--  * THE LIGHT RULE: a reach creeps toward the nearest lit flashlight it can sense, at walking pace
--    or slower. Inside the snuff distance the flashlight dies (EHLightSnuffAt, then EHLightBlocked,
--    which EquipmentService obeys). It works again after the player has stayed clear for a while.
--    Fixed lamps mean nothing to it. A light held well above the film is safe.
--  * Standing on film, or in the dosing room fumes, drains stamina and hazes the view (EHL3Haze).
--    Nothing here damages or downs anyone.
local CS=game:GetService('CollectionService')
local Config=require(game.ReplicatedStorage.Game.Shared.Config.Level3)
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local L=Config.Light
local Reach={};Reach.__index=Reach
local function now()return workspace:GetServerTimeNow()end
function Reach.new(model)return setmetatable({Model=model,_reaches={},_players={},_stopped=false},Reach)end
local function parse(text)
 local pts={}
 for chunk in string.gmatch(text,'[^;]+')do
  local x,y,z=string.match(chunk,'^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$')
  if x then table.insert(pts,Vector3.new(tonumber(x),tonumber(y),tonumber(z)))end
 end
 return pts
end
function Reach:Prepare(context)
 self._context=context
 for _,f in CS:GetTagged('BlackWaterReach')do
  if f:IsDescendantOf(self.Model) then
   local pts=parse(f:GetAttribute('Points') or '')
   if #pts>=2 then
    local cum={0}
    for i=2,#pts do cum[i]=cum[i-1]+(pts[i]-pts[i-1]).Magnitude end
    local r={folder=f,id=f:GetAttribute('ReachId'),pts=pts,cum=cum,length=cum[#cum],
     rest=f:GetAttribute('RestLength') or 4,max=math.min(f:GetAttribute('MaxLength') or cum[#cum],cum[#cum]),sensedAt=-math.huge}
    r.head=r.rest;f:SetAttribute('Head',r.head);f:SetAttribute('HeadAt',now())
    table.insert(self._reaches,r)
   end
  end
 end
 table.sort(self._reaches,function(a,b)return (a.id or 0)<(b.id or 0)end)
 self._fume=Refs.Find(self.Model,'FumeZone')
end
function Reach:Count()return #self._reaches end
function Reach:Get(id)for _,r in self._reaches do if r.id==id then return r end end end
-- a reach's resting length (every repair lets it go further)
function Reach:SetRest(id,rest)
 local r=self:Get(id);if not r then return end
 r.rest=math.clamp(rest,0,r.max);r.folder:SetAttribute('RestLength',r.rest)
end
function Reach:SetRestWhere(test,rest)for _,r in self._reaches do if test(r) then self:SetRest(r.id,rest) end end end
-- the point at a distance along a reach
local function pointAt(r,s)
 s=math.clamp(s,0,r.length)
 for i=2,#r.pts do
  if s<=r.cum[i] then local a,b=r.pts[i-1],r.pts[i];local seg=r.cum[i]-r.cum[i-1];return a:Lerp(b,seg>0 and (s-r.cum[i-1])/seg or 0) end
 end
 return r.pts[#r.pts]
end
-- closest point on a reach to a position, looking only at the path between s0 and s1:
-- returns the distance along the reach, the flat distance and the height of the position above it
local function closest(r,pos,s0,s1)
 local bestS,bestD,bestY=nil,math.huge,0
 for i=2,#r.pts do
  local c0,c1=r.cum[i-1],r.cum[i]
  if c1>=s0 and c0<=s1 then
   local a,b=r.pts[i-1],r.pts[i];local ab=b-a;local len=c1-c0
   local t=len>0 and math.clamp((pos-a):Dot(ab)/(len*len),0,1) or 0
   local s=math.clamp(c0+t*len,s0,s1)
   local q=a:Lerp(b,len>0 and (s-c0)/len or 0)
   local d=Vector3.new(pos.X-q.X,0,pos.Z-q.Z).Magnitude
   -- (a path on another storey is not "near": weigh the height in)
   local score=d+math.max(0,math.abs(pos.Y-q.Y)-9)*4
   if score<bestD then bestS,bestD,bestY=s,score,pos.Y-q.Y end
  end
 end
 return bestS,bestD,bestY
end
local function inside(zone,pos)
 if not zone then return false end
 local p=zone.CFrame:PointToObjectSpace(pos);local h=zone.Size/2
 return math.abs(p.X)<=h.X and math.abs(p.Y)<=h.Y and math.abs(p.Z)<=h.Z
end
function Reach:_Crew()
 local out={}
 for _,p in self._context.GetPlayers()do
  local root=typeof(p)=='Instance' and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
  if root and p:GetAttribute('EHLifeState')=='Alive' then
   table.insert(out,{player=p,pos=root.Position,feet=root.Position-Vector3.new(0,3,0),lit=p:GetAttribute('EHFlashlightOn')==true})
  end
 end
 return out
end
function Reach:_State(p)
 local s=self._players[p]
 if not s then s={blocked=false,clear=0,haze=0};self._players[p]=s end
 return s
end
function Reach:Snuff(player)
 local s=self:_State(player)
 if s.snuffing or s.blocked then return false end
 s.snuffing=true;s.clear=0
 player:SetAttribute('EHLightSnuffAt',now())
 if not self.Model:GetAttribute('FirstSnuffAt') then self.Model:SetAttribute('FirstSnuffAt',now()) end
 task.delay(L.SnuffSeconds,function()
  s.snuffing=false
  if self._stopped or not player.Parent then return end
  s.blocked=true;player:SetAttribute('EHLightBlocked',true)
 end)
 return true
end
function Reach:Step(dt)
 if self._stopped then return end
 local crew=self:_Crew();local t=now()
 -- the reaches
 for _,r in self._reaches do
  local headPoint=pointAt(r,r.head)
  local target,targetD=nil,math.huge
  for _,c in crew do
   if c.lit then
    local dHead=(c.pos-headPoint).Magnitude
    if dHead<=L.SenseHead then
     local s,d=closest(r,c.feet,0,r.max)
     if s and d<=L.SensePath and dHead<targetD then target,targetD=s,dHead end
    end
   end
  end
  local before=r.head
  if target then
   r.sensedAt=t
   if target>r.head then r.head=math.min(target,r.head+L.Creep*dt) end
  elseif t-r.sensedAt>L.Linger then
   if r.head>r.rest then r.head=math.max(r.rest,r.head-L.Retreat*dt)
   elseif r.head<r.rest then r.head=math.min(r.rest,r.head+L.Creep*dt) end
  end
  if math.abs(r.head-(r.published or -1))>.05 then
   r.published=r.head;r.folder:SetAttribute('Head',math.floor(r.head*100)/100);r.folder:SetAttribute('HeadAt',t)
  end
 end
 -- the crew
 local fumes=self.Model:GetAttribute('FumesActive')==true
 local seen={}
 for _,c in crew do
  local p=c.player;local s=self:_State(p);seen[p]=true
  local near,nearUp=math.huge,0
  for _,r in self._reaches do
   if r.head>.2 then
    local _,d,up=closest(r,c.feet,0,r.head)
    if d<near then near,nearUp=d,up end
   end
  end
  local onFilm=near<=1.9 and nearUp>-1.5 and nearUp<2.5
  -- the flashlight
  if c.lit and not s.blocked and not s.snuffing and near<=L.Snuff and nearUp>-4 and nearUp<=L.SnuffHeight then self:Snuff(p) end
  if s.blocked then
   if near>=L.ClearDistance then s.clear+=dt else s.clear=0 end
   if s.clear>=L.ClearSeconds then s.blocked=false;s.clear=0;p:SetAttribute('EHLightBlocked',nil) end
  end
  -- harm: film and fumes (stamina, haze, a slower walk; never damage)
  local haze,kind,speed=0,nil,nil
  local inFumes=fumes and inside(self._fume,c.pos)
  if inFumes then
   self._context.DrainStamina(p,Config.Fumes.Stamina*dt)
   local empty=(p:GetAttribute('EHStamina') or 100)<=1
   haze=empty and Config.Fumes.HazeEmpty or Config.Fumes.Haze;kind='Fume'
   if empty then speed=Config.Fumes.EmptySpeed end
  end
  if onFilm then
   self._context.DrainStamina(p,L.FilmStamina*dt)
   if L.FilmHaze>haze then haze,kind=L.FilmHaze,'Film' end
   speed=math.min(speed or 1,L.FilmSpeed)
  end
  if s.haze~=haze or s.kind~=kind then s.haze,s.kind=haze,kind;p:SetAttribute('EHL3Haze',haze>0 and haze or nil);p:SetAttribute('EHL3HazeKind',kind) end
  if s.speed~=speed then s.speed=speed;self._context.SetSpeedModifier(p,'L3Hazard',speed) end
 end
 for p,s in self._players do
  if not seen[p] and (s.haze~=0 or s.speed) and p.Parent then
   s.haze,s.kind,s.speed=0,nil,nil;p:SetAttribute('EHL3Haze',nil);p:SetAttribute('EHL3HazeKind',nil);self._context.SetSpeedModifier(p,'L3Hazard',nil)
  end
 end
end
function Reach:Stop()
 if self._stopped then return end
 self._stopped=true
 for p in self._players do
  if p.Parent then
   p:SetAttribute('EHLightBlocked',nil);p:SetAttribute('EHLightSnuffAt',nil);p:SetAttribute('EHL3Haze',nil);p:SetAttribute('EHL3HazeKind',nil)
   pcall(function()self._context.SetSpeedModifier(p,'L3Hazard',nil)end)
  end
 end
 table.clear(self._players)
end
Reach.PointAt=pointAt;Reach.Closest=closest
return table.freeze(Reach)
