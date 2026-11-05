--!nonstrict
-- Animate authored fixtures. Geometry, light types, sound IDs and tuning remain editable in Studio.
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
function Controller.new()return setmetatable({Name="FixtureController",Dependencies={},_fixtures={}},Controller)end
function Controller:Init()self._scope=Scope.new()end
function Controller:_Track(p)
    if not p:IsA("BasePart")or not p:GetAttribute("EHFlicker")then return end
    local record=self._fixtures[p]
    if not record then record={lights={},seen={},sound=nil};self._fixtures[p]=record end
    for _,light in p:GetDescendants()do
        if light:IsA("Light")and not record.seen[light]then
            record.seen[light]=true;table.insert(record.lights,{light=light,base=light.Brightness})
        end
    end
    record.sound=p:FindFirstChildWhichIsA("Sound",true)
end
function Controller:Start()
	self._active=true
	for _,p in workspace:GetDescendants()do self:_Track(p)end
	self._scope:Add(workspace.DescendantAdded:Connect(function(p)task.defer(function()if self._active then local host=p;while host and host~=workspace do self:_Track(host);if host:IsA("BasePart")then break end;host=host.Parent end end end)end))
	local elapsed=0
	self._scope:Add(game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.06 then return end;elapsed=0
		local now=workspace:GetServerTimeNow()
		for p,r in self._fixtures do
			if not p:IsDescendantOf(workspace)then self._fixtures[p]=nil;continue end
			local seed=tonumber(p:GetAttribute("FlickerSeed"))or 0
			-- Shared server time gives identical sparse pulses to late joiners and all clients.
			local period=math.max(2,tonumber(p:GetAttribute("FlickerPeriod"))or 11)
            if not r.sound or not r.sound.Parent then r.sound=p:FindFirstChildWhichIsA("Sound",true)end
			local phase=(now+seed)%period;local dipping=phase<.85
			local factor=dipping and 1-.85*math.sin(phase/.85*math.pi)or 1
			for _,entry in r.lights do if entry.light.Parent then entry.light.Brightness=entry.base*factor end end
			if dipping and not r.dipping and r.sound and r.sound.IsLoaded and not r.sound.IsPlaying then r.sound:Play()end
			r.dipping=dipping
		end
	end))
end
function Controller:Destroy()
	self._active=false;if self._scope then self._scope:Destroy()end
	for _,r in self._fixtures do for _,e in r.lights do if e.light.Parent then e.light.Brightness=e.base end end end
end
return table.freeze(Controller)
