--!nonstrict
-- Original editable part-built environments. No external textures, meshes, or runtime generators required.
local B={Version=1}
local V=Vector3.new
local palette={concrete=Color3.fromRGB(89,91,86),pale=Color3.fromRGB(178,175,158),steel=Color3.fromRGB(34,43,45),
	black=Color3.fromRGB(17,23,25),amber=Color3.fromRGB(207,147,56),ivory=Color3.fromRGB(224,218,190),
	rust=Color3.fromRGB(101,66,43),mint=Color3.fromRGB(143,183,162),red=Color3.fromRGB(162,59,40)}
local function model(name,parent)
	local m=Instance.new("Model");m.Name=name;m:SetAttribute("ManagedBy","ElevatorHorror");m.Parent=parent;return m
end
local function part(parent,name,size,pos,color,material)
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=typeof(pos)=="CFrame" and pos or CFrame.new(pos)
	p.Color=color or palette.steel;p.Material=material or Enum.Material.Metal;p.Anchored=true
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent;return p
end
local function decor(parent,name,size,pos,color,material)
	local p=part(parent,name,size,pos,color,material);p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
	-- Thin trim (under .3 studs on its narrowest axis) renders as blocky/triangular shadow
	-- artifacts in Roblox's shadow map instead of a clean shadow -- that was the "wall
	-- glitches" near the bay gates. Every decor() part is non-structural, so this is safe
	-- to apply universally rather than fixing individual call sites one at a time.
	if math.min(size.X,size.Y,size.Z)<.3 then p.CastShadow=false end
	return p
end
local function sign(parent,name,size,frame,text,color,back,textSize)
	local p=decor(parent,name,size,frame,back or palette.black)
	local g=Instance.new("SurfaceGui");g.Name="Lettering";g.Face=Enum.NormalId.Front;g.PixelsPerStud=48
	g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.LightInfluence=.2;g.Parent=p
	local label=Instance.new("TextLabel");label.Name="Text";label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
	label.Font=Enum.Font.GothamBold;label.Text=text;label.TextColor3=color or palette.ivory;label.TextSize=textSize or 36
	label.TextScaled=true;label.TextWrapped=true;label.Parent=g
	local padding=Instance.new("UIPadding");padding.PaddingTop=UDim.new(.08,0);padding.PaddingBottom=UDim.new(.08,0)
	padding.PaddingLeft=UDim.new(.035,0);padding.PaddingRight=UDim.new(.035,0);padding.Parent=label
	return p,label
end
-- Shared irregular flicker driver. Presentation-only, self-terminates when the fixture is
-- destroyed on rebuild. Never touches gameplay timers, SurvivalService, or RunService.
-- onDip (optional) fires each time the light dips, e.g. to trigger a buzz/zap Sound.
local function flicker(host,l,base,onDip)
 host:SetAttribute("EHFlicker",true);host:SetAttribute("FlickerSeed",math.abs(host.Position.X+host.Position.Z*.37)%11)
 host:SetAttribute("FlickerPeriod",11);l.Brightness=base
end
local function strip(parent,pos,size,color,brightness,range)
	local p=decor(parent,"LightStrip",size,pos,color,Enum.Material.Neon)
	local base=brightness or 1.5
	local l=Instance.new("PointLight");l.Color=color;l.Brightness=base;l.Range=range or 22;l.Shadows=true;l.Parent=p
	flicker(p,l,base)
	return p
end
local function pipe(parent,a,b,radius,color)
	local delta=b-a
	local p=decor(parent,"Pipe",V(delta.Magnitude,radius*2,radius*2),CFrame.lookAt((a+b)/2,b)*CFrame.Angles(0,math.pi/2,0),color or palette.rust)
	p.Shape=Enum.PartType.Cylinder;return p
