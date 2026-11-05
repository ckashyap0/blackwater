--!nonstrict
-- A clean beam of light drawn in 2D over a ViewportFrame, like a real torch beam: one solid cone that starts at
-- the lens exactly as wide as the lens (nothing reaches back over the flashlight), opens out, and fades away
-- smoothly along its length. The two sides get a 2px soft edge so they never look jagged.
-- Built only from CanvasGroups and frames (no font glyph or texture being stretched), so it stays smooth at
-- any size:
--   LightWedge (Frame) > Beam (CanvasGroup along the beam: cuts it off at the lens, fades it with distance)
--     > Cone (CanvasGroup: its top edge is the cone's upper side) > Fill (Frame: its bottom edge is the lower side)
-- API:
--   local w=LightWedge.Create(parentFrame,zIndex)
--   LightWedge.Place(w,lensPx,dirUnit,lengthPx,halfWidthPx,color,maxHalf,areaPx)
--       lens centre + lens radius, in the parent's pixels. maxHalf (optional): the biggest the lens will get,
--       so a beam moved every frame keeps one fixed size (no resizing = no shimmer). areaPx: the parent's
--       size in the same pixels - pass it! Positions are then placed as fractions (UDim offsets are whole
--       pixels only, which makes a moving beam step and sit a pixel off the lens)
--   LightWedge.SetColor(w,color)  /  LightWedge.SetAlpha(w,0..1)
--   LightWedge.Project(camera,frameSize,worldPoint)   -- -> pixel position in a ViewportFrame, depth
-- Used by the BEAM COLORS shop cards (placed once when authored) and the locker preview (every frame).
local W={}
local SPREAD=.36     -- how fast the beam opens (tan of the half angle)
local STRENGTH=.12   -- how see-through it is at the lens (0 = solid)
local SOFT=2         -- px of soft edge along each side
-- bright at the lens, fading out evenly to nothing at the far end
local FADE=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.08,.02),
	NumberSequenceKeypoint.new(.5,.5),NumberSequenceKeypoint.new(.82,.82),NumberSequenceKeypoint.new(1,.95)})
local function make(parent,name,class,z)
	local g=Instance.new(class);g.Name=name;g.BackgroundTransparency=1;g.BorderSizePixel=0
	g.AnchorPoint=Vector2.new(.5,.5);g.ZIndex=z;g.Parent=parent
	return g
end
local function edge(parent,name)
	local g=Instance.new("UIGradient");g.Name=name;g.Rotation=90;g.Parent=parent
	return g
end
function W.Create(parent,z)
	z=z or 2
	local f=Instance.new("Frame");f.Name="LightWedge";f.BackgroundTransparency=1;f.Size=UDim2.fromScale(1,1);f.ZIndex=z
	local beam=make(f,"Beam","CanvasGroup",z)
	local g=Instance.new("UIGradient");g.Name="Fade";g.Transparency=FADE;g.Parent=beam
	local cone=make(beam,"Cone","CanvasGroup",z);cone.GroupTransparency=STRENGTH
	edge(cone,"Soft")
	local fill=make(cone,"Fill","Frame",z);fill.BackgroundTransparency=0;fill.BackgroundColor3=Color3.new(1,1,1)
	edge(fill,"Soft")
	f.Parent=parent
	return f
end
local function off(v)return UDim2.fromOffset(v.X,v.Y)end
-- exact (sub-pixel) position inside a parent of the given pixel size
local function at(v,area)
	if area and area.X>0 and area.Y>0 then return UDim2.fromScale(v.X/area.X,v.Y/area.Y) end
	return off(v)
end
function W.Place(f,lens,dir,length,half,color,maxHalf,area)
	if dir.Magnitude<1e-3 then return end
	dir=dir.Unit;half=math.max(half or 8,1)
	local beam=f:FindFirstChild("Beam");if not beam then return end
	local cone=beam:FindFirstChild("Cone");local fill=cone and cone:FindFirstChild("Fill")
	if not fill then return end
	local big=math.max(maxHalf or half,half)
	local H=math.ceil(2*(big+length*SPREAD)+6)
	local Lb=math.ceil(length)
	local size=UDim2.fromOffset(Lb,H)
	if beam.Size~=size then beam.Size=size end
	beam.Position=at(lens+dir*(Lb/2),area)
	beam.Rotation=math.deg(math.atan2(dir.Y,dir.X))
	-- in the beam's own pixels: x runs along the light from the lens (x=0), the middle of the light is y=H/2
	local back=2*big+8 -- the cone starts a little behind the lens; Beam cuts it off exactly at the lens
	local Ls=math.ceil((length+back)/math.cos(math.atan(SPREAD))+8)
	local Hs=H+math.ceil(2*back)+8
	local t=SPREAD;local a=math.atan(t);local ca,sa=math.cos(a),math.sin(a)
	-- upper side: y=H/2-half-t*x ; the cone hangs below it
	local p2=Vector2.new(-back,H/2-half+t*back)
	local sc=p2+Vector2.new(ca,-sa)*(Ls/2)+Vector2.new(sa,ca)*(Hs/2)
	local csize=UDim2.fromOffset(Ls,Hs)
	if cone.Size~=csize then cone.Size=csize end
	cone.Position=at(sc,Vector2.new(Lb,H));cone.Rotation=-math.deg(a)
	-- lower side: y=H/2+half+t*x ; the fill sits above it
	local p1=Vector2.new(-back,H/2+half-t*back)
	local fc=p1+Vector2.new(ca,sa)*(Ls/2)+Vector2.new(sa,-ca)*(Hs/2)
	local d=fc-sc
	local q=Vector2.new(d.X*ca-d.Y*sa,d.X*sa+d.Y*ca)+Vector2.new(Ls/2,Hs/2)
	if fill.Size~=csize then fill.Size=csize end
	fill.Position=at(q,Vector2.new(Ls,Hs));fill.Rotation=2*math.deg(a)
	if color then fill.BackgroundColor3=color end
	-- soft sides: the cone fades in over its top SOFT px, the fill fades out over its bottom SOFT px
	local k=math.clamp(SOFT/Hs,.0005,.2)
	local cs,fs=cone:FindFirstChild("Soft"),fill:FindFirstChild("Soft")
	if cs and cs:GetAttribute("K")~=k then
		cs:SetAttribute("K",k);cs.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(k,0),NumberSequenceKeypoint.new(1,0)})
	end
	if fs and fs:GetAttribute("K")~=k then
		fs:SetAttribute("K",k);fs.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1-k,0),NumberSequenceKeypoint.new(1,1)})
	end
end
function W.SetColor(f,color)
	for _,d in f:GetDescendants() do if d.Name=="Fill" and d:IsA("Frame") then d.BackgroundColor3=color end end
end
-- 0 = gone, 1 = full strength
function W.SetAlpha(f,alpha)
	local beam=f:FindFirstChild("Beam")
	if beam then beam.GroupTransparency=1-math.clamp(alpha,0,1) end
end
function W.Project(cam,size,p)
	local q=cam.CFrame:PointToObjectSpace(p)
	local t=math.tan(math.rad(cam.FieldOfView)/2)
	local z=math.max(-q.Z,.01)
	local x,y=q.X/(z*t*size.X/size.Y),q.Y/(z*t)
	return Vector2.new((.5+.5*x)*size.X,(.5-.5*y)*size.Y),z
end
return W
