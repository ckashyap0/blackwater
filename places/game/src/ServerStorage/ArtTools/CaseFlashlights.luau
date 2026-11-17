--!nonstrict
-- (Nov 13, rebuilt Nov 15) CASE FLASHLIGHTS + CASE ART, all built from parts here (no recolours, nothing reused).
-- Flashlights: length along Z, lens at the front (-Z), pivot at the origin, Grip attachment on Body, Muzzle on Lens.
-- Each case has its own body shape: Flame = hex obsidian / torch, Hazard = square industrial, Freeze = crystal prism,
-- Storm = tapered coil, Golden = polished gold, Midnight/Abyssal/Crate = their own.
-- Moving pieces are tagged BWSkinFX (FX = Flicker/Spin/Pulse/Wiggle/Bob) and animated by StarterPlayerScripts.SkinFX.
-- Build(skinFolder) makes every flashlight; BuildBoxes(boxFolder,skinFolder) makes the five new case models with
-- each case's top flashlight inside. Run in BOTH places (Lobby: ShopArt.Skins + ShopArt.Boxes, Game: Assets).
local CS=game:GetService("CollectionService")
local M={}
local rad,pi=math.rad,math.pi
local function rgb(t) return typeof(t)=="Color3" and t or Color3.fromRGB(t[1],t[2],t[3]) end
local E=Enum.Material
local NEON,METAL,WOOD,GLASS,SMOOTH,FOIL,GRANITE,SLATE,ICE,DIAMOND,BASALT,CORRODED=E.Neon,E.Metal,E.Wood,E.Glass,E.SmoothPlastic,E.Foil,E.Granite,E.Slate,E.Ice,E.DiamondPlate,E.Basalt,E.CorrodedMetal
local GOLD,GOLD2,GOLD3={255,192,40},{255,224,110},{220,150,24}
local RUBBER,FABRIC,LEATHER,SNOW,GLACIER=E.Rubber,E.Fabric,E.Leather,E.Snow,E.Glacier
local V,CF=Vector3.new,CFrame.new
-- ===== primitives =====
local cur
local function part(name,shape,size,cf,color,mat,tr)
	local p=Instance.new(shape=="Wedge" and "WedgePart" or "Part")
	if shape=="Ellipsoid" then local sm=Instance.new("SpecialMesh");sm.MeshType=Enum.MeshType.Sphere;sm.Parent=p -- a stretchable ball (flames)
	elseif shape~="Wedge" then p.Shape=shape end
	p.Name=name;p.Size=size;p.CFrame=cf;p.Color=rgb(color);p.Material=mat or SMOOTH;p.Transparency=tr or 0
	p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Massless=true
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if mat==METAL or mat==FOIL then p.Reflectance=.08 end
	p.Parent=cur
	return p
end
local FXKEY={a="FXA",b="FXB",axis="FXAxis",center="FXCenter",dir="FXDir",amp="FXAmp",color="FXColor",n="FXN",i="FXI",duty="FXDuty",
	scale="FXScale",anchor="FXAnchor",growTo="FXGrowTo",offT="FXOffT",wob="FXWob",wobA="FXWobA",wobAxis="FXWobAxis",wobPivot="FXWobPivot",
	spin="FXSpin",spinAxis="FXSpinAxis",spinPivot="FXSpinPivot",on="FXOn"}
-- tag a moving piece: fx(part,"Kind",speed,phase) or fx(part,"Kind",{a=speed,b=phase,axis=...}) (see StarterPlayerScripts.SkinFX)
local function fx(p,kind,a,b)
	CS:AddTag(p,"BWSkinFX");p:SetAttribute("FX",kind)
	if type(a)=="table" then
		for k,v in a do if type(v)=="table" then v=rgb(v) end;p:SetAttribute(FXKEY[k] or k,v) end
	else
		if a then p:SetAttribute("FXA",a) end;if b then p:SetAttribute("FXB",b) end
	end
	return p
end
local ALONG=CFrame.Angles(0,rad(90),0) -- cylinders run along X; this lays them along Z
local UP=CFrame.Angles(rad(90),0,0)    -- a part's -Z now points up (flames stretch along -Z)
local function cyl(name,len,dia,z,color,mat,x,y,tr) return part(name,Enum.PartType.Cylinder,Vector3.new(len,dia,dia),CFrame.new(x or 0,y or 0,z)*ALONG,color,mat,tr) end
local function ball(name,d,pos,color,mat,tr) return part(name,Enum.PartType.Ball,Vector3.new(d,d,d),CFrame.new(pos),color,mat,tr) end
local function box(name,size,cf,color,mat,tr) return part(name,Enum.PartType.Block,size,cf,color,mat,tr) end
local function wedge(name,size,cf,color,mat) return part(name,"Wedge",size,cf,color,mat) end
local function around(n,r,z,fn) for i=0,n-1 do local a=i/n*pi*2;fn(i,CFrame.new(0,0,z)*CFrame.Angles(0,0,a)*CFrame.new(0,r,0),a) end end
-- ===== the shared core: body + head + lens =====
-- o.shape  : cyl | hex | box | taper | crystal      o.headShape : cyl | box | bell | orb | hammer | crystal
local function core(o)
	local L=o.len or .9;local d=(o.dia or .3)*1.25; -- (thicker grips)
	local hd=o.head or .46
	local bc,bm,tc=o.body,o.bodyMat or METAL,o.trim or o.body
	local sh=o.shape or "cyl"
	local body
	if sh=="hex" then
		body=box("Body",Vector3.new(d*.58,d,L),CFrame.new(),bc,bm)
		for k=1,2 do box("BodyFacet",Vector3.new(d*.58,d,L),CFrame.Angles(0,0,rad(60*k)),bc,bm) end
	elseif sh=="box" then
		body=box("Body",Vector3.new(d,d,L),CFrame.new(),bc,bm)
		for sx=-1,1,2 do for sy=-1,1,2 do box("BodyEdge",Vector3.new(.03,.03,L+.01),CFrame.new(sx*d/2,sy*d/2,0),tc,METAL) end end
	elseif sh=="taper" then
		body=cyl("Body",L*.55,d,-L*.225,bc,bm)
		cyl("BodyRear",L*.45,d*.78,L*.275,bc,bm);cyl("BodyStep",.04,d*.9,.06,tc,METAL)
	elseif sh=="crystal" then
		body=box("Body",Vector3.new(d*.7,d*.7,L),CFrame.Angles(0,0,rad(45)),bc,bm)
		box("BodyFacet",Vector3.new(d*.7,d*.7,L*.9),CFrame.new(),bc,bm,.15)
	else
		body=cyl("Body",L,d,0,bc,bm)
	end
	if o.bodyT then for _,x in cur:GetChildren() do if x.Name=="Body" or x.Name=="BodyFacet" or x.Name=="BodyRear" then x.Transparency=o.bodyT end end end
	local g=Instance.new("Attachment");g.Name="Grip";g.Parent=body;g.WorldCFrame=CFrame.new(0,0,.06)
	-- tail
	if sh=="box" then box("TailCap",Vector3.new(d+.05,d+.05,.08),CFrame.new(0,0,L/2+.04),tc,METAL)
	elseif sh=="crystal" then box("TailCap",Vector3.new(d*.55,d*.55,.16),CFrame.new(0,0,L/2+.06)*CFrame.Angles(0,0,rad(45)),tc,o.trimMat or ICE)
	else cyl("TailCap",.08,(sh=="taper" and d*.78 or d)+.04,L/2+.04,tc,METAL) end
	-- head
	local hs=o.headShape or "cyl"
	local hz=-L/2-.12
	if hs=="box" then
		box("Neck",Vector3.new((d+hd)/2,(d+hd)/2,.1),CFrame.new(0,0,-L/2-.04),tc,METAL)
		box("Head",Vector3.new(hd,hd,.22),CFrame.new(0,0,hz),o.headColor or bc,o.headMat or METAL)
		box("Bezel",Vector3.new(hd+.05,hd+.05,.05),CFrame.new(0,0,hz-.12),tc,METAL)
	elseif hs=="bell" then
		cyl("Neck",.08,d+.04,-L/2-.03,tc,METAL)
		cyl("Head",.1,(d+hd)/2,hz+.05,o.headColor or bc,o.headMat or METAL)
		cyl("Head2",.1,hd*.92,hz-.04,o.headColor or bc,o.headMat or METAL)
		cyl("Bezel",.05,hd+.06,hz-.12,tc,o.trimMat or METAL)
	elseif hs=="orb" then
		cyl("Neck",.1,d*.8,-L/2-.04,tc,METAL)
		ball("Head",hd,Vector3.new(0,0,hz+.12),o.headColor or bc,o.headMat or METAL) -- (sits back so the lens shows in front)
		cyl("Bezel",.05,hd*.62,hz-.12,tc,METAL)
	elseif hs=="hammer" then
		cyl("Neck",.1,d+.06,-L/2-.04,tc,METAL)
		box("Head",Vector3.new(hd*1.7,hd*.8,.3),CFrame.new(0,0,hz-.02),o.headColor or bc,o.headMat or METAL)
		box("Bezel",Vector3.new(hd*.8,hd*.8,.05),CFrame.new(0,0,hz-.12),tc,METAL)
	elseif hs=="crystal" then
		box("Neck",Vector3.new(d*.8,d*.8,.1),CFrame.new(0,0,-L/2-.04)*CFrame.Angles(0,0,rad(45)),tc,o.trimMat or ICE)
		box("Head",Vector3.new(hd*.72,hd*.72,.22),CFrame.new(0,0,hz)*CFrame.Angles(0,0,rad(45)),o.headColor or bc,o.headMat or ICE)
		box("Bezel",Vector3.new(hd*.74,hd*.74,.05),CFrame.new(0,0,hz-.12)*CFrame.Angles(0,0,rad(45)),tc,o.trimMat or ICE)
	else
		cyl("Neck",.1,(d+hd)/2,-L/2-.04,tc,METAL)
		cyl("Head",.2,hd,hz,o.headColor or bc,o.headMat or METAL)
		cyl("Bezel",.05,hd+.04,hz-.12,tc,o.trimMat or METAL)
	end
	local lw=(hs=="orb") and hd*.62 or hd
	cyl("Reflector",.02,lw-.06,hz-.135,{235,235,230},METAL)
	local lens=cyl("Lens",.02,lw-.1,hz-.15,o.lens or {255,240,200},NEON)
	local mz=Instance.new("Attachment");mz.Name="Muzzle";mz.Parent=lens;mz.WorldCFrame=CFrame.new(0,0,hz-.16)
	return hz-.16,L,d,hd
end
-- ===== features =====
local function bands(L,d,n,color,mat,sq) for i=1,n do local z=-L/2+L*(i/(n+1))
	if sq then box("Band",Vector3.new(d+.03,d+.03,.035),CFrame.new(0,0,z),color,mat or METAL) else cyl("Band",.035,d+.03,z,color,mat or METAL) end end end
local function stripes(L,d,n,c1,c2) for i=1,n do cyl("Stripe",L/(n*2),d+.012,-L/2+L*((i-.5)/n),(i%2==0) and c1 or c2,SMOOTH) end end
-- torch flames rising from the head: layered outer / middle / core tongues, every one flickering
local function flames(z,r,y0,colors,count,scale)
	count=count or 7;scale=scale or 1
	for layer=1,#colors do
		local n=math.max(3,count-(layer-1)*2);local lr=r*(1-(layer-1)*.3);local s=scale*(1-(layer-1)*.22)
		for i=1,n do
			local a=i/n*pi*2+layer*.7
			local h=(.3+.12*((i*7+layer)%3))*s;local w=.12*s
			local p=part("Flame","Ellipsoid",Vector3.new(w,w*.85,h),CFrame.new(math.cos(a)*lr,y0+h/2-.02,z+math.sin(a)*lr*.7)*UP*CFrame.Angles(math.sin(a)*.25,math.cos(a)*.25,0),colors[layer],NEON,(layer-1)*.05)
			fx(p,"Flicker",.45+((i*3+layer)%5)*.12)
		end
	end
end
local function embers(z,r,color,n,y) for i=1,n do local a=i/n*pi*2;local p=ball("Ember",.04,Vector3.new(math.cos(a)*r,math.sin(a)*r+(y or 0),z-(i%3)*.06),color,NEON);fx(p,"Spin",.5+(i%2)*.4) end end
local function cracks(L,d,color,n) for i=1,n do local a=i*2.399;local z=-L/2+L*((i*.37)%1)
	box("Crack",Vector3.new(.014,.014,.09+((i*13)%5)*.035),CFrame.new(0,0,z)*CFrame.Angles(0,0,a)*CFrame.new(0,d/2+.003,0)*CFrame.Angles(rad(((i*17)%40)-20),0,0),color,NEON) end end
local function spikes(z,r,n,len,color,mat,tilt) around(n,r,z,function(i,cf) wedge("Spike",Vector3.new(.04,len,.08),cf*CFrame.new(0,len/2,0)*CFrame.Angles(rad(tilt or 0),0,0),color,mat or METAL) end) end
local function fins(L,d,n,color,mat,size,len) size=size or .22 around(n,d/2,0,function(i,cf) wedge("Fin",Vector3.new(.03,size,len or L*.55),cf*CFrame.new(0,size/2,0),color,mat or METAL) end) end
local function gems(z,r,n,color,size,mat) around(n,r,z,function(i,cf) box("Gem",Vector3.new(size or .06,size or .06,size or .06),cf*CFrame.Angles(rad(45),rad(45),0),color,mat or NEON) end) end
local function crystals(z,r,n,color,len,mat,lean) around(n,r,z,function(i,cf) local l=len*(.7+((i*5)%3)*.2);box("Crystal",Vector3.new(.07,l,.07),cf*CFrame.Angles(rad(lean or 0),0,0)*CFrame.new(0,l/2,0)*CFrame.Angles(0,rad(45),rad(14)),color,mat or ICE) end) end
-- a ring made of short segments (so it reads as a ring, not a disc), spinning round the flashlight
local function ring(z,dia,color,speed,tilt,segs,thick,mat)
	segs=segs or 18;local r=dia/2;thick=thick or .03
	for i=0,segs-1 do local a=i/segs*pi*2
		local p=box("Halo",Vector3.new(2*pi*r/segs*.72,thick,thick),CFrame.new(0,0,z)*CFrame.Angles(rad(tilt or 0),0,0)*CFrame.Angles(0,0,a)*CFrame.new(0,r,0),color,mat or NEON)
		if speed and speed~=0 then fx(p,"Spin",speed) end end end
