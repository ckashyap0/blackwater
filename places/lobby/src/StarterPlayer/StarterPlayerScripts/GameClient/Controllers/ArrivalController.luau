--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)return setmetatable({Name="ArrivalController",Dependencies={"CameraController"},_player=player,_gui=gui,_seen={}},Controller)end
function Controller:Init()
	self._scope=Scope.new()
	-- authored in StarterGui.ArrivalEyes (UpperLid / LowerLid)
	local screen=AuthoredGui.Get(self._gui,"ArrivalEyes");screen.Enabled=false;self._screen=screen
	self._lids={screen:WaitForChild("UpperLid"),screen:WaitForChild("LowerLid")}
end
function Controller:Start()
	self._scope:Add(game:GetService("RunService").RenderStepped:Connect(function(dt)
		local id=self._player:GetAttribute("EHRunId")
		local context=self._player:GetAttribute("EHContext")
		if id and context=="Intro" and not self._seen[id] then self._seen[id]=true;self._elapsed=0;self._screen.Enabled=true end
		if not self._screen.Enabled then return end
		if context=="Dead" or context=="Results" or not id then self._screen.Enabled=false;return end
		self._elapsed+=dt
		local t=math.clamp((self._elapsed-.3)/1.5,0,1);local height=.51*(1-t*t*(3-2*t))
		for _,f in self._lids do f.Size=UDim2.fromScale(1,height)end
		if t==1 then self._screen.Enabled=false end
	end))
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
