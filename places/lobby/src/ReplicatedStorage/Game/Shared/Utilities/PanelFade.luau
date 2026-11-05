--!nonstrict
-- Fades a whole panel in or out as one piece: every fill, text, image and border inside it eases
-- together while the panel drifts a few pixels, then everything is put back exactly as it was.
--   local fade=PanelFade.new(panel)
--   fade:Show(true)  / fade:Show(false)   (Visible is handled for you; Visible stays true until a fade-out ends)
local RunService=game:GetService("RunService")
local PROPS={
	Frame={"BackgroundTransparency"},ScrollingFrame={"BackgroundTransparency","ScrollBarImageTransparency"},
	TextLabel={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},
	TextButton={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},
	TextBox={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},
	ImageLabel={"BackgroundTransparency","ImageTransparency"},ImageButton={"BackgroundTransparency","ImageTransparency"},
	ViewportFrame={"BackgroundTransparency","ImageTransparency"},UIStroke={"Transparency"},
}
local IN_TIME,OUT_TIME,DRIFT=.24,.14,10
local Fade={};Fade.__index=Fade
-- onDone (optional) runs after every finished fade, so the owner can repaint anything it changed mid-fade
function Fade.new(panel,onDone)
	return setmetatable({panel=panel,shown=panel.Visible,k=panel.Visible and 1 or 0,onDone=onDone},Fade)
end
function Fade:_Capture()
	local cache={}
	local list=self.panel:GetDescendants();table.insert(list,self.panel)
	for _,inst in list do
		local props=PROPS[inst.ClassName]
		if props then local t={};for _,p in props do t[p]=inst[p] end;cache[inst]=t end
	end
	self.cache=cache
end
function Fade:_Apply(k)
	for inst,t in self.cache do
		if inst.Parent then for p,orig in t do inst[p]=orig+(1-orig)*(1-k) end end
	end
	if self.home then self.panel.Position=self.home+UDim2.fromOffset(0,(1-k)*DRIFT) end
end
function Fade:_Restore()
	if self.cache then for inst,t in self.cache do if inst.Parent then for p,orig in t do inst[p]=orig end end end end
	self.cache=nil
	if self.home then self.panel.Position=self.home end
end
function Fade:IsShown()return self.shown end
-- true while the panel is on screen at all (including the moment it is fading away)
function Fade:IsVisible()return self.panel.Visible end
function Fade:Show(show)
	if show==self.shown then return end
	self.shown=show
	if self.conn then self.conn:Disconnect();self.conn=nil end
	-- (re)capture from the fully shown look, so a fade reversed half way never bakes in a faded value
	local k=self.k
	if self.cache then self:_Apply(1);self:_Restore() end
	self.home=self.panel.Position
	if show then self.panel.Visible=true end
	self:_Capture()
	self:_Apply(k)
	self.conn=RunService.RenderStepped:Connect(function(dt)
		dt=math.min(dt,1/30)
		if show then self.k=math.min(1,self.k+dt/IN_TIME) else self.k=math.max(0,self.k-dt/OUT_TIME) end
		local e=show and 1-(1-self.k)^3 or self.k*self.k
		self:_Apply(e)
		if self.k==(show and 1 or 0) then
			self.conn:Disconnect();self.conn=nil
			self:_Restore()
			if not show then self.panel.Visible=false end
			if self.onDone then task.spawn(self.onDone,show) end
		end
	end)
end
-- jump straight to a state (no animation)
function Fade:Snap(show)
	if self.conn then self.conn:Disconnect();self.conn=nil end
	if self.cache then self:_Apply(1);self:_Restore() end
	self.shown=show;self.k=show and 1 or 0;self.panel.Visible=show
end
return Fade