local function orbiters(z,r,n,color,size,speed,kind,mat)
	for i=1,n do local a=i/n*pi*2;local pos=Vector3.new(math.cos(a)*r,math.sin(a)*r,z)
		local p
		if kind=="coin" then p=part("Coin",Enum.PartType.Cylinder,Vector3.new(.025,size,size),CFrame.new(pos)*CFrame.Angles(0,0,a),color,mat or FOIL)
		elseif kind=="shard" then p=box("Shard",Vector3.new(size*.5,size*1.4,size*.5),CFrame.new(pos)*CFrame.Angles(0,0,a)*CFrame.Angles(0,rad(45),0),color,mat or ICE)
		else p=ball("Orbiter",size,pos,color,mat or NEON) end
		fx(p,"Spin",speed) end end
local function coil(L,d,color,turns,z0) local n=turns*10 for i=0,n do local t=i/n;local a=t*turns*pi*2
	box("Coil",Vector3.new(.03,.03,.06),CFrame.new(math.cos(a)*(d/2+.03),math.sin(a)*(d/2+.03),(z0 or 0)-L/2+L*t)*CFrame.Angles(0,0,a),color,NEON) end end
local function bolt(z,x,y,color,scale,ang) scale=scale or 1 local pts={{0,0},{.06,.1},{-.02,.17},{.07,.3}}
	local base=CFrame.new(x,y,z)*CFrame.Angles(0,0,ang or 0)
	for i=1,#pts-1 do local a,b=pts[i],pts[i+1];local p0=(base*CFrame.new(a[1]*scale,a[2]*scale,0)).Position;local p1=(base*CFrame.new(b[1]*scale,b[2]*scale,0)).Position
		local s=box("Bolt",Vector3.new(.03,.03,(p1-p0).Magnitude),CFrame.lookAt((p0+p1)/2,p1),color,NEON);fx(s,"Pulse",2.5+i,i*.2) end end
local function cage(z,r,n,len,color,mat) around(n,r,z,function(i,cf) box("Cage",Vector3.new(.025,.025,len),cf,color,mat or METAL) end) cyl("CageRing",.03,r*2+.04,z-len/2,color,mat or METAL) end
local function rivets(L,d,n,color,sq) for i=1,n do local a=i*2.399;local z=-L/2+L*((i*.61)%1)
	if sq then local side=i%4;local cf=CFrame.Angles(0,0,side*pi/2)*CFrame.new(0,d/2+.01,z);box("Rivet",Vector3.new(.04,.02,.04),cf,color,METAL)
	else box("Rivet",Vector3.new(.04,.02,.04),CFrame.new(0,0,z)*CFrame.Angles(0,0,a)*CFrame.new(0,d/2+.01,0),color,METAL) end end end
-- ===== the flashlights =====
local R={}
-- ---------- FLAME CASE (hex obsidian / torches) ----------
R.SkinEmber=function() local f,L,d,hd=core{shape="hex",body={34,24,22},bodyMat=BASALT,trim={110,46,20},head=.38,lens={255,150,60}}
	cracks(L,d,{255,90,20},10);flames(f+.12,.06,hd/2-.04,{{255,90,20},{255,190,80}},4,.6);embers(f-.04,.3,{255,140,40},4,0) end
R.SkinKindling=function() local f,L,d,hd=core{body={120,80,48},bodyMat=WOOD,trim={70,50,40},head=.4,lens={255,190,90},headShape="bell"}
	for i=1,3 do cyl("Twine",.05,d+.02,-L/2+i*.22,{170,140,90},E.Fabric) end
	for i=1,5 do box("Twig",Vector3.new(.035,.035,.32),CFrame.new(0,0,f+.16)*CFrame.Angles(0,0,i*1.25)*CFrame.new(0,hd/2-.02,0)*CFrame.Angles(rad(-25),0,0),{90,60,36},WOOD) end
	flames(f+.12,.07,hd/2-.02,{{255,110,20},{255,200,80}},5,.75) end
R.SkinFirebrand=function() local f,L,d,hd=core{shape="hex",body={28,24,22},bodyMat=SLATE,trim={210,96,24},head=.5,lens={255,160,40},headShape="bell"}
	for i=1,3 do box("Chevron",Vector3.new(d+.02,.05,.03),CFrame.new(0,0,-.25+i*.15)*CFrame.Angles(rad(30),0,0),{255,110,10},NEON) end
	spikes(f+.1,hd/2,8,.14,{210,96,24},METAL,-25);flames(f+.12,.1,hd/2-.04,{{255,80,10},{255,170,40},{255,240,170}},7,.85) end
R.SkinMagma=function() local f,L,d,hd=core{shape="hex",body={30,16,12},bodyMat=GRANITE,trim={60,30,20},head=.48,lens={255,120,40},headMat=GRANITE,headShape="orb"}
	cracks(L,d,{255,70,10},18)
	for i=1,6 do local p=box("LavaDrip",Vector3.new(.05,.12+(i%3)*.05,.05),CFrame.new(math.cos(i)*.1,-d/2-.04,-.3+i*.1),{255,110,20},NEON);fx(p,"Pulse",.7,i*.15) end
	local core2=ball("LavaCore",hd*.7,Vector3.new(0,0,f+.2),{255,90,10},NEON,.3);fx(core2,"Pulse",.8) end
R.SkinForge=function() -- a war-hammer lamp: wooden haft, iron hammer head with the lens in its face
	local f,L,d,hd=core{body={110,72,40},bodyMat=WOOD,dia=.22,len=.95,trim={70,66,62},head=.42,headShape="hammer",headColor={66,62,58},headMat=METAL,lens={255,170,70}}
	for i=1,4 do cyl("Wrap",.04,d+.03,.1+i*.07,{60,40,26},E.Fabric) end
	for sx=-1,1,2 do box("HammerFace",Vector3.new(.04,hd*.7,.26),CFrame.new(sx*hd*.86,0,f+.14),{255,120,30},NEON);for k=-1,1,2 do box("HotRivet",Vector3.new(.05,.05,.05),CFrame.new(sx*hd*.55,k*hd*.25,f+.14),{255,150,50},NEON) end end
	embers(f-.08,.42,{255,170,60},5) end
R.SkinBlueFlame=function() local f,L,d,hd=core{shape="taper",body={22,26,40},trim={60,120,220},head=.44,lens={160,220,255},headShape="bell"}
	coil(L*.5,d,{60,140,255},2,-L*.225);flames(f+.12,.09,hd/2-.03,{{30,90,255},{100,190,255},{220,245,255}},7,.85) end
R.SkinPhoenix=function() local f,L,d,hd=core{shape="taper",body={110,34,14},trim={255,190,60},head=.46,lens={255,210,120},headShape="bell",trimMat=FOIL}
	for s=-1,1,2 do for k=1,4 do local w=wedge("Wing",Vector3.new(.025,.1+k*.03,.18+k*.07),CFrame.new(s*(.14+k*.05),.05+k*.03,-.05+k*.06)*CFrame.Angles(0,0,rad(s*(70-k*10)))*CFrame.Angles(rad(180),0,0),k==1 and {255,200,70} or (k%2==0 and {255,110,20} or {220,60,20}),k==1 and NEON or SMOOTH);fx(w,"Bob",1.3,s) end end
	for i=1,5 do local t=wedge("TailFeather",Vector3.new(.025,.07,.34),CFrame.new((i-3)*.05,0,L/2+.2)*CFrame.Angles(rad(-15),0,rad((i-3)*14)),i%2==0 and {255,200,70} or {255,110,20},NEON);fx(t,"Bob",1.1,(i-3)*.3) end
	flames(f+.12,.08,hd/2-.03,{{255,80,20},{255,190,70}},5,.75) end
R.SkinEverflame=function() -- FLAME CASE ULTRA RARE: obsidian torch in golden claws, crowned with living fire
	local f,L,d,hd=core{shape="hex",body={20,12,10},bodyMat=BASALT,trim={255,186,70},trimMat=FOIL,head=.54,lens={255,236,180},len=.96,dia=.33,headShape="bell",headColor={36,18,12}}
	cracks(L,d,{255,100,16},22);bands(L,d,2,{255,186,70},FOIL)
	for i=1,3 do local p=box("Vein",Vector3.new(.02,.02,L*.9),CFrame.Angles(0,0,rad(i*120))*CFrame.new(0,d/2+.006,0),{255,140,30},NEON);fx(p,"Pulse",.6,i*.3) end
	-- golden claws wrapping the head
	around(6,hd/2,f+.2,function(i,cf) wedge("Claw",Vector3.new(.05,.22,.3),cf*CFrame.new(0,.1,0)*CFrame.Angles(rad(-150),0,0),{255,186,70},FOIL) end)
	-- the fire: three layers of flickering tongues rising off the head and a white-hot heart
	flames(f+.14,.17,hd/2-.06,{{255,50,10},{255,120,20},{255,200,60},{255,250,220}},12,1.35)
	local heart=ball("FireHeart",.2,Vector3.new(0,hd/2+.05,f+.14),{255,250,230},NEON);fx(heart,"Pulse",1.6)
	ring(f-.03,hd+.32,{255,150,40},.5,0,22,.035);ring(f-.06,hd+.5,{255,80,20},-.35,0,26,.025)
	embers(f-.08,.46,{255,200,90},10,0)
	-- a flame trail off the tail cap
	for i=1,3 do local p=part("TailFlame","Ellipsoid",Vector3.new(.08,.08,.22+i*.04),CFrame.new(math.cos(i*2.1)*.06,math.sin(i*2.1)*.06,L/2+.16+i*.02)*CFrame.Angles(0,pi,0),{255,90+i*40,20},NEON);fx(p,"Flicker",.6+i*.2) end end
local FZ={shape="crystal",headShape="crystal",bodyMat=ICE,trimMat=ICE}
local function fz(t) local o={} for k,v in FZ do o[k]=v end for k,v in t do o[k]=v end return o end
R.SkinAbsoluteZero=function() -- DEEP FREEZE top prize: a cryo crystal lamp in a storm of orbiting ice shards
	local f,L,d,hd=core(fz{body={60,110,160},trim={170,235,255},head=.56,lens={240,255,255},dia=.34})
	local c=box("CryoCore",Vector3.new(d*.4,d*.4,L*.85),CFrame.Angles(0,0,rad(45)),{90,220,255},NEON);fx(c,"Pulse",.9)
	crystals(f+.16,hd*.34,8,{180,236,255},.3,ICE,-30);crystals(f+.16,hd*.22,5,{90,220,255},.2,NEON,-15)
	crystals(L/2,d*.3,4,{180,236,255},.18,ICE,40)
	orbiters(f+.12,.46,8,{210,248,255},.08,.7,"shard");ring(f+.12,hd+.62,{140,225,255},-.4,0,24,.025) end
R.SkinKraken=function() -- ABYSSAL CASE top prize: a deep-sea relic with eight waving tentacles curling off the head
	local f,L,d,hd=core{shape="taper",body={14,26,34},trim={20,255,200},head=.54,lens={200,120,255},dia=.33,headShape="orb",headColor={26,50,60}}
	for i=1,8 do local a=i/8*pi*2;local segs=6
		for s=1,segs do local t=s/segs
			local p=box("Tentacle",Vector3.new(.07*(1.15-t*.7),.07*(1.15-t*.7),.1),
				CFrame.new(0,0,f+.12)*CFrame.Angles(0,0,a)*CFrame.new(0,hd/2+.01+t*.22,-t*.36+t*t*.18)*CFrame.Angles(rad(40+t*60),0,0),s==segs and {20,255,200} or {40,90,100},s==segs and NEON or SMOOTH)
			fx(p,"Wiggle",1+i*.15,s) end end
	local e=ball("KrakenEye",.16,Vector3.new(0,0,f+.02),{200,120,255},NEON);fx(e,"Pulse",.7)
	for i=1,10 do ball("Sucker",.05,Vector3.new(math.cos(i*2.2)*d/2,math.sin(i*2.2)*d/2,-.38+i*.075),{20,255,200},NEON) end end
R.SkinCrew=function() local f,L,d,hd=core{shape="box",body={34,58,42},trim={70,210,110},head=.44,lens={190,255,210},headShape="box"}
	box("Rail",Vector3.new(.07,.04,.52),CFrame.new(0,d/2+.03,0),{40,40,44},METAL);for i=1,5 do box("RailNotch",Vector3.new(.09,.02,.03),CFrame.new(0,d/2+.06,-.2+i*.08),{40,40,44},METAL) end;bands(L,d,2,{70,210,110},NEON,true) end
-- ===== extra helpers (Nov 15) =====
-- a straight bar from p0 to p1
local function seg(name,p0,p1,th,color,mat,tr)
	local d=p1-p0;local up=math.abs(d.Unit.Y)>.98 and Vector3.xAxis or Vector3.yAxis
	return box(name,V(th,th,d.Magnitude),CFrame.lookAt((p0+p1)/2,p1,up),color,mat,tr)
end
-- a still ring made of short pieces, lying in the XY plane of frame cf
local function hoop(name,cf,r,n,th,color,mat,tr)
	local out={}
	for i=0,n-1 do local a=i/n*pi*2
		table.insert(out,box(name,V(2*pi*r/n*.86,th,th),cf*CFrame.Angles(0,0,a)*CF(0,r,0),color,mat,tr)) end
	return out