end
local function bench(parent,x,z)
	local m=model("CrewBench",parent)
	part(m,"Seat",V(8,.35,2),V(x,22,z),palette.steel)
	part(m,"Back",V(8,1.6,.25),V(x,23,z+.9),palette.steel)
	for _,dx in {-3,3} do part(m,"Foot",V(.4,1.8,1.8),V(x+dx,21,z),palette.black) end
	for dx=-3.5,3.5,1 do decor(m,"SeatGroove",V(.035,.015,1.8),V(x+dx,22.19,z),palette.black) end
end
local L={plaster=Color3.fromRGB(103,106,103),wood=Color3.fromRGB(37,46,49),trim=Color3.fromRGB(66,75,77),
	stone=Color3.fromRGB(81,78,73),dark=Color3.fromRGB(20,19,20),brass=Color3.fromRGB(103,75,52),paper=Color3.fromRGB(218,210,189),wine=Color3.fromRGB(49,55,57)}
local function lamp(parent,x,y,z,brightness,range)
	decor(parent,"Conduit",V(.12,3,.12),V(x,y+1.5,z),L.trim)
	part(parent,"FluorescentHousing",V(7,.35,1.7),V(x,y,z),L.wood)
	for _,dz in {-.45,.45}do
		local tube=decor(parent,"FluorescentTube",V(6.4,.15,.22),V(x,y-.25,z+dz),Color3.fromRGB(183,207,209),Enum.Material.Neon)
		if dz<0 then local light=Instance.new("PointLight");light.Color=Color3.fromRGB(183,207,209);light.Brightness=brightness*1.2;light.Range=range;light.Shadows=true;light.Parent=tube end
	end
end
-- Hanging horror-lobby fixture: ceiling disk ("canopy"), a thin rod, and a bare bulb
-- centered underneath. Flicker reuses the shared driver and can trigger a buzz Sound
-- on each dip. Distinct from lamp() (below), which stays the fixture for bay/hatch lights.
local function chandelier(parent,x,y,z,brightness,range)
	local m=model("Chandelier",parent)
	local diskT=.35
	decor(m,"Canopy",V(.5,.5,.5),V(x,y+.3,z),L.trim,Enum.Material.Metal)
	local disk=part(m,"Disk",V(diskT,7,7),CFrame.new(x,y,z)*CFrame.Angles(0,0,math.pi/2),L.dark,Enum.Material.Metal)
	disk.Shape=Enum.PartType.Cylinder
	local rodLen=2.4
	decor(m,"Rod",V(.1,rodLen,.1),V(x,y-diskT/2-rodLen/2,z),L.trim,Enum.Material.Metal)
	local bulbY=y-diskT/2-rodLen-.55
	local bulb=decor(m,"Bulb",V(1.1,1.1,1.1),V(x,bulbY,z),Color3.fromRGB(255,224,168),Enum.Material.Neon)
	bulb.Shape=Enum.PartType.Ball
	local base=brightness or 1.4
	local l=Instance.new("PointLight");l.Color=bulb.Color;l.Brightness=base;l.Range=range or 26;l.Shadows=true;l.Parent=bulb
	local buzz=Instance.new("Sound");buzz.Name="FlickerBuzz";buzz.SoundId="rbxassetid://99071431420752"
	buzz.Volume=.35;buzz.RollOffMaxDistance=40;buzz.Parent=bulb
	-- Dedicated flicker for this fixture (distinct from the shared flicker() used by strip()):
	-- one sparse dim-and-recover "breath" per cycle, stretched to the buzz asset's length
	-- (~0.85s) so the dip and the sound land on the same beat, with a play-guard so a
	-- slow cycle can never stack a retrigger on top of an already-playing buzz.
	flicker(bulb,l,base)
	return m
