--!nonstrict
-- R43: short camera cuts for every floor. Server: Cinematic.Play(floorModel, id) stamps CineId/CineAt on the
-- floor. Every client then plays the same shots in sync from that server time (late joiners join mid-shot,
-- anyone arriving after it ended skips it). The definitions live in Config.Cinematics[EncounterId][id].
--
-- A cut: fade to black, the shots (each a camera move between two marker parts), fade to black, your own eyes.
-- While it plays EHCinematic is set, so InputController locks movement and HudReveal hides the HUD.
-- Afterwards the view returns facing where it faced before (ControlLock.returnRot).
--
-- Shot fields (Config.Cinematics):
--   from, to   Ref names of camera marker parts (their CFrame is the camera pose; LookVector = where it looks)
--   lookAt     optional Ref name to keep the camera aimed at (overrides the markers' facing)
--   dur        seconds          ease  'Linear' | 'Sine' (default) | 'Quad'      fov  number or {from, to}
--   shake      studs of camera shake (default 0)        caption  text shown low on screen for this shot
--   sound      {id=, volume=, speed=} played when the shot starts
-- Cut fields: shots = {...}, letterbox = true/false (default true), fade = seconds (default .35).
local RunService=game:GetService('RunService')
local Players=game:GetService('Players')
local TweenService=game:GetService('TweenService')
local SoundService=game:GetService('SoundService')
local M={}
M.LEAD=.6 -- seconds between the server's call and the first frame (time for the stamp to replicate)

local function config()
	local ok,c=pcall(function()return require(game.ReplicatedStorage.Game.Shared.Config.Cinematics)end)
	return ok and c or {}
end

-- total length of a cut in seconds, fades included
function M.Length(def)
	local t=0;for _,s in def.shots do t+=s.dur or 3 end
	return t+2*(def.fade or .35)
end

-- server
function M.Play(model,id,lead)
	model:SetAttribute('CineId',id)
	model:SetAttribute('CineAt',workspace:GetServerTimeNow()+(lead or M.LEAD))
end

------------------------------------------------------------------------------------------- client
local Refs
local function find(floor,name)
	if type(name)~='string' then return nil end
	Refs=Refs or require(script.Parent.FloorRefs)
	return Refs.Find(floor,name)
end
local EASE={
	Linear=function(u)return u end,
	Sine=function(u)return .5-.5*math.cos(math.pi*u) end,
	Quad=function(u)return u<.5 and 2*u*u or 1-(-2*u+2)^2/2 end,
}
local playing=false

local function ui(player)
	local pg=player:FindFirstChild('PlayerGui')
	local gui=pg and pg:FindFirstChild('Cinematic')
	if not gui then return nil end
	return {gui=gui,black=gui:FindFirstChild('Black'),top=gui:FindFirstChild('BarTop'),bottom=gui:FindFirstChild('BarBottom'),caption=gui:FindFirstChild('Caption')}
end
local function tween(obj,t,props)
	if not obj then return end
	local tw=TweenService:Create(obj,TweenInfo.new(t,Enum.EasingStyle.Quart,Enum.EasingDirection.InOut),props);tw:Play();return tw
end

local function play(floor,def,at)
	if playing then return end
	local player=Players.LocalPlayer;local cam=workspace.CurrentCamera
	if not cam or not def or not def.shots or #def.shots==0 then return end
	local fade=def.fade or .35
	local total=M.Length(def)
	if workspace:GetServerTimeNow()>at+total-fade then return end -- already over
	-- resolve every shot first; a cut with a missing marker is skipped rather than played wrong
	local shots,t={},fade
	for _,s in def.shots do
		local a,b=find(floor,s.from),find(floor,s.to or s.from)
		if not a or not b then warn('[ElevatorHorror] cinematic shot marker missing: '..tostring(s.from)..' / '..tostring(s.to));return end
		table.insert(shots,{a=a.CFrame,b=b.CFrame,look=find(floor,s.lookAt),t0=t,t1=t+(s.dur or 3),def=s})
		t+=s.dur or 3
	end
	playing=true
	local u=ui(player)
	if u and u.gui then u.gui.Enabled=true end
	local Lock=require(script.Parent.ControlLock)
	local back=cam.CFrame.Rotation
	player:SetAttribute('EHCinematic',true)
	if u then
		if u.black then u.black.BackgroundTransparency=1;tween(u.black,fade,{BackgroundTransparency=0}) end
	end
	local function wait(to) local d=at+to-workspace:GetServerTimeNow();if d>0 then task.wait(d) end end
	wait(fade)
	pcall(function()player:RequestStreamAroundAsync(shots[1].a.Position,2)end)
	local fov0=cam.FieldOfView
	cam.CameraType=Enum.CameraType.Scriptable
	local started={}
	local name='BlackwaterCinematic'
	RunService:BindToRenderStep(name,Enum.RenderPriority.Camera.Value+4,function()
		local now=workspace:GetServerTimeNow()-at
		local s=shots[#shots]
		for _,x in shots do if now<x.t1 then s=x;break end end
		local d=s.def
		if not started[s] then
			started[s]=true
			if d.sound and d.sound.id then
				local snd=Instance.new('Sound');snd.SoundId=d.sound.id;snd.Volume=d.sound.volume or .5;snd.PlaybackSpeed=d.sound.speed or 1
				snd.Parent=SoundService;snd:Play();task.delay(math.max(3,(d.dur or 3)+2),function()snd:Destroy()end)
			end
			if u and u.caption then
				u.caption.Text=d.caption or '';u.caption.TextTransparency=1
				if d.caption then tween(u.caption,.6,{TextTransparency=0});task.delay(math.max(.8,(d.dur or 3)-1),function()tween(u.caption,.6,{TextTransparency=1})end) end
			end
		end
		local k=math.clamp((now-s.t0)/(s.t1-s.t0),0,1);k=(EASE[d.ease or 'Sine'] or EASE.Sine)(k)
		local cf=s.a:Lerp(s.b,k)
		if s.look then cf=CFrame.lookAt(cf.Position,s.look.Position) end
		if d.shake and d.shake>0 then
			local n=os.clock()*14
			cf*=CFrame.new(math.noise(n,1)*d.shake,math.noise(n,2)*d.shake,0)*CFrame.Angles(0,0,math.noise(n,3)*d.shake*.03)
		end
		cam.CFrame=cf
		local fov=d.fov
		if type(fov)=='table' then cam.FieldOfView=fov[1]+(fov[2]-fov[1])*k elseif type(fov)=='number' then cam.FieldOfView=fov else cam.FieldOfView=60 end
	end)
	if u then
		local bars=def.letterbox~=false
		if bars then tween(u.top,.6,{Size=UDim2.fromScale(1,.11)});tween(u.bottom,.6,{Size=UDim2.fromScale(1,.11)}) end
		if u.black then tween(u.black,fade,{BackgroundTransparency=1}) end
	end
	wait(total-fade)
	if u then
		if u.black then tween(u.black,fade,{BackgroundTransparency=0}) end
		tween(u.top,fade,{Size=UDim2.fromScale(1,0)});tween(u.bottom,fade,{Size=UDim2.fromScale(1,0)})
	end
	task.wait(fade)
	RunService:UnbindFromRenderStep(name)
	cam.FieldOfView=fov0
	cam.CameraType=Enum.CameraType.Custom
	-- back in your own eyes, facing the way you faced before the cut
	Lock.returnRot=back
	player:SetAttribute('EHCinematic',nil)
	task.wait(.15)
	if u then
		if u.black then tween(u.black,fade,{BackgroundTransparency=1}) end
		if u.caption then u.caption.TextTransparency=1 end
	end
	playing=false
end

local started=false
function M.Start()
	if started or not RunService:IsClient() then return end
	started=true
	local seen=setmetatable({},{__mode='k'})
	task.spawn(function()
		while true do
			local runtime=workspace:FindFirstChild('Runtime')
			local env=runtime and runtime:FindFirstChild('DescentEnvironment')
			if env then
				for _,m in env:GetChildren() do
					if not seen[m] and m:GetAttribute('EncounterId') then
						seen[m]=true
						local last
						local function check()
							local at,id=m:GetAttribute('CineAt'),m:GetAttribute('CineId')
							if type(at)~='number' or type(id)~='string' or last==at then return end
							last=at
							local defs=config()[m:GetAttribute('EncounterId')]
							local def=defs and defs[id]
							if def then task.spawn(play,m,def,at) end
						end
						m:GetAttributeChangedSignal('CineAt'):Connect(check)
						check()
					end
				end
			end
			task.wait(.5)
		end
	end)
end

return M