end
-- an ancient key-pattern band (little hooked blocks) round the body at z
local function meander(z,r,n,color,mat)
	for i=0,n-1 do local cf=CF(0,0,z)*CFrame.Angles(0,0,i/n*pi*2)*CF(0,r,0)
		local w=2*pi*r/n*.7
		box("KeyBar",V(w,.014,.014),cf*CF(0,0,-.03),color,mat)
		box("KeyBar",V(.014,.014,.06),cf*CF(w/2,0,0),color,mat)
		box("KeyBar",V(w*.55,.014,.014),cf*CF(w*.22,0,.03),color,mat)
	end
end
local function hazardBands(d,z0,len,n,square)
	for i=1,n do local z=z0-len/2+len*((i-.5)/n);local c=i%2==0 and {255,196,0} or {24,24,24}
		if square then box("HazardStripe",V(d+.016,d+.016,len/n),CF(0,0,z),c,SMOOTH) else cyl("HazardStripe",len/n,d+.014,z,c,SMOOTH) end end
end
-- a cloud: a dark flat base with lighter billowing puffs on top, lying along frame's X axis.
-- flash = {a=speed,b=phase} makes the whole cloud light up from inside now and then (lightning)
local function cloud(frame,w,h,dp,n,flash)
	local top,low,lit={150,154,170},{78,80,96},{232,228,255}
	local function flashIt(p,k)
		if flash then fx(p,"Blink",{a=flash.a,b=(flash.b or 0)+((k%2)*.035),duty=.045,on=lit}) end
	end
	for k=-1,1 do
		flashIt(part("CloudBase","Ellipsoid",V(w*.5,h*.38,dp*(.9-math.abs(k)*.15)),frame*CF(k*w*.27,-h*.2,(k%2)*dp*.06),low,SMOOTH),k)
	end
	for i=1,n do local u=(i-.5)/n;local bump=math.sin(u*pi)
		local s=h*(.42+.5*bump)*(.85+.15*((i*37)%7)/6)
		local c=i%2==0 and top or {128,132,148}
		flashIt(part("CloudPuff","Ellipsoid",V(s*1.3,s,s*1.15),frame*CF((u-.5)*w*.78,-h*.12+s*.36,((i%3)-1)*dp*.2),c,SMOOTH),i)
	end
end
-- ===================== HAZARD KIT =====================
R.SkinCaution=function() -- COMMON: a rubber-armoured site light: ribbed grip, yellow rails, lens guard, carabiner
	local f,L,d,hd=core{body={44,42,38},bodyMat=RUBBER,trim={255,196,0},head=.5,headShape="bell",lens={255,236,150}}
	for i=0,6 do cyl("GripRib",.022,d+.022,.02+i*.06,{24,24,24},RUBBER) end
	for _,z in {-.3,.4} do cyl("Overmold",.05,d+.03,z,{255,196,0},RUBBER) end
	part("SwitchBoot","Ellipsoid",V(.1,.06,.1),CF(0,d/2+.01,-.2),{24,24,24},RUBBER)
	part("SwitchNub","Ellipsoid",V(.05,.04,.05),CF(0,d/2+.04,-.2),{255,196,0},RUBBER)
	cyl("BumperRing",.12,.5+.07,f+.07,{24,24,24},RUBBER)
	hazardBands(.5,f+.2,.12,4,false)
	for _,a in {45,-45} do box("LensGuard",V(.016,.5*.9,.016),CF(0,0,f-.012)*CFrame.Angles(0,0,rad(a)),{150,154,160},METAL) end
	hoop("LensGuardRim",CF(0,0,f-.012),.5*.45,20,.018,{150,154,160},METAL)
	cyl("TailPlate",.03,d*.7,L/2+.095,{255,196,0},SMOOTH)
	hoop("Carabiner",CF(0,0,L/2+.17)*CFrame.Angles(0,rad(90),0),.07,10,.02,{150,155,160},METAL)
end
R.SkinHiVis=function() -- COMMON: fluorescent site-vest colours, reflective chevrons, rubber end caps, a lanyard
	local f,L,d,hd=core{body={200,240,30},bodyMat=SMOOTH,trim={40,42,46},head=.48,headShape="bell",lens={240,255,190}}
	for _,z in {-.18,.12} do
		cyl("ReflectTape",.06,d+.022,z,{215,220,222},FOIL)
		for s=-1,1,2 do cyl("TapeEdge",.012,d+.026,z+s*.036,{255,120,20},SMOOTH) end
	end
	for k=0,2 do local z=-.06+k*.11
		for s=-1,1,2 do box("Chevron",V(.12,.012,.025),CF(s*.045,d/2+.006,z)*CFrame.Angles(0,rad(s*35),0),{220,224,226},FOIL) end end
	cyl("EndCap",.1,d+.03,L/2-.02,{36,38,42},RUBBER)
	for k=0,2 do cyl("CapRidge",.012,d+.04,L/2-.06+k*.035,{24,24,26},RUBBER) end
	part("SwitchBoot","Ellipsoid",V(.08,.05,.08),CF(0,d/2+.01,.3),{36,38,42},RUBBER)
	cyl("Bumper",.06,hd+.08,f+.05,{30,30,30},RUBBER)
	box("Clip",V(.08,.02,.36),CF(-(d/2+.015),0,.0)*CFrame.Angles(0,0,rad(90)),{60,62,66},METAL)
	hoop("Lanyard",CF(0,0,L/2+.14)*CFrame.Angles(0,rad(90),0),.09,12,.016,{255,120,20},FABRIC)
end
R.SkinFlare=function() -- RARE: a lit road flare: paper wraps, ribbed striker cap, a burning tip spitting sparks and smoke
	local f,L,d,hd=core{body={200,30,24},bodyMat=SMOOTH,trim={235,232,225},dia=.27,head=.32,len=1.05,headColor={70,30,26},lens={255,170,100}}
	cyl("PaperBand",.16,d+.012,.08,{235,232,225},SMOOTH)
	for _,z in {-.02,.18} do cyl("PrintLine",.012,d+.014,z,{150,20,16},SMOOTH) end
	box("Seam",V(.012,.004,L*.95),CF(0,d/2+.005,0),{160,22,18},SMOOTH)
	cyl("StrikerCap",.14,d+.03,L/2+.02,{240,238,232},SMOOTH)
	for k=0,4 do cyl("CapRidge",.012,d+.042,L/2-.03+k*.025,{220,216,208},SMOOTH) end
	for s=-1,1,2 do seg("StandWire",V(s*.05,-d/2+.02,L/2+.06),V(s*.12,-d/2-.12,L/2+.2),.018,{150,150,155},METAL) end
	fx(part("FlareFire","Ellipsoid",V(.2,.2,.3),CF(0,0,f-.1),{255,70,40},NEON,.15),"Flicker",1.6)
	fx(part("FlareCore","Ellipsoid",V(.1,.1,.2),CF(0,0,f-.07),{255,215,170},NEON),"Flicker",2.3)
	for i=1,10 do local a=i*2.4
		local dir=V(math.cos(a)*.7,math.sin(a)*.7+.25,-1).Unit
		fx(ball("Spark",.03,V(0,0,f-.1),i%2==0 and {255,230,150} or {255,150,60},NEON),"Rise",{a=1.3+(i%4)*.25,b=i/10,dir=dir,amp=.38})
	end
	for i=1,3 do fx(ball("Smoke",.09,V(0,.08,f-.14),{150,140,140},SMOOTH,.55),"Rise",{a=.4,b=i/3,dir=V(0,1,-.15).Unit,amp=.5,growTo=2.6}) end
end
R.SkinLockout=function() -- RARE: a red lockout sleeve, a scissor hasp, a padlock and a tag that flutters
	local f,L,d,hd=core{body={40,40,44},trim={230,40,30},head=.46,headShape="cyl",lens={255,214,200}}
	cyl("Sleeve",.36,d+.03,.2,{210,36,28},SMOOTH)
	for _,z in {.04,.36} do cyl("SleeveLip",.025,d+.045,z,{30,30,32},SMOOTH) end
	hazardBands(hd,f+.17,.12,4,false)
	local x0=d/2+.0275
	box("HaspPlate",V(.015,.2,.14),CF(x0,-.02,-.12),{196,198,202},METAL)
	for k=0,5 do part("HaspHole",Enum.PartType.Cylinder,V(.018,.026,.026),CF(x0+.001,.05-(k%3)*.05,-.15+math.floor(k/3)*.06),{30,30,32},SMOOTH) end
	local LX,z=x0+.035,-.15
	for s=-1,1,2 do box("Shackle",V(.022,.1,.022),CF(LX-.01,-.03,z+s*.035),{200,202,206},METAL) end
	box("Shackle",V(.022,.022,.092),CF(LX-.01,.02,z),{200,202,206},METAL)
	box("Lock",V(.08,.15,.13),CF(LX,-.15,z),{230,40,30},SMOOTH)
	box("LockBase",V(.084,.03,.134),CF(LX,-.21,z),{180,182,186},METAL)
	box("Keyhole",V(.084,.035,.012),CF(LX,-.16,z),{30,30,30},SMOOTH)
	box("Cord",V(.01,.07,.01),CF(LX,-.26,z),{40,40,40},FABRIC)
	local W={wob=16,wobA=.7,wobAxis=V(0,0,1)}
	local function tag(p,py) local t=table.clone(W);t.wobPivot=V(0,py,0);fx(p,"Still",t) end
	tag(box("Tag",V(.015,.16,.1),CF(LX,-.375,z),{240,238,232},SMOOTH),.08)
	tag(box("TagStripe",V(.017,.035,.1),CF(LX,-.315,z),{230,40,30},SMOOTH),.02)
	tag(part("Grommet",Enum.PartType.Cylinder,V(.019,.025,.025),CF(LX,-.312,z),{200,202,206},METAL),.017)
end
R.SkinWarningLight=function() -- EPIC: a diamond-plate lamp carrying a rotating amber beacon
	local f,L,d,hd=core{body={52,50,46},bodyMat=DIAMOND,trim={255,170,0},head=.5,headShape="bell",lens={255,230,150}}
	hazardBands(d,.3,.2,4,false)
	for _,sx in {1,-1} do box("SideLight",V(.012,.05,.22),CF(sx*(d/2+.006),0,-.05),{255,160,20},NEON,.35) end
	for _,z in {.12,.36} do box("HandlePost",V(.04,.1,.04),CF(0,d/2+.05,z),{255,170,0},METAL) end
	box("Handle",V(.06,.04,.3),CF(0,d/2+.11,.24),{255,170,0},METAL)
	local c=V(0,d/2+.17,-.12)
	part("BeaconBase",Enum.PartType.Cylinder,V(.07,.24,.24),CF(0,d/2+.035,-.12)*CFrame.Angles(0,0,rad(90)),{200,202,206},METAL)
	part("BeaconCollar",Enum.PartType.Cylinder,V(.02,.25,.25),CF(0,d/2+.075,-.12)*CFrame.Angles(0,0,rad(90)),{30,30,30},METAL)
	ball("Dome",.23,c,{255,170,0},GLASS,.3)
	ball("Bulb",.07,c,{255,200,90},NEON,.2)
	part("DomeCap",Enum.PartType.Cylinder,V(.03,.08,.08),CF(0,d/2+.285,-.12)*CFrame.Angles(0,0,rad(90)),{30,30,30},METAL)
	fx(box("Reflector",V(.02,.1,.12),CF(c+V(0,0,.03)),{235,235,235},METAL),"Spin",{a=1.1,axis=V(0,1,0),center=c})
	for s=-1,1,2 do fx(box("BeamFan",V(.012,.05,.24),CF(c+V(0,0,s*.15)),{255,190,60},NEON,.45),"Spin",{a=1.1,axis=V(0,1,0),center=c}) end
end
R.SkinHotZone=function() -- EPIC: a containment lamp: a caged toxic vial that bubbles and breathes, a twitching pressure gauge
	local f,L,d,hd=core{body={56,58,54},trim={255,214,0},head=.48,headShape="cyl",lens={210,255,130}}
	hazardBands(d,.36,.14,3,false)
	local y=d/2+.09
	cyl("Vial",.36,.13,.02,{190,255,120},GLASS,0,y,.5)
	for _,z in {-.18,.22} do cyl("VialCap",.05,.16,z,{150,152,156},METAL,0,y) end
	for i=0,3 do local a=i*pi/2+pi/4;box("CageBar",V(.014,.014,.36),CF(math.cos(a)*.085,y+math.sin(a)*.085,.02),{255,214,0},METAL) end
	for _,z in {-.18,.22} do box("CageFoot",V(.06,.06,.04),CF(0,d/2+.03,z),{255,214,0},METAL) end
	fx(cyl("ToxicCore",.3,.06,.02,{150,255,60},NEON,0,y),"Breathe",{a=.45,amp=.3,scale=V(0,1,1)})
	for i=1,5 do fx(ball("VialBubble",.02,V(((i%3)-1)*.03,y-.045,-.12+i*.05),{220,255,180},NEON,.2),"Rise",{a=.7+(i%3)*.15,b=i/5,dir=V(0,1,0),amp=.08}) end
	local gx=d/2+.012
	part("GaugeRim",Enum.PartType.Cylinder,V(.02,.13,.13),CF(gx,0,.12),{150,152,156},METAL)
	part("GaugeFace",Enum.PartType.Cylinder,V(.024,.11,.11),CF(gx+.002,0,.12),{240,238,228},SMOOTH)
	fx(box("GaugeNeedle",V(.006,.045,.008),CF(gx+.016,.0225,.12),{220,30,30},SMOOTH),"Swing",{a=1.4,amp=25,axis=V(1,0,0),center=V(gx+.016,0,.12)})
	cyl("ValveBody",.05,.06,-.24,{150,150,150},METAL,0,y)
	box("ValveStem",V(.02,.04,.02),CF(0,y+.05,-.24),{150,150,150},METAL)
	fx(box("ValveCap",V(.06,.03,.05),CF(0,y+.085,-.24),{230,40,30},METAL),"Still",{wob=6,wobA=5,wobAxis=V(1,0,0),wobPivot=V(0,-.015,0)})
	for i=1,3 do fx(ball("Vapor",.06,V(0,y+.11,-.24),{160,255,90},SMOOTH,.55),"Rise",{a=.5,b=i/3,dir=V(0,1,.15).Unit,amp=.38,growTo=2.4}) end