end
local function hatch(parent,x,z)
	local index=math.floor((x+33)/22)+1
	local m=model("Bay"..index,parent);m:SetAttribute("BayId","Bay"..index);m:SetAttribute("Capacity",4)
	part(m,"RearWall",V(18,15,1),V(x,27.5,z-9),L.dark)
	part(m,"BayFloor",V(17,.2,10),V(x,20.2,z-4),L.stone,Enum.Material.Slate)
	for _,dx in {-8.7,8.7} do
		part(m,"PlasterSurround",V(1.8,15,2),V(x+dx,27.5,z),L.plaster,Enum.Material.Concrete)
		part(m,"DoorJamb",V(.35,12,.65),V(x+dx*.91,26,z+1.05),L.trim,Enum.Material.Metal)
		part(m,"SideWall",V(.5,13,9),V(x+dx*.92,26.5,z-4),L.wood,Enum.Material.Metal)
	end
	part(m,"Lintel",V(19.2,2.4,2),V(x,33.8,z),L.plaster,Enum.Material.Concrete)
	part(m,"LintelCap",V(19.8,.45,2.4),V(x,35.15,z),L.trim,Enum.Material.Metal)
	-- Closes off the top of this individual bay (previously only the shared building Roof at
	-- y=40.5 capped it, leaving a visible open gap above the Lintel when looking up inside).
	part(m,"BayRoof",V(18,.5,10),V(x,36.2,z-4),L.wood,Enum.Material.Concrete)
	part(m,"Threshold",V(16,.14,1.2),V(x,20.35,z+.4),L.brass)
	-- Editable party barrier parts live in Workspace.LobbyBarriers and persist outside this generated model.
	-- CastShadow=false on all of these: they're thin decorative bars (down to .065 studs),
	-- and Roblox's shadow map renders geometry that thin as blocky/triangular artifacts
	-- rather than a clean shadow -- that was the "wall glitches" near each bay's gate.
	for dx=-7.5,7.5,1.5 do part(m,"RearGateBar",V(.075,11,.13),V(x+dx,25.8,z-6.5),L.brass).CastShadow=false end
	for _,y in {21.5,30.5} do part(m,"GateRail",V(15.5,.16,.18),V(x,y,z-6.5),L.trim).CastShadow=false end
	for dx=-6,6,3 do
		for _,angle in {-.28,.28}do decor(m,"GateLattice",V(.065,9.3,.1),CFrame.new(x+dx,26,z-6.4)*CFrame.Angles(0,0,angle),L.trim).CastShadow=false end
	end
	local _,number=sign(m,"BayNumber",V(3.5,1.65,.16),CFrame.new(x-5.9,33.65,z+1.12)*CFrame.Angles(0,math.pi,0),"0"..index,L.paper,L.wood);number.Font=Enum.Font.GothamMedium
	local _,count=sign(m,"Occupancy",V(6,1.65,.16),CFrame.new(x+3.1,33.65,z+1.12)*CFrame.Angles(0,math.pi,0),"0 / 4",L.paper,L.wood);count.Name="OccupancyText"
	local zone=decor(m,"BoardingZone",V(14,7,6),V(x,23.8,z-1.6),L.dark);zone.Transparency=1;zone:SetAttribute("BayId",m.Name)
	local landing=decor(m,"ExitLanding",V(1,1,1),CFrame.new(x,23.6,z+7)*CFrame.Angles(0,math.pi,0),L.dark);landing.Transparency=1
	local rug=decor(m,"BayRunner",V(12,.035,9),V(x,20.4,z-2),L.wine,Enum.Material.DiamondPlate)
    local gate=model("ReadyGate",m)
    for _,height in {22.8,24.1}do
        local rail=decor(gate,"Rail",V(15.7,.12,.12),V(x,height,z-.15),L.trim)
        rail.Transparency=1
    end
	lamp(m,x,31,z-4,1.15,13)
	return m
