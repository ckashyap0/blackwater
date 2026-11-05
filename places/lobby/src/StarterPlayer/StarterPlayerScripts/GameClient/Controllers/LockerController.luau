--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
-- LOCKER (lobby): a catalog of everything you can wear, with a live preview of you holding it.
-- Authored in StarterGui.ShopControls (edit it there):
--   LockerButton > Icon                    2D locker icon
--   LockerPanel > Header (Kicker, Title, Underline, Close)
--               > Side > Tabs > one TextButton per tab: attribute Slot (Title / Flashlight / Beam, as in
--                               Config.CosmeticsConfig) and Caption (heading shown above the grid);
--                               child frame "Active" shows on the open tab
--                      > Caption
--                      > List (ScrollingFrame + UIGridLayout) > TileTemplate, copied once per item:
--                            Rarity (top strip), Tier, Equipped (check), Label, State, and Art >
--                            View (3D, skins) / Orb + Halo (colours) / Tag (titles) / Lock (padlock)
--                      > Hint
--               > Preview > Avatar (ViewportFrame + WorldModel), Glow, Floor, Kicker, ShowName, ShowState
--                 A copy of your character holding the flashlight with its beam. Hovering a tile tries it
--                 on (skins and colours, even ones you don't own yet; secret ones stay hidden).
-- Clicking a tile: owned -> equip (the server saves it); gamepass item -> purchase prompt; coin item ->
-- opens the SHOP on that tab. Tiles repaint from player attributes.
local GuiService=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Market=game:GetService("MarketplaceService")
local SoundService=game:GetService("SoundService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.CosmeticsConfig)
local OrbitParts=require(Shared.Utilities.OrbitParts)
local LightWedge=require(Shared.Utilities.LightWedge)
local PanelFade=require(Shared.Utilities.PanelFade)
local Cosmetics=require(script.Parent.CosmeticsController)
local Controller={};Controller.__index=Controller
local WHITE=Color3.fromRGB(235,232,225)
local FAINT=Color3.fromRGB(150,146,138)
local DIM=Color3.fromRGB(95,93,88)
local GREEN=Color3.fromRGB(110,220,130)
local GOLD=Color3.fromRGB(226,182,81)
local PURPLE=Color3.fromHex("B36BFF")
-- same quiet UI sounds as the shop (Cuelume set)
local SOUNDS={Hover={"rbxassetid://118800406096048",.3},Tab={"rbxassetid://111764646352235",.45},Click={"rbxassetid://103859976078601",.5}}
local ATTR={Title="EHTitle",Flashlight="EHFlashlightSkin",Beam="EHFlashlightColor"}
local SHOP_TAB={Flashlight="Skins",Beam="Colors"}
local BoxConfig=require(Shared.Config.MysteryBoxConfig)
local FADE=TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local HOVER=TweenInfo.new(.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local RAINBOW=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHex("FF4A5A")),ColorSequenceKeypoint.new(.17,Color3.fromHex("FF9A3A")),
	ColorSequenceKeypoint.new(.33,Color3.fromHex("FFE24A")),ColorSequenceKeypoint.new(.5,Color3.fromHex("5AFF7A")),ColorSequenceKeypoint.new(.67,Color3.fromHex("4AD8FF")),
	ColorSequenceKeypoint.new(.83,Color3.fromHex("5A6AFF")),ColorSequenceKeypoint.new(1,Color3.fromHex("C25AFF"))})
local function commas(n)
	local s=tostring(math.floor(n+.5))
	local r=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
	return (r:gsub("^,",""))
end
local function entry(slot,id)for _,e in Config[slot] or {} do if e.Id==id then return e end end end
local function rainbowAt(t)return Color3.fromHSV((t*.12)%1,.72,1)end
local function beamColor(id)
	local e=entry("Beam",id) or entry("Beam","Default")
	if e.Rainbow then return rainbowAt(os.clock()),true end
	if e.Pulse then
		local k=.5-.5*math.cos(os.clock()*.9)
		return Color3.fromRGB(e.Beam[1],e.Beam[2],e.Beam[3]):Lerp(Color3.fromRGB(e.Pulse[1],e.Pulse[2],e.Pulse[3]),k),true
	end
	return Color3.fromRGB(e.Beam[1],e.Beam[2],e.Beam[3]),false
end
-- rarity label + colour (nil colour = rainbow), matching the shop's tiers
local function tierOf(slot,e)
	-- (only ULTRA RARE is drawn in rainbow; every other set rarity uses its mystery-box colour)
	if e.Rarity then
		if e.Rarity=="ULTRA RARE" then return e.Rarity,nil end
		return e.Rarity,Color3.fromHex(BoxConfig.Colors[e.Rarity] or "EBE8E1")
	end
	if e.Pass then return "GAMEPASS",GOLD end
	if not e.Price then
		if e.Id=="Default" then return "STANDARD",FAINT end
		return "SECRET",PURPLE
	end
	local p=e.Price
	if slot=="Beam" then
		if e.Rainbow then return "ULTRA RARE",nil end
		if p>=2500 then return "MYTHIC",Color3.fromHex("FF4F8B") end
		if p>=1500 then return "LEGENDARY",GOLD end
		if p>=800 then return "EPIC",PURPLE end
		if p>=400 then return "RARE",Color3.fromHex("5AA0FF") end
		return "COMMON",FAINT
	end
	if p>=20000 then return "ULTRA RARE",nil end
	if p>=3200 then return "MYTHIC",Color3.fromHex("FF4F8B") end
	if p>=1250 then return "LEGENDARY",GOLD end
	if p>=1000 then return "EPIC",PURPLE end
	if p>=650 then return "RARE",Color3.fromHex("5AA0FF") end
	return "COMMON",FAINT
