--!nonstrict
local Shared=game.ReplicatedStorage.Game.Shared
local Policy=require(Shared.Contracts.CharacterContract)
local Scope=require(Shared.Utilities.CleanupScope)
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Controller={};Controller.__index=Controller
-- Lobby: third person by default, and players can scroll all the way in to first person (up to 16 studs
-- out). Inside an elevator cabin the zoom eases down to first person in one smooth dolly (no rotation),
-- instead of the third-person camera colliding with the lintel/doors and popping in. Leaving eases back
-- out to third person, then the full zoom range is free again.
local THIRD_MIN,THIRD_MAX,FIRST=8,16,.5
local LOBBY_MIN=.5 -- closest the player may zoom in the lobby (first person)
local ZOOM_RATE=4.5 -- higher = faster ease
local ENTER_SECONDS=.85
function Controller.new(player)
	return setmetatable({Name="CameraController",Dependencies={"InputController"},_player=player,
		_zMin=LOBBY_MIN,_zMax=THIRD_MAX,_last=os.clock()},Controller)
end
function Controller:Init(deps)
	self._input=deps.InputController
	self._scope=Scope.new()
	self:_LockThirdPerson()
end
function Controller:_LockThirdPerson()
	local player=self._player
	player.CameraMode=Enum.CameraMode.Classic
	player.CameraMinZoomDistance=self._zMin or LOBBY_MIN
	player.CameraMaxZoomDistance=self._zMax or THIRD_MAX
end
function Controller:_CabinBay()
	local env=workspace:FindFirstChild("Runtime") and workspace.Runtime:FindFirstChild("LobbyEnvironment")
	if not env then return nil end
	local raw=self._player:GetAttribute("EHPartyView")
	local id=raw and tonumber(string.match(raw,'"bayId":(%d+)'))
	if id then return env:FindFirstChild("Bay"..id) end
	-- Start the dolly as soon as we're properly inside a cabin (same line the server admits at),
	-- rather than waiting a tick + network round trip for the party to replicate.
	local root=self._player.Character and self._player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	for i=1,4 do
		local bay=env:FindFirstChild("Bay"..i);local zone=bay and bay:FindFirstChild("BoardingZone")
		if zone then
			local p=zone.CFrame:PointToObjectSpace(root.Position);local h=zone.Size/2
			if math.abs(p.X)<=h.X and math.abs(p.Y)<=h.Y+1 and p.Z<=h.Z-2.85 and p.Z>=-h.Z-3.5 then return bay end
		end
	end
	return nil
end

function Controller:_Update()
	local camera=workspace.CurrentCamera
	if not camera then return end

	local player=self._player
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local context=self._input:GetContext()
	local policy=Policy.Contexts[context] or Policy.Contexts.Lobby
	local holdView=policy.camera=="Spectator" or policy.camera=="Results"

	local now=os.clock();local dt=math.clamp(now-self._last,0,.1);self._last=now
	-- Ease the zoom range toward first person while inside a cabin, third person otherwise.
	local cabin=context=="Lobby" and self:_CabinBay() or nil
	if cabin~=self._cabin then
		self._cabin=cabin
		if cabin then
			-- Entering: one clean, eased dolly straight in from wherever the camera is now.
			local dist=(camera.CFrame.Position-camera.Focus.Position).Magnitude
			self._enterFrom=math.clamp(dist,FIRST,THIRD_MAX);self._enterStart=now
		else
			self._enterStart=nil;self._easeOut=true
		end
	end
	if cabin then
		local d=FIRST
		if self._enterStart then
			local t=math.clamp((now-self._enterStart)/ENTER_SECONDS,0,1)
			local k=t*t*t*(t*(t*6-15)+10) -- smootherstep: no jolt at start or end
			d=self._enterFrom+(FIRST-self._enterFrom)*k
			if t>=1 then self._enterStart=nil end
		end
		-- min = max pins the distance exactly, so the zoom follows the curve with no spring overshoot
		self._zMin,self._zMax=d,d
	else
		-- Leaving: ease back out to third person.
		local a=1-math.exp(-dt*ZOOM_RATE)
		if self._easeOut then
			self._zMin+=(THIRD_MIN-self._zMin)*a
			if math.abs(self._zMin-THIRD_MIN)<.05 then self._zMin=LOBBY_MIN;self._easeOut=nil end
		else
			self._zMin=LOBBY_MIN
		end
		self._zMax+=(THIRD_MAX-self._zMax)*a
		if math.abs(self._zMax-THIRD_MAX)<.02 then self._zMax=THIRD_MAX end
	end
	self:_LockThirdPerson()
	UIS.MouseIconEnabled=true
	if holdView then
		camera.CameraType=Enum.CameraType.Scriptable
		UIS.MouseBehavior=Enum.MouseBehavior.Default
	else
		camera.CameraType=Enum.CameraType.Custom
		if humanoid and camera.CameraSubject~=humanoid then
			camera.CameraSubject=humanoid
		end
		if cabin then
			-- First person locks the cursor; keep it free so the elevator panel stays clickable.
			UIS.MouseBehavior=Enum.MouseBehavior.Default
		end
	end

	script.Parent:SetAttribute("CameraContext",context)
end
function Controller:Start()
	RunService:BindToRenderStep("EHCamera",Enum.RenderPriority.Camera.Value+1,function()
		self:_Update()
	end)
	self._scope:Add(function()
		RunService:UnbindFromRenderStep("EHCamera")
	end)
	self:_Update()
end
function Controller:Destroy()
	if self._scope then self._scope:Destroy() end
	self._zMin,self._zMax=LOBBY_MIN,THIRD_MAX
	self:_LockThirdPerson()
	UIS.MouseIconEnabled=true
	local camera=workspace.CurrentCamera
	local character=self._player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType=Enum.CameraType.Custom
		if humanoid then camera.CameraSubject=humanoid end
	end
end
return table.freeze(Controller)
