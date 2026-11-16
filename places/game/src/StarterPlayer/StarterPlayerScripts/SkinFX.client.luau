--!nonstrict
-- (Nov 15) SKIN FX v2: moves the animated pieces of the case flashlights and the case art (CollectionService tag
-- BWSkinFX) wherever they are shown: your hand, other players' hands, the shop, the locker and the case previews.
-- Every piece moves relative to its own model's pivot (a flashlight's frame: Z = its long axis, lens at -Z), so it
-- works however the flashlight itself is moved or scaled. Only copies on screen move; the templates never do.
-- Attributes on a tagged part (set by ServerStorage.ArtTools.CaseFlashlights):
--   FX     kind (list below)          FXA  speed (cycles or turns per second)     FXB  phase (cycles)
--   FXAxis / FXCenter  axis and centre of a turn or swing, in the MODEL's space (default: the long axis)
--   FXDir  direction in the model's space (Hover, Rise)       FXAmp  amplitude (degrees, studs or a fraction)
--   FXColor  second colour (Shimmer; the "off" colour of Blink and Chase)   FXOffT  transparency when off (1)
--   FXOn  Blink/Chase: the colour it turns while "on" (it keeps its own colour the rest of the time)
--   FXN / FXI  how many lights take turns in a Chase / which turn is this one     FXDuty  on-share of a Blink
--   FXScale / FXAnchor  Breathe: which of the part's own axes grow, and the point that stays put
--   FXGrowTo  Rise: size multiplier reached at the end of the trip (smoke spreading out)
--   Extra motion in the part's own space, on top of any kind: FXWob (degrees) FXWobA (Hz) FXWobAxis FXWobPivot
--   (a flap or flip), FXSpin (turns per second) FXSpinAxis FXSpinPivot (a steady spin)
-- Kinds: Flicker (flame tongue), Spin/Turn (keeps turning), Swing (rocks back and forth), Hover (drifts and comes
--   back), Rise (travels, fades, starts again), Blink (on/off), Chase (lights take turns), Shimmer (colour drifts),
--   Breathe (grows and shrinks), Look (an eye darting about), Pulse (glow fades), Wiggle (tentacle sway), Bob (flap),
--   Still (no main motion, only the extra motion).
local CS=game:GetService("CollectionService")
local RS=game:GetService("RunService")
local Players=game:GetService("Players")
local TAU=math.pi*2
local noise=math.noise
local items={} -- part -> record

local function ownerOf(p)
	local m=p:FindFirstAncestorWhichIsA("Model")
	local first=m
	while m do
		if m:GetAttribute("BuiltBy") then return m end
		m=m:FindFirstAncestorWhichIsA("Model")
	end
	return first
end
local function onScreen(p)
	if p:IsDescendantOf(workspace) then return true end
	local lp=Players.LocalPlayer
	local gui=lp and lp:FindFirstChildOfClass("PlayerGui")
	return gui~=nil and p:IsDescendantOf(gui)
end
local function vec(p,key,default)
	local v=p:GetAttribute(key)
	return typeof(v)=="Vector3" and v or default
end
local function unit(v,default) return v.Magnitude>0 and v.Unit or default end
local function add(p)
	if not p:IsA("BasePart") or items[p] then return end
	task.defer(function()
		if items[p] or not p.Parent or not onScreen(p) then return end
		local owner=ownerOf(p)
		if not owner then return end
		local A=function(k) return p:GetAttribute(k) end
		items[p]={owner=owner,s0=owner:GetScale(),rel=owner:GetPivot():ToObjectSpace(p.CFrame),size=p.Size,
			tr=p.Transparency,color=p.Color,fx=A("FX"),a=A("FXA") or 1,b=A("FXB") or 0,
			axis=unit(vec(p,"FXAxis",Vector3.zAxis),Vector3.zAxis),center=vec(p,"FXCenter",Vector3.zero),
			dir=vec(p,"FXDir",Vector3.yAxis),amp=A("FXAmp"),c2=A("FXColor"),offT=A("FXOffT") or 1,
			onC=A("FXOn"),n=A("FXN") or 1,i=A("FXI") or 0,duty=A("FXDuty") or .5,growTo=A("FXGrowTo"),
			grow=vec(p,"FXScale",Vector3.one),anchor=vec(p,"FXAnchor",Vector3.zero),seed=math.random()*100,
			wob=A("FXWob"),wobA=A("FXWobA") or 1,wobAxis=unit(vec(p,"FXWobAxis",Vector3.xAxis),Vector3.xAxis),wobPivot=vec(p,"FXWobPivot",Vector3.zero),
			spin=A("FXSpin"),spinAxis=unit(vec(p,"FXSpinAxis",Vector3.yAxis),Vector3.yAxis),spinPivot=vec(p,"FXSpinPivot",Vector3.zero)}
	end)