end
R.SkinSiren=function() -- HAZARD KIT top prize: an emergency light bar: red/blue domes with spinning mirrors, a speaker horn, chasing amber side lights
	local f,L,d,hd=core{body={24,24,30},trim={210,210,220},head=.54,headShape="bell",lens={255,255,255},bodyMat=METAL}
	hazardBands(d,.32,.2,4,false)
	for i=1,8 do box("Rivet",V(.035,.02,.035),CFrame.Angles(0,0,(i%4)*pi/2)*CF(0,d/2+.01,-.3+i*.08),{150,150,155},METAL) end
	for _,sx in {1,-1} do for k=0,4 do
		fx(box("SideLED",V(.012,.04,.06),CF(sx*(d/2+.006),0,.3-k*.12),{255,160,20},NEON),"Chase",{a=8,n=5,i=k,offT=.8})
	end end
	local y,z=hd*.445+.075,f+.2
	box("BarBase",V(.66,.05,.18),CF(0,hd*.445+.025,z),{200,202,208},METAL)
	box("BarTrim",V(.67,.012,.19),CF(0,hd*.445+.052,z),{30,30,34},SMOOTH)
	-- speaker horn in the middle, facing forward
	box("HornBox",V(.14,.08,.1),CF(0,y,z+.02),{50,50,56},METAL)
	for k=1,3 do part("HornBell",Enum.PartType.Cylinder,V(.02,.05+k*.02,.05+k*.02),CF(0,y,z-.03-k*.02)*ALONG,{60,60,66},METAL) end
	-- two lamp domes: a lamp, a mirror turning inside it, a clear dome over both
	for _,side in {{-.2,{255,40,40},0},{.2,{60,110,255},1}} do
		local x=side[1];local c=V(x,y+.005,z)
		box("LampSocket",V(.15,.02,.15),CF(x,hd*.445+.065,z),{30,30,30},METAL)
		fx(box("Lamp",V(.07,.06,.07),CF(c),side[2],NEON),"Chase",{a=6,n=2,i=side[3],offT=.6})
		fx(box("LampMirror",V(.015,.06,.1),CF(c+V(0,0,.02)),{235,235,240},METAL),"Spin",{a=1.6,b=side[3]*.25,axis=V(0,1,0),center=c})
		part("LampDome","Ellipsoid",V(.16,.11,.16),CF(c+V(0,.01,0)),x<0 and {255,120,120} or {150,180,255},GLASS,.6)
	end
end
-- ===================== DEEP FREEZE =====================
R.SkinIcebreaker=function() -- RARE: a clean cut ice prism with an ice-axe blade and glinting points
	local f,L,d,hd=core(fz{body={186,222,244},trim={235,246,255},head=.5,lens={235,250,255}})
	for _,z in {-.25,.02,.28} do box("FrostBand",V(d*.7+.03,d*.7+.03,.03),CF(0,0,z)*CFrame.Angles(0,0,rad(45)),{240,248,255},SMOOTH) end
	local top=d*.7*.707
	wedge("PickBlade",V(.04,.12,.46),CF(0,top+.06,.02),{130,146,162},METAL)
	for _,z in {-.16,.2} do box("PickCollar",V(.07,.04,.05),CF(0,top+.01,z),{90,100,112},METAL) end
	around(6,hd*.34,f+.13,function(i,cf)
		fx(box("Point",V(.06,.2,.06),cf*CFrame.Angles(rad(-35),0,0)*CF(0,.1,0)*CFrame.Angles(0,rad(45),0),{200,236,255},ICE),"Shimmer",{a=.35,b=i/6,color={255,255,255}})
	end)
end
R.SkinSnowdrift=function() -- RARE: a puffer-jacket light with a snow cap; snow drifts down past it
	local f,L,d,hd=core{body={160,200,236},bodyMat=SMOOTH,trim={150,190,230},head=.46,headShape="bell",lens={255,255,255}}
	for i=0,4 do cyl("Puff",.13,d+.05,-.32+i*.16,{245,248,255},FABRIC) end
	part("SnowCap","Ellipsoid",V(.42,.13,.3),CF(0,hd/2+.02,f+.2),{250,252,255},SNOW)
	cyl("Cuff",.05,d+.03,L/2-.03,{200,40,50},FABRIC);cyl("Cuff",.03,d+.035,L/2-.07,{245,245,245},FABRIC)
	for i=1,10 do local x=(i%2==0) and (d/2+.1) or -(d/2+.1)
		fx(box("Snowflake",V(.05,.05,.012),CF(x,.4,-.4+(i-1)*.09)*CFrame.Angles(0,0,rad(45)),{245,250,255},NEON),"Rise",
			{a=.28+(i%3)*.06,b=i/10,dir=V(0,-1,0),amp=.62,spin=.5,spinAxis=V(0,0,1)})
	end
end
R.SkinPermafrost=function() -- EPIC: frozen bedrock with ice crystals slowly growing out of it
	local f,L,d,hd=core(fz{body={70,92,124},bodyMat=SLATE,trim={170,220,255},head=.5,lens={200,235,255}})
	for _,z in {-.3,.3} do box("FrostRing",V(d*.7+.03,d*.7+.03,.04),CF(0,0,z)*CFrame.Angles(0,0,rad(45)),{200,235,255},ICE) end
	for c=0,2 do local a=c*2.1+.4;local z=-.2+c*.2
		for k=0,2 do local len=.12+k*.04
			local cf=CF(0,0,z+(k-1)*.05)*CFrame.Angles(0,0,a+(k-1)*.35)*CF(0,d*.36,0)*CFrame.Angles(rad((k-1)*15),0,0)*CF(0,len/2,0)
			fx(box("IceCrystal",V(.06,len,.06),cf,{170,225,255},ICE),"Breathe",{a=.22,b=c*.33,amp=.28,scale=V(0,1,0),anchor=V(0,-len/2,0)})
		end
	end
end
R.SkinHailstorm=function() -- EPIC: a small storm cloud on top pelting the light with hail
	local f,L,d,hd=core{body={84,96,110},bodyMat=SLATE,trim={170,200,225},head=.48,headShape="bell",lens={225,245,255}}
	bands(L,d,2,{170,200,225})
	local cy=d/2+.3
	cloud(CF(0,cy,-.06)*CFrame.Angles(0,rad(90),0),.56,.18,.26,5,nil)
	for i=1,8 do fx(ball("Hail",.045,V(((i%3)-1)*.06,cy-.08,-.24+(i-1)*.06),{240,248,255},ICE),"Rise",{a=1.4+(i%3)*.2,b=i/8,dir=V(0,-1,0),amp=.16}) end
	for i=1,4 do ball("HailStone",.04,V((i%2==0 and 1 or -1)*.06,d/2+.005,-.25+i*.1),{235,245,255},ICE) end
end
R.SkinGlacierCore=function() -- LEGENDARY: see-through glacier ice round a glowing core, chunks drifting round the head
	local f,L,d,hd=core(fz{body={170,220,245},bodyMat=GLASS,bodyT=.45,trim={235,246,255},head=.5,lens={225,250,255}})
	fx(box("GlacierCore",V(d*.3,d*.3,L*.85),CFrame.Angles(0,0,rad(45)),{40,140,255},NEON),"Pulse",{a=.4})
	for _,z in {-.28,-.1,.08,.26} do box("Strata",V(d*.7+.012,d*.7+.012,.02),CF(0,0,z)*CFrame.Angles(0,0,rad(45)),{235,246,255},SMOOTH,.2) end
	around(4,hd/2+.13,f+.2,function(i,cf)
		fx(box("IceChunk",V(.09,.07,.08),cf*CFrame.Angles(rad(i*30),rad(i*50),0),{200,236,255},ICE),"Hover",{a=.35,b=i/4,dir=V(0,1,0),amp=.035,spin=.15,spinAxis=V(1,1,0).Unit})
	end)
end
R.SkinPolaris=function() -- LEGENDARY: the north star turning on a mast over an aurora ribbon
	local f,L,d,hd=core{body={196,212,230},bodyMat=METAL,trim={240,248,255},head=.48,headShape="bell",lens={240,250,255}}
	for i=0,17 do local t=i/17;local a=t*pi*4;local z=-L/2+.06+(L-.12)*t
		fx(box("Aurora",V(.06,.02,.07),CF(0,0,z)*CFrame.Angles(0,0,a)*CF(0,d/2+.02,0),{60,255,170},NEON),"Shimmer",{a=.3,b=-t,color={170,90,255}})
	end
	local sc=V(0,hd/2+.26,f+.16)
	seg("Mast",V(.06,hd/2-.06,f+.16),sc+V(.06,0,0),.025,{220,226,236},METAL);seg("MastPin",sc+V(.06,0,0),sc+V(.035,0,0),.02,{220,226,236},METAL)
	for k=0,7 do local l=(k%2==0) and .15 or .08
		fx(wedge("StarPoint",V(.02,l,.06),CF(sc)*CFrame.Angles(k*pi/4,0,0)*CF(0,.035+l/2,0),{235,245,255},NEON),"Turn",{a=.12,axis=V(1,0,0),center=sc})
	end
	fx(ball("StarCore",.07,sc,{255,255,255},NEON),"Pulse",{a=.6})
end
-- ===================== STORM CASE =====================
R.SkinStatic=function() -- EPIC: insulated windings with a spark hopping between two electrodes
	local f,L,d,hd=core{shape="taper",body={26,30,42},trim={90,170,255},head=.44,lens={220,240,255}}
	coil(L*.5,d,{90,170,255},3,-L*.225)
	for s=-1,1,2 do cyl("Electrode",.16,.035,L/2+.12,{200,205,215},METAL,s*.07,0);ball("ElectrodeTip",.05,V(s*.07,0,L/2+.21),{230,235,240},METAL) end
	local pts={V(-.05,0,L/2+.21),V(-.02,.03,L/2+.2),V(.01,-.02,L/2+.22),V(.05,0,L/2+.21)}
	for k=1,3 do fx(seg("Arc",pts[k],pts[k+1],.016,{200,230,255},NEON),"Chase",{a=10,n=5,i=k-1}) end
	fx(ball("ArcFlash",.05,V(0,0,L/2+.21),{200,230,255},NEON,.3),"Chase",{a=10,n=5,i=3})
end
R.SkinThunderhead=function() -- EPIC: a thundercloud riding the head; it lights up from inside and a bolt strikes the head
	local f,L,d,hd=core{shape="taper",body={52,52,68},trim={150,120,255},head=.48,headShape="bell",lens={230,220,255}}
	local cz=f+.2;local cy=hd/2+.27
	cloud(CF(0,cy,cz+.04)*CFrame.Angles(0,rad(90),0),.52,.2,.3,6,{a=.5})
	local pts={V(0,cy-.09,cz),V(.05,cy-.15,cz-.02),V(-.02,cy-.2,cz-.03),V(.03,hd/2+.005,cz-.04)}
	for k=1,3 do fx(seg("Strike",pts[k],pts[k+1],.025,{235,230,255},NEON),"Blink",{a=.5,duty=.045,offT=1}) end
end
R.SkinLightningRod=function() -- LEGENDARY: a copper spire under a small storm; the bolt travels down to it and the tip glows
	local f,L,d,hd=core{shape="taper",body={46,50,64},trim={196,118,60},head=.44,lens={235,245,255}}
	for _,z in {-.25,.05,.3} do cyl("CopperBand",.04,d+.03,z,{196,118,60},METAL) end
	local z0=f+.18;local base=hd/2
	cyl("SpireCollar",.05,.1,z0,{196,118,60},METAL,0,base+.01)
	seg("Spire",V(0,base,z0),V(0,base+.4,z0),.035,{196,118,60},METAL)
	for k=1,3 do part("Insulator",Enum.PartType.Cylinder,V(.025,.1-k*.015,.1-k*.015),CF(0,base+.06+k*.08,z0)*CFrame.Angles(0,0,rad(90)),{170,220,200},GLASS,.2) end
	fx(ball("SpireTip",.06,V(0,base+.42,z0),{220,140,80},METAL),"Blink",{a=.75,b=-.5,duty=.18,on={225,235,255}})
	local top=base+.8;local pts={}
	for k=0,6 do local t=k/6;table.insert(pts,V((k%2==0 and -1 or 1)*.06*(1-t),top-(top-base-.45)*t,z0+(k%3-1)*.03)) end
	cloud(CF(0,top+.08,z0)*CFrame.Angles(0,rad(90),0),.42,.16,.26,5,{a=.75})
	for k=1,6 do fx(seg("Bolt",pts[k],pts[k+1],.03,{225,235,255},NEON),"Chase",{a=9,n=12,i=k-1}) end
	for k=1,6 do fx(seg("BoltFlash",pts[k],pts[k+1],.06,{200,220,255},NEON,.55),"Blink",{a=.75,b=-.5,duty=.12,offT=1}) end
