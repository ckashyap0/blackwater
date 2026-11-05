--!nonstrict
-- HeldSway (Oct 25): the one shared "held in front of you" motion. The mop uses it, the keycard uses
-- it, and anything else carried in view should too, so every held item walks, runs and rises the same.
--   local sway=HeldSway.new()                      -- (or HeldSway.new({ampX=..}) to tune one item)
--   local p=sway:Point(dt,camera,root,x,y,depth,show) -- view-space position for a hold pose
--      x,y are screen fractions (-1..1 of the half width / half height) at `depth` studs.
--      show=true rises it up from below the screen (equipSeconds), show=false lowers it back out.
--   sway:Lowered()  -> true once it has gone fully down (safe to destroy)
--   sway:Bob(dt,root) -> bobX,bobY,moving (screen fractions) for code that places things itself
local M={};M.__index=M
M.Defaults={hz=1.3,ampX=.018,ampY=.03,walkSpeed=12,equipSeconds=.4,equipDrop=1.3,spring=32}
local function smooth(x)x=math.clamp(x,0,1);return x*x*(3-2*x)end
local function springTo(x,v,target,w,dt)
 local delta=x-target;local e=math.exp(-w*dt);local t=(v+delta*w)*dt
 return target+(delta+t)*e,(v-t*w)*e
end
function M.new(opts)
 local s=setmetatable({o=table.clone(M.Defaults),phase=0,equip=0},M)
 for k,v in opts or {} do s.o[k]=v end
 return s
end
function M:Reset(up) self.phase=0;self.equip=up and 1 or 0;self.sp=nil end
function M:Bob(dt,root)
 local v=root and root.AssemblyLinearVelocity or Vector3.zero
 local moving=math.clamp(Vector3.new(v.X,0,v.Z).Magnitude/self.o.walkSpeed,0,1)
 self.phase+=dt*math.pi*2*self.o.hz*moving
 return math.sin(self.phase)*self.o.ampX*moving,-math.abs(math.sin(self.phase))*self.o.ampY*moving,moving
end
function M:Rise(dt,show)
 local o=self.o
 if show==false then self.equip=math.max(0,self.equip-dt/o.equipSeconds) else self.equip=math.min(1,self.equip+dt/o.equipSeconds) end
 return (1-smooth(self.equip))*o.equipDrop
end
function M:Lowered() return self.equip<=0 end
function M:Point(dt,camera,root,x,y,depth,show)
 local bx,by=self:Bob(dt,root);local rise=self:Rise(dt,show)
 local tan=math.tan(math.rad(camera.FieldOfView)/2)
 local hor=tan*math.clamp(camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y),.45,2.5)
 local tp=Vector3.new((x+bx)*hor*depth,(y+by-rise)*tan*depth,-depth)
 local s=self.sp
 if not s or (s.p-tp).Magnitude>6 then s={p=tp,v=Vector3.zero};self.sp=s end
 s.p,s.v=springTo(s.p,s.v,tp,self.o.spring,dt)
 return s.p
end
return M
