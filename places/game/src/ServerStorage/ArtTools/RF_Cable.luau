--!nonstrict
-- RF_Cable (2026-11-13, Ryan: 'hanging wires should look like natural wire'): smooth cables built from
-- many short overlapping cylinders along a Catmull-Rom spline (no ball joints, no kinks). Each segment
-- overlaps the next by one radius so bends read as one continuous rubber cable.
local M={}
local function cr(p0,p1,p2,p3,t)
 local t2,t3=t*t,t*t*t
 return 0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t2+(-p0+3*p1-3*p2+p3)*t3)
end
-- points: list of Vector3 the cable passes through. opts: radius, color, material, variant, perSpan, name
function M.Build(points,parent,opts)
 opts=opts or {}
 local r=opts.radius or .045
 local model=Instance.new('Model');model.Name=opts.name or 'RF_Cable'
 model:SetAttribute('RV_Added',opts.tag or 'RF_Cable: Ryan 11-13 natural cable')
 local pts={points[1]}
 local n=#points
 local per=opts.perSpan or 8
 for i=1,n-1 do
  local p0=points[math.max(1,i-1)];local p1=points[i];local p2=points[i+1];local p3=points[math.min(n,i+2)]
  for k=1,per do table.insert(pts,cr(p0,p1,p2,p3,k/per)) end
 end
 for i=1,#pts-1 do
  local a,b=pts[i],pts[i+1];local d=(b-a).Magnitude
  if d>1e-3 then
   local c=Instance.new('Part');c.Name='Cable';c.Shape=Enum.PartType.Cylinder
   c.Size=Vector3.new(d+r*1.6,r*2,r*2)
   c.CFrame=CFrame.lookAt((a+b)/2,b)*CFrame.Angles(0,math.rad(90),0)
   c.Anchored=true;c.CanCollide=false;c.CanQuery=false;c.CanTouch=false;c.CastShadow=opts.shadow~=false
   c.Material=opts.material or Enum.Material.Rubber;c.Color=opts.color or Color3.fromRGB(28,28,30)
   if opts.variant then c.MaterialVariant=opts.variant end
   c.TopSurface=Enum.SurfaceType.Smooth;c.BottomSurface=Enum.SurfaceType.Smooth
   c.Parent=model
  end
 end
 model.Parent=parent
 return model
end
-- a cable hanging freely from 'top' with gravity: falls, sways a little and curls at the end
function M.Hanging(top,length,parent,opts)
 opts=opts or {}
 local seed=opts.seed or 1
 local rng=Random.new(seed)
 local sway=opts.sway or Vector3.new(rng:NextNumber(-1,1),0,rng:NextNumber(-1,1)).Unit*(opts.swayAmt or .35)
 local pts={top}
 local steps=6
 for i=1,steps do
  local t=i/steps
  -- mostly straight down (gravity), a soft bow out and back, and a curl right at the tip
  local bow=math.sin(t*math.pi)*.6+ (t>.8 and (t-.8)*2.2 or 0)
  table.insert(pts,top+Vector3.new(0,-length*t,0)+sway*bow+Vector3.new(rng:NextNumber(-.04,.04),0,rng:NextNumber(-.04,.04)))
 end
 return M.Build(pts,parent,opts),pts[#pts]
end
-- a cable between two fixed points that sags under its own weight (catenary-like)
function M.Sag(a,b,sag,parent,opts)
 local pts={}
 local steps=opts and opts.steps or 6
 for i=0,steps do local t=i/steps;table.insert(pts,a:Lerp(b,t)+Vector3.new(0,-sag*4*t*(1-t),0)) end
 return M.Build(pts,parent,opts)
end
return M