end
R.SkinTempest=function() -- LEGENDARY: rain pours from a storm shelf; a wind vane swings at the tail
	local f,L,d,hd=core{shape="taper",body={30,36,58},trim={120,170,230},head=.48,headShape="bell",lens={210,230,255}}
	local cy=d/2+.3
	cloud(CF(0,cy,-.05)*CFrame.Angles(0,rad(90),0),.95,.22,.32,8,{a=.18})
	for i=1,16 do local x=(i%2==0) and .27 or -.27
		fx(box("Rain",V(.012,.09,.012),CF(x+(x>0 and 1 or -1)*(i%3)*.03,cy-.12,-.36+(i-1)*.046),{170,210,255},NEON,.25),"Rise",{a=1.8+(i%4)*.25,b=i*.137,dir=V(0,-1,0),amp=.6})
	end
	local mz=L/2+.02;seg("VaneMast",V(0,d*.39,mz),V(0,d*.39+.2,mz),.025,{150,160,180},METAL)
	local pc=V(0,d*.39+.2,mz)
	for _,p in {box("VaneArrow",V(.02,.02,.22),CF(pc+V(0,.02,0)),{200,210,230},METAL),wedge("VaneTail",V(.02,.08,.07),CF(pc+V(0,.04,.11)),{120,170,230},METAL),wedge("VaneTip",V(.02,.04,.05),CF(pc+V(0,.02,-.13))*CFrame.Angles(0,pi,0),{200,210,230},METAL)} do
		fx(p,"Swing",{a=.22,amp=35,axis=V(0,1,0),center=pc})
	end
end
R.SkinSupercell=function() -- MYTHIC: a twisting tornado funnel hanging from a storm cloud
	local f,L,d,hd=core{shape="taper",body={26,20,42},trim={170,110,255},head=.5,headShape="orb",lens={180,220,255}}
	local zc=.12;local y0=d*.39
	for k=1,6 do local y=y0+.02+k*.08;local r=.03+k*.035;local n=6+k
		for i=0,n-1 do local a=i/n*pi*2
			fx(box("Funnel",V(2*pi*r/n*.75,.03,.03),CF(math.cos(a)*r,y,zc+math.sin(a)*r)*CFrame.Angles(0,-a+pi/2,0),k%2==0 and {150,140,170} or {110,100,140},SMOOTH),
				"Turn",{a=1.3-k*.15,axis=V(0,1,0),center=V(0,0,zc)})
		end
	end
	cloud(CF(0,y0+.64,zc),.72,.22,.55,7,{a=.4})
	for i=1,4 do fx(box("Debris",V(.03,.03,.03),CF(math.cos(i*1.6)*.14,y0+.11,zc+math.sin(i*1.6)*.14),{90,80,70},SMOOTH),"Turn",{a=1.6,axis=V(0,1,0),center=V(0,0,zc)}) end
end
R.SkinStormEye=function() -- MYTHIC: hurricane arms turning round a watching eye
	local f,L,d,hd=core{shape="taper",body={22,26,40},trim={90,220,255},head=.52,headShape="orb",lens={200,170,255}}
	local z=f+.1
	for arm=0,3 do for s=0,6 do
		local r0,r1=.27+s*.042,.27+(s+1)*.042;local a0,a1=arm*pi/2+s*.5,arm*pi/2+(s+1)*.5
		fx(seg("SpiralArm",V(math.cos(a0)*r0,math.sin(a0)*r0,z),V(math.cos(a1)*r1,math.sin(a1)*r1,z),.03-s*.002,s%2==0 and {90,220,255} or {200,240,255},NEON),
			"Turn",{a=.18,axis=V(0,0,1),center=V(0,0,z)})
	end end
	fx(part("Pupil",Enum.PartType.Cylinder,V(.012,.1,.1),CF(0,0,f-.012)*ALONG,{20,10,40},SMOOTH),"Look",{a=.35,amp=.05})
end
R.SkinStormbringer=function() -- STORM CASE ULTRA RARE: lightning-bolt blades charging toward a storm-crowned head
	local f,L,d,hd=core{shape="taper",body={20,26,52},trim={190,230,255},head=.58,headShape="orb",lens={235,245,255},dia=.33,bodyMat=METAL}
	-- the two bolt blades (top and bottom): energy runs from the tail to the head along them
	for _,sy in {1,-1} do
		local pts={}
		for k=0,6 do local z=L/2-k*(L-.06)/6;local r=(z>-L*.05) and d*.39 or d/2
			table.insert(pts,V(0,sy*(r+.03+(k%2==0 and .02 or .14)),z)) end
		for k=1,6 do
			fx(seg("BoltBlade",pts[k],pts[k+1],.04,{200,235,255},NEON),"Chase",{a=11,n=9,i=k-1,offT=.78})
			fx(seg("BoltGlow",pts[k],pts[k+1],.08,{120,170,255},NEON,.6),"Chase",{a=11,n=9,i=k-1,offT=1})
		end
		for k=1,7,2 do local p=pts[k];seg("Insulator",V(0,sy*(math.abs(p.Y)-.04),p.Z),V(0,sy*(math.abs(p.Y)-.01),p.Z),.03,{150,160,180},METAL) end
	end
	coil(L*.5,d,{80,130,230},2,-L*.225)
	-- a crown of storm clouds round the head: lightning flickers round it from cloud to cloud, rain falls out of it
	local cz=f+.24
	for i=0,5 do local a=i/6*pi*2
		cloud(CF(math.cos(a)*.46,math.sin(a)*.46,cz)*CFrame.Angles(0,0,a-pi/2),.3,.15,.2,3,{a=.5,b=i*.07})
	end
	for i=1,10 do local x=(i%2==0) and .46 or -.46
		fx(box("Rain",V(.012,.08,.012),CF(x+((i%3)-1)*.04,-.14,cz-.1+((i%4)-1.5)*.06),{170,210,255},NEON,.25),"Rise",{a=1.9+(i%3)*.3,b=i*.17,dir=V(0,-1,0),amp=.42})
	end
	-- the strike: a burst at the lens every few seconds
	for k=0,3 do local a=k*pi/2+pi/4
		fx(seg("StrikeRay",V(math.cos(a)*.06,math.sin(a)*.06,f-.03),V(math.cos(a)*.32,math.sin(a)*.32,f-.05),.025,{230,240,255},NEON),"Blink",{a=.42,duty=.07,offT=1})
	end
	fx(part("StrikeDisc",Enum.PartType.Cylinder,V(.01,.2,.2),CF(0,0,f-.025)*ALONG,{220,235,255},NEON,.3),"Blink",{a=.42,duty=.07,offT=1})
	local tail={V(0,0,L/2+.08),V(.06,.04,L/2+.17),V(-.03,.06,L/2+.24),V(.04,.1,L/2+.33)}
	for k=1,3 do seg("TailBolt",tail[k],tail[k+1],.035,{200,235,255},NEON) end
end
-- ===================== GOLDEN CASE (polished gold, ancient designs) =====================
local BRIGHT={255,200,60}
R.SkinGilded=function() -- LEGENDARY: polished gold with key-pattern bands; a shine sweeps along it
	local f,L,d,hd=core{body=BRIGHT,bodyMat=METAL,trim=GOLD2,trimMat=FOIL,head=.48,headShape="bell",lens={255,244,200}}
	meander(-.22,d/2+.006,10,GOLD2,FOIL);meander(.24,d/2+.006,10,GOLD2,FOIL)
	for i=0,9 do box("Flute",V(.02,.02,.2),CF(0,0,f+.2)*CFrame.Angles(0,0,i/10*pi*2)*CF(0,hd*.47,0),GOLD3,METAL) end
	for i=0,3 do box("Inlay",V(.045,.045,.045),CF(0,0,L/2+.05)*CFrame.Angles(0,0,i*pi/2)*CF(0,.1,0)*CFrame.Angles(0,0,rad(45)),{40,200,120},GLASS) end
	fx(cyl("Sheen",.05,d+.07,L/2-.06,{255,248,215},NEON,0,0,.3),"Rise",{a=.35,dir=V(0,0,-1),amp=L-.12})
end
R.SkinGoldRush=function() -- LEGENDARY: dark ore veined with gold; gold dust glitters across it
	local f,L,d,hd=core{body={44,36,32},bodyMat=BASALT,trim=GOLD,trimMat=FOIL,head=.46,lens={255,236,170}}
	for i=1,10 do local a=i*2.399
		box("GoldVein",V(.016,.012,.12+(i%3)*.06),CF(0,0,-.35+((i*.37)%1)*.7)*CFrame.Angles(0,0,a)*CF(0,d/2,0)*CFrame.Angles(0,rad((i*31)%60-30),0),BRIGHT,FOIL) end
	for i=1,9 do local a=i*2.1;ball("Nugget",.06+(i%3)*.02,V(math.cos(a)*d/2,math.sin(a)*d/2,-.4+i*.085),BRIGHT,FOIL) end
	for i=1,14 do local a=i*1.7
		fx(box("GoldDust",V(.025,.025,.025),CF(0,0,-.42+((i*.43)%1)*.84)*CFrame.Angles(0,0,a)*CF(0,d/2+.01,0)*CFrame.Angles(rad(45),0,rad(45)),{255,244,200},NEON),"Blink",{a=.35+(i%5)*.11,b=i*.17,duty=.12})
	end
	seg("PickShaft",V(d/2+.04,-.08,.25),V(d/2+.04,.12,-.05),.03,{110,72,40},WOOD)
	seg("PickHead",V(d/2+.04,.16,-.15),V(d/2+.04,.06,.06),.035,{150,150,156},METAL)
end
R.SkinCrownJewel=function() -- LEGENDARY: royal velvet, a turning crown and a breathing ruby
	local f,L,d,hd=core{body={74,24,92},bodyMat=FABRIC,trim=GOLD,trimMat=FOIL,head=.5,headShape="bell",lens={255,250,235}}
	for _,z in {-.25,.02,.28} do cyl("GoldBand",.05,d+.03,z,BRIGHT,FOIL) end
	for i=0,5 do box("BandGem",V(.04,.04,.04),CF(0,0,.02)*CFrame.Angles(0,0,i/6*pi*2)*CF(0,d/2+.02,0)*CFrame.Angles(0,0,rad(45)),i%2==0 and {40,120,255} or {40,200,120},GLASS) end
	local cz=f+.24
	cyl("Circlet",.06,hd+.1,cz,BRIGHT,FOIL)
	around(8,hd/2+.04,cz-.02,function(i,cf)
		fx(wedge("CrownPoint",V(.04,.14,.07),cf*CF(0,.07,0)*CFrame.Angles(rad(-15),0,0),BRIGHT,FOIL),"Turn",{a=.06})
		fx(ball("Pearl",.045,(cf*CF(0,.155,-.02)).Position,{250,246,236},SMOOTH),"Turn",{a=.06})
	end)
	fx(box("Ruby",V(.17,.17,.17),CF(0,0,L/2+.16)*CFrame.Angles(rad(45),rad(45),0),{220,20,60},GLASS,.1),"Breathe",{a=.45,amp=.1})
	ball("RubyHeart",.07,V(0,0,L/2+.16),{255,60,90},NEON)
	cyl("RubySeat",.04,.14,L/2+.06,BRIGHT,FOIL)
end
R.SkinMidas=function() -- GOLDEN CASE ULTRA RARE: the king's light; everything about it is gold and moving
	local f,L,d,hd=core{body={255,205,60},bodyMat=METAL,trim={255,232,140},trimMat=FOIL,head=.62,headShape="bell",lens={255,248,210},dia=.34,len=.98}
	-- 1. the golden touch: a bright wave rolls down the body, again and again
	for i=0,7 do fx(cyl("TouchRing",.08,d+.014,-L/2+.08+i*.115,{255,205,60},METAL),"Shimmer",{a=.35,b=-i/9,color={255,250,215}}) end
	-- 2. a crown of sun rays round the head, slowly turning
	for i=0,15 do local long=i%2==0
		fx(wedge("SunRay",V(.02,long and .16 or .1,.05),CF(0,0,f+.1)*CFrame.Angles(0,0,i/16*pi*2)*CF(0,hd/2+.03+(long and .08 or .05),0),long and {255,236,150} or {255,205,60},FOIL),"Turn",{a=.07})
	end
	-- 3. a ring of gems at the bezel turning the other way
	for i=0,9 do
		fx(box("BezelGem",V(.045,.045,.045),CF(0,0,f-.04)*CFrame.Angles(0,0,i/10*pi*2)*CF(0,hd/2-.01,0)*CFrame.Angles(rad(45),0,rad(45)),i%2==0 and {220,20,60} or {30,200,110},GLASS),"Turn",{a=-.12})
	end
	-- 4. a golden crown floating over the head, bobbing and turning
	local cc=V(0,hd/2+.28,f+.16)
	local crown=hoop("CrownBand",CF(cc)*CFrame.Angles(rad(90),0,0),.11,12,.03,{255,215,80},FOIL)
	for i=0,5 do local a=i/6*pi*2
		table.insert(crown,wedge("CrownPoint",V(.03,.1,.05),CF(cc+V(math.cos(a)*.11,.065,math.sin(a)*.11))*CFrame.Angles(0,-a+pi/2,0),{255,226,120},FOIL))
		table.insert(crown,ball("CrownPearl",.035,cc+V(math.cos(a)*.11,.13,math.sin(a)*.11),{255,250,240},SMOOTH))
	end
	for _,p in crown do
		fx(p,"Hover",{a=.35,dir=V(0,1,0),amp=.03,spin=.12,spinAxis=p.CFrame:VectorToObjectSpace(Vector3.yAxis),spinPivot=p.CFrame:PointToObjectSpace(cc)})
	end
	-- 5. molten gold dripping from under the head
	for i=1,3 do local x=(i-2)*.09
		part("MoltenDrip","Ellipsoid",V(.06,.1,.06),CF(x,-.225,f+.2),{255,205,60},FOIL)
		fx(ball("MoltenDrop",.045,V(x,-.29,f+.2),{255,215,80},FOIL),"Rise",{a=.55,b=i/3,dir=V(0,-1,0),amp=.28})
	end
	-- 6. coins circling the body, flipping as they go
	for i=0,5 do local a=i/6*pi*2;local z=-.2+(i%3)*.12
		fx(part("Coin",Enum.PartType.Cylinder,V(.025,.12,.12),CF(math.cos(a)*.34,math.sin(a)*.34,z)*CFrame.Angles(0,0,a),{255,215,80},FOIL),
			"Turn",{a=.25,axis=V(0,0,1),center=V(0,0,0),spin=.8,spinAxis=V(0,1,0)})
	end
	-- 7. gold dust rising off the head
	for i=1,6 do local a=i*1.05
		fx(box("GoldDust",V(.025,.025,.025),CF(math.cos(a)*.18,hd/2+.06,f+.16+math.sin(a)*.1)*CFrame.Angles(rad(45),0,rad(45)),{255,240,170},NEON),"Rise",{a=.4+(i%3)*.1,b=i/6,dir=V(0,1,0),amp=.45})
	end
	-- 8. glints across the body
	for i=1,10 do local a=i*2.399
		fx(box("Glint",V(.022,.022,.022),CF(0,0,-.42+((i*.41)%1)*.84)*CFrame.Angles(0,0,a)*CF(0,d/2+.02,0)*CFrame.Angles(rad(45),0,rad(45)),{255,252,230},NEON),"Blink",{a=.3+(i%4)*.09,b=i*.19,duty=.1})
	end
	-- 9. golden laurel wings at the tail, slowly beating
	for s=-1,1,2 do for k=1,4 do
		fx(wedge("Laurel",V(.02,.05,.16),CF(s*(d/2+.07),.04+k*.025,L/2-.05-k*.07)*CFrame.Angles(0,s*rad(25),s*rad(-(20+k*8))),k%2==0 and {255,236,150} or {255,205,60},FOIL),
			"Swing",{a=.5,amp=12,axis=V(0,0,1),center=V(s*d/2,0,0)})
	end end
	-- 10. an orb at the tail with a ruby heart that beats
	cyl("OrbSeat",.05,.16,L/2+.08,{255,232,140},FOIL)
	ball("TailOrb",.2,V(0,0,L/2+.19),{255,215,80},FOIL)
	fx(box("RubyHeart",V(.09,.09,.09),CF(0,0,L/2+.29)*CFrame.Angles(rad(45),rad(45),0),{220,20,60},GLASS,.1),"Breathe",{a=.9,amp=.15})