end
local RANK={STANDARD=0,COMMON=1,RARE=2,EPIC=3,LEGENDARY=4,GAMEPASS=4.5,SECRET=4.6,MYTHIC=5,["ULTRA RARE"]=6}
-- a copy of a skin's shop art: lens toward -Z, grip at the origin (anything built another way is turned,
-- centred and sized to match)
local function skinModel(id)
	local art=Shared.Parent:FindFirstChild("ShopArt")
	local skins=art and art:FindFirstChild("Skins")
	if not skins then return nil end
	local e=entry("Flashlight",id)
	local src=e and (skins:FindFirstChild(e.Model) or art:FindFirstChild(e.Model) or art:FindFirstChild(id))
	src=src or skins:FindFirstChild("BeamDisplay")
	if not src then return nil end
	local m=src:Clone()
	for _,d in m:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CastShadow=false
		elseif d:IsA("LuaSourceContainer") then d:Destroy() end
	end
	local lens=m:FindFirstChild("Lens",true)
	local piv=m:GetPivot()
	if lens and piv:PointToObjectSpace(lens.Position).Z>-.2 then
		local cf=m:GetBoundingBox()
		m:PivotTo(CFrame.lookAt(Vector3.zero,(lens.Position-cf.Position).Unit):Inverse()*CFrame.new(-cf.Position)*piv)
		m.WorldPivot=CFrame.identity
		local _,size=m:GetBoundingBox()
		local long=math.max(size.X,size.Y,size.Z)
		if long>1.6 then m:ScaleTo(m:GetScale()*1.4/long) end
	end
	return m
end

-- how the held light sits in a hand (shared shape with EquipmentController): the tail end rests just behind
-- the fist and the light points down the arm, top kept up. Works for slim R15 hands, block hands and R6 arms.
local HOLD_SCALE=.85
local SKIN_SCALE={UFO=1.3} -- same as the Game's EquipmentController: short skins held a bit bigger
local function holdFrame(hand,r15,tailZ)
	local fwd=-hand.CFrame.UpVector
	local fist=hand.Position+fwd*hand.Size.Y*(r15 and .15 or .4)
	local origin=fist+fwd*(tailZ-.12)
	return CFrame.lookAt(origin,origin+fwd,Vector3.yAxis)
end
-- put every part back where its joints say it rests (the copy is taken mid-animation: running, jumping...)
local function restPose(rig,root)
	local links={}
	for _,w in rig:GetDescendants() do
		local a,b,rel
		if w:IsA("JointInstance") and w.Part0 and w.Part1 then a,b,rel=w.Part0,w.Part1,w.C0*w.C1:Inverse()
		elseif (w:IsA("AnimationConstraint") or w:IsA("RigidConstraint")) and w.Attachment0 and w.Attachment1 then
			a,b,rel=w.Attachment0.Parent,w.Attachment1.Parent,w.Attachment0.CFrame*w.Attachment1.CFrame:Inverse()
		elseif w:IsA("WeldConstraint") and w.Part0 and w.Part1 then a,b,rel=w.Part0,w.Part1,w.Part0.CFrame:ToObjectSpace(w.Part1.CFrame) end
		if a and b and a:IsA("BasePart") and b:IsA("BasePart") then table.insert(links,{a,b,rel}) end
	end
	local placed={[root]=true}
	local changed=true
	while changed do
		changed=false
		for _,l in links do
			local a,b,rel=l[1],l[2],l[3]
			if placed[a] and not placed[b] then b.CFrame=a.CFrame*rel;placed[b]=true;changed=true
			elseif placed[b] and not placed[a] then a.CFrame=b.CFrame*rel:Inverse();placed[a]=true;changed=true end
		end
	end