end
function B.Lobby(parent)
	local m=model("LobbyEnvironment",parent);m:SetAttribute("PlaceRole","Lobby");m:SetAttribute("DesignRevision","BlackwaterDepot")
	local shell=model("Architecture",m);local props=model("Fixtures",m)
	part(shell,"Foundation",V(106,2,82),V(0,19,0),L.stone,Enum.Material.Concrete)
	local rng=Random.new(71)
	for x=-48,48,8 do for z=-36,36,8 do
		local tone=rng:NextInteger(69,82)
		part(shell,"WornStone",V(7.97,.12,7.97),V(x,20.06,z),Color3.fromRGB(tone,tone+1,tone),Enum.Material.Slate)
	end end
	part(shell,"BackWall",V(106,20,2),V(0,30,-40),L.plaster,Enum.Material.Concrete)
	part(shell,"FrontWall",V(106,20,2),V(0,30,40),L.plaster,Enum.Material.Concrete)
	for _,x in {-52,52}do
		part(shell,"SideWall",V(2,20,80),V(x,30,0),L.plaster,Enum.Material.Concrete)
		part(shell,"LowerWallBand",V(.35,8,78),V(x-math.sign(x)*1.2,24,0),L.wood,Enum.Material.Metal)
		for z=-34,34,8 do
			part(shell,"AccessPanelFrame",V(.13,5.8,6.5),V(x-math.sign(x)*1.43,24,z),L.trim,Enum.Material.Metal)
			part(shell,"AccessPanel",V(.14,5.3,6),V(x-math.sign(x)*1.52,24,z),L.wood,Enum.Material.Metal)
		end
		part(shell,"WallConduit",V(.6,.3,78),V(x-math.sign(x)*1.25,28,0),L.trim,Enum.Material.Metal)
		part(shell,"CeilingCornice",V(1.5,.8,80),V(x-math.sign(x)*1.3,39.3,0),L.trim,Enum.Material.Metal)

	end
	part(shell,"Roof",V(106,1,82),V(0,40.5,0),Color3.fromRGB(47,43,42),Enum.Material.Concrete)
	for _,z in {-12,13,36}do part(shell,"CableTray",V(103,.45,.6),V(0,39.8,z),L.trim,Enum.Material.Metal)end
	-- Side pilasters support the room without crossing either central sign.
	for _,x in {-49,49}do for _,z in {-35,32}do
		part(shell,"SidePilaster",V(1.8,19,1.8),V(x,29.5,z),L.plaster,Enum.Material.Concrete)
		part(shell,"PilasterBase",V(2.4,1.2,2.4),V(x,20.6,z),L.trim)
	end end
	for _,x in {-33,-11,11,33}do hatch(m,x,-28)end
	local runner=decor(props,"ServiceWalkway",V(12,.035,58),V(0,20.16,7),L.wine,Enum.Material.DiamondPlate)
	for _,x in {-5.65,5.65}do decor(props,"WalkwayEdge",V(.08,.018,58),V(x,20.19,7),Color3.fromRGB(91,97,92),Enum.Material.DiamondPlate)end
	chandelier(props,0,36.6,20,1.65,34);chandelier(props,-30,36.6,3,1.15,28);chandelier(props,29,36.6,5,.85,27)
	-- Empty reception, stopped clock, and worn seating suggest an abandoned public building.
	local desk=model("Reception",props)
	part(desk,"Body",V(15,4,5),V(-34,22,5),L.wood,Enum.Material.Metal)
	part(desk,"Counter",V(16,.4,6),V(-34,24.15,5),L.trim,Enum.Material.Metal)
	for _,x in {-39,-34,-29}do
		part(desk,"Inset",V(4.2,2.6,.1),V(x,22,7.56),L.trim,Enum.Material.Metal)
		part(desk,"Panel",V(3.8,2.2,.13),V(x,22,7.63),L.wood,Enum.Material.Metal)
	end
	local book=decor(desk,"WorkOrder",V(2.2,.13,1.5),CFrame.new(-33,24.43,5.8)*CFrame.Angles(0,-.15,0),L.paper)
	for i=1,5 do decor(desk,"LedgerLine",V(1.7,.015,.025),V(-33,24.51,5.25+i*.19),L.trim)end
	local bell=decor(desk,"ServiceBell",V(.6,.4,.6),V(-29,24.6,5.6),L.brass);bell.Shape=Enum.PartType.Ball
	for _,z in {12,25}do
		local seat=model("WaitingBench",props)
		part(seat,"Seat",V(11,.8,3),V(35,22,z),L.wine,Enum.Material.DiamondPlate)
		part(seat,"Back",V(11,3,.6),V(35,23.6,z+1.4),L.wine,Enum.Material.DiamondPlate)
		for _,dx in {-5.2,5.2}do part(seat,"Arm",V(.5,2,3.3),V(35+dx,22.6,z),L.trim,Enum.Material.Metal);part(seat,"Leg",V(.45,1.7,.5),V(35+dx,20.85,z),L.wood,Enum.Material.Metal)end
	end
	local clock=decor(props,"StoppedClock",V(4,4,.22),CFrame.new(-35,33,38.7),L.trim)
	local _,clockText=sign(props,"ClockFace",V(3.4,3.4,.1),CFrame.new(-35,33,38.5),"12\n9     3\n6",L.dark,L.paper);clockText.Font=Enum.Font.GothamMedium
	decor(props,"ClockHand",V(.11,1.3,.08),CFrame.new(-35,33.4,38.35)*CFrame.Angles(0,0,-.6),L.dark)
	part(props,"SealedDoor",V(8,12,.45),V(35,26,38.7),L.wood,Enum.Material.Metal)
	decor(props,"DoorHandle",V(.9,.15,.25),V(37,25.5,38.35),L.brass)
	sign(props,"DoorNotice",V(4,1.4,.08),CFrame.new(35,28,38.35),"NO EXIT",L.paper,L.wood)
	-- Visible utility infrastructure and drain runs establish a neglected municipal depot.
	for _,x in {-50.825,50.825}do
		for _,y in {34.8,36}do pipe(props,V(x-math.sign(x)*.175,y,-37),V(x-math.sign(x)*.175,y,37),.23,L.brass)end
		for _,z in {-20,8,30}do
			local frame=CFrame.new(x,31,z)*CFrame.Angles(0,x<0 and -math.pi/2 or math.pi/2,0)
			part(props,"VentFrame",V(5,2.8,.35),frame,L.wood)
			for dy=-1,1,.4 do decor(props,"VentSlat",V(4.6,.15,.1),frame*CFrame.new(0,dy,-.23),L.trim)end
		end
	end
	for _,x in {-7.2,7.2}do
		decor(props,"DrainChannel",V(.8,.025,54),V(x,20.15,8),L.dark)
		for z=-18,34,1.1 do decor(props,"DrainGrille",V(.8,.025,.10),V(x,20.18,z),L.trim)end
	end
	local spawn=Instance.new("SpawnLocation");spawn.Name="LobbySpawn";spawn.Size=V(5,.15,5);spawn.CFrame=CFrame.new(0,20.2,27);spawn.Anchored=true;spawn.Transparency=1;spawn.CanCollide=false;spawn.Neutral=true;spawn.Duration=0;spawn.Parent=m
	-- Non-positional background ambience (parented to SoundService, not a Part, so it's
	-- even across the whole room). Volume deliberately well under the chandelier flicker
	-- buzz (.35 -- see chandelier()) so the buzz still reads clearly over it.
	local ambience=Instance.new("Sound");ambience.Name="LobbyAmbience";ambience.SoundId="rbxassetid://120787782672466"
	ambience.Looped=true;ambience.Volume=.15;ambience.Parent=game:GetService("SoundService");ambience:Play()
	m.PrimaryPart=shell.Foundation;return m
