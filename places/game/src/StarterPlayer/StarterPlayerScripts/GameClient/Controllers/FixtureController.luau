--!nonstrict
-- Animate authored fixtures. Geometry, light types, sound IDs and tuning remain editable in Studio.
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
function Controller.new()return setmetatable({Name="FixtureController",Dependencies={},_fixtures={}},Controller)end
function Controller:Init()self._scope=Scope.new()end
function Controller:_Track(p)
    if not p:IsA("BasePart")or not p:GetAttribute("EHFlicker")or p:GetAttribute("EHSteadyTaskLight")then return end
    local record=self._fixtures[p]
    if not record then record={lights={},seen={},sound=nil,neon=p.Material==Enum.Material.Neon};self._fixtures[p]=record end
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
			local cycle=math.floor((now+seed)/period)
            local phase=(now+seed)%period;local dipping=phase<.85 and cycle%3~=1
            local powered=false;for _,entry in r.lights do if entry.light.Parent and entry.light.Enabled then powered=true;break end end
            dipping=dipping and powered
			local factor=dipping and (.3+.3*math.abs(math.sin(phase*17)))or 1
			if r.factor~=factor then
             r.factor=factor;for _,entry in r.lights do if entry.light.Parent then entry.light.Brightness=entry.base*factor end end
             -- the tube itself dims with its light (server power state still owns the base colour)
             if r.neon then p.Transparency=factor<1 and .35 or 0 end
            end
			local camera=workspace.CurrentCamera;local nearby=camera and (camera.CFrame.Position-p.Position).Magnitude<45
			-- the floor's flickering tubes are not heard from inside the lift during the descent cinematic
			nearby=nearby and game.Players.LocalPlayer:GetAttribute('EHContext')=='ActiveFloor' and not game.ReplicatedStorage.Game:GetAttribute('SurfaceBoarding')
			if nearby and dipping and not r.dipping and r.sound and r.sound.IsLoaded and not r.sound.IsPlaying then r.sound:Play()end
			r.dipping=dipping
		end
	end))
end
function Controller:Destroy()
	self._active=false;if self._scope then self._scope:Destroy()end
	for _,r in self._fixtures do for _,e in r.lights do if e.light.Parent then e.light.Brightness=e.base end end end
end
return table.freeze(Controller)

