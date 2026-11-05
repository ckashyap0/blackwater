--!nonstrict
-- Crawl state (client). One owner for lying down:
--
--   Standing --(climb into a duct: EHInVent)--> Vent --(drop out of an open end)--> Standing
--
-- There is NO crawl key: Left Ctrl is a plain crouch (MovementController). Lying down only ever
-- happens inside a duct. Vent means: lying flat on your front with the prone crawl (HazardController
-- poses it, moves the body and eases its pace), no jumping or standing, and the eye eased down and
-- forward to your head (a TweenService tween on CrawlState.camera, which CameraController turns into
-- Humanoid.CameraOffset). The server's EHInVent says who is in a duct, for every client.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Crawl=require(Shared.Utilities.CrawlState)
local Controller={};Controller.__index=Controller
local CAMERA_DOWN,CAMERA_UP=.45,.8   -- seconds for the eye to drop to the floor / come back up (the up
                                     -- glide matches the climb-out, so the eye rises WITH the body)
local VENT_CLIMB_SECONDS=1.05        -- (matches HazardController)
function Controller.new(player)return setmetatable({Name='CrawlController',Dependencies={'InputController'},_player=player},Controller)end
function Controller:Init(deps)self._input=deps.InputController;self._scope=Scope.new()end
function Controller:_Set(state)
 if Crawl.state==state then return end
 Crawl.state=state;Crawl.changedAt=os.clock()
end
-- every frame: follow the duct state, and steer the camera tween
function Controller:_Step()
 local p=self._player
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if not h or h.Health<=0 then self:_Set('Standing')
 elseif p:GetAttribute('EHInVent')~=nil then self:_Set('Vent')
 else self:_Set('Standing') end
 -- the eye goes down once you are actually lying down (in a duct: once the climb is over the lip)
 local low=false
 if Crawl.state=='Vent' and not Crawl.exiting then
  local at=p:GetAttribute('EHVentAt')
  low=type(at)~='number' or workspace:GetServerTimeNow()>=at+VENT_CLIMB_SECONDS*.75
 end
 local target=low and 1 or 0
 if self._cameraTarget~=target then
  self._cameraTarget=target
  if self._tween then self._tween:Cancel() end
  self._tween=TweenService:Create(Crawl.camera,TweenInfo.new(low and CAMERA_DOWN or CAMERA_UP,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Value=target})
  self._tween:Play()
 end
end
function Controller:Start()
 Crawl.state='Standing';Crawl.camera.Value=0
 self._scope:Add(RunService.Heartbeat:Connect(function()local ok,err=pcall(self._Step,self);if not ok then warn('[ElevatorHorror] crawl: '..tostring(err))end end))
 self._scope:Add(self._player.CharacterAdded:Connect(function()self:_Set('Standing');Crawl.camera.Value=0;self._cameraTarget=0 end))
end
function Controller:Destroy()
 if self._tween then self._tween:Cancel() end
 if self._scope then self._scope:Destroy()end
 Crawl.state='Standing'
end
return table.freeze(Controller)