end
R.SkinSovereign=function() -- MYTHIC: a royal sceptre; its golden orb floats in a cradle with gems circling it
	local f,L,d,hd=core{body=BRIGHT,bodyMat=METAL,trim=GOLD2,trimMat=FOIL,head=.5,headShape="bell",lens={255,250,230}}
	for _,z in {-.18,.18} do cyl("Velvet",.14,d+.02,z,{74,20,110},FABRIC) end
	meander(0,d/2+.006,9,GOLD2,FOIL)
	for i=0,5 do wedge("CrownTip",V(.03,.08,.05),CF(0,0,f+.06)*CFrame.Angles(0,0,i/6*pi*2)*CF(0,hd/2+.06,0),GOLD2,FOIL) end
	local oz=L/2+.25
	for i=0,3 do local a=i*pi/2+pi/4;local r0,r1=.07,.12
		seg("Cradle",V(math.cos(a)*r0,math.sin(a)*r0,L/2+.05),V(math.cos(a)*r1,math.sin(a)*r1,L/2+.18),.025,GOLD2,FOIL) end
	fx(ball("Orb",.17,V(0,0,oz),BRIGHT,FOIL),"Hover",{a=.45,dir=V(0,0,1),amp=.025})
	for i=0,5 do local a=i/6*pi*2
		fx(box("OrbGem",V(.04,.04,.04),CF(math.cos(a)*.15,math.sin(a)*.15,oz)*CFrame.Angles(rad(45),rad(45),0),i%2==0 and {150,60,255} or {40,200,120},GLASS),"Turn",{a=.22,axis=V(0,0,1),center=V(0,0,oz)})
	end
end
R.SkinTreasure=function() -- GOLDEN CASE top prize: a temple relic; its sun petals open and close under a floating emerald
	local f,L,d,hd=core{body=BRIGHT,bodyMat=METAL,trim=GOLD2,trimMat=FOIL,head=.6,headShape="bell",lens={255,252,236},dia=.33,len=.95}
	for k,s in {.14,.1,.06} do box("Ziggurat",V(d+s,d+s,.05),CF(0,0,-L/2+.06+k*.06),GOLD3,METAL) end
	meander(.02,d/2+.006,10,GOLD2,FOIL);meander(.3,d/2+.006,10,GOLD2,FOIL)
	for i=0,7 do box("Jewel",V(.04,.04,.04),CF(0,0,.16)*CFrame.Angles(0,0,i/8*pi*2)*CF(0,d/2+.015,0)*CFrame.Angles(0,0,rad(45)),i%2==0 and {220,20,60} or {30,200,110},GLASS) end
	for k,s in {.2,.14,.08} do box("Step",V(s,s,.05),CF(0,0,L/2+.06+k*.05),k%2==0 and GOLD3 or BRIGHT,METAL) end
	box("Capstone",V(.08,.08,.08),CF(0,0,L/2+.27)*CFrame.Angles(rad(45),0,rad(45)),{30,200,110},GLASS)
	-- sun petals round the head: they open and close
	local pz=f+.22
	for i=0,9 do local a=i/10*pi*2
		local radial=V(-math.sin(a),math.cos(a),0);local tangent=V(math.cos(a),math.sin(a),0)
		local base=radial*(hd/2+.01)+V(0,0,pz)
		fx(wedge("SunPetal",V(.035,.18,.1),CF(0,0,pz)*CFrame.Angles(0,0,a)*CF(0,hd/2+.09,0)*CFrame.Angles(rad(-20),0,0),i%2==0 and GOLD2 or BRIGHT,i%2==0 and FOIL or METAL),
			"Swing",{a=.3,amp=18,axis=tangent,center=base})
	end
	-- floating emerald over the head
	local gc=V(0,hd/2+.3,pz)
	fx(box("Emerald",V(.15,.15,.15),CF(gc)*CFrame.Angles(rad(45),rad(45),0),{30,220,120},GLASS,.15),"Hover",{a=.4,dir=V(0,1,0),amp=.035,spin=.25,spinAxis=V(0,1,0)})
	fx(ball("EmeraldHeart",.065,gc,{90,255,160},NEON),"Hover",{a=.4,dir=V(0,1,0),amp=.035})
	for i=1,8 do local a=i*2.399
		fx(box("Glint",V(.022,.022,.022),CF(0,0,-.4+((i*.41)%1)*.8)*CFrame.Angles(0,0,a)*CF(0,d/2+.012,0)*CFrame.Angles(rad(45),0,rad(45)),{255,252,230},NEON),"Blink",{a=.3+(i%4)*.09,b=i*.19,duty=.1})
	end
end
R.SkinGoldenHour=function() -- ULTRA RARE: a sundial; the sun circles the light and the dial's shadow follows it
	local f,L,d,hd=core{body={214,140,66},bodyMat=METAL,trim=GOLD,trimMat=FOIL,head=.52,headShape="bell",lens={255,226,160}}
	for _,z in {-.28,-.05,.32} do cyl("Band",.04,d+.03,z,GOLD,FOIL) end
	local dz=.18;local dy=d/2+.09
	seg("DialPost",V(0,d/2-.01,dz),V(0,dy-.01,dz),.04,GOLD3,METAL)
	part("Dial",Enum.PartType.Cylinder,V(.025,.32,.32),CF(0,dy,dz)*CFrame.Angles(0,0,rad(90)),GOLD2,FOIL)
	for i=0,11 do box("HourMark",V(.012,.006,.035),CF(0,dy+.014,dz)*CFrame.Angles(0,i/12*pi*2,0)*CF(0,0,.13),GOLD3,METAL) end
	wedge("Gnomon",V(.012,.09,.12),CF(0,dy+.058,dz-.0),GOLD3,METAL)
	fx(box("DialShadow",V(.014,.004,.12),CF(0,dy+.022,dz+.075),{120,70,30},SMOOTH),"Turn",{a=.1,axis=V(0,1,0),center=V(0,dy,dz)})
	local sz=-.06
	fx(ball("Sun",.11,V(0,.44,sz),{255,190,70},NEON),"Turn",{a=-.1,axis=V(0,0,1),center=V(0,0,sz)})
	fx(ball("SunHalo",.2,V(0,.44,sz),{255,150,40},NEON,.75),"Turn",{a=-.1,axis=V(0,0,1),center=V(0,0,sz)})
	for i=0,13 do fx(wedge("Corona",V(.02,.08,.05),CF(0,0,f+.03)*CFrame.Angles(0,0,i/14*pi*2)*CF(0,hd/2+.07,0),BRIGHT,FOIL),"Shimmer",{a=.4,b=i/14,color={255,110,50}}) end
end
-- ===================== RUSTY CRATE =====================
R.SkinScrapMetal=function() -- COMMON: welded together from scrap: mismatched patches, weld beads, a bent guard
	local f,L,d,hd=core{body={96,74,58},bodyMat=CORRODED,trim={150,90,50},head=.44,lens={240,200,150}}
	for i=1,6 do local a=i*1.3;local z=-.35+i*.11
		local cf=CF(0,0,z)*CFrame.Angles(0,0,a)*CF(0,d/2+.008,0)
		box("Patch",V(.13,.015,.1),cf,i%2==0 and {120,80,50} or {80,84,86},METAL)
		for k=-1,1 do ball("Weld",.022,(cf*CF(k*.05,.006,.05)).Position,{60,58,56},METAL) end
	end
	seg("Guard",V(-.12,d/2,-L/2+.06),V(-.12,hd/2+.08,f+.12),.03,{70,70,72},METAL);seg("Guard",V(.12,d/2,-L/2+.06),V(.12,hd/2+.08,f+.12),.03,{70,70,72},METAL)
	seg("Guard",V(-.13,hd/2+.08,f+.12),V(.13,hd/2+.08,f+.12),.03,{70,70,72},METAL)
	for i=0,3 do cyl("Wire",.02,d+.02,.28+i*.025,{150,110,70},METAL) end
end
R.SkinToolbox=function() -- RARE: a red tool case light; its tape measure slides out and back
	local f,L,d,hd=core{shape="box",body={186,36,28},bodyMat=SMOOTH,trim={36,36,40},head=.46,headShape="box",lens={255,214,170}}
	for _,z in {-.28,.3} do box("Latch",V(.1,.03,.06),CF(0,d/2+.015,z),{200,200,205},METAL) end
	for _,z in {-.14,.16} do box("HandlePost",V(.04,.08,.04),CF(0,d/2+.04,z),{30,30,32},RUBBER) end
	box("Handle",V(.06,.04,.36),CF(0,d/2+.1,.01),{30,30,32},RUBBER)
	local tx=-(d/2+.05)
	part("TapeDrum",Enum.PartType.Cylinder,V(.09,.2,.2),CF(tx,0,.2),{250,200,30},SMOOTH)
	part("TapeHub",Enum.PartType.Cylinder,V(.095,.07,.07),CF(tx,0,.2),{30,30,32},SMOOTH)
	fx(box("TapeBlade",V(.012,.05,.36),CF(tx,-.07,-.08),{250,215,60},METAL),"Breathe",{a=.25,amp=.4,scale=V(0,0,1),anchor=V(0,0,.18)})
	local wx=d/2+.03
	box("WrenchShaft",V(.035,.03,.42),CF(wx,0,.02),{190,190,196},METAL)
	box("WrenchJaw",V(.035,.035,.05),CF(wx,.045,-.21),{190,190,196},METAL);box("WrenchJaw",V(.035,.035,.05),CF(wx,-.045,-.21),{190,190,196},METAL)
	part("WrenchRing",Enum.PartType.Cylinder,V(.035,.09,.09),CF(wx,0,.25),{190,190,196},METAL)
end
R.SkinOldTimer=function() -- EPIC: a brass miner's lamp; the warm glow wavers and the bail handle sways
	local f,L,d,hd=core{body={176,134,64},bodyMat=METAL,trim={120,88,40},head=.5,headColor={176,134,64},lens={255,220,150}}
	cyl("LeatherGrip",.42,d+.02,.1,{92,58,34},LEATHER)
	for i=0,5 do box("Stitch",V(.012,.012,.42),CF(0,0,.1)*CFrame.Angles(0,0,i/6*pi*2)*CF(0,d/2+.012,0),{200,170,120},FABRIC) end
	for i=0,5 do box("CageBar",V(.02,.02,.16),CF(0,0,f+.07)*CFrame.Angles(0,0,i/6*pi*2)*CF(0,hd/2+.02,0),{120,88,40},METAL) end
	fx(cyl("Glow",.012,hd-.16,f-.004,{255,190,110},NEON,0,0,.3),"Pulse",{a=.35})
	local hz=f+.16
	for s=-1,1,2 do part("BailStud",Enum.PartType.Cylinder,V(.04,.05,.05),CF(s*(hd/2+.01),0,hz),{120,88,40},METAL) end
	local r=hd/2+.06
	for i=0,6 do local a0,a1=i/7*pi,(i+1)/7*pi
		fx(seg("Bail",V(math.cos(a0)*r,math.sin(a0)*r,hz),V(math.cos(a1)*r,math.sin(a1)*r,hz),.02,{140,104,52},METAL),"Swing",{a=.35,amp=14,axis=V(1,0,0),center=V(0,0,hz)})
	end