end
for _,p in CS:GetTagged("BWSkinFX") do add(p) end
CS:GetInstanceAddedSignal("BWSkinFX"):Connect(add)
CS:GetInstanceRemovedSignal("BWSkinFX"):Connect(function(p) items[p]=nil end)
-- a copy moved onto the screen later (a template parented after it was tagged) is picked up when it arrives
workspace.DescendantAdded:Connect(function(d) if d:IsA("BasePart") and CS:HasTag(d,"BWSkinFX") then add(d) end end)
task.spawn(function()
	local lp=Players.LocalPlayer
	local gui=lp and lp:WaitForChild("PlayerGui",30)
	if gui then gui.DescendantAdded:Connect(function(d) if d:IsA("BasePart") and CS:HasTag(d,"BWSkinFX") then add(d) end end) end
end)

local reduced=false
local function refresh()
	local lp=Players.LocalPlayer
	reduced=lp~=nil and lp:GetAttribute("EHReduceMotion")==true
end
refresh()
if Players.LocalPlayer then Players.LocalPlayer:GetAttributeChangedSignal("EHReduceMotion"):Connect(refresh) end

-- Only pieces you can see are moved: a shop page, card or preview that is hidden costs nothing.
local VIS_EVERY=.25
local vis={} -- owner -> {seen, checkedAt}
local function visible(o,t)
	local v=vis[o]
	if v and t-v[2]<VIS_EVERY then return v[1] end
	local seen=true
	local x=o.Parent
	while x and x~=game do
		if x:IsA("GuiObject") and not x.Visible then seen=false break end
		if x:IsA("LayerCollector") then seen=x.Enabled break end
		if x==workspace then break end
		x=x.Parent
	end
	if seen and o:IsDescendantOf(workspace) then -- a held or world copy far away from the camera does not need to move
		local cam=workspace.CurrentCamera
		if cam and (cam.CFrame.Position-o:GetPivot().Position).Magnitude>120 then seen=false end
	end
	vis[o]={seen,t}
	return seen
