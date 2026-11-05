--!nonstrict
-- SHOP. Everything you see is authored in StarterGui.ShopControls (edit it there):
--   ShopButton > Icon (the cart), ShineClip > Shine (UIGradient light sweep), NewBadge (+ UIScale "Pulse")
--                every few seconds a light sweeps across the button and the cart gives a little shake;
--                the NEW badge pulses until the shop is opened once this session
--   ShopPanel > Header (Title, Underline, Balance, Close)
--             > TabBar > Fill (+ Line)   the highlight that slides under the open tab
--             > Tabs > one TextButton per tab: attribute Tab = the page it opens (Pages.<Tab>),
--                      Accent = the highlight colour for that tab. Child "Label".
--             > Pages > Gamepasses, Coins, Skins, Colors
-- GAMEPASS CARDS: any frame with a GamePassId attribute and a "Buy" button. Opens the purchase prompt
--   and flips to OWNED once owned. Add a pass by copying a card and changing the id.
-- COIN PACKS: any frame with a "Pack" attribute (an Id in Config.CoinConfig.Packs) and a "Buy" button.
--   The Developer Product id comes from CoinConfig; with ProductId 0 the button reads COMING SOON.
-- COSMETIC CARDS (Skins / Colors pages, each a scrolling Grid): any frame with a Cosmetic attribute
--   "<Slot>:<Id>" naming a CosmeticsConfig entry with a Price, and a Buy button holding Row > CoinIcon + Label.
--   One button does it all: price -> buy with coins (the server equips it straight away), EQUIP once owned,
--   EQUIPPED for the one in use. Not enough coins flashes how many more are needed.
-- Header > Balance > Amount shows the player's coins (EHCoins) and counts up when it changes.
-- Card extras (all optional):
--   card attribute Featured = true     -> the border's "Sheen" gradient slowly turns
--   Buy attribute Verb                 -> text after the price ("GET VIP")
--   Art > Shine (frame + UIGradient)   -> a light sweep crosses the art every few seconds
--   Art > Sparkles > dots              -> drift upward and twinkle
--   UIStroke named "Halo"              -> breathes
--   ViewportFrame attribute Spin=true  -> its camera slowly orbits the model (Swing = degrees to rock
--                                         back and forth instead of a full turn)
--   model child "Floater"              -> hovers and turns on its own (the heart)
--   part attribute Orbit = rad/s       -> turns (Shared.Utilities.OrbitParts: rings, gears, planets on the flashlights)
--   part attribute Rainbow = 0..1      -> its colour cycles through every hue (offset by the value): the Rainbow beam
--   model child "Lid"                  -> swings open each time the shop opens (attribute ClosedAngle)
-- Only the open page animates, and models never move: the cameras orbit instead, which keeps it smooth.
-- Camera objects don't replicate, so each ViewportFrame stores its shot in attributes (CamCFrame,
-- CamFov) and a camera is made for it here on the client.
local GuiService=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local Marketplace=game:GetService("MarketplaceService")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local SoundService=game:GetService("SoundService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Responsive=require(Shared.Utilities.ResponsiveScale)
local AuthoredGui=require(Shared.Utilities.AuthoredGui)
local CoinConfig=require(Shared.Config.CoinConfig)
local CosmeticsConfig=require(Shared.Config.CosmeticsConfig)
local TokenConfig=require(Shared.Config.TokenConfig)
local BoxConfig=require(Shared.Config.MysteryBoxConfig)
local OrbitParts=require(Shared.Utilities.OrbitParts)
local Cosmetics=require(script.Parent.CosmeticsController)
local EQUIP_ATTR={Flashlight="EHFlashlightSkin",Beam="EHFlashlightColor"}
local Controller={}
Controller.__index=Controller
Controller.Name="ShopController"
Controller.Dependencies={"FocusController"}

local WHITE=Color3.fromRGB(235,232,225)
local FAINT=Color3.fromRGB(150,146,138)
local GREEN=Color3.fromRGB(110,220,130)
local GOLD=Color3.fromRGB(226,182,81)
local INK=Color3.fromRGB(10,10,12)
local RED=Color3.fromRGB(230,95,90)
local ROBUX="\u{E002}"
local HOVER=TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local SLIDE=TweenInfo.new(.38,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
-- quiet UI sounds (Cuelume set): hover tick, tab toggle, button release. Opening and closing the shop
-- are silent; the only purchase sound is the till's cha-ching once a purchase actually goes through.
local SOUNDS={
	Hover={Id="rbxassetid://118800406096048",Volume=.3},
	Tab={Id="rbxassetid://111764646352235",Volume=.45},
	Click={Id="rbxassetid://103859976078601",Volume=.5},
	Cash={Id="rbxassetid://120891770644830",Volume=.5},
}
local function commas(n)
	local s=tostring(math.floor(math.abs(n)+.5))
	local r=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
	return (n<0 and "-" or "")..(r:gsub("^,",""))
end

function Controller.new(player,gui)
	return setmetatable({_player=player,_gui=gui,_tabs={},_cards={},_packs={},_cosmetics={},_owned={},_spins={},_orbits={},_rainbows={},_shines={},_sheens={},_sparks={},_halos={},_sounds={},_lastHover=0},Controller)
end

-- ===== sound =====
function Controller:_Sound(name)
	local s=self._sounds[name]
	if s then SoundService:PlayLocalSound(s) end
end
function Controller:_HoverSound(gui)
	self._scope:Add(gui.MouseEnter:Connect(function()
		if os.clock()-self._lastHover<.05 then return end
		self._lastHover=os.clock();self:_Sound("Hover")
	end))
end

function Controller:Init(deps)
	self._focus=deps.FocusController
	self._scope=Scope.new()
	local gui=AuthoredGui.Get(self._gui,"ShopControls")
	self._button=gui:WaitForChild("ShopButton")
	self._panel=gui:WaitForChild("ShopPanel")
	self._close=self._panel:FindFirstChild("Close",true)
	self._pages=self._panel:WaitForChild("Pages")
	self._veil=self._panel:FindFirstChild("Veil")
	-- designed at 1200x675: the 860x500 panel takes about 72% of the screen on every device,
	-- scaled up or down as one piece (never reflowed)
	-- (on phones/tablets - touch screens - and very short windows a tighter 900x540 canvas: the shop and
	-- locker fill ~93% of the height, so everything is big enough to read and tap)
	Responsive.WatchDesignSize(gui,1200,675,.35,2.5,{Width=900,Height=540,Below=560})
	self._panel.Visible=false
	for name,spec in SOUNDS do
		local s=Instance.new("Sound");s.Name="Shop"..name;s.SoundId=spec.Id;s.Volume=spec.Volume;s.PlaybackSpeed=spec.Speed or 1;s.Parent=SoundService
		self._sounds[name]=s;self._scope:Add(s)
	end
	self._scope:Add(self._button.Activated:Connect(function()self:SetOpen(not self:IsOpen())end))
	self:_SetupAttention()
	self:_HoverSound(self._button)
	if self._close then
		self._scope:Add(self._close.Activated:Connect(function()self:_Sound("Click");self:SetOpen(false)end))
		self:_HoverSound(self._close)
	end
	self._scope:Add(Input.InputBegan:Connect(function(input)
		if self:IsOpen() and (input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB) then if self._contentsFor then self:_CloseContents() else self:SetOpen(false) end end
	end))
	-- tabs
	local list={}
	for _,b in self._panel:WaitForChild("Tabs"):GetChildren() do
		local id=b:IsA("GuiButton") and b:GetAttribute("Tab")
		if id then
			local t={button=b,id=id,label=b:FindFirstChild("Label"),accent=b:GetAttribute("Accent") or GOLD,order=b.LayoutOrder}
			table.insert(list,t)
			self._scope:Add(b.Activated:Connect(function()
				if self._tab~=id then self:_Sound("Tab") end
				self:_Select(id)
			end))
			self:_HoverSound(b)
			self._scope:Add(b.MouseEnter:Connect(function()if self._tab~=id and t.label then TweenService:Create(t.label,HOVER,{TextColor3=WHITE}):Play() end end))
			self._scope:Add(b.MouseLeave:Connect(function()if self._tab~=id and t.label then TweenService:Create(t.label,HOVER,{TextColor3=FAINT}):Play() end end))
		end
	end
	table.sort(list,function(a,b)return a.order<b.order end)
	for i,t in list do t.index=i end
	self._tabs=list
	self._tab=list[1] and list[1].id
	local bar=self._panel:FindFirstChild("TabBar")
	self._fill=bar and bar:FindFirstChild("Fill")
	-- cameras for every 3D view (see the note at the top)
	for _,vp in self._panel:GetDescendants() do
		if vp:IsA("ViewportFrame") and vp:GetAttribute("CamCFrame") then
			local cam=Instance.new("Camera")
			cam.Name="ShopCamera";cam.CFrame=vp:GetAttribute("CamCFrame");cam.FieldOfView=vp:GetAttribute("CamFov") or 30
			cam.Parent=vp;vp.CurrentCamera=cam
		end
	end
	-- moving art (each item remembers which page it is on, so only the open page animates)
	for _,page in self._pages:GetChildren() do
		for _,d in page:GetDescendants() do self:_Collect(d,page) end
	end
	-- gamepass cards
	for _,card in self._pages:GetDescendants() do
		local id=card:GetAttribute("GamePassId")
		local buy=id and card:FindFirstChild("Buy")
		if buy then
			local stroke=buy:FindFirstChildOfClass("UIStroke")
			local c={card=card,id=id,buy=buy,stroke=stroke,strokeT=stroke and stroke.Transparency or .55,strokeColor=stroke and stroke.Color or WHITE,text=buy.TextColor3,
				bg=buy.BackgroundColor3,bgT=buy.BackgroundTransparency,verb=buy:GetAttribute("Verb"),featured=card:GetAttribute("Featured")==true,
				accent=card:GetAttribute("Accent"),lift=card:FindFirstChild("Lift"),price=buy.Text,dot=card:FindFirstChild("OwnedDot",true),
				cardStroke=card:FindFirstChildOfClass("UIStroke")}
			c.cardStrokeT=c.cardStroke and c.cardStroke.Transparency
			table.insert(self._cards,c)
			self._scope:Add(buy.Activated:Connect(function()
				self:_Sound("Click")
				self:_Buy(c)
			end))
			self:_HoverSound(buy)
			self:_HoverLook(c,function()return not self._owned[id] end)
			self:_Paint(c)
		end
	end
	-- coin packs
	local byId={}
	for _,p in CoinConfig.Packs do byId[p.Id]=p end
	for _,card in self._pages:GetDescendants() do
		local pack=byId[card:GetAttribute("Pack") or ""]
		local buy=pack and card:FindFirstChild("Buy")
		if buy then
			local c={card=card,pack=pack,buy=buy,productId=pack.ProductId or 0,price=ROBUX.." "..pack.Price,bg=buy.BackgroundColor3,bgT=0,text=buy.TextColor3,
				lift=card:FindFirstChild("Lift"),accent=card:GetAttribute("Accent"),featured=card:GetAttribute("Featured")==true,cardStroke=card:FindFirstChildOfClass("UIStroke")}
			c.cardStrokeT=c.cardStroke and c.cardStroke.Transparency
			table.insert(self._packs,c)
			self._scope:Add(buy.Activated:Connect(function()
				self:_Sound("Click")
				if c.productId>0 then pcall(function()Marketplace:PromptProductPurchase(self._player,c.productId)end) end
			end))
			self:_HoverSound(buy)
			self:_HoverLook(c,function()return c.productId>0 end)
			self:_PaintPack(c)
		end
	end
	-- coin-shop cosmetics (flashlight skins, beam colours)
	local entries={}
	for slot in EQUIP_ATTR do for _,e in CosmeticsConfig[slot] do entries[slot..":"..e.Id]=e end end
	for _,card in self._pages:GetDescendants() do
		local key=card:GetAttribute("Cosmetic")
		local e=key and entries[key]
		local buy=e and e.Price and card:FindFirstChild("Buy")
		if buy then
			local slot,id=key:match("^(%w+):(%w+)$")
			local row=buy:FindFirstChild("Row")
			local stroke=buy:FindFirstChildOfClass("UIStroke")
			local c={card=card,slot=slot,id=id,e=e,buy=buy,label=row and row:FindFirstChild("Label"),icon=row and row:FindFirstChild("CoinIcon"),
				bg=buy.BackgroundColor3,shade=buy:FindFirstChild("Shade"),stroke=stroke,strokeColor=stroke and stroke.Color,
				accent=card:GetAttribute("Accent"),featured=card:GetAttribute("Featured")==true,cardStroke=card:FindFirstChildOfClass("UIStroke")}
			c.text=c.label and c.label.TextColor3 or INK
			c.cardStrokeT=c.cardStroke and c.cardStroke.Transparency
			table.insert(self._cosmetics,c)
			self._scope:Add(buy.Activated:Connect(function()self:_Sound("Click");self:_CosmeticPress(c)end))
			self:_HoverSound(buy)
			self._scope:Add(buy.MouseEnter:Connect(function()c.hoverBuy=true;self:_PaintCosmetic(c)end))
			self._scope:Add(buy.MouseLeave:Connect(function()c.hoverBuy=false;self:_PaintCosmetic(c)end))
			self._scope:Add(card.MouseEnter:Connect(function()c.hovered=true;self:_PaintCosmetic(c)end))
			self._scope:Add(card.MouseLeave:Connect(function()c.hovered=false;self:_PaintCosmetic(c)end))
			self:_PaintCosmetic(c)
		end
	end
	-- tokens (Jumpscare / Extra Life): Developer Products bought again and again; the card shows how many you have
	local tokenById={}
	for _,t in TokenConfig.Tokens do tokenById[t.Id]=t end
	self._tokens={}
	for _,card in self._pages:GetDescendants() do
		local t=tokenById[card:GetAttribute("Token") or ""]
		local buy=t and card:FindFirstChild("Buy")
		if buy then
			local c={card=card,t=t,buy=buy,productId=t.ProductId or 0,price=ROBUX.." "..t.Price,bg=buy.BackgroundColor3,bgT=0,text=buy.TextColor3,
				have=card:FindFirstChild("Have"),accent=card:GetAttribute("Accent"),cardStroke=card:FindFirstChildOfClass("UIStroke")}
			c.cardStrokeT=c.cardStroke and c.cardStroke.Transparency
			table.insert(self._tokens,c)
			self._scope:Add(buy.Activated:Connect(function()
				self:_Sound("Click")
				if c.productId>0 then pcall(function()Marketplace:PromptProductPurchase(self._player,c.productId)end) end
			end))
			self:_HoverSound(buy)
			self:_HoverLook(c,function()return c.productId>0 end)
			self._scope:Add(self._player:GetAttributeChangedSignal(t.Attr):Connect(function()self:_PaintToken(c)end))
			self:_PaintToken(c)
		end
	end
	-- mystery boxes: coin boxes open through the server; the Robux box is a Developer Product
	local boxById={}
	for _,b in BoxConfig.Boxes do boxById[b.Id]=b end
	self._boxes={}
	for _,card in self._pages:GetDescendants() do
		local b=boxById[card:GetAttribute("Box") or ""]
		local buy=b and card:FindFirstChild("Buy")
		if buy then
			local row=buy:FindFirstChild("Row")
			local c={card=card,b=b,buy=buy,productId=b.ProductId or 0,price=ROBUX.." "..(b.Price or 0),bg=buy.BackgroundColor3,bgT=0,text=buy.TextColor3,
				label=row and row:FindFirstChild("Label"),icon=row and row:FindFirstChild("CoinIcon"),stroke=buy:FindFirstChildOfClass("UIStroke"),
				accent=card:GetAttribute("Accent"),featured=card:GetAttribute("Featured")==true,cardStroke=card:FindFirstChildOfClass("UIStroke")}
			c.labelColor=c.label and c.label.TextColor3
			c.cardStrokeT=c.cardStroke and c.cardStroke.Transparency
			table.insert(self._boxes,c)
			self._scope:Add(buy.Activated:Connect(function()self:_Sound("Click");self:_BoxPress(c)end))
			self:_HoverSound(buy)
			self:_HoverLook(c,function()return b.Coins~=nil or c.productId>0 end)
			self:_PaintBox(c)
			local inside=card:FindFirstChild("Inside")
			if inside then
				self._scope:Add(inside.Activated:Connect(function()self:_Sound("Click");self:_ShowContents(c)end))
				self:_HoverSound(inside)
				self._scope:Add(inside.MouseEnter:Connect(function()TweenService:Create(inside,HOVER,{TextColor3=WHITE}):Play()end))
				self._scope:Add(inside.MouseLeave:Connect(function()TweenService:Create(inside,HOVER,{TextColor3=FAINT}):Play()end))
			end
		end
	end
	self:_SetupReveal()
	self:_SetupContents()
	-- header balance
	local bal=self._panel:FindFirstChild("Balance",true)
	self._balance=bal
	self._amount=bal and bal:FindFirstChild("Amount")
	self._shown=Instance.new("NumberValue")
	self._scope:Add(self._shown)
	self._scope:Add(self._shown.Changed:Connect(function(v)if self._amount then self._amount.Text=commas(v) end end))
end

-- hover look shared by both card types: the border fades to the card's colour and the buy button
-- brightens. Nothing scales or moves, so the 3D art and the borders stay pixel-steady.
function Controller:_HoverLook(c,canBuy)
	self._scope:Add(c.buy.MouseEnter:Connect(function()
		if canBuy() then TweenService:Create(c.buy,HOVER,{BackgroundColor3=c.bg:Lerp(Color3.new(1,1,1),.18)}):Play() end
	end))
	self._scope:Add(c.buy.MouseLeave:Connect(function()
		if canBuy() then TweenService:Create(c.buy,HOVER,{BackgroundColor3=c.bg}):Play() end
	end))
	self._scope:Add(c.card.MouseEnter:Connect(function()
		c.hovered=true
		if c.cardStroke and not c.featured and canBuy() then
			TweenService:Create(c.cardStroke,HOVER,{Color=c.accent or WHITE,Transparency=.25}):Play()
		end
	end))
	self._scope:Add(c.card.MouseLeave:Connect(function()
		c.hovered=false
		if c.cardStroke and not c.featured then
			local owned=c.id and self._owned[c.id]
			TweenService:Create(c.cardStroke,HOVER,{Color=owned and GREEN or WHITE,Transparency=owned and .55 or c.cardStrokeT}):Play()
		end
	end))
end

function Controller:_Collect(d,page)
	if d:IsA("ViewportFrame") then
		-- moving pieces (gears, halos, orbiting shards) on the flashlight models
		local list=OrbitParts.Collect(d)
		if #list>0 then table.insert(self._orbits,{list=list,page=page}) end
		for _,p in d:GetDescendants() do
			local off=p:IsA("BasePart") and p:GetAttribute("Rainbow")
			if off then table.insert(self._rainbows,{part=p,page=page,off=off}) end
		end
		-- the 2D light wedge drawn over the viewport (Shared.Utilities.LightWedge)
		local wedge=d.Parent and d.Parent:FindFirstChild("LightWedge")
		if wedge then
			for _,t in wedge:GetDescendants() do
				local off=t:IsA("GuiObject") and t:GetAttribute("Rainbow")
				if off then table.insert(self._rainbows,{label=t,page=page,off=off}) end
			end
		end
	end
	if d:IsA("ViewportFrame") and d:GetAttribute("Spin") then
		local m=d:FindFirstChildWhichIsA("Model")
		local cam=d.CurrentCamera or d:FindFirstChildWhichIsA("Camera")
		if m and cam then
			local small=d.Parent and d.Parent.Name=="Icon"
			local s={vp=d,page=page,model=m,cam=cam,baseCam=cam.CFrame,center=(m:GetBoundingBox()).Position,
				speed=small and .9 or .6,phase=#self._spins*1.7,swing=d:GetAttribute("Swing")}
			local floater=m:FindFirstChild("Floater")
			if floater then s.floater=floater;s.floatBase=floater:GetPivot();s.floatC=(floater:GetBoundingBox()).Position end
			local lid=m:FindFirstChild("Lid")
			if lid then
				s.lid=lid;s.lidBase=lid:GetPivot();s.lidClosed=math.rad(lid:GetAttribute("ClosedAngle") or 100)
				-- the card's glow behind the case brightens as the lid opens
				local glow=d.Parent and d.Parent:FindFirstChild("Glow")
				if glow and glow:IsA("GuiObject") then s.glow=glow;s.glowBase=glow.BackgroundTransparency end
			end
			table.insert(self._spins,s)
		end
	elseif d:IsA("UIGradient") and d.Parent and d.Parent.Name=="Shine" then
		table.insert(self._shines,{g=d,page=page,phase=#self._shines*1.1})
	elseif d:IsA("UIGradient") and d.Name=="Sheen" then
		table.insert(self._sheens,{g=d,page=page})
	elseif d:IsA("GuiObject") and d.Parent and d.Parent.Name=="Sparkles" then
		table.insert(self._sparks,{f=d,page=page,x=d.Position.X.Scale,y=d.Position.Y.Scale,speed=.035+(#self._sparks%5)*.012,phase=#self._sparks*.73})
	elseif d:IsA("UIStroke") and d.Name=="Halo" then
		table.insert(self._halos,{s=d,page=page,t=d.Transparency,th=d.Thickness})
	end
end

function Controller:_Select(id,instant)
	local prev=self._tab
	self._tab=id
	for _,t in self._tabs do
		local on=t.id==id
		if t.label then
			if instant then t.label.TextColor3=on and WHITE or FAINT
			else TweenService:Create(t.label,HOVER,{TextColor3=on and WHITE or FAINT}):Play() end
		end
		if on and self._fill then
			-- the highlight glides to the open tab and takes its colour
			local w=self._fill.Size.X.Offset
			local goal={Position=UDim2.fromOffset((t.index-1)*w,0),BackgroundColor3=t.accent}
			local line=self._fill:FindFirstChild("Line")
			if instant then
				self._fill.Position=goal.Position;self._fill.BackgroundColor3=t.accent
				if line then line.BackgroundColor3=t.accent end
			else
				TweenService:Create(self._fill,SLIDE,goal):Play()
				if line then TweenService:Create(line,SLIDE,{BackgroundColor3=t.accent}):Play() end
			end
		end
	end
	for _,page in self._pages:GetChildren() do
		if page:IsA("GuiObject") then page.Visible=(page.Name==id) end
	end
	if self._panel.Visible and id~=prev then self._lidT=0 end
end

-- ===== gamepasses =====
function Controller:_Paint(c)
	local owned=self._owned[c.id]
	if owned then
		c.buy.Text="OWNED";c.buy.TextColor3=GREEN
		c.buy.BackgroundColor3=INK;c.buy.BackgroundTransparency=.45
		if c.stroke then c.stroke.Color=GREEN;c.stroke.Transparency=.35;c.stroke.Thickness=1 end
		if c.cardStroke and not c.featured then c.cardStroke.Color=GREEN;c.cardStroke.Transparency=.55 end
	else
		c.buy.Text=c.verb and (c.price.."   ·   "..c.verb) or c.price;c.buy.TextColor3=c.text
		c.buy.BackgroundColor3=c.bg;c.buy.BackgroundTransparency=c.bgT
		if c.stroke then c.stroke.Color=c.strokeColor;c.stroke.Transparency=c.strokeT end
		if c.cardStroke and not c.featured then c.cardStroke.Color=WHITE;c.cardStroke.Transparency=c.cardStrokeT end
	end
	if c.dot then c.dot.Visible=owned==true end
end
function Controller:_Buy(c)
	if self._owned[c.id] then return end
	pcall(function()Marketplace:PromptGamePassPurchase(self._player,c.id)end)
end
function Controller:_Fetch()
	for _,c in self._cards do
		task.spawn(function()
			for attempt=1,3 do
				local ok,has=pcall(function()return Marketplace:UserOwnsGamePassAsync(self._player.UserId,c.id)end)
				if ok then self._owned[c.id]=self._owned[c.id] or has;break end
				task.wait(attempt)
			end
			self:_Paint(c)
		end)
		task.spawn(function()
			local ok,info=pcall(function()return Marketplace:GetProductInfo(c.id,Enum.InfoType.GamePass)end)
			if ok and info and info.PriceInRobux then c.price=ROBUX.." "..info.PriceInRobux;self:_Paint(c) end
		end)
	end
	-- tokens and the Robux box: live prices too
	for _,list in {self._tokens or {},self._boxes or {}} do
		for _,c in list do
			if c.productId>0 then task.spawn(function()
				local ok,info=pcall(function()return Marketplace:GetProductInfo(c.productId,Enum.InfoType.Product)end)
				if ok and info and info.PriceInRobux then
					c.price=ROBUX.." "..info.PriceInRobux
					if c.t then self:_PaintToken(c) else self:_PaintBox(c) end
				end
			end) end
		end
	end
	for _,c in self._packs do
		if c.productId>0 then task.spawn(function()
			local ok,info=pcall(function()return Marketplace:GetProductInfo(c.productId,Enum.InfoType.Product)end)
			if ok and info and info.PriceInRobux then c.price=ROBUX.." "..info.PriceInRobux;self:_PaintPack(c) end
		end) end
	end
end

-- ===== the SHOP button asking to be opened =====
function Controller:_SetupAttention()
	local b=self._button
	local clip=b:FindFirstChild("ShineClip")
	local shine=clip and clip:FindFirstChild("Shine")
	local grad=shine and shine:FindFirstChildOfClass("UIGradient")
	local icon=b:FindFirstChild("Icon")
	local badge=b:FindFirstChild("NewBadge")
	local pulse=badge and badge:FindFirstChild("Pulse")
	local stroke=b:FindFirstChildOfClass("UIStroke")
	local strokeColor,strokeT=stroke and stroke.Color,stroke and stroke.Transparency
	if pulse then
		local tw=TweenService:Create(pulse,TweenInfo.new(.7,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Scale=1.14})
		tw:Play();self._badgeTween=tw
	end
	self._badge=badge
	local alive=true
	self._scope:Add(function()alive=false end)
	task.spawn(function()
		while alive do
			task.wait(4.5)
			if not alive then break end
			-- only while the button is actually on screen (no panel open - FocusController hides it then)
			if not self:IsOpen() and b.Interactable and not (self._focus and self._focus:IsFocused()) then
				if grad then
					grad.Offset=Vector2.new(-1,0)
					TweenService:Create(grad,TweenInfo.new(.9,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{Offset=Vector2.new(1,0)}):Play()
				end
				if icon then
					for _,r in {-12,10,-6,0} do
						TweenService:Create(icon,TweenInfo.new(.09,Enum.EasingStyle.Sine),{Rotation=r}):Play()
						task.wait(.09)
					end
				end
				if stroke and self._badge then
					stroke.Color=GOLD;stroke.Transparency=0
					TweenService:Create(stroke,TweenInfo.new(1.2),{Color=strokeColor,Transparency=strokeT}):Play()
				end
			end
		end
	end)
end

-- ===== cosmetics (bought with coins) =====
function Controller:_EquippedId(slot)
	local v=self._player:GetAttribute(EQUIP_ATTR[slot])
	return (type(v)=="string" and v~="") and v or "Default"
end
function Controller:_PaintCosmetic(c)
	local owned=Cosmetics.Owns(self._player,c.slot,c.id)
	local equipped=owned and self:_EquippedId(c.slot)==c.id
	if equipped then c.pending=nil end
	local flash=c.flash and os.clock()<c.flash.until_ and c.flash.text
	local b,label,icon,stroke=c.buy,c.label,c.icon,c.stroke
	if not label then return end
	if c.shade then c.shade.Enabled=not owned and not flash end
	if flash then
		label.Text=flash;label.TextColor3=RED;if icon then icon.Visible=false end
		b.BackgroundColor3=INK;b.BackgroundTransparency=.3
		if stroke then stroke.Color=RED;stroke.Transparency=.3 end
	elseif c.pending then
		label.Text="· · ·";if icon then icon.Visible=false end
	elseif equipped then
		label.Text="EQUIPPED";label.TextColor3=GREEN;if icon then icon.Visible=false end
		b.BackgroundColor3=INK;b.BackgroundTransparency=.45
		if stroke then stroke.Color=GREEN;stroke.Transparency=.35 end
	elseif owned then
		label.Text="EQUIP";label.TextColor3=WHITE;if icon then icon.Visible=false end
		b.BackgroundColor3=c.hoverBuy and Color3.fromRGB(40,38,34) or INK;b.BackgroundTransparency=c.hoverBuy and .1 or .35
		if stroke then stroke.Color=WHITE;stroke.Transparency=c.hoverBuy and .15 or .55 end
	else
		label.Text=commas(c.e.Price);label.TextColor3=c.text;if icon then icon.Visible=true end
		b.BackgroundColor3=c.hoverBuy and c.bg:Lerp(Color3.new(1,1,1),.18) or c.bg;b.BackgroundTransparency=0
		if stroke then stroke.Color=c.strokeColor;stroke.Transparency=0 end
	end
	-- the card's border: green while it is the one in use, the card's colour on hover
	if c.cardStroke and not c.featured then
		if equipped then c.cardStroke.Color=GREEN;c.cardStroke.Transparency=.4
		elseif c.hovered then c.cardStroke.Color=c.accent or WHITE;c.cardStroke.Transparency=.25
		else c.cardStroke.Color=WHITE;c.cardStroke.Transparency=c.cardStrokeT end
	end
end
function Controller:_RefreshCosmetics()for _,c in self._cosmetics do self:_PaintCosmetic(c) end end
function Controller:_FlashCosmetic(c,text)
	c.flash={text=text,until_=os.clock()+1.4}
	self:_PaintCosmetic(c)
	task.delay(1.45,function()self:_PaintCosmetic(c)end)
end
function Controller:_CosmeticPress(c)
	if c.pending then return end
	local remote=game.ReplicatedStorage.Game.Network:FindFirstChild("Cosmetics")
	if not remote then return end
	if Cosmetics.Owns(self._player,c.slot,c.id) then
		if self:_EquippedId(c.slot)==c.id then return end
		remote:FireServer("Equip",c.slot,c.id)
	else
		local coins=self._player:GetAttribute("EHCoins")
		if type(coins)=="number" and coins<c.e.Price then
			self:_FlashCosmetic(c,"NEED "..commas(c.e.Price-coins).." MORE")
			-- straight to Roblox's purchase window for the smallest coin pack that covers the gap; the
			-- item is bought for them the moment the coins land
			self:_TopUp(c.e.Price,function()self:_CosmeticPress(c) end)
			return
		end
		remote:FireServer("Buy",c.slot,c.id)
	end
	local stamp=os.clock();c.pending=stamp
	self:_PaintCosmetic(c)
	-- never stuck on "..." if the server didn't answer
	task.delay(5,function()if c.pending==stamp then c.pending=nil;self:_PaintCosmetic(c) end end)
end
-- NOT ENOUGH COINS -> TOP UP. Picks the cheapest coin pack that covers the shortfall (price minus
-- balance) - never a bigger pack than needed, never one too small - and opens Roblox's purchase
-- window for it straight away. If even the largest pack falls short, the largest is offered. When
-- the coins arrive (within two minutes of buying), the original purchase goes through on its own;
-- closing the window without buying simply drops it.
function Controller:_PackFor(shortfall)
	local best,biggest
	for _,p in CoinConfig.Packs do
		if (p.ProductId or 0)>0 then
			if p.Coins>=shortfall and (not best or p.Coins<best.Coins) then best=p end
			if not biggest or p.Coins>biggest.Coins then biggest=p end
		end
	end
	return best or biggest
end
function Controller:_TopUp(price,resume)
	local coins=self._player:GetAttribute("EHCoins")
	if type(coins)~="number" or coins>=price then return false end
	local pack=self:_PackFor(price-coins)
	if not pack then return false end
	if self._topUp and os.clock()-self._topUp.at<1 then return true end -- (double tap)
	self._topUp={pack=pack,price=price,resume=resume,at=os.clock(),bought=false}
	self:_Sound("Click")
	pcall(function()Marketplace:PromptProductPurchase(self._player,pack.ProductId)end)
	return true
end
function Controller:_TopUpCoins()
	local t=self._topUp;if not t then return end
	if os.clock()-t.at>120 then self._topUp=nil;return end
	local coins=self._player:GetAttribute("EHCoins")
	if t.bought and type(coins)=="number" and coins>=t.price then
		self._topUp=nil
		task.delay(.6,function()if t.resume then t.resume() end end) -- (after the "+N" has started)
	end
end
-- open the shop straight on a tab (the locker sends you here to buy something)
function Controller:OpenTo(tab)
	if tab and self._pages:FindFirstChild(tab) then self._tab=tab end
	if self:IsOpen() then self:_Select(self._tab) else self:SetOpen(true) end
end

-- ===== coins =====
function Controller:_PaintPack(c)
	if c.productId>0 then
		c.buy.Text=c.price;c.buy.TextColor3=c.text
		c.buy.BackgroundColor3=c.bg;c.buy.BackgroundTransparency=0
	else
		-- not set up on the Creator Dashboard yet
		c.buy.Text="COMING SOON";c.buy.TextColor3=FAINT
		c.buy.BackgroundColor3=INK;c.buy.BackgroundTransparency=.4
	end
end
function Controller:_ShowBalance(animate)
	local coins=self._player:GetAttribute("EHCoins")
	if not self._amount then return end
	if type(coins)~="number" then self._amount.Text="…";return end
	if self._balanceTween then self._balanceTween:Cancel() end
	if animate and math.abs(coins-self._shown.Value)>=1 then
		self._balanceTween=TweenService:Create(self._shown,TweenInfo.new(math.clamp(math.abs(coins-self._shown.Value)/400,.4,1.4),Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Value=coins})
		self._balanceTween:Play()
	else
		self._shown.Value=coins;self._amount.Text=commas(coins)
	end
end
-- "+560" rising out of the balance (the shop's, or the coin chip when the shop is shut)
function Controller:_CoinPop(n,bal)
	bal=bal or self._balance;if not bal or n==0 then return end
	local l=Instance.new("TextLabel")
	l.Name="CoinPop";l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(1,1)
	l.FontFace=Font.new("rbxasset://fonts/families/RobotoMono.json",Enum.FontWeight.Bold);l.TextSize=18
	l.TextColor3=n>0 and GOLD or FAINT;l.Text=(n>0 and "+" or "")..commas(n);l.TextXAlignment=Enum.TextXAlignment.Right
	l.TextStrokeColor3=Color3.new(0,0,0);l.TextStrokeTransparency=.4
	l.Size=UDim2.fromOffset(160,22);l.Position=UDim2.new(1,-10,0,4);l.ZIndex=10;l.Parent=bal
	local sc=Instance.new("UIScale");sc.Scale=.6;sc.Parent=l
	TweenService:Create(sc,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
	TweenService:Create(l,TweenInfo.new(.45,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=UDim2.new(1,-10,0,-6)}):Play()
	task.delay(.9,function()
		if l.Parent then TweenService:Create(l,TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(1,-10,0,-22),TextTransparency=1,TextStrokeTransparency=1}):Play() end
	end)
	task.delay(1.6,function()l:Destroy() end)
	local stroke=bal:FindFirstChildOfClass("UIStroke")
	if stroke then
		local c0,t0=stroke.Color,stroke.Transparency
		stroke.Color=GOLD;stroke.Transparency=0
		TweenService:Create(stroke,TweenInfo.new(1.2),{Color=c0,Transparency=t0}):Play()
	end
end

-- the coin chip: when coins come in while the shop is shut, a copy of the shop's balance slides in above
-- the SHOP button, counts up to the new total under a "+N", and slides away again
local HUD_POS=UDim2.new(1,-20,.5,-86)
function Controller:_SetupCoinHud()
	local bal=self._balance;local screen=self._panel:FindFirstAncestorOfClass("ScreenGui")
	if not bal or not screen then return end
	local f=bal:Clone();f.Name="CoinHud";f.AnchorPoint=Vector2.new(1,1);f.Position=HUD_POS;f.Visible=false
	for _,c in f:GetChildren() do if c.Name=="CoinPop" then c:Destroy() end end
	f.Parent=screen
	local shown=Instance.new("NumberValue");self._scope:Add(shown);self._scope:Add(f)
	local amount=f:FindFirstChild("Amount")
	self._scope:Add(shown.Changed:Connect(function(v)if amount then amount.Text=commas(v) end end))
	self._hud={frame=f,shown=shown,n=0}
end
function Controller:_HudGain(from,to)
	local h=self._hud;if not h then return end
	h.n+=1;local my=h.n
	if not h.frame.Visible then
		h.shown.Value=from
		h.frame.Position=HUD_POS+UDim2.fromOffset(200,0);h.frame.Visible=true
		TweenService:Create(h.frame,TweenInfo.new(.35,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=HUD_POS}):Play()
	end
	if h.tween then h.tween:Cancel() end
	h.tween=TweenService:Create(h.shown,TweenInfo.new(math.clamp((to-h.shown.Value)/400,.6,1.6),Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Value=to})
	h.tween:Play()
	self:_CoinPop(to-from,h.frame)
	self:_Sound("Cash")
	task.delay(3.2,function()
		if h.n~=my or not h.frame.Parent then return end
		local t=TweenService:Create(h.frame,TweenInfo.new(.3,Enum.EasingStyle.Quint,Enum.EasingDirection.In),{Position=HUD_POS+UDim2.fromOffset(200,0)})
		t:Play();t.Completed:Wait()
		if h.n==my then h.frame.Visible=false end
	end)
end
-- the balance went up: "+N" and a count-up. While a mystery box is still sealed (or its result is
-- waiting behind Roblox's purchase window) the gain is held back so it can't spoil the prize; the
-- reveal lets it out when the box bursts.
function Controller:_CoinsChanged()
	local coins=self._player:GetAttribute("EHCoins")
	local last=self._lastCoins;self._lastCoins=coins
	if type(coins)~="number" or type(last)~="number" or coins<=last then
		if not self._heldCoins then self:_ShowBalance(self._panel.Visible) end
		return
	end
	local gain=coins-last
	self._heldCoins=(self._heldCoins or 0)+gain
	local stamp=os.clock();self._heldAt=stamp
	-- (a box result can land just after the coins: give it a moment before deciding)
	task.delay(.25,function()
		if self._heldAt~=stamp then return end
		local rv=self._reveal
		if (rv and rv.phase=="charge") or self._queuedResult then return end -- the reveal releases it
		self:_ReleaseCoins()
	end)
end
function Controller:_ReleaseCoins()
	local n=self._heldCoins;self._heldCoins=nil;self._heldAt=nil
	if not n or n<=0 then self:_ShowBalance(self._panel.Visible) return end
	local coins=self._player:GetAttribute("EHCoins")
	if type(coins)~="number" then return end
	if self._panel.Visible then
		self:_ShowBalance(true);self:_CoinPop(n)
	else
		self:_ShowBalance(false);self:_HudGain(coins-n,coins)
	end
end

-- ===== tokens =====
function Controller:_PaintToken(c)
	local n=self._player:GetAttribute(c.t.Attr)
	if c.have then c.have.Text="YOU HAVE "..(type(n)=="number" and commas(n) or "0") end
	if c.productId>0 then
		c.buy.Text=c.price.."   ·   BUY";c.buy.TextColor3=c.text
		c.buy.BackgroundColor3=c.bg;c.buy.BackgroundTransparency=0
	else
		c.buy.Text="COMING SOON";c.buy.TextColor3=FAINT
		c.buy.BackgroundColor3=INK;c.buy.BackgroundTransparency=.4
	end
end

-- ===== mystery boxes =====
function Controller:_PaintBox(c)
	local flash=c.flash and os.clock()<c.flash.until_ and c.flash.text
	if c.b.Coins then
		if not c.label then return end
		if flash then
			c.label.Text=flash;c.label.TextColor3=RED;if c.icon then c.icon.Visible=false end
			c.buy.BackgroundColor3=INK;c.buy.BackgroundTransparency=.3
			if c.stroke then c.stroke.Color=RED end
		elseif c.pending then
			c.label.Text="· · ·";if c.icon then c.icon.Visible=false end
		else
			c.label.Text=commas(c.b.Coins).."   ·   OPEN";c.label.TextColor3=c.labelColor;if c.icon then c.icon.Visible=true end
			c.buy.BackgroundColor3=c.bg;c.buy.BackgroundTransparency=0
			if c.stroke then c.stroke.Color=c.bg end
		end
	elseif c.productId>0 then
		c.buy.Text=c.price.."   ·   OPEN";c.buy.TextColor3=c.text
		c.buy.BackgroundColor3=c.bg;c.buy.BackgroundTransparency=0
	else
		c.buy.Text="COMING SOON";c.buy.TextColor3=FAINT
		c.buy.BackgroundColor3=INK;c.buy.BackgroundTransparency=.4
	end
end
function Controller:_FlashBox(c,text)
	c.flash={text=text,until_=os.clock()+1.4}
	self:_PaintBox(c)
	task.delay(1.45,function()self:_PaintBox(c)end)
end
function Controller:_BoxPress(c)
	if c.pending or self._reveal then return end
	-- (mystery boxes aren't offered where Roblox restricts paid random items; every cosmetic can still
	-- be bought directly in the shop)
	if self._player:GetAttribute("EHPaidRandomRestricted")~=false then self:_FlashBox(c,"NOT AVAILABLE HERE");return end
	if c.b.Coins then
		local coins=self._player:GetAttribute("EHCoins")
		if type(coins)=="number" and coins<c.b.Coins then self:_FlashBox(c,"NEED "..commas(c.b.Coins-coins).." MORE");self:_TopUp(c.b.Coins,function()self:_BoxPress(c) end);return end
		local remote=game.ReplicatedStorage.Game.Network:FindFirstChild("Cosmetics")
		if not remote then return end
		local stamp=os.clock();c.pending=stamp
		self:_PaintBox(c)
		remote:FireServer("OpenBox",c.b.Id)
		self:_ShowReveal(c.b)
		task.delay(6,function()
			if c.pending==stamp then c.pending=nil;self:_PaintBox(c);if self._reveal and not self._reveal.done then self:_CloseReveal() end end
		end)
	elseif c.productId>0 then
		-- (the unboxing waits until Roblox's purchase window has closed - see _RevealResult)
		self._promptOpen=os.clock()
		pcall(function()Marketplace:PromptProductPurchase(self._player,c.productId)end)
	end
end

-- ===== what's inside (one view per box) =====
-- A grid of everything the box can give - every one a box exclusive - with its rarity and chance.
local function skinArt(e)
	local art=game.ReplicatedStorage.Game:FindFirstChild("ShopArt")
	return art and art:FindFirstChild("Skins") and art.Skins:FindFirstChild(e.Model or "")
end
-- coin prizes are shot from the same side as their COINS-tab cards (the safe from its open-door side)
local COIN_DIRS={CoinPack_Vault=Vector3.new(-.58,.3,.76)}
local function coinDir(e)return COIN_DIRS[e.Model or ""] or Vector3.new(.2,.38,.9) end
local function coinArt(e)
	local art=game.ReplicatedStorage.Game:FindFirstChild("ShopArt")
	return art and art:FindFirstChild(e.Model or "")
end
local function tokenArt(t)
	local art=game.ReplicatedStorage.Game:FindFirstChild("ShopArt")
	return art and art:FindFirstChild(t.Model or "",true)
end
-- the side a token is shot from: straight at its decorated face (the coin's axis, on the side its
-- emblem sits), tipped a little so the rim shows
local tokenDirs={}
function Controller:_TokenDir(id)
	if tokenDirs[id] then return tokenDirs[id][1],tokenDirs[id][2] end
	local t;for _,x in TokenConfig.Tokens do if x.Id==id then t=x end end
	local art=game.ReplicatedStorage.Game:FindFirstChild("ShopArt")
	local model=t and art and art:FindFirstChild(t.Model or "",true)
	local dir=Vector3.new(1,.2,-.35)
	if model and typeof(model:GetAttribute("ViewDir"))=="Vector3" then
		dir=model:GetAttribute("ViewDir").Unit -- (set by hand on the model, in its own space)
	elseif model then
		local piv=model:GetPivot()
		local coin=model:FindFirstChild("Coin",true)
		if not coin then for _,p in model:GetDescendants() do if p:IsA("BasePart") and p.Shape==Enum.PartType.Cylinder and (not coin or p.Size.Y>coin.Size.Y) then coin=p end end end
		if coin then
			local axis=coin.CFrame.RightVector
			local sum,n=Vector3.zero,0
			for _,p in model:GetDescendants() do
				if p:IsA("BasePart") and p~=coin and p.Name~="Rim" and p.Size.Magnitude<coin.Size.Magnitude*.8 then sum+=p.Position;n+=1 end
			end
			local side=(n>0 and (sum/n-coin.Position):Dot(axis)<0) and -1 or 1
			local face=piv:VectorToObjectSpace(axis*side)
			local up=piv:VectorToObjectSpace(Vector3.yAxis)
			local across=face:Cross(up);across=across.Magnitude>1e-3 and across.Unit or Vector3.xAxis
			dir=(face+up*.18+across*.32).Unit
		end
	end
	tokenDirs[id]={dir,model}
	return dir,model
end
local function entryOf(slot,id)
	if slot=="Coins" then
		local c=BoxConfig.CoinPrize(id);if not c then return nil end
		return {Id=c.Id,Name=commas(c.Amount).." Coins",Amount=c.Amount,Model=c.Model,Rarity=c.Rarity}
	end
	if slot=="Token" then for _,t in TokenConfig.Tokens do if t.Id==id then return t end end return nil end
	for _,x in CosmeticsConfig[slot] or {} do if x.Id==id then return x end end
	return nil
end
-- a title prize is shown as the tag itself, in its own colour, the way it floats over your name
local function tagChip(parent,e,size)
	local l=parent:FindFirstChild("TagChip")
	if not l then
		l=Instance.new("TextLabel");l.Name="TagChip";l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(.5,.5)
		l.Position=UDim2.fromScale(.5,.5);l.Size=UDim2.fromScale(1,.5);l.TextScaled=true;l.Font=Enum.Font.GothamBlack
		l.TextStrokeColor3=Color3.new(0,0,0);l.TextStrokeTransparency=.35;l.ZIndex=(parent:IsA("GuiObject") and parent.ZIndex or 1)+2
		local c=Instance.new("UITextSizeConstraint");c.MaxTextSize=size or 22;c.Parent=l
		l.Parent=parent
	end
	l.Text="["..(e.Label or e.Name).."]";l.TextColor3=Color3.fromHex(e.Color or "EBE8E1");l.Visible=true
	return l
end
-- a still 3D shot of a model inside a small view
local function shoot(view,m,dir)
	for _,c in view:GetChildren() do if c:IsA("Model") or c:IsA("Camera") then c:Destroy() end end
	if not m then view.Visible=false return end
	m:PivotTo(CFrame.new());m.Parent=view
	local cf,size=m:GetBoundingBox()
	local cam=Instance.new("Camera");cam.FieldOfView=30;cam.Parent=view;view.CurrentCamera=cam
	local dist=(size.Magnitude/2)/math.sin(math.rad(15))*.92
	cam.CFrame=CFrame.lookAt(cf.Position+dir.Unit*dist,cf.Position)
	view.Visible=true
end
function Controller:_SetupContents()
	local r=self._panel:FindFirstChild("BoxContents");if not r then return end
	r.Visible=false
	local card=r:WaitForChild("Card")
	local grid=card:WaitForChild("Grid")
	local u={root=r,card=card,title=card:FindFirstChild("Title"),grid=grid,template=grid:WaitForChild("ItemTemplate"),open=card:FindFirstChild("Open"),
		close=card:FindFirstChild("Close"),stroke=card:FindFirstChildOfClass("UIStroke"),pop=card:FindFirstChild("Pop")}
	u.template.Visible=false
	self._contentsUI=u
	self._scope:Add(u.close.Activated:Connect(function()self:_Sound("Click");self:_CloseContents()end))
	self._scope:Add(u.open.Activated:Connect(function()
		local c=self._contentsFor;if not c then return end
		self:_Sound("Click");self:_CloseContents();self:_BoxPress(c)
	end))
	self:_HoverSound(u.close);self:_HoverSound(u.open)
end
function Controller:_ShowContents(c)
	local u=self._contentsUI;if not u then return end
	self._contentsFor=c
	local accent=Color3.fromHex(c.b.Accent)
	u.title.Text=c.b.Name
	if u.stroke then u.stroke.Color=accent end
	for _,x in u.grid:GetChildren() do if x:IsA("Frame") and x~=u.template then x:Destroy() end end
	for i,it in BoxConfig.Contents(c.b) do
		local e=entryOf(it.slot,it.id)
		if e then
			local t=u.template:Clone();t.Name=it.id;t.LayoutOrder=i;t.Visible=true
			local col=Color3.fromHex(BoxConfig.Colors[it.tier] or "EBE8E1")
			t.ItemName.Text=string.upper(e.Name)
			t.Tier.Text=it.jackpot and "JACKPOT" or it.slot=="Token" and (it.tier.."  TOKEN") or it.slot=="Coins" and (it.tier.."  COINS") or it.tier
			t.Tier.TextColor3=col;t.Strip.BackgroundColor3=col;t.Edge.Color=col;t.Edge.Transparency=it.jackpot and 0 or .55
			t.Chance.Text=(it.chance<1 and string.format("%.1f",it.chance) or string.format("%.1f",it.chance):gsub("%.0$",""))..'%'
			if it.slot=="Title" then
				t.Art.View.Visible=false
				tagChip(t.Art,e,20)
			elseif it.slot=="Beam" then
				local orb=t.Art.Orb;orb.Visible=true
				local c1=Color3.fromRGB(e.Beam[1],e.Beam[2],e.Beam[3])
				orb.BackgroundColor3=c1;orb.Halo.Color=c1
				if e.Pulse then
					local g=Instance.new("UIGradient");g.Color=ColorSequence.new(c1,Color3.fromRGB(e.Pulse[1],e.Pulse[2],e.Pulse[3]));g.Rotation=45;g.Parent=orb
					orb.BackgroundColor3=Color3.new(1,1,1)
				end
			elseif it.slot=="Coins" then
				local src=coinArt(e)
				t.Parent=u.grid
				shoot(t.Art.View,src and src:Clone(),coinDir(e))
			else
				local src=it.slot=="Token" and (select(2,self:_TokenDir(it.id)) or tokenArt(e)) or skinArt(e)
				t.Parent=u.grid -- (the view needs to be in the tree to show)
				shoot(t.Art.View,src and src:Clone(),it.slot=="Token" and self:_TokenDir(it.id) or Vector3.new(1,.4,-.5))
			end
			t.Parent=u.grid
		end
	end
	u.grid.CanvasPosition=Vector2.zero
	u.open.Text=c.b.Coins and (commas(c.b.Coins).."  ·  OPEN") or (c.productId>0 and (c.price.."  ·  OPEN") or "COMING SOON")
	u.open.AutoButtonColor=false
	u.open.BackgroundTransparency=(c.b.Coins or c.productId>0) and 0 or .6
	u.root.Visible=true
	if u.pop then u.pop.Scale=.94;TweenService:Create(u.pop,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
end
function Controller:_CloseContents()
	local u=self._contentsUI
	self._contentsFor=nil
	if u then u.root.Visible=false end
end

-- ===== the unboxing =====
-- 1. The box drops into the card with a heavy thud and starts to shudder. TAP TO OPEN: every tap (or click)
--    jolts it and lights a pip, while the light behind it flickers through the rarity colours like a
--    slot machine. Three taps - or a few seconds - and it bursts.
-- 2. The burst: white flash, the card punches out and shakes, confetti in the prize's colours, rays
--    spinning behind the prize, its name typed in and the rarity badge underneath. LEGENDARY and up
--    get a big stamp on top; ULTRA RARE and the jackpot go rainbow.
-- opens by itself after AUTO_OPEN seconds; the three stages (pips) light up on their own at even steps
-- through that time, and every click jumps a stage ahead
local AUTO_OPEN,TAPS,DROP=10,3,.45
-- embers thrown out by the burst (more for the better pulls)
local CONFETTI={COMMON=12,RARE=16,EPIC=22,LEGENDARY=28,MYTHIC=34,["ULTRA RARE"]=42,JACKPOT=48}
-- the tap kick spring (stiffness, damping)
local JOLT_K,JOLT_D=520,17
function Controller:_SetupReveal()
	local r=self._panel:FindFirstChild("BoxReveal");if not r then return end
	r.Visible=false
	local card=r:WaitForChild("Card")
	local v={root=r,card=card,view=card:FindFirstChild("View"),orb=card:FindFirstChild("Orb"),name=card:FindFirstChild("ItemName"),
		kicker=card:FindFirstChild("Kicker"),rarity=card:FindFirstChild("Rarity",true),pill=card:FindFirstChild("Pill"),note=card:FindFirstChild("Note"),
		equip=card:FindFirstChild("Equip"),done=card:FindFirstChild("Done"),glow=card:FindFirstChild("Glow"),rays=card:FindFirstChild("Rays"),
		flash=card:FindFirstChild("Flash"),halo=card:FindFirstChild("PrizeGlow"),stroke=card:FindFirstChildOfClass("UIStroke"),pop=card:FindFirstChild("Pop"),
		tap=card:FindFirstChild("TapArea"),hint=card:FindFirstChild("TapHint"),pips=card:FindFirstChild("Pips"),confetti=card:FindFirstChild("Confetti"),
		stamp=card:FindFirstChild("Stamp")}
	if v.kicker then v.kicker.Visible=false end -- (no grey "NEW TITLE" / box-name line: the prize says it)
	v.cardPos=card.Position
	local cam=Instance.new("Camera");cam.FieldOfView=30;cam.Parent=v.view;v.view.CurrentCamera=cam;v.cam=cam
	self._revealUI=v
	self._scope:Add(v.done.Activated:Connect(function()self:_Sound("Click");self:_CloseReveal()end))
	self._scope:Add(v.equip.Activated:Connect(function()
		self:_Sound("Click")
		local res=self._reveal and self._reveal.result
		local remote=game.ReplicatedStorage.Game.Network:FindFirstChild("Cosmetics")
		if res and remote then remote:FireServer("Equip",res.slot,res.id) end
		self:_CloseReveal()
	end))
	if v.tap then
		v.tap.Size=UDim2.fromScale(1,1);v.tap.Position=UDim2.new() -- (click anywhere on the card to open)
		self._scope:Add(v.tap.Activated:Connect(function()self:_RevealTap()end))
	end
	self:_HoverSound(v.done);self:_HoverSound(v.equip)
end
local function frameModel(cam,m,dir)
	local cf,size=m:GetBoundingBox()
	local dist=(size.Magnitude/2)/math.sin(math.rad(cam.FieldOfView/2))*.86
	return cf.Position,dist,dir.Unit
end
function Controller:_ShowView(m,dir)
	local v=self._revealUI
	for _,c in v.view:GetChildren() do if c:IsA("Model") then c:Destroy() end end
	if not m then return end
	m:PivotTo(CFrame.new());m.Parent=v.view
	local center,dist,d=frameModel(v.cam,m,dir)
	self._reveal.model=m;self._reveal.center=center;self._reveal.dist=dist;self._reveal.dir=d;self._reveal.base=m:GetPivot()
	self._reveal.orbit=OrbitParts.Collect(m)
	v.cam.CFrame=CFrame.lookAt(center+d*dist,center)
end
local function setRays(v,col,alpha)
	if not v.rays then return end
	for _,r in v.rays:GetChildren() do if r:IsA("Frame") then r.BackgroundColor3=col end end
	if alpha then v.rays.GroupTransparency=alpha end
end
local function paintPips(v,n,col)
	if not v.pips then return end
	for i=1,TAPS do local p=v.pips:FindFirstChild("Pip"..i);if p then p.BackgroundColor3=i<=n and col or Color3.fromRGB(235,232,225);p.BackgroundTransparency=i<=n and 0 or .75 end end
end
function Controller:_ShowReveal(box)
	local v=self._revealUI;if not v then return end
	-- (a Robux box can finish after you have closed the shop: open it again so you see your prize)
	if not self:IsOpen() then self:SetOpen(true) end
	self:_CloseContents()
	if v.confetti then v.confetti:ClearAllChildren() end
	self._reveal={box=box,started=os.clock(),t=0,phase="charge",taps=0,jx=0,jv=0,confetti={}}
	local accent=Color3.fromHex(box.Accent)
	v.kicker.Text=string.upper(box.Name);v.name.Text="";v.name.MaxVisibleGraphemes=-1;v.rarity.Text="";v.note.Text=""
	v.equip.Visible=false;v.done.Visible=false;v.orb.Visible=false
	do local chip=v.orb.Parent:FindFirstChild("TagChip");if chip then chip.Visible=false end end
	if v.pill then v.pill.Visible=false end
	if v.stamp then v.stamp.Visible=false end
	if v.flash then v.flash.BackgroundTransparency=1 end
	if v.halo then v.halo.BackgroundColor3=accent;v.halo.BackgroundTransparency=1 end
	if v.hint then v.hint.Visible=true;v.hint.Text=Input.PreferredInput==Enum.PreferredInput.Touch and "TAP THE BOX TO OPEN" or "CLICK THE BOX TO OPEN" end
	if v.pips then v.pips.Visible=true;paintPips(v,0,accent) end
	if v.tap then v.tap.Visible=true end
	setRays(v,accent,1)
	if v.glow then v.glow.BackgroundColor3=accent end
	if v.stroke then v.stroke.Color=accent;v.stroke.Transparency=.3 end
	v.card.Position=v.cardPos
	local art=game.ReplicatedStorage.Game:FindFirstChild("ShopArt")
	local src=art and art:FindFirstChild("Boxes") and art.Boxes:FindFirstChild(box.Model)
	self:_ShowView(src and src:Clone(),Vector3.new(.62,.42,-1))
	v.root.Visible=true
	if v.pop then v.pop.Scale=.85;TweenService:Create(v.pop,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
	self:_Modal(true)
end
-- While a box is being opened nothing else on screen can be clicked: a see-through blocker covers
-- the whole screen just under the shop (a click on it counts as a tap on the box), the shop is drawn
-- above every other screen, and the SHOP / LOCKER buttons, tabs and header are switched off.
function Controller:_Modal(on)
	local screen=self._panel:FindFirstAncestorOfClass("ScreenGui");if not screen then return end
	if on and not self._modal then
		local g=Instance.new("ScreenGui");g.Name="RevealBlocker";g.IgnoreGuiInset=true;g.ResetOnSpawn=false;g.Enabled=false
		local b=Instance.new("TextButton");b.Name="Blocker";b.Size=UDim2.fromScale(1,1);b.BackgroundTransparency=1;b.Text="";b.AutoButtonColor=false;b.Parent=g
		self._scope:Add(b.Activated:Connect(function()self:_RevealTap()end))
		g.Parent=screen.Parent
		self._modal={gui=g,order=screen.DisplayOrder}
		self._scope:Add(g)
	end
	local md=self._modal;if not md then return end
	if on then md.gui.DisplayOrder=97;screen.DisplayOrder=98 else screen.DisplayOrder=md.order end
	md.gui.Enabled=on
	for _,x in {screen:FindFirstChild("ShopButton"),screen:FindFirstChild("LockerButton"),self._panel:FindFirstChild("Header"),self._panel:FindFirstChild("Tabs"),self._panel:FindFirstChild("Pages")} do
		if x and x:IsA("GuiObject") then x.Interactable=not on end
	end
end
-- a tap on the box while it rattles
function Controller:_RevealTap()
	local rv=self._reveal;if not rv or rv.phase~="charge" or rv.t<DROP or rv.taps>=TAPS then return end
	rv.taps=math.min(TAPS,rv.taps+1)
	-- a kick into the spring, alternating sides, a little harder each time
	rv.jv+=(rv.taps%2==0 and -1 or 1)*(2.6+rv.taps*.5)
	local s=self._sounds and self._sounds.Click
	if s then s.PlaybackSpeed=.9+rv.taps*.18;SoundService:PlayLocalSound(s);task.delay(.2,function()s.PlaybackSpeed=1 end) end
	paintPips(self._revealUI,rv.taps,rv.tease or Color3.new(1,1,1))
	if rv.taps>=TAPS then rv.wantOpen=true end
end
function Controller:_RevealResult(boxId,slot,id,refund,tierName)
	for _,c in self._boxes do if c.b.Id==boxId then c.pending=nil;self:_PaintBox(c) end end
	-- a Robux box: the result can land while Roblox's purchase window is still on screen. It waits
	-- until that window has gone (or 25 s, in case the close is never reported), then the unboxing starts.
	if self._promptOpen and os.clock()-self._promptOpen<25 then
		self._queuedResult={boxId,slot,id,refund,tierName}
		return
	end
	if not self._reveal or self._reveal.box.Id~=boxId or self._reveal.phase~="charge" then
		local box;for _,b in BoxConfig.Boxes do if b.Id==boxId then box=b end end
		if not box then return end
		self:_ShowReveal(box)
	end
	local rv=self._reveal
	local e=entryOf(slot,id)
	if not e then self:_CloseReveal() return end
	local jackpot=rv.box.Jackpot and rv.box.Jackpot.Id==id and rv.box.Jackpot.Slot==slot
	local tier=tierName or (slot=="Coins" and e.Rarity) or (slot~="Token" and slot~="Coins" and BoxConfig.Rarity(slot,e)) or "RARE"
	rv.result={slot=slot,id=id,refund=refund,e=e,tier=tier,jackpot=jackpot,
		col=Color3.fromHex(BoxConfig.Colors[jackpot and "JACKPOT" or tier] or "EBE8E1")}
end
-- the burst
function Controller:_OpenReveal(rv)
	local v=self._revealUI
	local r=rv.result;local e,slot,col=r.e,r.slot,r.col
	rv.phase="open";rv.openedAt=rv.t;rv.col=col;rv.rainbowRays=r.jackpot or r.tier=="ULTRA RARE"
	if v.hint then v.hint.Visible=false end
	if v.pips then v.pips.Visible=false end
	if v.tap then v.tap.Visible=false end
	v.kicker.Text=r.jackpot and "JACKPOT!" or slot=="Token" and "YOU GOT A TOKEN" or slot=="Beam" and "NEW BEAM COLOR" or slot=="Title" and "NEW TITLE" or "NEW FLASHLIGHT"
	v.name.Text=e.Name;v.name.MaxVisibleGraphemes=0
	v.rarity.Text=r.jackpot and "JACKPOT  ·  ULTRA RARE" or r.tier;v.rarity.TextColor3=col
	if v.pill then
		v.pill.Visible=true;v.pill.BackgroundColor3=col
		local ps=v.pill:FindFirstChildOfClass("UIStroke");if ps then ps.Color=col end
		v.pill.Size=UDim2.fromOffset(20,24);TweenService:Create(v.pill,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(180,24)}):Play()
	end
	if slot=="Coins" then
		v.note.Text="+"..commas(e.Amount).." COINS";v.note.TextColor3=GOLD
	elseif slot=="Token" then
		local n=self._player:GetAttribute(e.Attr)
		v.note.Text="+1 TOKEN   ·   YOU HAVE "..commas(math.max(1,type(n)=="number" and n or 0));v.note.TextColor3=GREEN
	elseif r.refund and r.refund>0 then
		v.note.Text="ALREADY OWNED   ·   +"..commas(r.refund).." COINS";v.note.TextColor3=GOLD
	else
		v.note.Text="ADDED TO YOUR LOCKER";v.note.TextColor3=GREEN
	end
	if v.glow then v.glow.BackgroundColor3=col end
	if v.stroke then v.stroke.Color=col;v.stroke.Transparency=0 end
	-- a flash in the prize's own colour (not a white pop), fading out slowly like an afterglow
	if v.flash then v.flash.BackgroundColor3=col:Lerp(Color3.new(1,1,1),.35);v.flash.BackgroundTransparency=.15;TweenService:Create(v.flash,TweenInfo.new(.9,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play() end
	setRays(v,col,.15)
	if v.rays then TweenService:Create(v.rays,TweenInfo.new(1.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{GroupTransparency=.3}):Play() end
	if v.halo then v.halo.BackgroundColor3=col;v.halo.BackgroundTransparency=.4;TweenService:Create(v.halo,TweenInfo.new(.8),{BackgroundTransparency=.75}):Play() end
	v.done.Visible=true
	v.equip.Visible=not (r.refund and r.refund>0) and slot~="Token" and slot~="Coins"
	if not v.equip.Visible then v.done.Position=UDim2.new(1,-16,1,-16);v.done.Size=UDim2.new(1,-32,0,38)
	else v.done.Size=UDim2.new(.5,-22,0,38) end
	do local old=v.orb.Parent:FindFirstChild("TagChip");if old then old.Visible=false end end
	if slot=="Title" then
		self:_ShowView(nil)
		rv.model=nil
		v.orb.Visible=false
		local chip=tagChip(v.orb.Parent,e,26)
		chip.Position=v.orb.Position;chip.AnchorPoint=v.orb.AnchorPoint;chip.Size=UDim2.new(1,-90,0,30);chip.ZIndex=v.orb.ZIndex
		local cap=chip:FindFirstChildOfClass("UITextSizeConstraint");if cap then cap.MaxTextSize=26 end
		local sc=chip:FindFirstChildOfClass("UIScale") or Instance.new("UIScale",chip)
		sc.Scale=.2;TweenService:Create(sc,TweenInfo.new(.5,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
	elseif slot=="Coins" then
		self:_ShowView(coinArt(e) and coinArt(e):Clone(),coinDir(e))
		rv.rise=0
		v.orb.Visible=false
	elseif slot=="Flashlight" or slot=="Token" then
		local src=slot=="Token" and (select(2,self:_TokenDir(r.id)) or tokenArt(e)) or skinArt(e)
		self:_ShowView(src and src:Clone(),slot=="Token" and self:_TokenDir(r.id) or Vector3.new(1,.35,-.4))
		rv.rise=0
		v.orb.Visible=false
	else
		self:_ShowView(nil)
		rv.model=nil
		v.orb.Visible=true
		local c=e.Beam and Color3.fromRGB(e.Beam[1],e.Beam[2],e.Beam[3]) or col
		v.orb.BackgroundColor3=c
		local halo=v.orb:FindFirstChild("Halo");if halo then halo.Color=c end
		rv.rainbow=e.Rainbow==true
		rv.pulse=e.Pulse and {c,Color3.fromRGB(e.Pulse[1],e.Pulse[2],e.Pulse[3])} or nil
		local sc=v.orb:FindFirstChildOfClass("UIScale") or Instance.new("UIScale",v.orb)
		sc.Scale=.2;TweenService:Create(sc,TweenInfo.new(.5,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
	end
	-- the big stamp for the best pulls
	local big=r.jackpot or r.tier=="ULTRA RARE" or r.tier=="MYTHIC" or r.tier=="LEGENDARY"
	if v.stamp and big then
		v.stamp.Visible=true
		v.stamp.Text=r.jackpot and "JACKPOT!" or (r.tier.."!")
		v.stamp.TextColor3=col
		local b=v.stamp:FindFirstChildOfClass("UIScale")
		if b then b.Scale=2.4;TweenService:Create(b,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
	end
	-- embers: small glowing sparks in the prize's colour burst out of the box, then drift up and die
	if v.confetti then
		local n=CONFETTI[r.jackpot and "JACKPOT" or r.tier] or 16
		local rng=Random.new()
		local cols={col,col:Lerp(Color3.new(1,1,1),.3),col:Lerp(Color3.new(0,0,0),.35)}
		for i=1,n do
			local f=Instance.new("Frame");f.BorderSizePixel=0
			local sz=rng:NextNumber(3,6.5)
			f.Size=UDim2.fromOffset(sz,sz)
			f.AnchorPoint=Vector2.new(.5,.5);f.ZIndex=38;f.BackgroundTransparency=1
			f.BackgroundColor3=rv.rainbowRays and Color3.fromHSV(rng:NextNumber(),.5,.95) or cols[rng:NextInteger(1,#cols)]
			local c=Instance.new("UICorner");c.CornerRadius=UDim.new(.5,0);c.Parent=f
			f.Parent=v.confetti
			local ang=rng:NextNumber(0,math.pi*2)
			local spd=rng:NextNumber(110,330)
			table.insert(rv.confetti,{f=f,x=170+math.cos(ang)*14,y=150+math.sin(ang)*14,vx=math.cos(ang)*spd,vy=math.sin(ang)*spd*.8-60,
				rot=rng:NextNumber(0,360),vr=rng:NextNumber(-90,90),life=rng:NextNumber(1.3,2.4),age=0,ph=rng:NextNumber(0,10)})
		end
	end
	rv.shake=.4
	self:_Sound("Cash")
	if self._heldCoins then task.delay(.5,function()self:_ReleaseCoins()end) end
	if v.pop then v.pop.Scale=1.07;TweenService:Create(v.pop,TweenInfo.new(.55,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Scale=1}):Play() end
end
function Controller:_RevealFailed(boxId,reason)
	for _,c in self._boxes do
		if c.b.Id==boxId then
			c.pending=nil
			if reason=="Restricted" then self:_FlashBox(c,"NOT AVAILABLE HERE") elseif reason=="Funds" then self:_FlashBox(c,"NOT ENOUGH COINS");if c.b.Coins then self:_TopUp(c.b.Coins,function()self:_BoxPress(c) end) end else self:_FlashBox(c,"TRY AGAIN") end
		end
	end
	self:_CloseReveal()
end
function Controller:_CloseReveal()
	local v=self._revealUI
	self._reveal=nil
	if self._heldCoins then self:_ReleaseCoins() end
	self:_Modal(false)
	if not v then return end
	v.root.Visible=false
	v.card.Position=v.cardPos
	v.name.MaxVisibleGraphemes=-1
	if v.confetti then v.confetti:ClearAllChildren() end
	for _,c in v.view:GetChildren() do if c:IsA("Model") then c:Destroy() end end
end
-- every frame while the reveal is up
function Controller:_AnimateReveal(dt)
	local rv=self._reveal;if not rv then return end
	rv.t+=dt
	local v=self._revealUI
	if rv.phase=="charge" then
		-- the stages come on their own at even steps through the wait (as if tapped), so the pips, the
		-- shudder and the build-up always line up with the time left
		local due=math.floor((rv.t-DROP)/((AUTO_OPEN-DROP)/TAPS)+1e-6)
		if due>rv.taps and rv.t>=DROP then self:_RevealTap() end
		rv.k=(rv.k or 0)+(math.clamp(rv.taps/TAPS,0,1)-(rv.k or 0))*(1-math.exp(-dt*5))
		local k=rv.k
		-- each tap is a kick into a stiff, lightly damped spring: one solid thunk that settles in a couple
		-- of wobbles (stepped at 240 Hz, so it is identical at any frame rate)
		local steps=math.max(1,math.ceil(dt*240));local h=dt/steps
		for _=1,steps do rv.jv+=(-JOLT_K*rv.jx-JOLT_D*rv.jv)*h;rv.jx+=rv.jv*h end
		-- the slot machine: the light flickers through the rarity colours, faster as it builds (the rays are
		-- only recoloured when the colour actually changes - recolouring every frame is what made it stutter)
		rv.spin=(rv.spin or 0)+dt*(4+11*k)
		local order=BoxConfig.Order
		local idx=math.floor(rv.spin)%#order+1
		if idx~=rv.teaseIdx then
			rv.teaseIdx=idx
			local tease=Color3.fromHex(BoxConfig.Colors[order[idx]] or "FFFFFF")
			rv.tease=tease
			setRays(v,tease)
			if v.halo then v.halo.BackgroundColor3=tease end
			if v.stroke then v.stroke.Color=tease end
		end
		if v.rays then v.rays.GroupTransparency=1-.5*k;v.rays.Rotation=(v.rays.Rotation+dt*(30+170*k))%360 end
		if v.halo then v.halo.BackgroundTransparency=1-.42*k end
		if v.hint then v.hint.TextTransparency=.15+.45*(.5+.5*math.sin(rv.t*4)) end
		if rv.result and ((rv.wantOpen and rv.t>DROP+.15) or rv.t>=AUTO_OPEN) then self:_OpenReveal(rv);return end
		if rv.model and rv.center then
			-- a heavy drop (it gathers speed and lands with a thud), then it shudders harder and harder.
			-- All smooth noise and springs - nothing that steps between frames - and the box itself never
			-- moves: the viewport's camera takes the opposite motion, which looks identical and is far cheaper.
			local u=math.clamp(rv.t/DROP,0,1)
			local fall=2.2*(1-u*u)
			local land=rv.t-DROP
			local thud=land>0 and .09*math.exp(-land*10)*math.sin(land*24) or 0
			local s=u>=1 and (.008+.05*k*k) or 0
			local f=rv.t*(4.5+6*k)
			local x=math.noise(f,1.3)*s*2
			local y=fall-thud+math.noise(f,7.1)*s+rv.jx*.45
			local roll=math.noise(f,13.7)*s*2.4+rv.jx*.8
			local pitch=math.noise(f,21.9)*s*1.4-rv.jx*.25
			local c=rv.center
			-- (framed with room to spare, so even at its biggest shudder the box never touches the edges)
			local cam=CFrame.lookAt(c+rv.dir*rv.dist*(1.32-.1*k),c)
			local move=CFrame.new(c)*CFrame.new(x,y,0)*CFrame.Angles(pitch,0,roll)*CFrame.new(-c)
			v.cam.CFrame=move:Inverse()*cam
		end
		return
	end
	-- opened
	local since=rv.t-(rv.openedAt or 0)
	if v.rays then v.rays.Rotation=(v.rays.Rotation+dt*(18+120*math.exp(-since*2)))%360 end
	if rv.rainbowRays then
		local c=Color3.fromHSV((rv.t*.08)%1,.5,.92)
		setRays(v,c)
		if v.stroke then v.stroke.Color=c end
		if v.stamp and v.stamp.Visible then v.stamp.TextColor3=c end
	end
	-- the name types itself in
	if v.name.MaxVisibleGraphemes>=0 then
		local n=math.floor(since*30)
		if n>=#v.name.Text then v.name.MaxVisibleGraphemes=-1 else v.name.MaxVisibleGraphemes=n end
	end
	-- the card shudders for a moment on the burst (smooth noise, easing out)
	if rv.shake and rv.shake>0 then
		rv.shake=math.max(0,rv.shake-dt)
		local a=(rv.shake/.4)^2*10
		local f=rv.t*16
		v.card.Position=v.cardPos+UDim2.fromOffset(math.noise(f,3.3)*a,math.noise(f,9.1)*a)
		if rv.shake==0 then v.card.Position=v.cardPos end
	end
	if v.stamp and v.stamp.Visible then v.stamp.Rotation=-6+math.sin(rv.t*3)*2 end
	-- embers: thrown out by the burst, they slow, then drift upward and flicker out
	for i=#rv.confetti,1,-1 do
		local c=rv.confetti[i]
		c.age+=dt
		if c.age>=c.life then c.f:Destroy();table.remove(rv.confetti,i)
		else
			local drag=math.exp(-dt*3.2)
			c.vx*=drag;c.vy=c.vy*drag-70*dt
			c.x+=(c.vx+math.sin(c.age*2.6+c.ph)*14)*dt;c.y+=c.vy*dt;c.rot+=c.vr*dt*drag
			c.f.Position=UDim2.fromScale(c.x/340,c.y/420);c.f.Rotation=c.rot
			local life=c.age/c.life
			c.f.BackgroundTransparency=math.clamp(.05+life*life*.95+math.noise(c.age*6,c.ph)*.25,0,1)
		end
	end
	if rv.model and rv.center then
		-- the prize rises up out of the burst and turns slowly
		local up=math.clamp(since/.45,0,1);up=1-(1-up)^3
		local a=since*.7
		local d=CFrame.fromAxisAngle(Vector3.yAxis,a)*rv.dir
		v.cam.CFrame=CFrame.lookAt(rv.center+d*rv.dist*(1.65-.4*up)+Vector3.new(0,-(1-up)*rv.dist*.25,0),rv.center)
		if rv.orbit then OrbitParts.Step(rv.orbit,rv.t) end
	end
	if rv.pulse and v.orb.Visible then
		local c=rv.pulse[1]:Lerp(rv.pulse[2],.5-.5*math.cos(rv.t*.9))
		v.orb.BackgroundColor3=c
		local halo=v.orb:FindFirstChild("Halo");if halo then halo.Color=c end
	end
	if rv.rainbow and v.orb.Visible then
		local c=Color3.fromHSV((rv.t*.12)%1,.72,1)
		v.orb.BackgroundColor3=c
		local halo=v.orb:FindFirstChild("Halo");if halo then halo.Color=c end
	end
end

-- ===== animation (open page only) =====
-- Everything runs on one clock that advances by the frame time, capped at 1/30 s per frame, so a
-- slow frame (the moment a page first appears) never makes anything jump.
-- The unboxing: one clean, unhurried swing - the lid lifts gently, opens in a single smooth arc
-- and comes to rest softly (no pause, no bounce). Light spills out of the case as it opens.
local LID_DELAY,LID_TIME=.18,1.35
local function lidOpen(t) -- 0 shut .. 1 open
	local u=math.clamp((t-LID_DELAY)/LID_TIME,0,1)
	return u*u*u*(u*(u*6-15)+10) -- smootherstep: zero speed and acceleration at both ends
end
function Controller:_Animate(dt)
	dt=math.min(dt or 1/60,1/30)
	self._clock=(self._clock or 0)+dt
	self._lidT=(self._lidT or 0)+dt
	local t=self._clock
	self:_AnimateReveal(dt)
	-- (while a box is opening the page behind it holds still, so the unboxing gets the whole frame)
	if self._reveal then return end
	local open=self._pages:FindFirstChild(self._tab or "")
	for _,s in self._spins do
		if s.page==open then
			-- the camera orbits; the model stays still (cheap to draw, perfectly smooth)
			-- swinging cards rock slowly side to side on a sine, so they ease to a stop and glide back
			local a=s.swing and math.rad(s.swing)*math.sin(t*s.speed*.7+s.phase) or (s.floater and 0 or t*s.speed+s.phase)
			local bob=(s.floater or s.lid) and 0 or math.sin(t*1.6+s.phase)*.03
			s.cam.CFrame=CFrame.new(s.center)*CFrame.Angles(0,-a,0)*CFrame.new(-s.center)*s.baseCam*CFrame.new(0,-bob,0)
			if s.floater then
				local up=.08+math.sin(t*1.8)*.07
				local turn=CFrame.new(s.floatC+Vector3.new(0,up,0))*CFrame.Angles(0,math.rad(28)*math.sin(t*.9),0)*CFrame.new(-s.floatC)
				s.floater:PivotTo(turn*s.floatBase)
			end
			if s.lid then
				-- unboxing: the lid lifts open each time the shop (or this tab) opens
				local k=lidOpen(self._lidT)
				if k~=s.lidK then
					s.lidK=k
					s.lid:PivotTo(s.lidBase*CFrame.Angles(s.lidClosed*(1-k),0,0))
					if s.glow then s.glow.BackgroundTransparency=s.glowBase+(1-s.glowBase)*.75*(1-math.clamp(k,0,1)) end
				end
			end
		end
	end
	for _,o in self._orbits do
		if o.page==open then OrbitParts.Step(o.list,t) end
	end
	for _,r in self._rainbows do
		if r.page==open then
			local c=Color3.fromHSV((t*.12+r.off)%1,.72,1)
			if r.part then r.part.Color=c elseif r.label:IsA("TextLabel") then r.label.TextColor3=c else r.label.BackgroundColor3=c end
		end
	end
	for _,s in self._shines do
		if s.page==open then
			local k=((t+s.phase)%3.4)/.9
			s.g.Offset=Vector2.new(k<1 and (-1+2*k) or -1,0)
		end
	end
	for _,s in self._sheens do if s.page==open then s.g.Rotation=(t*45)%360 end end
	for _,s in self._sparks do
		if s.page==open then
			local y=(s.y-t*s.speed)%1
			s.f.Position=UDim2.fromScale(s.x+math.sin(t*1.3+s.phase)*.015,y)
			local tw=.5+.5*math.sin(t*3+s.phase*2)
			local edge=math.min(1,y/.15,(1-y)/.15)
			s.f.BackgroundTransparency=1-(.25+.6*tw)*edge
		end
	end
	-- glows breathe by fading only (changing a border's thickness makes it shimmer)
	local pulse=.5+.5*math.sin(t*2.4)
	for _,h in self._halos do if h.page==open then h.s.Transparency=h.t+(1-h.t)*.6*pulse end end
	for _,c in self._cards do
		if c.featured and c.stroke and not self._owned[c.id] then c.stroke.Thickness=2;c.stroke.Transparency=.1+.5*pulse end
	end
end

-- Opening eases the panel up a few pixels while its contents fade in from the panel colour
-- (ShopPanel.Veil), in step with the background blur; closing is the same, quicker, in reverse.
local OPEN_MOVE=TweenInfo.new(.32,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
local OPEN_FADE=TweenInfo.new(.26,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local CLOSE=TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
function Controller:_Transition(open)
	local panel,veil=self._panel,self._veil
	self._home=self._home or panel.Position
	self._transition=(self._transition or 0)+1
	local id=self._transition
	if open then
		panel.Position=self._home+UDim2.fromOffset(0,12)
		if veil then veil.BackgroundTransparency=0;TweenService:Create(veil,OPEN_FADE,{BackgroundTransparency=1}):Play() end
		TweenService:Create(panel,OPEN_MOVE,{Position=self._home}):Play()
	else
		if veil then TweenService:Create(veil,CLOSE,{BackgroundTransparency=0}):Play() end
		TweenService:Create(panel,CLOSE,{Position=self._home+UDim2.fromOffset(0,6)}):Play()
		task.delay(CLOSE.Time,function()
			if self._transition==id and self._closing then panel.Visible=false;panel.Position=self._home;self._closing=false end
		end)
	end
end
function Controller:IsOpen()return self._panel.Visible and not self._closing end
function Controller:SetOpen(open)
	if open==self:IsOpen() then return end
	if open then self._closing=false;self._panel.Visible=true else self._closing=true;self:_CloseReveal();self:_CloseContents() end
	if open and self._badge then
		-- seen it: the NEW badge goes away for this session
		if self._badgeTween then self._badgeTween:Cancel() end
		self._badge.Visible=false;self._badge=nil
	end
	self:_Transition(open)
	if self._focus then self._focus:Set("Shop",open) end
	if open then
		self._lidT=0
		self:_Select(self._tab,true)
		self:_ShowBalance(false)
		if not self._animating then
			self._animating=true
			self:_Animate(0)
			RunService:BindToRenderStep("BlackwaterShopArt",Enum.RenderPriority.Last.Value,function(dt)self:_Animate(dt)end)
		end
		if Input.PreferredInput==Enum.PreferredInput.Gamepad then GuiService.SelectedObject=self._close end
	else
		if self._animating then self._animating=false;RunService:UnbindFromRenderStep("BlackwaterShopArt") end
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self._panel) then GuiService.SelectedObject=nil end
	end
end

function Controller:Start()
	self:_Select(self._tab,true)
	self:_Fetch()
	-- download every mesh / image the shop and locker use right away, so the coin models and
	-- flashlights are already there the first time a panel opens
	task.spawn(function()
		local list={}
		local screen=self._panel:FindFirstAncestorOfClass("ScreenGui")
		if screen then table.insert(list,screen) end
		local art=game.ReplicatedStorage.Game:FindFirstChild("ShopArt")
		if art then table.insert(list,art) end
		pcall(function()game:GetService("ContentProvider"):PreloadAsync(list)end)
	end)
	-- Roblox's purchase window has closed: a box bought with Robux opens now (a moment later, once the
	-- window has faded away)
	local function flushQueued()
		self._promptOpen=nil
		local q=self._queuedResult;self._queuedResult=nil
		if q then task.delay(.35,function()self:_RevealResult(table.unpack(q,1,5))end) end
	end
	self._scope:Add(Marketplace.PromptProductPurchaseFinished:Connect(function(userId,productId,bought)
		if userId~=self._player.UserId then return end
		flushQueued()
		-- a top-up window closed: bought -> wait for the coins and finish the purchase; cancelled -> drop it
		local t=self._topUp
		if t and t.pack.ProductId==productId then
			if bought then t.bought=true;t.at=os.clock();self:_TopUpCoins() else self._topUp=nil end
		end
	end))
	-- (if the close is never reported, the result is shown anyway after the wait in _RevealResult)
	self._scope:Add(game:GetService("RunService").Heartbeat:Connect(function()
		if self._queuedResult and self._promptOpen and os.clock()-self._promptOpen>=25 then flushQueued() end
	end))
	self._scope:Add(Marketplace.PromptGamePassPurchaseFinished:Connect(function(player,id,bought)
		if player~=self._player or not bought then return end
		self:_Sound("Cash")
		self._owned[id]=true
		for _,c in self._cards do if c.id==id then self:_Paint(c) end end
	end))
	-- coins
	self:_ShowBalance(false)
	self._lastCoins=self._player:GetAttribute("EHCoins")
	self:_SetupCoinHud()
	self._scope:Add(self._player:GetAttributeChangedSignal("EHCoins"):Connect(function()self:_CoinsChanged();self:_TopUpCoins() end))
	task.spawn(function()
		local remote=game.ReplicatedStorage.Game.Network:WaitForChild("Coins",15)
		if remote then self._scope:Add(remote.OnClientEvent:Connect(function(kind,n)
			if kind=="Bought" then self:_Sound("Cash") end
			-- (the "+N" itself comes from the balance changing: _CoinsChanged)
		end)) end
	end)
	-- cosmetics: repaint when ownership / what's equipped changes; purchase results from the server
	for _,attr in {"EHOwnedCosmetics","EHFlashlightSkin","EHFlashlightColor"} do
		self._scope:Add(self._player:GetAttributeChangedSignal(attr):Connect(function()self:_RefreshCosmetics()end))
	end
	task.spawn(function()
		local remote=game.ReplicatedStorage.Game.Network:WaitForChild("Cosmetics",15)
		if remote then self._scope:Add(remote.OnClientEvent:Connect(function(kind,slot,id,reason,extra,tier)
			-- mystery boxes: ("BoxResult",boxId,slot,id,refund,rarity) / ("BoxFailed",boxId,reason)
			if kind=="BoxResult" then self:_RevealResult(slot,id,reason,extra,tier) return end
			if kind=="BoxFailed" then self:_RevealFailed(slot,id) return end
			if kind~="Bought" and kind~="BuyFailed" then return end
			for _,c in self._cosmetics do
				if c.slot==slot and c.id==id then
					c.pending=nil
					if kind=="Bought" then
						self:_Sound("Cash")
						if self._panel.Visible then self:_CoinPop(-c.e.Price) end
						self:_PaintCosmetic(c)
					elseif reason=="Funds" then self:_FlashCosmetic(c,"NOT ENOUGH COINS");self:_TopUp(c.e.Price,function()self:_CosmeticPress(c) end)
					elseif reason=="Unavailable" then self:_FlashCosmetic(c,"TRY AGAIN")
					else self:_PaintCosmetic(c) end
				end
			end
		 end)) end
	end)
	-- a token arriving after a Robux purchase
	task.spawn(function()
		local remote=game.ReplicatedStorage.Game.Network:WaitForChild("Tokens",15)
		if remote then self._scope:Add(remote.OnClientEvent:Connect(function(kind)
			if kind=="Bought" then self:_Sound("Cash") end
		end)) end
	end)
	-- close the shop when the elevator panel opens so the two never overlap
	local function sync()
		if self._player:GetAttribute("EHPartyView")~=nil and self._panel.Visible then self:SetOpen(false) end
	end
	self._scope:Add(self._player:GetAttributeChangedSignal("EHPartyView"):Connect(sync))
	sync()
end
function Controller:Destroy()
	if self._animating then RunService:UnbindFromRenderStep("BlackwaterShopArt");self._animating=false end
	if self._scope then self._scope:Destroy() end
end
return Controller