end
-- camera that fits a model snugly inside a view of the given aspect, from direction dir, leaving `fill`
-- of the width/height used (every part's corners are checked, so nothing ever touches the border)
local function fitCamera(model,dir,fov,aspect,fill)
	local f=-dir.Unit
	local cam=CFrame.lookAt(Vector3.zero,f)
	local r,u=cam.RightVector,cam.UpVector
	local tv=math.tan(math.rad(fov)/2)*fill
	local th=tv*aspect
	local d=0
	for _,p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency<.95 then
			local h=p.Size/2
			for _,s in {Vector3.new(1,1,1),Vector3.new(1,1,-1),Vector3.new(1,-1,1),Vector3.new(1,-1,-1),Vector3.new(-1,1,1),Vector3.new(-1,1,-1),Vector3.new(-1,-1,1),Vector3.new(-1,-1,-1)} do
				local q=p.CFrame*(h*s)
				d=math.max(d,math.abs(q:Dot(r))/th-q:Dot(f),math.abs(q:Dot(u))/tv-q:Dot(f))
			end
		end
	end
	return CFrame.lookAt(-f*d,Vector3.zero)
end
function Controller.new(player,gui)
	return setmetatable({Name="LockerController",Dependencies={"FocusController","ShopController"},_player=player,_gui=gui,_rows={},_tabs={}},Controller)
end
function Controller:Init(deps)
	self._focus=deps.FocusController
	self._shop=deps.ShopController
	self._scope=Scope.new()
	self._sounds={}
	for name,spec in SOUNDS do
		local s=Instance.new("Sound");s.Name="Locker"..name;s.SoundId=spec[1];s.Volume=spec[2];s.Parent=SoundService
		self._sounds[name]=s;self._scope:Add(s)
	end
	local controls=AuthoredGui.Get(self._gui,"ShopControls")
	local panel=controls and controls:FindFirstChild("LockerPanel")
	local button=controls and controls:FindFirstChild("LockerButton")
	if not panel or not button then return end
	self._button=button
	self._uiScale=controls:FindFirstChildOfClass("UIScale") -- the whole UI is drawn at this scale
	-- the hanger icon is a Path2D, whose line width is in screen pixels: keep it in step with the UI scale
	local hanger=button:FindFirstChild("HangerPath",true)
	if hanger and self._uiScale then
		local base=hanger.Thickness
		local function fit()hanger.Thickness=base*self._uiScale.Scale end
		self._scope:Add(self._uiScale:GetPropertyChangedSignal("Scale"):Connect(fit));fit()
	end
	self._panel=panel;panel.Visible=false
	self._fade=PanelFade.new(panel,function(shown)if shown then self:_Refresh() end end)
	self._caption=panel:FindFirstChild("Caption",true)
	self._hint=panel:FindFirstChild("Hint",true)
	self._hintDefault=self._hint and self._hint.Text or ""
	self._list=panel:FindFirstChild("List",true)
	self._template=self._list:WaitForChild("TileTemplate");self._template.Visible=false
	self._scope:Add(self._list.MouseLeave:Connect(function()self:_ListLeft()end))
	self:_SetupPreview()
	local first
	for _,tab in panel:FindFirstChild("Tabs",true):GetChildren() do
		local slot=tab:IsA("GuiButton") and tab:GetAttribute("Slot")
		if slot and Config[slot] then
			local stroke=tab:FindFirstChildOfClass("UIStroke")
			local t={button=tab,slot=slot,stroke=stroke,caption=tab:GetAttribute("Caption") or tab.Text,active=tab:FindFirstChild("Active"),order=tab.LayoutOrder}
			table.insert(self._tabs,t)
			self._scope:Add(tab.Activated:Connect(function()if self._slot~=slot then self:_Sound("Tab") end;self:_Select(slot)end))
			self._scope:Add(tab.MouseEnter:Connect(function()self:_Sound("Hover")end))
			if not first or t.order<first.order then first=t end
		end
	end
	self._slot=first and first.slot
	self._scope:Add(button.Activated:Connect(function()self:SetOpen(not self._fade:IsShown())end))
	local close=panel:FindFirstChild("Close",true)
	if close then
		self._scope:Add(close.Activated:Connect(function()self:_Sound("Click");self:SetOpen(false)end))
		self._scope:Add(close.MouseEnter:Connect(function()self:_Sound("Hover")end))
	end
	self._scope:Add(button.MouseEnter:Connect(function()self:_Sound("Hover")end))
	self._scope:Add(Input.InputBegan:Connect(function(input)
		if self._fade:IsShown() and (input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB) then self:SetOpen(false) end
	end))
end
function Controller:_ListLeft()
	task.delay(.05,function()
		if self._hovered then return end
		if self._hint then self._hint.Text=self._hintDefault end
		if self._hoverId then self._hoverSlot,self._hoverId=nil,nil;self:_ShowPreview() end
	end)
end
function Controller:_Select(slot)
	self._slot=slot
	for _,t in self._tabs do
		local on=t.slot==slot
		t.button.TextColor3=on and WHITE or FAINT
		if t.stroke then t.stroke.Transparency=on and .2 or .7 end
		if t.active then t.active.Visible=on end
		if on and self._caption then self._caption.Text=t.caption end
	end
	self:_Build()
end
function Controller:_Build()
	for _,r in self._rows do r.button:Destroy() end
	table.clear(self._rows)
	self._hovered=nil
	if self._hint then self._hint.Text=self._hintDefault end
	if self._hoverId then self._hoverSlot,self._hoverId=nil,nil;self:_ShowPreview() end
	local slot=self._slot;if not slot then return end
	-- only what you own, in rarity order (the default first, then common -> ultra rare; inside a
	-- rarity, cheapest first, then the catalogue's own order)
	local list={}
	for i,e in Config[slot] do
		if e.Id=="Default" or Cosmetics.Owns(self._player,slot,e.Id) then
			local tier=tierOf(slot,e)
			table.insert(list,{e=e,i=i,rank=e.Id=="Default" and 0 or (RANK[tier] or 4),value=e.Price or e.Value or 0})
		end
	end
	table.sort(list,function(a,b)
		if a.rank~=b.rank then return a.rank<b.rank end
		if a.value~=b.value then return a.value<b.value end
		return a.i<b.i
	end)
	for n,x in list do self:_Tile(n,slot,x.e) end
	self._builtCount=#list
	self._list.CanvasPosition=Vector2.zero
end
-- may this item be shown (art, name)? Secret items stay hidden until you have them.
function Controller:_Revealed(slot,e)
	-- (mystery-box exclusives are always on show: seeing them is what makes people want the boxes)
	return e.Id=="Default" or e.Price~=nil or e.Pass~=nil or e.Box~=nil or Cosmetics.Owns(self._player,slot,e.Id)
end

-- ===== catalog tiles =====
function Controller:_Tile(order,slot,e)
	local b=self._template:Clone()
	b.Name=e.Id;b.LayoutOrder=order;b.Visible=true
	local art=b:FindFirstChild("Art")
	local accent=(slot=="Beam" and e.Beam and Color3.fromRGB(e.Beam[1],e.Beam[2],e.Beam[3])) or (e.Color and Color3.fromHex(e.Color)) or WHITE
	local tile={button=b,slot=slot,e=e,accent=accent,stroke=b:FindFirstChildOfClass("UIStroke"),art=art,
		view=art:FindFirstChild("View"),orb=art:FindFirstChild("Orb"),halo=art:FindFirstChild("Halo"),tag=art:FindFirstChild("Tag"),lock=art:FindFirstChild("Lock"),
		rarity=b:FindFirstChild("Rarity"),tier=b:FindFirstChild("Tier"),check=b:FindFirstChild("Equipped"),name=b:FindFirstChild("Label"),state=b:FindFirstChild("State")}
	art.BackgroundColor3=accent
	local tt,tc=tierOf(slot,e)
	tile.tier.Text=tt
	if tc then
		tile.tier.TextColor3=tc;tile.rarity.BackgroundColor3=tc
	else
		tile.tier.TextColor3=WHITE;tile.rarity.BackgroundColor3=WHITE
		for _,x in {tile.tier,tile.rarity} do local g=Instance.new("UIGradient");g.Color=RAINBOW;g.Parent=x end
	end
	table.insert(self._rows,tile)
	b.MouseEnter:Connect(function()
		tile.hover=true;self._hovered=tile;self:_Paint(tile);self:_Sound("Hover")
		if self._hint then
			local owned=Cosmetics.Owns(self._player,slot,e.Id)
			self._hint.Text=owned and self._hintDefault or (e.Hint or (e.Price and "Buy it in the SHOP for "..commas(e.Price).." coins") or "Locked.")
		end
		if slot~="Title" and self:_Revealed(slot,e) then
			self._hoverSlot,self._hoverId=slot,e.Id;self:_ShowPreview()
		end
	end)
	b.MouseLeave:Connect(function()
		-- the preview keeps showing this item while the cursor crosses the gaps between tiles; it only goes
		-- back to what you have equipped once the cursor leaves the whole list (see _ListLeft)
		tile.hover=false;if self._hovered==tile then self._hovered=nil end
		self:_Paint(tile)
	end)
	b.Activated:Connect(function()
		self:_Sound("Click")
		if not Cosmetics.Owns(self._player,slot,e.Id) then
			local pass=e.Pass and Config.GamePasses[e.Pass]
			if pass then pcall(function()Market:PromptGamePassPurchase(self._player,pass.Id)end)
			elseif e.Price and self._shop and self._shop.OpenTo then self._shop:OpenTo(SHOP_TAB[slot])
			elseif e.Box and self._shop and self._shop.OpenTo then self._shop:OpenTo("Boxes") end
			return
		end
		if self:_Equipped(slot)==e.Id then return end
		local remote=game.ReplicatedStorage.Game.Network:FindFirstChild("Cosmetics")
		if remote then remote:FireServer("Equip",slot,e.Id) end
		tile.pending=true;self:_Paint(tile)
	end)
	b.Parent=self._list
	self:_TileArt(tile)
	self:_Paint(tile)
end
-- what's drawn in the tile: the flashlight in 3D, a glowing orb for a colour, the tag for a title
function Controller:_TileArt(tile)
	local slot,e=tile.slot,tile.e
	local shown=self:_Revealed(slot,e)
	tile.shown=shown
	if tile.view then tile.view.Visible=false end
	if tile.orb then tile.orb.Visible=false end
	if tile.halo then tile.halo.Visible=false end
	if tile.tag then tile.tag.Visible=false end
	if not shown then tile.art.BackgroundColor3=DIM return end
	if slot=="Flashlight" and tile.view then
		local m=skinModel(e.Id)
		if m then
			local cf=m:GetBoundingBox()
			m:PivotTo(CFrame.Angles(math.rad(14),0,0)*CFrame.new(-cf.Position)*m:GetPivot())
			m.Parent=tile.view
			-- every flashlight is fitted to the same share of its tile, so they all sit evenly inside the border
			local cam=Instance.new("Camera");cam.FieldOfView=30
			local size=tile.view.AbsoluteSize
			local aspect=(size.X>1 and size.Y>1) and size.X/size.Y or 140/98
			local fit=fitCamera(m,Vector3.new(1,.35,-.4),30,aspect,.74)
			-- sat a little below the middle: the tier tag takes the top of the tile
			cam.CFrame=fit*CFrame.new(0,fit.Position.Magnitude*math.tan(math.rad(15))*.2,0)
			cam.Parent=tile.view;tile.view.CurrentCamera=cam
			tile.view.Visible=true
		end
	elseif slot=="Beam" and tile.orb then
		tile.orb.Visible=true;tile.halo.Visible=true
		tile.orb.BackgroundColor3=tile.accent;tile.halo.BackgroundColor3=tile.accent
		if e.Rainbow then
			local g=tile.orb:FindFirstChild("Shade") or Instance.new("UIGradient",tile.orb)
			g.Color=RAINBOW;tile.orb.BackgroundColor3=WHITE;tile.halo.BackgroundColor3=WHITE
			tile.rainbow=g
		elseif e.Pulse then
			-- a two-tone orb for a colour that drifts between two
			local g=tile.orb:FindFirstChild("Shade") or Instance.new("UIGradient",tile.orb)
			g.Color=ColorSequence.new(tile.accent,Color3.fromRGB(e.Pulse[1],e.Pulse[2],e.Pulse[3]))
			tile.orb.BackgroundColor3=WHITE;tile.rainbow=g
		end
	elseif slot=="Title" and tile.tag then
		tile.tag.Visible=true
		tile.tag.Text=e.Id=="Default" and "NONE" or e.Label
		tile.tag.TextColor3=e.Color and Color3.fromHex(e.Color) or FAINT
	end
end
function Controller:_Sound(name)
	local now=os.clock()
	if name=="Hover" and now-(self._lastHover or 0)<.05 then return end
	if name=="Hover" then self._lastHover=now end
	local s=self._sounds and self._sounds[name]
	if s then SoundService:PlayLocalSound(s) end
end
function Controller:_Equipped(slot)
	local v=self._player:GetAttribute(ATTR[slot])
	return (type(v)=="string" and v~="") and v or "Default"
end
function Controller:_Paint(tile)
	local e,slot=tile.e,tile.slot
	local owned=Cosmetics.Owns(self._player,slot,e.Id)
	local equipped=self:_Equipped(slot)==e.Id
	if equipped then tile.pending=false end
	if self:_Revealed(slot,e)~=tile.shown then self:_TileArt(tile) end
	local st=tile.stroke
	if tile.name then
		tile.name.Text=tile.shown and e.Label or "? ? ?"
		tile.name.TextColor3=tile.shown and (owned and WHITE or FAINT) or DIM
	end
	if tile.check then tile.check.Visible=equipped end
	if tile.lock then
		tile.lock.Visible=not owned
		tile.lock.BackgroundTransparency=tile.shown and (tile.hover and .7 or .5) or .2
	end
	local state,col
	if equipped then state,col="EQUIPPED",GREEN
	elseif owned then state,col=tile.pending and "· · ·" or "CLICK TO EQUIP",tile.hover and WHITE or FAINT
	elseif e.Pass then state,col="GET "..e.Pass,GOLD
	elseif e.Price then state,col=commas(e.Price).." COINS",GOLD
	elseif e.Box then state,col=(e.Box=="Jackpot" and "CASE JACKPOT" or "MYSTERY BOX"),Color3.fromHex("FF4F8B")
	else state,col="LOCKED",DIM end
	if tile.state then tile.state.Text=state;tile.state.TextColor3=col end
	if st then
		if equipped then st.Color=GREEN;st.Transparency=.25
		elseif tile.hover then st.Color=tile.accent;st.Transparency=.15
		else st.Color=WHITE;st.Transparency=.8 end
	end
end
function Controller:_Refresh()
	-- something new was unlocked (or one went away): rebuild the list so it shows up in its place
	local slot=self._slot
	if slot and Config[slot] then
		local n=0
		for _,e in Config[slot] do if e.Id=="Default" or Cosmetics.Owns(self._player,slot,e.Id) then n+=1 end end
		if n~=self._builtCount then self:_Build() end
	end
	for _,r in self._rows do self:_Paint(r) end;self:_ShowPreview()
end

-- ===== character preview =====
function Controller:_SetupPreview()
	local frame=self._panel:FindFirstChild("Preview",true)
	local vp=frame and frame:FindFirstChild("Avatar")
	if not vp then return end
	local cam=Instance.new("Camera");cam.FieldOfView=26;cam.Parent=vp;vp.CurrentCamera=cam
	self._pv={frame=frame,vp=vp,cam=cam,world=vp:FindFirstChildOfClass("WorldModel") or Instance.new("WorldModel",vp),
		glow=frame:FindFirstChild("Glow"),floor=frame:FindFirstChild("Floor"),name=frame:FindFirstChild("ShowName"),state=frame:FindFirstChild("ShowState"),t=0}
	-- the beam is a smooth 2D light drawn over the 3D view, kept on the lens every frame
	-- under the 3D view, so the flashlight's head covers the beam's tip and the light pours out of the lens
	self._pv.wedge=LightWedge.Create(frame,2)
end
-- a copy of your character as it looks right now, right arm held out in front with the light
function Controller:_BuildAvatar()
	local pv=self._pv;if not pv then return end
	if pv.rig then pv.rig:Destroy();pv.rig=nil;pv.hand=nil end
	local char=self._player.Character;if not char then return end
	local was=char.Archivable;char.Archivable=true
	local ok,rig=pcall(function()return char:Clone()end)
	char.Archivable=was
	if not ok or not rig then return end
	for _,d in rig:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("Tool") then d:Destroy()
		elseif d:IsA("BasePart") then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CastShadow=false end
	end
	local root=rig:FindFirstChild("HumanoidRootPart")
	local hum=rig:FindFirstChildOfClass("Humanoid")
	if not root or not hum then rig:Destroy();return end
	root.Transparency=1
	hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
	local animator=hum:FindFirstChildOfClass("Animator");if animator then animator:Destroy() end
	local r15=hum.RigType==Enum.HumanoidRigType.R15
	-- joints off (everything is anchored and placed by hand; a viewport doesn't run joints, and an enabled
	-- joint would drag the whole body along whenever one part moves), then stand up straight
	for _,w in rig:GetDescendants() do
		if w:IsA("JointInstance") or w:IsA("WeldConstraint") or w:IsA("Constraint") then pcall(function()w.Enabled=false end) end
	end
	restPose(rig,root)
	rig:PivotTo(CFrame.identity) -- at the origin facing -Z
	-- the two parts a joint connects (Motor6D/Weld, or the newer AnimationConstraint/RigidConstraint)
	local function ends(w)
		if w:IsA("JointInstance") or w:IsA("WeldConstraint") then return w.Part0,w.Part1 end
		if w:IsA("Constraint") and w.Attachment0 and w.Attachment1 then return w.Attachment0.Parent,w.Attachment1.Parent end
	end
	-- everything is anchored (a viewport doesn't run joints), so the arm is raised by turning its parts
	-- about the shoulder: upper arm, lower arm, hand and anything worn on them
	local shoulder=rig:FindFirstChild(r15 and "RightShoulder" or "Right Shoulder",true)
	local torso,upper=nil,nil
	if shoulder then torso,upper=ends(shoulder) end
	if torso and upper then
		local pivot
		if shoulder:IsA("JointInstance") then pivot=(shoulder.Part0.CFrame*shoulder.C0).Position else pivot=shoulder.Attachment0.WorldPosition end
		local arm={}
		for _,n in r15 and {"RightUpperArm","RightLowerArm","RightHand"} or {"Right Arm"} do
			local p=rig:FindFirstChild(n);if p then arm[p]=true end
		end
		for _,w in rig:GetDescendants() do
			local a,b=ends(w)
			if a and b and w~=shoulder and a:IsA("BasePart") and b:IsA("BasePart") then
				if arm[a] and not arm[b] and b~=torso then arm[b]=true
				elseif arm[b] and not arm[a] and a~=torso then arm[a]=true end
			end
		end
		-- held out in front, a touch below level and only slightly out to the side - a natural flashlight hold
		local turn=CFrame.new(pivot)*CFrame.Angles(0,math.rad(-12),0)*CFrame.Angles(math.rad(74),0,0)*CFrame.new(-pivot)
		local moved={}
		for p in arm do moved[p]=turn*p.CFrame end
		for p,cf in moved do p.CFrame=cf end
	end
	rig.Parent=pv.world
	pv.rig=rig;pv.r15=r15
	pv.hand=rig:FindFirstChild("RightHand") or rig:FindFirstChild("Right Arm")
	local cf,size=rig:GetBoundingBox()
	pv.focus=cf.Position+Vector3.new(0,-size.Y*.04,0)
	pv.dist=(size.Y*.86)/math.tan(math.rad(pv.cam.FieldOfView)/2)
	-- the camera turns about a point a little toward the held light, so the body and the light both stay
	-- in frame from every side
	-- the camera turns about a point just in front of the body (toward the held light), so seen from the
	-- front the avatar is dead centre, and from the sides the light still stays in frame
	local hand=pv.hand and pv.hand.Position or cf.Position
	local rp=root.Position -- the body's own centre (the raised arm would pull a bounding-box centre sideways)
	pv.focus=Vector3.new(rp.X,pv.focus.Y,rp.Z+(hand.Z-rp.Z)*.4)
end
-- Every flashlight you look at is built once and then kept in the preview's world: switching just
-- moves the new one into your hand and parks the old one far out of view. (Building a fresh copy on
-- every switch made the preview blink and the light jump for a frame.)
local PARK=CFrame.new(0,-5000,0)
function Controller:_SkinRecord(id)
	local pv=self._pv
	pv.skins=pv.skins or {}
	local rec=pv.skins[id]
	if rec and rec.model.Parent then return rec end
	local m=skinModel(id);if not m then return nil end
	m:ScaleTo(m:GetScale()*HOLD_SCALE*(SKIN_SCALE[id] or 1))
	local lens=m:FindFirstChild("Lens",true)
	local cf,size=m:GetBoundingBox()
	rec={model=m,orbit=OrbitParts.Collect(m),
		lensZ=lens and m:GetPivot():PointToObjectSpace(lens.Position).Z-.02 or -.7,
		lensR=lens and math.max(lens.Size.X,lens.Size.Y,lens.Size.Z)/2 or .17,
		tailZ=m:GetPivot():PointToObjectSpace(cf.Position).Z+size.Z/2}
	m:PivotTo(PARK)
	m.Parent=pv.world
	pv.skins[id]=rec
	return rec
end
function Controller:_SetSkin(id)
	local pv=self._pv
	if pv.skinId==id and pv.light and pv.light.Parent then return end
	local rec=self:_SkinRecord(id);if not rec then return end
	if pv.light and pv.light~=rec.model then pv.light:PivotTo(PARK) end
	pv.skinId=id
	pv.light=rec.model;pv.orbit=rec.orbit;pv.lensZ=rec.lensZ;pv.lensR=rec.lensR;pv.tailZ=rec.tailZ
	-- straight into the hand this very frame (never a frame anywhere else)
	if pv.hand then pv.light:PivotTo(holdFrame(pv.hand,pv.r15,pv.tailZ or .4)) end
end
-- builds the flashlights you can scroll through a few at a time in the background, so the first hover
-- over each one is as smooth as every later one
function Controller:_Prebuild()
	if self._prebuilt then return end
	self._prebuilt=true
	task.spawn(function()
		for _,e in Config.Flashlight or {} do
			if not self._pv then return end
			if self:_Revealed("Flashlight",e) then pcall(self._SkinRecord,self,e.Id) end
			task.wait()
		end
	end)
end
-- what the preview shows: the item you're hovering, otherwise what you have equipped
function Controller:_ShowPreview()
	local pv=self._pv;if not pv then return end
	local skin=(self._hoverSlot=="Flashlight" and self._hoverId) or self:_Equipped("Flashlight")
	local beam=(self._hoverSlot=="Beam" and self._hoverId) or self:_Equipped("Beam")
	self:_SetSkin(skin)
	local col,rainbow=beamColor(beam)
	pv.rainbow=rainbow;pv.beamId=beam
	if pv.wedge then LightWedge.SetColor(pv.wedge,col) end
	if pv.glow then TweenService:Create(pv.glow,FADE,{BackgroundColor3=col}):Play() end
	if pv.floor then TweenService:Create(pv.floor,FADE,{BackgroundColor3=col}):Play() end
	local slot,id=self._hoverSlot,self._hoverId
	if not slot then slot,id=(self._slot=="Beam") and "Beam" or "Flashlight",(self._slot=="Beam") and beam or skin end
	local e=entry(slot,id)
	if pv.name and e then pv.name.Text=e.Name end
	if pv.state and e then
		if self:_Equipped(slot)==id then pv.state.Text="EQUIPPED";pv.state.TextColor3=GREEN
		elseif Cosmetics.Owns(self._player,slot,id) then pv.state.Text="OWNED  ·  CLICK TO EQUIP";pv.state.TextColor3=WHITE
		elseif e.Pass then pv.state.Text="COMES WITH "..e.Pass;pv.state.TextColor3=GOLD
		elseif e.Price then pv.state.Text=commas(e.Price).." COINS  ·  IN THE SHOP";pv.state.TextColor3=GOLD
		elseif e.Box=="Jackpot" then pv.state.Text="ABYSSAL CASE JACKPOT  ·  1%";pv.state.TextColor3=Color3.fromHex("FF7AE0")
		elseif e.Box then pv.state.Text="ONLY IN MYSTERY BOXES";pv.state.TextColor3=Color3.fromHex("FF4F8B")
		else pv.state.Text="LOCKED";pv.state.TextColor3=FAINT end
	end
end
function Controller:_Render(dt)
	dt=math.min(dt,1/30)
	local pv=self._pv
	local now=os.clock()
	-- (the catalog tiles stay still; only the rainbow orbs cycle)
	for _,r in self._rows do if r.rainbow then r.rainbow.Rotation=(now*90)%360 end end
	if not pv or not pv.rig then return end
	pv.t+=dt
	local t=pv.t
	-- starts a little to the side (so the light is already showing the moment the locker opens), then
	-- slowly turns out to 70 degrees, back through the front to 70 degrees the other way and back again -
	-- a sine, so it eases to a gentle stop at each end and never jerks
	local SWEEP_PERIOD=36
	local a=math.rad(70)*math.sin(t/SWEEP_PERIOD*2*math.pi+.62)
	pv.cam.CFrame=CFrame.lookAt(pv.focus+Vector3.new(math.sin(a),.12,-math.cos(a)).Unit*pv.dist,pv.focus)
	if pv.rainbow then
		local col=beamColor(pv.beamId)
		if pv.wedge then LightWedge.SetColor(pv.wedge,col) end
		if pv.glow then pv.glow.BackgroundColor3=col end
		if pv.floor then pv.floor.BackgroundColor3=col end
	end
	if pv.light and pv.hand then
		local frame=holdFrame(pv.hand,pv.r15,pv.tailZ or .4)
		pv.light:PivotTo(frame)
		OrbitParts.Step(pv.orbit,t)
		if pv.wedge then
			-- work in the UI's own units (screen pixels divided by the UI scale)
			local size=pv.vp.AbsoluteSize/((self._uiScale and self._uiScale.Scale) or 1)
			local front=frame*Vector3.new(0,0,pv.lensZ-.02)
			local a,da=LightWedge.Project(pv.cam,size,front)
			local b=LightWedge.Project(pv.cam,size,front+frame.LookVector*3.4)
			-- the lens's radius on screen (a round lens seen at any angle is still that wide across the beam)
			local R=pv.lensR or .17
			local rimU=LightWedge.Project(pv.cam,size,front+frame.UpVector*R)
			local rimR=LightWedge.Project(pv.cam,size,front+frame.RightVector*R)
			local half=math.max((rimU-a).Magnitude,(rimR-a).Magnitude)
			local dir=b-a
			pv.wedge.Visible=da>.1 and dir.Magnitude>4
			-- pointing at (or away from) the camera there's no beam to see side-on: fade it out smoothly
			local side=1-math.abs(frame.LookVector:Dot(pv.cam.CFrame.LookVector))
			-- (only right when the light points straight down the lens; otherwise it's on with everything else)
			LightWedge.SetAlpha(pv.wedge,math.clamp((side-.03)/.1,0,1))
			if dir.Magnitude>4 then
				-- exactly on the lens every frame (no easing, so it never lags behind the flashlight), as wide
				-- as the lens, running out past the frame; one fixed size so it doesn't shimmer
				LightWedge.Place(pv.wedge,a,dir.Unit,math.floor(size.Magnitude*.8),half,nil,size.Y*.06,size)
			end
		end
	end
end
function Controller:SetOpen(open)
	if not self._panel then return end
	if open==self._fade:IsShown() then return end
	if open and self._shop then self._shop:SetOpen(false) end
	self._focus:Set("Locker",open)
	if open then
		self._hoverSlot,self._hoverId=nil,nil
		if self._pv then self._pv.t=0 end -- (every time it opens, the view starts straight on)
		self:_BuildAvatar()
		if self._pv then self:_Prebuild() end
		self:_Select(self._slot)
		self:_ShowPreview()
		if not self._bound then
			self._bound=true
			RunService:BindToRenderStep("BlackwaterLocker",Enum.RenderPriority.Last.Value,function(dt)self:_Render(dt)end)
		end
	elseif self._bound then
		self._bound=false
		RunService:UnbindFromRenderStep("BlackwaterLocker")
	end
	-- fades in/out as one piece (the panel stays on screen until the fade-out ends)
	self._fade:Show(open)
	if open then
		if Input.PreferredInput==Enum.PreferredInput.Gamepad and self._tabs[1] then GuiService.SelectedObject=self._tabs[1].button end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self._panel) then
		GuiService.SelectedObject=nil
	end
end
function Controller:Start()
	if not self._panel then return end
	self:_Select(self._slot)
	for _,attr in {"EHOwnedCosmetics","EHTitle","EHFlashlightSkin","EHFlashlightColor"} do
		self._scope:Add(self._player:GetAttributeChangedSignal(attr):Connect(function()self:_Refresh()end))
	end
	-- the shop and the locker never sit on top of each other; neither stays open inside an elevator
	local shopPanel=self._button.Parent:FindFirstChild("ShopPanel")
	if shopPanel then self._scope:Add(shopPanel:GetPropertyChangedSignal("Visible"):Connect(function()if shopPanel.Visible then self:SetOpen(false) end end)) end
	self._scope:Add(self._player:GetAttributeChangedSignal("EHPartyView"):Connect(function()
		if self._player:GetAttribute("EHPartyView")~=nil then self:SetOpen(false) end
	end))
end
function Controller:Destroy()
	if self._bound then self._bound=false;RunService:UnbindFromRenderStep("BlackwaterLocker") end
	if self._panel and self._panel.Visible then self._focus:Set("Locker",false) end
	if self._fade then self._fade:Snap(false) end
	if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