end
local frames={} -- owner -> {pivot, scale} for this frame
RS:BindToRenderStep("BWSkinFX",Enum.RenderPriority.Last.Value+5,function()
	local t=os.clock()
	local k=reduced and .25 or 1
	table.clear(frames)
	if math.random()<.01 then for o in vis do if not o.Parent then vis[o]=nil end end end
	for p,r in items do
		local o=r.owner
		if not p.Parent or not o.Parent then items[p]=nil continue end
		local f=frames[o]
		if not f then
			if not visible(o,t) then f=false else f={o:GetPivot(),o:GetScale()} end
			frames[o]=f
		end
		if not f then continue end
		-- sc: size change since this piece was first seen; S: the model's absolute scale (attribute distances are at scale 1)
		local cf,S=f[1],f[2];local sc=S/r.s0
		local rel=r.rel
		if sc~=1 then rel=(rel-rel.Position)+rel.Position*sc end
		local fx=r.fx
		local ph=t*r.a+r.b
		local pose
		if fx=="Flicker" then
			local s=t*r.a*6+r.seed
			local h=1+(.35*noise(s,0)+.15*math.sin(s*2.3))*k
			local w=1+.15*noise(s,5)*k
			local size=r.size*sc
			p.Size=Vector3.new(size.X*w,size.Y*w,size.Z*h)
			-- the flame's root stays planted while it stretches out along its own -Z
			pose=cf*rel*CFrame.new(.012*sc*noise(s,9)*k,.012*sc*noise(s,11)*k,-(size.Z*(h-1))/2)
			p.Transparency=math.clamp(r.tr+.18+.18*noise(s,3),0,.9)
		elseif fx=="Spin" or fx=="Turn" then
			local c=r.center*S
			pose=cf*CFrame.new(c)*CFrame.fromAxisAngle(r.axis,ph*TAU*k)*CFrame.new(-c)*rel
		elseif fx=="Swing" then
			local c=r.center*S
			pose=cf*CFrame.new(c)*CFrame.fromAxisAngle(r.axis,math.rad(r.amp or 15)*math.sin(ph*TAU)*k)*CFrame.new(-c)*rel
		elseif fx=="Hover" then
			pose=cf*CFrame.new(r.dir*((r.amp or .04)*S*math.sin(ph*TAU)*k))*rel
		elseif fx=="Rise" then
			local u=ph%1
			pose=cf*CFrame.new(r.dir*((r.amp or .3)*S*u))*rel
			p.Transparency=1-(1-r.tr)*math.clamp(math.min(u/.15,(1-u)/.35),0,1)
			if r.growTo then p.Size=r.size*sc*(1+(r.growTo-1)*u) end
		elseif fx=="Blink" or fx=="Chase" then
			local on
			if fx=="Blink" then on=(ph%1)<r.duty else on=(math.floor(ph)%r.n)==r.i end
			if r.onC then p.Color=on and r.onC or r.color -- lights up (a cloud flashing from inside)
			elseif r.c2 then p.Color=on and r.color or r.c2 else p.Transparency=on and r.tr or r.offT end
		elseif fx=="Shimmer" then
			p.Color=r.color:Lerp(r.c2 or Color3.new(1,1,1),.5+.5*math.sin(ph*TAU))
		elseif fx=="Breathe" then
			local s=(r.amp or .08)*math.sin(ph*TAU)*k
			local g=r.grow
			local mul=Vector3.new(1+s*g.X,1+s*g.Y,1+s*g.Z)
			p.Size=r.size*sc*mul
			local a=r.anchor*S
			pose=cf*rel*CFrame.new(a-a*mul)
		elseif fx=="Look" then
			local A=(r.amp or .03)*S*k
			local s=t*r.a+r.seed
			pose=cf*rel*CFrame.new(A*noise(s,1.7),A*noise(s,9.3),0)
		elseif fx=="Pulse" then
			p.Transparency=math.clamp(r.tr+.55*(1-(.5+.5*math.sin(ph*TAU))),0,.95)
		elseif fx=="Wiggle" then
			local a=math.sin(t*r.a*2+r.b*.6+r.seed)*.06*sc*r.b*k
			pose=cf*rel*CFrame.new(a,a*.6,0)
		elseif fx=="Bob" then
			pose=cf*rel*CFrame.Angles(0,0,math.sin(t*r.a*2)*.18*r.b*k)
		end
		if r.spin or r.wob then
			local ex=CFrame.identity
			if r.spin then local pv=r.spinPivot*S;ex=ex*CFrame.new(pv)*CFrame.fromAxisAngle(r.spinAxis,t*r.spin*TAU*k)*CFrame.new(-pv) end
			if r.wob then local pv=r.wobPivot*S;ex=ex*CFrame.new(pv)*CFrame.fromAxisAngle(r.wobAxis,math.rad(r.wob)*math.sin((t*r.wobA+r.b)*TAU)*k)*CFrame.new(-pv) end
			pose=(pose or cf*rel)*ex
		end
		if pose then p.CFrame=pose end
	end
end)