end
-- ===================== MIDNIGHT CASE =====================
R.SkinMidnight=function() -- RARE: a night-sky body whose stars twinkle
	local f,L,d,hd=core{body={18,16,40},bodyMat=METAL,trim={140,110,255},head=.46,lens={215,200,255}}
	for i=1,14 do local a=i*2.399
		fx(ball("Star",.03,(CF(0,0,-.42+((i*.37)%1)*.84)*CFrame.Angles(0,0,a)*CF(0,d/2+.003,0)).Position,{235,225,255},NEON),"Blink",{a=.2+(i%5)*.07,b=i*.13,duty=.72,offT=.75})
	end
	part("MoonDisc",Enum.PartType.Cylinder,V(.01,.14,.14),CF(0,0,L/2+.085)*ALONG,{240,210,120},NEON)
	part("MoonShade",Enum.PartType.Cylinder,V(.01,.13,.13),CF(.035,.02,L/2+.092)*ALONG,{18,16,40},SMOOTH)
	cyl("NightBand",.02,d+.02,-L/2+.04,{140,110,255},NEON)
end
R.SkinNightOwl=function() -- EPIC: an owl head whose eyes look around and blink
	local f,L,d,hd=core{body={88,70,56},bodyMat=SMOOTH,trim={170,120,255},head=.54,headShape="orb",headColor={96,78,62},lens={255,214,120}}
	local hc=f+.16+.12
	for s=-1,1,2 do
		local ep=V(s*.1,.15,hc-.215)
		part("EyeRing",Enum.PartType.Cylinder,V(.01,.12,.12),CF(ep+V(0,0,.004))*ALONG,{60,48,40},SMOOTH)
		part("Eye",Enum.PartType.Cylinder,V(.012,.1,.1),CF(ep)*ALONG,{255,200,80},NEON)
		fx(part("Pupil",Enum.PartType.Cylinder,V(.012,.045,.045),CF(ep-V(0,0,.008))*ALONG,{20,14,10},SMOOTH),"Look",{a=.3,amp=.02,b=0})
		fx(part("Lid",Enum.PartType.Cylinder,V(.012,.11,.11),CF(ep-V(0,0,.016))*ALONG,{70,56,46},SMOOTH),"Blink",{a=.28,duty=.06,offT=1})
		wedge("EarTuft",V(.035,.16,.08),CF(s*.13,hd/2+.02,hc-.02)*CFrame.Angles(0,0,rad(-s*20)),{70,56,46},SMOOTH)
		for k=1,3 do wedge("Feather",V(.02,.08,.2),CF(s*(d/2+.015),.04-k*.05,.05+k*.06)*CFrame.Angles(0,0,rad(s*80)),k%2==0 and {120,96,76} or {70,56,46},SMOOTH) end
	end
	wedge("Beak",V(.04,.05,.04),CF(0,.1,hc-.26)*CFrame.Angles(rad(180),0,0),{200,150,60},SMOOTH)
end
R.SkinMoonlight=function() -- LEGENDARY: a silver moon on a crescent stand, cycling through its phases
	local f,L,d,hd=core{body={58,66,96},bodyMat=METAL,trim={205,214,240},head=.48,headShape="bell",lens={235,240,255}}
	for _,z in {-.25,.25} do cyl("SilverBand",.04,d+.03,z,{205,214,240},FOIL) end
	local mc=V(0,hd/2+.22,f+.2)
	for i=0,5 do local a0,a1=pi*1.15+i/6*pi*.7,pi*1.15+(i+1)/6*pi*.7
		seg("Crescent",mc+V(0,math.sin(a0)*.2,math.cos(a0)*.2),mc+V(0,math.sin(a1)*.2,math.cos(a1)*.2),.03,{205,214,240},FOIL) end
	seg("MoonPost",V(0,hd/2-.02,f+.2),mc-V(0,.2,0),.03,{205,214,240},FOIL)
	ball("Moon",.18,mc,{236,238,248},NEON)
	fx(ball("MoonShadow",.188,mc+V(.075,0,0),{22,26,48},SMOOTH),"Turn",{a=.09,axis=V(0,1,0),center=mc})
	for i=1,5 do local a=i*1.25
		fx(box("Star",V(.035,.035,.035),CF(mc+V(math.cos(a)*.26,math.sin(a)*.1,math.sin(a)*.2))*CFrame.Angles(0,0,rad(45)),{235,240,255},NEON),"Hover",{a=.3+i*.05,b=i/5,dir=V(0,1,0),amp=.03})
	end
end
-- ===================== ABYSSAL CASE =====================
R.SkinDeepDiver=function() -- EPIC: a brass diving helmet with portholes and a trail of rising bubbles
	local f,L,d,hd=core{body={40,46,50},bodyMat=METAL,trim={196,150,70},head=.58,headShape="orb",headColor={196,150,70},headMat=METAL,lens={170,255,230}}
	local hc=f+.28
	for s=-1,1,2 do
		part("PortRing",Enum.PartType.Cylinder,V(.03,.15,.15),CF(s*(hd/2-.02),0,hc),{150,110,40},METAL)
		part("PortGlass",Enum.PartType.Cylinder,V(.035,.11,.11),CF(s*(hd/2-.015),0,hc),{120,220,210},GLASS,.2)
	end
	for i=0,7 do local a=i/8*pi*2;cyl("CollarBolt",.03,.045,-L/2-.02,{150,110,40},METAL,math.cos(a)*(d/2+.03),math.sin(a)*(d/2+.03)) end
	local hose={V(0,d/2,L/2-.05),V(0,d/2+.12,.2),V(0,d/2+.16,-.1),V(0,hd/2+.02,hc+.08)}
	for k=1,3 do seg("AirHose",hose[k],hose[k+1],.045,{50,50,52},RUBBER) end
	cyl("Vent",.06,.06,hc,{150,110,40},METAL,0,hd/2+.02)
	for i=1,7 do fx(ball("Bubble",.04+(i%3)*.015,V(((i%3)-1)*.03,hd/2+.07,hc),{200,255,250},GLASS,.3),"Rise",{a=.4+(i%4)*.06,b=i/7,dir=V(0,1,0),amp=.42,growTo=1.4}) end
end
R.SkinLeviathan=function() -- LEGENDARY: a sea serpent; its dorsal fins ripple in a wave
	local f,L,d,hd=core{shape="taper",body={14,52,58},trim={30,220,200},head=.5,headShape="bell",lens={180,255,240}}
	for i=1,14 do wedge("Scale",V(.08,.035,.1),CF(0,0,-.42+(i%7)*.12)*CFrame.Angles(0,0,(i>7 and 1 or -1)*1.4+(i%2)*.3)*CF(0,d*.42,0),{20,120,120},SMOOTH) end
	for k=0,5 do local z=.32-k*.12;local r=(z>-.05) and d*.39 or d/2
		fx(wedge("DorsalFin",V(.025,.14,.11),CF(0,r+.07,z),{30,190,170},SMOOTH),"Still",{wob=14,wobA=.9,b=-k*.12,wobAxis=V(0,0,1),wobPivot=V(0,-.07,0)})
	end
	for s=-1,1,2 do wedge("Frill",V(.02,.12,.14),CF(s*(hd/2+.02),0,f+.24)*CFrame.Angles(0,0,rad(s*90)),{30,220,200},NEON);ball("SerpentEye",.04,V(s*.13,.08,f+.1),{255,230,80},NEON) end
end
R.SkinTrench=function() -- LEGENDARY: an anglerfish; its glowing lure bobs in front, its spots pulse
	local f,L,d,hd=core{body={14,16,24},bodyMat=METAL,trim={40,130,210},head=.54,headShape="bell",headColor={20,24,34},lens={120,230,255}}
	around(12,hd/2-.01,f+.04,function(i,cf) wedge("Tooth",V(.025,.06,.05),cf*CF(0,.02,0)*CFrame.Angles(rad(-60),0,0),{235,230,215},SMOOTH) end)
	for i=1,10 do local a=i*2.399
		fx(ball("Biolume",.035,(CF(0,0,-.4+((i*.37)%1)*.8)*CFrame.Angles(0,0,a)*CF(0,d/2+.004,0)).Position,{60,240,255},NEON),"Pulse",{a=.3,b=i*.11})
	end
	local p={V(0,hd/2,f+.24),V(0,hd/2+.16,f+.18),V(0,hd/2+.2,f+.02),V(0,hd/2+.14,f-.12)}
	for k=1,3 do seg("LureStalk",p[k],p[k+1],.025,{30,34,46},SMOOTH) end
	box("LureCord",V(.01,.06,.01),CF(p[4]-V(0,.03,0)),{30,34,46},SMOOTH)
	fx(ball("LureBulb",.08,p[4]-V(0,.1,0),{120,255,240},NEON),"Hover",{a=.55,dir=V(0,1,0),amp=.03})
	fx(ball("LureShell",.11,p[4]-V(0,.1,0),{150,240,255},GLASS,.6),"Hover",{a=.55,dir=V(0,1,0),amp=.03})
end
R.SkinUndertow=function() -- MYTHIC: currents race along the body into a turning tail screw
	local f,L,d,hd=core{body={12,30,44},bodyMat=METAL,trim={60,220,200},head=.5,headShape="bell",lens={160,170,255}}
	for i=0,11 do local a=i/12*pi*2
		fx(box("Current",V(.02,.015,.12),CF(0,0,-L/2+.08)*CFrame.Angles(0,0,a)*CF(0,d/2+.045,0),i%2==0 and {60,240,220} or {150,160,255},NEON,.2),"Rise",{a=.35+(i%3)*.08,b=i/12,dir=V(0,0,1),amp=L-.18})
	end
	cyl("ScrewHub",.08,.12,L/2+.12,{60,220,200},METAL)
	for i=0,4 do local a=i/5*pi*2
		fx(box("ScrewBlade",V(.13,.02,.06),CF(0,0,L/2+.12)*CFrame.Angles(0,0,a)*CF(.09,0,0)*CFrame.Angles(rad(30),0,0),{40,180,170},METAL),"Turn",{a=.6,axis=V(0,0,1),center=V(0,0,L/2+.12)})
	end
end
M.Recipes=R
local function make(name,fn)
	local m=Instance.new("Model");m.Name=name;cur=m
	local ok,err=pcall(fn,m);cur=nil
	if not ok then m:Destroy();return nil,err end
	m.WorldPivot=CFrame.new();m:SetAttribute("BuiltBy","CaseFlashlights Nov15")
	return m
end
function M.Build(folder)
	local fails={};local n=0
	for name,fn in R do
		local m,err=make(name,fn)
		if m then local old=folder:FindFirstChild(name);if old then old:Destroy() end;m.Parent=folder;n+=1 else table.insert(fails,name..": "..tostring(err)) end
	end
	return n.." built, "..#fails.." failed "..table.concat(fails," | ")
end
-- ===================== CASE ART (box format, like the Rusty Crate / Midnight / Abyssal cases) =====================
-- A glass display box about 2.2 x 1.9 x 1.7, glass at the front (-Z), a back panel, a base with a glowing floor and
-- a pedestal; the case's top flashlight stands on the pedestal. Each case dresses the box in its own theme.
local SKINS
local W,H,D=1.095,.9,.845
local function prize(m,skin)
	local src=SKINS:FindFirstChild(skin);if not src then return end
	local p=src:Clone();p.Name="Prize";p.Parent=m
	local _,sz=p:GetBoundingBox();local big=math.max(sz.X,sz.Y,sz.Z);if big>1.3 then p:ScaleTo(p:GetScale()*1.3/big) end
	p:PivotTo(CFrame.new(0,0,0)*CFrame.Angles(rad(72),rad(-28),0))
	-- stand it on the pedestal (lowest point of any part = pedestal top)
	local low=math.huge
	for _,x in p:GetDescendants() do if x:IsA("BasePart") then
		local c,s=x.CFrame,x.Size/2
		local ext=math.abs(c.RightVector.Y)*s.X+math.abs(c.UpVector.Y)*s.Y+math.abs(c.LookVector.Y)*s.Z
		low=math.min(low,c.Position.Y-ext) end end
	p:PivotTo(p:GetPivot()+V(0,-.69-low+.01,0))
end
local function frame(t)
	local em=t.edgeMat or METAL
	for _,x in {-W,W} do for _,z in {-D,D} do box("Edge",V(.11,2*H,.11),CF(x,0,z),t.edge,em) end end
	for _,y in {-H,H} do
		for _,z in {-D,D} do box("Edge",V(2*W-.11,.11,.11),CF(0,y,z),t.edge,em) end
		for _,x in {-W,W} do box("Edge",V(.11,.11,2*D-.11),CF(x,y,0),t.edge,em) end
	end
	for _,x in {-W,W} do for _,y in {-H,H} do for _,z in {-D,D} do box("CornerCap",V(.16,.16,.16),CF(x,y,z),t.cap,t.capMat or METAL) end end end
	box("Glass",V(2*W-.11,2*H-.11,.035),CF(0,0,-D),t.glass,GLASS,t.glassT or .6)
	for _,x in {-W,W} do box("Glass",V(.035,2*H-.11,2*D-.11),CF(x,0,0),t.glass,GLASS,t.glassT or .6) end
	box("BackPanel",V(2*W-.11,2*H-.11,.03),CF(0,0,D),t.back,t.backMat or SMOOTH)
	box("Base",V(2*W-.11,.05,2*D-.11),CF(0,-H+.025,0),t.base,t.baseMat or METAL)
	box("FloorGlow",V(1.86,.02,1.4),CF(0,-H+.06,0),t.glow,NEON,.4)
	part("Pedestal",Enum.PartType.Cylinder,V(.14,.62,.62),CF(0,-.76,0)*CFrame.Angles(0,0,rad(90)),t.ped or t.edge,t.pedMat or METAL)
	part("PedestalRing",Enum.PartType.Cylinder,V(.03,.68,.68),CF(0,-.72,0)*CFrame.Angles(0,0,rad(90)),t.accent,NEON)
	for _,x in {-W+.09,W-.09} do box("LightStrip",V(.03,2*H-.2,.03),CF(x,0,-D+.08),t.accent,NEON,.1) end
	box("Glint",V(.14,1.5,.004),CF(-.4,.05,-D-.022)*CFrame.Angles(0,0,rad(-31)),{255,255,255},SMOOTH,.8)
