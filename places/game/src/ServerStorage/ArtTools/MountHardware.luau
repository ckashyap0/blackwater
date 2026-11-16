-- Mounting hardware generator (edit-time tool, Nov 10). Adds conduit, straps, brackets and backplates to
-- wall props so nothing looks glued on. Everything is plain anchored Parts using existing materials.
local H={}
local GALV,DARK='BW5_P_Galv','BW5_P_DarkSteel'
local rng=Random.new(77)
local function mk(parent,name,shape,size,cf,mv,col)
 local p=Instance.new('Part') p.Name=name p.Shape=shape p.Size=size p.CFrame=cf p.Anchored=true p.CanCollide=false p.CanTouch=false p.CanQuery=false
 p.Material=Enum.Material.Metal p.MaterialVariant=mv or GALV local g=rng:NextNumber(.84,.97) p.Color=col or Color3.new(g,g,g*.98) p.TopSurface=0 p.BottomSurface=0 p.Parent=parent return p
end
local function cyl(parent,name,a,b,d,mv,col)
 local v=b-a return mk(parent,name,Enum.PartType.Cylinder,Vector3.new(v.Magnitude,d,d),CFrame.lookAt((a+b)/2,b)*CFrame.Angles(0,math.pi/2,0),mv,col)
end
H.mk=mk H.cyl=cyl
-- nearest wall: returns normal (into the room), a point on the wall at the prop centre height, distance
function H.wall(level,m)
 local cf,sz=m:GetBoundingBox()
 local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={level.Architecture}
 local best
 for _,ax in {Vector3.xAxis,-Vector3.xAxis,Vector3.zAxis,-Vector3.zAxis} do
  local r=workspace:Raycast(cf.Position,ax*(math.max(sz.X,sz.Z)/2+2.5),rp)
  if r and math.abs(r.Normal.Y)<.3 and (not best or r.Distance<best.d) then best={n=-ax,p=r.Position,d=r.Distance} end
 end
 return best,cf,sz
end
local function blocked(level,from,to,ignore)
 local saved={}
 for _,f in {level:FindFirstChild('Services'),level:FindFirstChild('RoomPipework'),level:FindFirstChild('Machinery'),level:FindFirstChild('LightingGroups'),level:FindFirstChild('Dressing'),level:FindFirstChild('PropCollections'),level:FindFirstChild('Ventilation')} do
  if f then for _,p in f:GetDescendants() do if p:IsA('BasePart') and not p.CanQuery and p.Transparency<1 then saved[p]=true p.CanQuery=true end end end end
 local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances={level.Architecture,ignore} rp.RespectCanCollide=false
 local r=workspace:Spherecast(from,.12,to-from,rp)
 for p in saved do p.CanQuery=false end
 return r