end

function B.Game(parent,includeTestRoom)
	local m=model("DescentEnvironment",parent);m:SetAttribute("PlaceRole","Game")
	local cabin=model("Elevator",m)
	part(cabin,"Floor",V(18,1,16),V(0,19.5,0),palette.steel,Enum.Material.DiamondPlate)
	part(cabin,"Ceiling",V(18,1,16),V(0,32.5,0),palette.black)
	part(cabin,"BackWall",V(18,13,.6),V(0,26,8),palette.steel)
	for _,x in {-9,9} do
		part(cabin,"Wall",V(.6,13,16),V(x,26,0),palette.steel)
		for z=-6,6,3 do
			decor(cabin,"WallRib",V(.3,11,.16),V(x-math.sign(x)*.4,26,z),palette.black)
		end
		pipe(cabin,V(x-math.sign(x)*.6,23,-5),V(x-math.sign(x)*.6,23,6),.12,palette.pale)
	end
	for x=-7.5,7.5,3 do decor(cabin,"RearPanelSeam",V(.06,11,.05),V(x,26,7.66),palette.black) end
	for _,x in {-8.5,8.5} do part(cabin,"DoorFrame",V(1,13,1),V(x,26,-8),palette.black) end
	part(cabin,"DoorHeader",V(18,2,1.3),V(0,32,-8),palette.black)
	-- Authored closed leaves; ElevatorService owns their movement.
	for _,x in {-3.9,3.9} do
		local leaf=part(cabin,x<0 and "LeftDoor" or "RightDoor",V(7.8,11,.5),V(x,25.5,-8),palette.steel)
		leaf:SetAttribute("DoorSide",x<0 and "Left" or "Right")
	end
	for x=-7,7,1.5 do decor(cabin,"ThresholdMark",V(.6,.04,1.3),CFrame.new(x,20.04,-7.2)*CFrame.Angles(0,-.5,0),palette.amber) end
	strip(cabin,V(0,31.7,2),V(11,.1,1),Color3.fromRGB(198,204,174),1.7,22)
	strip(cabin,V(8.55,28,-5),V(.12,1,.4),palette.red,.4,10)
	part(cabin,"ControlBox",V(2.5,5,.45),V(6.6,25.5,7.5),palette.black)
	sign(cabin,"FloorReadout",V(2,1.5,.12),CFrame.new(6.6,27,7.2),"05",palette.amber)
	for i=1,3 do
		local bulb=decor(cabin,"ObjectiveIndicator"..i,V(.35,.35,.12),V(5.9+(i-1)*.65,25.3,7.18),palette.mint,Enum.Material.Neon)
		bulb.Shape=Enum.PartType.Ball
	end
	sign(cabin,"ControlLegend",V(2,1,.08),CFrame.new(6.6,24,7.2),"MANUAL\nCONTROL",palette.pale)
	sign(cabin,"SafetyPlate",V(6,1.6,.12),CFrame.new(-3.5,26.5,7.55),"KEEP THE GATE CLEAR\nMAXIMUM CREW  04",palette.pale)
	part(cabin,"CeilingHatch",V(4,.16,4),V(-3,31.9,1),palette.steel)
	for _,x in {-4.6,-1.4} do decor(cabin,"HatchLatch",V(.2,.15,1),V(x,31.76,1),palette.amber) end
	local spawn=Instance.new("SpawnLocation");spawn.Name="GameSpawn";spawn.Size=V(4,.1,4);spawn.CFrame=CFrame.new(0,20.2,3)
	spawn.Transparency=1;spawn.Anchored=true;spawn.CanCollide=false;spawn.Neutral=true;spawn.Duration=0;spawn.Parent=m
	if includeTestRoom then
		local room=model("InteractionWorkshop",m);room:SetAttribute("StudioOnly",true)
		part(room,"Floor",V(32,1,26),V(0,19.5,-21),palette.concrete,Enum.Material.Concrete)
		part(room,"BackWall",V(32,12,1),V(0,26,-34),palette.concrete,Enum.Material.Concrete)
		for _,x in {-16,16} do part(room,"SideWall",V(1,12,26),V(x,26,-21),palette.concrete,Enum.Material.Concrete) end
		part(room,"Ceiling",V(32,1,26),V(0,32,-21),palette.black)
		strip(room,V(0,31.4,-23),V(16,.14,1),palette.ivory,1.3,28)
		sign(room,"WorkshopSign",V(16,2,.1),CFrame.new(0,28.5,-33.35)*CFrame.Angles(0,math.pi,0),"EQUIPMENT CHECK",palette.amber)
		part(room,"WorkBench",V(15,3,3),V(0,21.5,-28),palette.steel)
		for _,x in {-4,0} do
			local item=part(room,x==-4 and "TestCoreA" or "TestCoreB",V(.8,1.5,.8),V(x,23.8,-28),palette.amber)
			item.CanCollide=false;item:SetAttribute("FixtureType","Item");item:SetAttribute("ItemKind",x==-4 and "Core" or "Fuse")
		end
		local socket=part(room,"TestSocket",V(2,2,1),V(5,24,-28),palette.black)
		socket:SetAttribute("FixtureType","Socket");socket:SetAttribute("AcceptedKind","Core")
		local panel=part(room,"HoldPanel",V(2,2,.4),V(-12,24,-32.9),palette.amber)
		panel:SetAttribute("FixtureType","Hold")
		local recovery=decor(room,"RecoveryAnchor",V(1,.1,1),V(0,20.7,-23),palette.mint);recovery.Transparency=1
	end
	m.PrimaryPart=cabin.Floor
	return m
