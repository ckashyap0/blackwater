--!nonstrict
-- Five deliberately small engineering templates. Story encounters replace these in Chunk 11.
local T={}
local labels={[5]="MAINTENANCE",[4]="DRAINAGE",[3]="SERVICE PASSAGE",[2]="SHAFT ACCESS",[1]="DEEP INTAKE"}
local colors={[5]=Color3.fromRGB(145,157,139),[4]=Color3.fromRGB(102,153,164),[3]=Color3.fromRGB(113,120,145),[2]=Color3.fromRGB(176,97,79),[1]=Color3.fromRGB(165,127,86)}
function T.Build(number)
	assert(labels[number],"Unknown floor")
	local m=Instance.new("Model");m.Name="TemporaryFloor"..number;m:SetAttribute("ManagedBy","ElevatorHorror");m:SetAttribute("Temporary",true)
	local function part(name,size,position,color,material)
		local p=Instance.new("Part");p.Name=name;p.Size=size;p.Position=position;p.Anchored=true;p.Color=color or Color3.fromRGB(61,67,65)
		p.Material=material or Enum.Material.Concrete;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=m;return p
	end
	local function anchor(name,size,position)
		local p=part(name,size,position);p.Transparency=1;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;return p
	end
	part("Floor",Vector3.new(36,1,32),Vector3.new(0,19.5,-24),nil,Enum.Material.DiamondPlate)
	part("RearWall",Vector3.new(36,13,1),Vector3.new(0,26,-40))
	part("Ceiling",Vector3.new(36,1,32),Vector3.new(0,32.5,-24),Color3.fromRGB(32,37,37),Enum.Material.Metal)
	for _,x in {-18,18} do part("SideWall",Vector3.new(1,13,32),Vector3.new(x,26,-24)) end
	for _,x in {-13,13} do part("DockSurround",Vector3.new(10,13,1),Vector3.new(x,26,-8),nil,Enum.Material.CorrodedMetal) end
	for _,z in {-14,-28} do
		local lamp=part("Fluorescent",Vector3.new(9,.2,.7),Vector3.new(0,31.7,z),colors[number],Enum.Material.Neon)
		local light=Instance.new("PointLight");light.Color=colors[number];light.Brightness=1.8;light.Range=23;light.Shadows=true;light.Parent=lamp
	end
	local panel=part("ObjectivePanel",Vector3.new(3,3,.6),Vector3.new(-9,24,-38.9),Color3.fromRGB(112,88,52),Enum.Material.CorrodedMetal)
	local sign=part("LevelSign",Vector3.new(19,3,.2),Vector3.new(0,28,-39.3),Color3.fromRGB(20,27,28),Enum.Material.Metal)
	local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Back;gui.PixelsPerStud=45;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.Parent=sign
	local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.TextColor3=colors[number];label.Font=Enum.Font.GothamMedium;label.TextScaled=true
	label.Text=string.format("%02d  %s\nSYSTEMS TEST ROOM",number,labels[number]);label.Parent=gui
	anchor("ElevatorDock",Vector3.new(1,1,1),Vector3.new(0,20,-8))
	anchor("PlayerRecovery",Vector3.new(1,1,1),Vector3.new(0,23,-14))
	anchor("ObjectiveRecovery",Vector3.new(1,1,1),Vector3.new(0,21,-20))
	anchor("FloorBounds",Vector3.new(36,16,34),Vector3.new(0,26,-24))
	m.PrimaryPart=m.Floor;return m
end
return table.freeze(T)