end
-- conduit from the top of a prop up into the ceiling (or into the wall if something is in the way)
function H.conduit(level,m,folder,opt)
 opt=opt or {}
 local w,cf,sz=H.wall(level,m) if not w then return 'nowall' end
 local r=opt.r or .09
 local n=w.n local t=n:Cross(Vector3.yAxis)
 local top=cf.Y+sz.Y/2
 local ceil=opt.ceil
 if top>ceil-.6 then return 'tall' end
 local g=Instance.new('Model') g.Name=(opt.name or 'Conduit')..'_'..m.Name
 local half=math.abs(t.X)*sz.X/2+math.abs(t.Z)*sz.Z/2
 local tries={0} for _,k in {.3,-.3,.6,-.6} do if math.abs(k)*half*2>.1 then tries[#tries+1]=k*half end end
 for _,off in opt.offsets or tries do
  local base=Vector3.new(w.p.X,top-.03,w.p.Z)+n*(r+.035)+t*off
  local hit=blocked(level,base+Vector3.new(0,.2,0),Vector3.new(base.X,ceil-.02,base.Z),m)
  local endY=ceil
  local intoWall=false
  if hit then endY=hit.Position.Y-.45 intoWall=true end
  if endY-base.Y>.35 then
   cyl(g,'Connector',base-Vector3.new(0,.02,0),base+Vector3.new(0,.14,0),r*2+.1,DARK)
   cyl(g,'Conduit',base,Vector3.new(base.X,endY,base.Z),r*2,GALV)
   local L=endY-base.Y
   local k=math.max(1,math.floor(L/3.2))
   for i=1,k do local y=base.Y+L*i/(k+1)
    mk(g,'Strap',Enum.PartType.Block,Vector3.new(r*2+.36,.1,.03),CFrame.lookAt(Vector3.new(base.X,y,base.Z)-n*(r+.02),Vector3.new(base.X,y,base.Z)-n*(r+.02)+n)*CFrame.Angles(0,0,0),GALV)
    mk(g,'StrapBand',Enum.PartType.Block,Vector3.new(r*2+.05,.1,r*2+.04),CFrame.lookAt(Vector3.new(base.X,y,base.Z),Vector3.new(base.X,y,base.Z)+n),GALV)
    for _,s in {-1,1} do cyl(g,'Screw',Vector3.new(base.X,y,base.Z)-n*(r+.01)+t*s*(r+.12),Vector3.new(base.X,y,base.Z)-n*(r-.03)+t*s*(r+.12),.07,DARK) end
   end
   if intoWall then
    local e=Vector3.new(base.X,endY,base.Z)
    mk(g,'Elbow',Enum.PartType.Ball,Vector3.new(r*2+.03,r*2+.03,r*2+.03),CFrame.new(e),GALV)
    cyl(g,'Stub',e,e-n*(r+.08),r*2,GALV)
    cyl(g,'WallPlate',e-n*(r+.035),e-n*(r-.02),r*2+.3,DARK)
   else
    cyl(g,'CeilingPlate',Vector3.new(base.X,ceil-.05,base.Z),Vector3.new(base.X,ceil,base.Z),r*2+.3,DARK)
   end
   g.Parent=folder
   return intoWall and 'wall' or 'ceiling'
  end
 end
 g:Destroy() return 'noroom'
end
-- cantilever brackets under a wall-hung unit
function H.brackets(level,m,folder,count,depth)
 local w,cf,sz=H.wall(level,m) if not w then return 'nowall' end
 local n=w.n local t=n:Cross(Vector3.yAxis)
 local half=math.abs(t.X)*sz.X/2+math.abs(t.Z)*sz.Z/2
 local bottom=cf.Y-sz.Y/2
 local g=Instance.new('Model') g.Name='Brackets_'..m.Name
 depth=depth or math.min(2.4,(math.abs(n.X)*sz.X+math.abs(n.Z)*sz.Z)*.9)
 for i=1,count do
  local off=(count==1) and 0 or (-half*.8+(i-1)*(half*1.6)/(count-1))
  local o=Vector3.new(w.p.X,bottom,w.p.Z)+t*off
  local base=CFrame.lookAt(o,o+n)   -- -Z = out of the wall
  mk(g,'WallPlate',Enum.PartType.Block,Vector3.new(.3,2.3,.08),base*CFrame.new(0,-.95,-.04),DARK)
  mk(g,'Arm',Enum.PartType.Block,Vector3.new(.24,.2,depth),base*CFrame.new(0,-.1,-depth/2),DARK)
  local L=math.sqrt(1.75^2+(depth-.3)^2)
  local a=math.atan2(1.75,depth-.3)
  mk(g,'Brace',Enum.PartType.Block,Vector3.new(.18,.14,L),base*CFrame.new(0,-.2-1.75/2,-(depth-.3)/2-.05)*CFrame.Angles(-a,0,0),DARK)
  for _,y in {-.15,-1.0,-1.9} do cyl(g,'Bolt',(base*CFrame.new(0,y,-.08)).Position,(base*CFrame.new(0,y,-.14)).Position,.12,GALV) end
  mk(g,'ArmCap',Enum.PartType.Block,Vector3.new(.3,.26,.06),base*CFrame.new(0,-.1,-depth),GALV)
 end
 g.Parent=folder return 'ok'
end
-- backplate + strap for an extinguisher (or any small wall-hung item)
function H.strap(level,m,folder)
 local w,cf,sz=H.wall(level,m) if not w then return 'nowall' end
 local n=w.n
 local body
 for _,p in m:GetDescendants() do if p:IsA('BasePart') and p.Name:match('Red') then body=p end end
 local c=body and body.Position or cf.Position
 local d=body and math.min(body.Size.X,body.Size.Z) or math.min(sz.X,sz.Z)
 local wp=Vector3.new(c.X,c.Y,c.Z)-n*((c-w.p):Dot(n))
 local base=CFrame.lookAt(wp,wp+n)
 local g=Instance.new('Model') g.Name='Strap_'..m.Name
 mk(g,'BackPlate',Enum.PartType.Block,Vector3.new(.42,1.35,.05),base*CFrame.new(0,.1,-.025),DARK)
 for _,y in {.62,-.42} do cyl(g,'Screw',(base*CFrame.new(0,y,-.05)).Position,(base*CFrame.new(0,y,-.09)).Position,.09,GALV) end
 for _,y in {.35,-.25} do
  cyl(g,'Band',Vector3.new(c.X,c.Y+y-.05,c.Z),Vector3.new(c.X,c.Y+y+.05,c.Z),d+.07,GALV)
 end
 mk(g,'Cradle',Enum.PartType.Block,Vector3.new(.36,.08,d*.9),base*CFrame.new(0,-(body and body.Size.Y/2 or sz.Y/2)-.02,-d*.45),DARK)
 g.Parent=folder return 'ok'
end
return H