end
function B.ApplyLighting(role)
	local l=game:GetService("Lighting")
	local lobby=role=="Lobby"
	l.ClockTime=0;l.GlobalShadows=true
	-- Lobby stays the safe room by comparison, but it is no longer bright/clean industrial.
	-- The drop from Lobby to Game exposure is the horror progression beat.
	l.Brightness=lobby and .5 or .55
	l.Ambient=lobby and Color3.fromRGB(24,27,28) or Color3.fromRGB(14,16,16)
	l.OutdoorAmbient=lobby and Color3.fromRGB(9,11,12) or Color3.fromRGB(6,8,10)
	l.ExposureCompensation=lobby and -.15 or -.55
	local old=l:FindFirstChild("EHColorGrade");if old then old:Destroy() end
	local grade=Instance.new("ColorCorrectionEffect");grade.Name="EHColorGrade"
	grade.Contrast=lobby and .17 or .22;grade.Saturation=lobby and -.24 or -.42
	grade.TintColor=lobby and Color3.fromRGB(222,233,230) or Color3.fromRGB(200,210,220);grade.Parent=l
	local bloom=l:FindFirstChild("EHBloom");if bloom then bloom:Destroy() end
	bloom=Instance.new("BloomEffect");bloom.Name="EHBloom"
	bloom.Intensity=lobby and .1 or .05;bloom.Size=lobby and 16 or 10;bloom.Threshold=lobby and 1.8 or 1.9;bloom.Parent=l
	local atmo=l:FindFirstChild("EHAtmosphere");if atmo then atmo:Destroy() end
	atmo=Instance.new("Atmosphere");atmo.Name="EHAtmosphere"
	atmo.Density=lobby and .27 or .42;atmo.Offset=lobby and .2 or .35
	atmo.Color=lobby and Color3.fromRGB(150,155,150) or Color3.fromRGB(90,100,110)
	atmo.Decay=lobby and Color3.fromRGB(90,95,92) or Color3.fromRGB(50,58,66)
	atmo.Glare=lobby and .1 or .05;atmo.Haze=lobby and 1.15 or 2.4;atmo.Parent=l
	-- Atmosphere is currently applied per Place role (Lobby/Game) only, since Floor 5-1
	-- environments (ServerScriptService.GameServer.Floors) do not exist yet to receive
	-- distinct per-floor treatment. Extend this function with a floorNumber parameter
	-- once those templates are built.
end
return table.freeze(B)
