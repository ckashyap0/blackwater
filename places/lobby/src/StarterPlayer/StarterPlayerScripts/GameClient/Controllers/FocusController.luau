--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
-- Knows when a full panel is open (elevator crew panel, shop, gallery). While any one is open:
--  * the other on-screen buttons (SHOP, the status strip, REJOIN) fade away and stop taking input
--  * the world behind gets a light blur
-- Panels call Set(key,true/false); everything eases in and out together, so nothing pops.
local RunService=game:GetService("RunService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local BLUR_SIZE=14       -- background blur strength while a panel is open (BlurEffect.Size)
local FADE_SECONDS=.28
-- on-screen chrome that steps aside while a panel is open: {ScreenGui name, child name}
local CHROME={{"ShopControls","ShopButton"},{"ShopControls","LockerButton"},{"GameInterface","StatusLayer"},{"BoardingControls","Reconnect"},{"DevelopmentStatus","FoundationStatus"}}
local PROPS={
	Frame={"BackgroundTransparency"},CanvasGroup={"GroupTransparency"},
	TextLabel={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},
	TextButton={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},
	TextBox={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},
	ImageLabel={"BackgroundTransparency","ImageTransparency"},ImageButton={"BackgroundTransparency","ImageTransparency"},
	ViewportFrame={"BackgroundTransparency","ImageTransparency"},ScrollingFrame={"BackgroundTransparency","ScrollBarImageTransparency"},UIStroke={"Transparency"},
}
local function smooth(t)return t*t*(3-2*t)end
-- effects that animate on their own (a button's click flash, the shop button's light sweep): left out of
-- the fade, or a value caught mid-animation would be "restored" afterwards and stick (a grey button)
local SKIP={ClickFlash=true,ShineClip=true}
local function skipped(inst,root)
	while inst and inst~=root do
		if SKIP[inst.Name] then return true end
		inst=inst.Parent
	end
	return false
end
function Controller.new(player,gui)
	return setmetatable({Name="FocusController",Dependencies={},_player=player,_gui=gui,_keys={},_t=0,_chrome={}},Controller)
end
function Controller:Init()
	self._scope=Scope.new()
	local blur=Instance.new("BlurEffect");blur.Name="EHFocusBlur";blur.Size=0;blur.Enabled=false
	self._blur=blur;self._scope:Add(blur)
	local function place()blur.Parent=workspace.CurrentCamera end
	place();self._scope:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(place))
end
-- key: any short name ("Party","Shop","Gallery"). Focus stays on while at least one key is on.
function Controller:Set(key,on)
	self._keys[key]=on and true or nil
end
function Controller:IsFocused()return next(self._keys)~=nil end
function Controller:_Capture()
	local cache={}
	for _,root in self._chrome do
		if root.Parent then
			local list=root:GetDescendants();table.insert(list,root)
			for _,inst in list do
				local props=PROPS[inst.ClassName]
				if props and not skipped(inst,root) then local t={};for _,p in props do t[p]=inst[p] end;cache[inst]=t end
			end
		end
	end
	self._cache=cache
end
function Controller:_Apply(a)
	for inst,t in self._cache do
		if inst.Parent then for p,orig in t do inst[p]=orig+(1-orig)*a end end
	end
	for _,root in self._chrome do
		if root:IsA("GuiObject") then root.Interactable=a<.5 end
		-- the skipped effects simply hide while the chrome is faded out
		for _,n in {"ClickFlash","ShineClip"} do
			local fx=root:FindFirstChild(n)
			if fx and fx:IsA("GuiObject") then fx.Visible=a<.05 end
		end
	end
end
function Controller:_Step(dt)
	local target=self:IsFocused() and 1 or 0
	if self._t==target then return end
	if not self._cache then self:_Capture() end
	if target>self._t then self._t=math.min(1,self._t+dt/FADE_SECONDS) else self._t=math.max(0,self._t-dt/FADE_SECONDS) end
	local a=smooth(self._t)
	self:_Apply(a)
	self._blur.Size=BLUR_SIZE*a;self._blur.Enabled=a>0
	if self._t==0 then
		-- fully back: restore the exact originals and forget them, so later changes by other code stand
		for inst,t in self._cache do if inst.Parent then for p,orig in t do inst[p]=orig end end end
		for _,root in self._chrome do
			if root:IsA("GuiObject") then root.Interactable=true end
			local flash=root:FindFirstChild("ClickFlash")
			if flash and flash:IsA("GuiObject") then flash.BackgroundTransparency=1;flash.Visible=true end
			local shine=root:FindFirstChild("ShineClip")
			if shine and shine:IsA("GuiObject") then shine.Visible=true end
		end
		self._cache=nil
	end
end
function Controller:Start()
	for _,c in CHROME do
		task.spawn(function()
			local g=AuthoredGui.Get(self._gui,c[1])
			local item=g and g:WaitForChild(c[2],5)
			if item then table.insert(self._chrome,item) end
		end)
	end
	self._scope:Add(RunService.RenderStepped:Connect(function(dt)self:_Step(dt)end))
end
function Controller:Destroy()
	if self._cache then for inst,t in self._cache do if inst.Parent then for p,orig in t do inst[p]=orig end end end end
	if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