end
local B={}
B.BoxFlame=function(m) -- FLAME CASE: an obsidian reliquary with gold claw corners, lava-cracked edges and four braziers on top
	frame{edge={28,18,14},edgeMat=BASALT,cap={255,186,70},capMat=FOIL,glass={255,190,140},glassT=.72,back={20,12,10},backMat=BASALT,base={30,20,16},baseMat=BASALT,glow={255,100,20},accent={255,120,30},ped={30,20,16},pedMat=BASALT}
	-- lava cracks down the front pillars and across the base
	for _,x in {-W,W} do for k=0,5 do box("LavaCrack",V(.02,.18,.012),CF(x+((k%2)-.5)*.03,-.75+k*.3,-D-.056)*CFrame.Angles(0,0,rad((k%2==0) and 20 or -20)),{255,100,20},NEON) end end
	for k=0,8 do box("LavaCrack",V(.16,.02,.012),CF(-.9+k*.225,-H+((k%2)-.5)*.03,-D-.056)*CFrame.Angles(0,0,rad((k%2==0) and 12 or -12)),{255,100,20},NEON) end
	-- ember grate on the back panel, glowing through
	for k=0,5 do fx(box("EmberGrate",V(1.6,.04,.02),CF(0,-.5+k*.2,D-.03),{255,90,20},NEON,.2),"Shimmer",{a=.3,b=k/6,color={150,30,10}}) end
	-- four gold braziers on the roof corners, each burning
	for _,x in {-W,W} do for _,z in {-D,D} do
		part("BrazierBowl",Enum.PartType.Cylinder,V(.1,.24,.24),CF(x,H+.13,z)*CFrame.Angles(0,0,rad(90)),{255,186,70},FOIL)
		for k=1,3 do local s=1-(k-1)*.28
			fx(part("Flame","Ellipsoid",V(.17*s,.15*s,.42*s),CF(x+((k%2)-.5)*.03,H+.17+.21*s,z)*UP,k==1 and {255,70,15} or (k==2 and {255,150,30} or {255,235,170}),NEON),"Flicker",.55+k*.15+x*.05)
		end
	end end
	-- gold crest on the front top with an ember gem
	box("CrestPlate",V(.5,.18,.03),CF(0,H,-D-.06),{255,186,70},FOIL)
	fx(box("CrestGem",V(.12,.12,.04),CF(0,H,-D-.08)*CFrame.Angles(0,0,rad(45)),{255,90,20},NEON),"Pulse",{a=.6})
	for i=1,6 do fx(ball("Ember",.035,V(-.6+i*.17,-.8,-.3+((i*7)%5)*.15),{255,170,60},NEON),"Rise",{a=.25+(i%3)*.06,b=i/6,dir=V(0,1,0),amp=1.4}) end
	prize(m,"SkinEverflame")
end
B.BoxHazard=function(m) -- HAZARD KIT: a containment box in diamond plate with striped pillars, wired glass and twin beacons
	frame{edge={255,196,0},cap={24,24,24},capMat=RUBBER,glass={230,230,200},glassT=.68,back={86,88,90},backMat=DIAMOND,base={86,88,90},baseMat=DIAMOND,glow={255,190,40},accent={255,190,40},ped={60,62,64}}
	for _,x in {-W,W} do for _,z in {-D,D} do for k=0,4 do box("PillarStripe",V(.115,.17,.115),CF(x,-.68+k*.34,z),{24,24,24},SMOOTH) end end end
	for k=1,7 do box("Wire",V(.006,2*H-.12,.006),CF(-W+k*.27,0,-D-.022),{60,60,60},METAL) end
	for k=1,5 do box("Wire",V(2*W-.12,.006,.006),CF(0,-H+k*.3,-D-.022),{60,60,60},METAL) end
	for k=0,9 do box("Kickplate",V(.2,.12,.02),CF(-.9+k*.2,-H+.11,-D-.065),k%2==0 and {255,196,0} or {24,24,24},SMOOTH) end
	for _,x in {-.65,.65} do
		local c=V(x,H+.2,0)
		part("BeaconBase",Enum.PartType.Cylinder,V(.08,.26,.26),CF(x,H+.08,0)*CFrame.Angles(0,0,rad(90)),{30,30,30},METAL)
		ball("BeaconDome",.24,c,{255,170,0},GLASS,.35)
		fx(box("BeaconMirror",V(.02,.12,.14),CF(c),{235,235,235},METAL),"Spin",{a=1,b=x>0 and .5 or 0,axis=V(0,1,0),center=c})
		for s=-1,1,2 do fx(box("BeaconBeam",V(.012,.06,.3),CF(c+V(0,0,s*.17)),{255,190,60},NEON,.45),"Spin",{a=1,b=x>0 and .5 or 0,axis=V(0,1,0),center=c}) end
	end
	part("StopButtonGuard",Enum.PartType.Cylinder,V(.05,.26,.26),CF(0,H+.08,0)*CFrame.Angles(0,0,rad(90)),{255,196,0},METAL)
	part("StopButton",Enum.PartType.Cylinder,V(.08,.16,.16),CF(0,H+.11,0)*CFrame.Angles(0,0,rad(90)),{230,40,30},SMOOTH)
	prize(m,"SkinSiren")
end
B.BoxFreeze=function(m) -- DEEP FREEZE: a frozen box: ice pillars, icicles, frosted corners, snow on the floor, cold mist
	frame{edge={190,230,250},edgeMat=ICE,cap={240,250,255},capMat=SNOW,glass={200,236,255},glassT=.55,back={40,90,140},backMat=GLACIER,base={245,248,255},baseMat=SNOW,glow={120,220,255},accent={140,230,255},ped={170,220,245},pedMat=ICE}
	for i=0,13 do local x=-W+.15+i*.145;local l=.1+((i*7)%5)*.05
		box("Icicle",V(.05,l,.05),CF(x,H-.055-l/2,-D-.04)*CFrame.Angles(0,rad(45),0),{210,240,255},ICE)
		box("IcicleTip",V(.025,.05,.025),CF(x,H-.055-l-.02,-D-.04)*CFrame.Angles(0,rad(45),0),{230,248,255},ICE) end
	for _,x in {-1,1} do for _,y in {-1,1} do wedge("FrostCorner",V(.01,.22,.22),CF(x*(W-.17),y*(H-.17),-D-.025)*CFrame.Angles(0,rad(90),0)*CFrame.Angles(y>0 and pi or 0,0,0)*CFrame.Angles(0,x*y>0 and pi or 0,0),{235,248,255},SNOW) end end
	for _,x in {-W,W} do part("SnowRidge","Ellipsoid",V(.24,.1,1.7),CF(x,H+.06,0),{248,250,255},SNOW) end
	for _,z in {-D,D} do part("SnowRidge","Ellipsoid",V(2.2,.1,.24),CF(0,H+.06,z),{248,250,255},SNOW) end
	for c=0,3 do local x=(c%2==0 and -1 or 1)*.75;local z=(c<2 and -1 or 1)*.5
		for k=0,2 do box("FloorCrystal",V(.08,.18+k*.06,.08),CF(x+(k-1)*.07,-H+.12+k*.03,z)*CFrame.Angles(rad((k-1)*15),rad(45),rad((k-1)*12)),{180,230,255},ICE) end end
	for i=1,6 do fx(ball("ColdMist",.16,V(-.6+i*.17,-.8,-.2+((i*3)%4)*.15),{235,248,255},SMOOTH,.7),"Rise",{a=.15+(i%3)*.04,b=i/6,dir=V(0,1,0),amp=.9,growTo=2.2}) end
	prize(m,"SkinAbsoluteZero")
end
B.BoxStorm=function(m) -- STORM CASE: a storm chamber: a thundercloud on the roof strikes copper terminals; rain falls inside
	frame{edge={40,42,56},cap={196,118,60},glass={170,190,255},glassT=.62,back={14,16,30},base={30,32,44},glow={140,120,255},accent={160,140,255},ped={196,118,60}}
	for _,x in {-W,W} do for _,z in {-D,D} do for k=0,2 do part("Insulator",Enum.PartType.Cylinder,V(.04,.16,.16),CF(x,-.4+k*.4,z)*CFrame.Angles(0,0,rad(90)),{170,220,200},GLASS,.2) end end end
	-- thundercloud on the roof: lights up from inside as the bolt strikes
	cloud(CF(0,H+.25,0),2.0,.46,1.3,9,{a=.714})
	-- the bolt: down from the roof to the back-left terminal
	local pts={V(-.55,H-.08,.55),V(-.45,.5,.6),V(-.62,.2,.55),V(-.5,-.1,.6),V(-.66,-.4,.55),V(-.58,-.8,.58)}
	for k=1,5 do
		fx(seg("Bolt",pts[k],pts[k+1],.035,{230,235,255},NEON),"Chase",{a=10,n=14,i=k-1})
		fx(seg("BoltFlash",pts[k],pts[k+1],.08,{180,170,255},NEON,.5),"Blink",{a=.714,b=-.36,duty=.1,offT=1})
	end
	ball("Terminal",.1,V(-.58,-.82,.58),{196,118,60},METAL)
	-- rain inside the back of the box
	for i=1,14 do fx(box("Rain",V(.012,.12,.012),CF(-.8+i*.12,H-.12,.62+((i%3)-1)*.06),{170,210,255},NEON,.3),"Rise",{a=1.2+(i%4)*.18,b=i*.137,dir=V(0,-1,0),amp=1.55}) end
	for k=0,5 do part("PedestalCoil",Enum.PartType.Cylinder,V(.02,.66,.66),CF(0,-.82+k*.02,0)*CFrame.Angles(0,0,rad(90)),{196,118,60},METAL) end
	prize(m,"SkinStormbringer")
end
B.BoxGolden=function(m) -- GOLDEN CASE: an ancient golden reliquary (Midas, the top prize, inside): fluted pillars, key-pattern friezes, a turning sun disc and a stepped roof
	frame{edge={255,200,60},cap={220,20,60},capMat=GLASS,glass={255,245,210},glassT=.7,back={140,96,24},base={255,200,60},glow={255,210,90},accent={255,226,120},ped={255,200,60}}
	-- fluted pillars: capitals and feet on each front pillar
	for _,x in {-W,W} do for _,z in {-D,D} do
		for _,y in {-H+.14,H-.14} do box("PillarCapital",V(.18,.06,.18),CF(x,y,z),GOLD2,FOIL) end
		for k=0,2 do box("Flute",V(.012,1.5,.012),CF(x+(k-1)*.035,0,z-.057),GOLD3,METAL) end
	end end
	-- key-pattern frieze along the front top and bottom
	for _,y in {H,-H} do for i=0,9 do local x=-.9+i*.2
		box("Frieze",V(.12,.016,.012),CF(x,y+.03,-D-.058),GOLD2,FOIL);box("Frieze",V(.016,.06,.012),CF(x+.06,y,-D-.058),GOLD2,FOIL);box("Frieze",V(.07,.016,.012),CF(x+.025,y-.03,-D-.058),GOLD2,FOIL)
	end end
	-- sun disc on the back panel, turning slowly
	local sc=V(0,.1,D-.04)
	part("SunDisc",Enum.PartType.Cylinder,V(.03,.62,.62),CF(sc)*ALONG,GOLD2,FOIL)
	for i=0,15 do fx(wedge("SunRay",V(.02,.2,.07),CF(sc)*CFrame.Angles(0,0,i/16*pi*2)*CF(0,.42,0),i%2==0 and GOLD2 or {255,200,60},FOIL),"Turn",{a=.05,axis=V(0,0,1),center=sc}) end
	-- stepped (ziggurat) roof with a gem at the top
	for k=0,2 do local s=1-k*.28;box("RoofStep",V(2.1*s,.1,1.6*s),CF(0,H+.1+k*.1,0),k%2==0 and {255,200,60} or GOLD2,k%2==0 and METAL or FOIL) end
	fx(box("ApexGem",V(.2,.2,.2),CF(0,H+.48,0)*CFrame.Angles(rad(45),rad(45),0),{30,220,120},GLASS,.1),"Breathe",{a=.4,amp=.1})
	ball("ApexHeart",.08,V(0,H+.48,0),{90,255,160},NEON)
	-- coins and gold bars on the floor
	for i=1,14 do local a=i*2.399;local r=.45+((i*13)%5)*.1
		part("Coin",Enum.PartType.Cylinder,V(.025,.14,.14),CF(math.cos(a)*r,-H+.075,math.sin(a)*r*.75)*CFrame.Angles(0,0,rad(90)),GOLD2,FOIL) end
	for i=1,3 do box("GoldBar",V(.3,.08,.13),CF(.55,-H+.09+((i-1)%2)*.08,-.35+i*.14)*CFrame.Angles(0,rad(10),0),{255,200,60},FOIL) end
	for i=1,8 do fx(box("Glint",V(.04,.04,.04),CF(math.cos(i)*.85,-.6+((i*7)%9)*.15,math.sin(i)*.55)*CFrame.Angles(rad(45),0,rad(45)),{255,250,225},NEON),"Blink",{a=.4+(i%3)*.1,b=i*.2,duty=.1}) end
	prize(m,"SkinMidas")
end
function M.BuildBoxes(boxFolder,skinFolder)
	SKINS=skinFolder
	local fails={};local n=0
	for name,fn in B do
		local m=Instance.new("Model");m.Name=name;cur=m
		local ok,err=pcall(fn,m)
		cur=nil
		if ok then m.WorldPivot=CFrame.new();m:SetAttribute("BuiltBy","CaseArt Nov15");local old=boxFolder:FindFirstChild(name);if old then old:Destroy() end;m.Parent=boxFolder;n+=1
		else m:Destroy();table.insert(fails,name..": "..tostring(err)) end
	end
	return n.." cases built, "..#fails.." failed "..table.concat(fails," | ")
end
return M
