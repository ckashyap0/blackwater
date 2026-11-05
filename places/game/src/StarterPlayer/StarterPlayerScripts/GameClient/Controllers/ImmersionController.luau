--!nonstrict
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.ImmersionConfig)
-- Standard cinematic motion blur: {per radian/sec of turning, while sprinting, max size}.
local MOTION_BLUR={.3,1.2,1.8}
local Controller={};Controller.__index=Controller
function Controller.new(player)return setmetatable({Name='ImmersionController',Dependencies={'CameraController','InputController'},_player=player,_characters={},_weight=0,_sprint=0},Controller)end
function Controller:Init(deps)self._input=deps.InputController;self._scope=Scope.new()end
function Controller:_Attach(player,character)
 local old=self._characters[player];if old then old.scope:Destroy()end
 local r={character=character,scope=Scope.new(),distance=0};self._characters[player]=r
 local function mute(v)
  if (v:IsA('Sound') or v:IsA('AudioPlayer')) and v.Name=='Running' then
   v.Volume=0
   r.scope:Add(v:GetPropertyChangedSignal('Volume'):Connect(function()if v.Volume~=0 then v.Volume=0 end end))
  end
 end
 for _,v in character:GetDescendants()do mute(v)end
 r.scope:Add(character.DescendantAdded:Connect(mute))
end
function Controller:_Audio(dt)
 for player,r in self._characters do
  local h=r.character:FindFirstChildOfClass('Humanoid');local root=r.character:FindFirstChild('HumanoidRootPart')
  if not root or not h or not root.Parent then continue end
  if not r.sound then
   r.sound=r.scope:Add(Instance.new('Sound'));r.sound.Name='BlackwaterSteps';r.sound.RollOffMode=Enum.RollOffMode.InverseTapered;r.sound.RollOffMinDistance=4;r.sound.RollOffMaxDistance=Config.StepRange;r.sound.Volume=Config.StepVolume;r.sound.Parent=root
   local eq=Instance.new('EqualizerSoundEffect',r.sound);eq.HighGain=-8;eq.MidGain=-2;eq.LowGain=1
  end
  local pos=root.Position;local delta=r.last and (pos-r.last).Magnitude or 0;r.last=pos
  local context=player:GetAttribute('EHContext')
  local moving=h.Health>0 and h.FloorMaterial~=Enum.Material.Air and Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude>.7 and (context=='ActiveFloor' or context=='Transit')
  if not moving or delta>10 then r.distance=0;continue end
  r.distance+=delta
  if r.distance>=Config.StepDistance then
   r.distance%=Config.StepDistance
   local metal=h.FloorMaterial==Enum.Material.Metal or h.FloorMaterial==Enum.Material.DiamondPlate or h.FloorMaterial==Enum.Material.CorrodedMetal
   local id=metal and Config.MetalSound or Config.ConcreteSound
   if r.sound.SoundId~=id then r.sound.SoundId=id end
   r.sound.Volume=(metal and Config.StepVolume*.55 or Config.StepVolume)*(player:GetAttribute("EHSprinting")and 1.25 or player:GetAttribute("EHCrouching")and .45 or 1)
   r.sound.PlaybackSpeed=1+math.random(-5,5)/100;r.sound:Play()
  end
 end
end
function Controller:_Camera(dt)
 local camera=workspace.CurrentCamera;if not camera then return end
 local context=self._input:GetContext()
 local character=self._player.Character
 local h=character and character:FindFirstChildOfClass('Humanoid')
 local root=character and character:FindFirstChild('HumanoidRootPart')
 local active=(context=='ActiveFloor' or context=='Transit') and camera.CameraType==Enum.CameraType.Custom and h and root and h.Health>0
 local velocity=root and root.AssemblyLinearVelocity or Vector3.zero
 local planar=Vector3.new(velocity.X,0,velocity.Z)
 local speed=planar.Magnitude
 local grounded=active and h.FloorMaterial~=Enum.Material.Air
 local moving=grounded and h.MoveDirection.Magnitude>.05 and speed>.1
 local blend=1-math.exp(-Config.MotionResponse*math.min(dt,.1))
 self._weight+=(math.clamp(moving and speed/12 or 0,0,1)-self._weight)*blend
 local sprintTarget=moving and self._player:GetAttribute('EHSprinting')==true and 1 or 0
 self._sprint+=(sprintTarget-self._sprint)*blend
 if not active or self._menu then
  self._lastLook=nil
  if self._blur then self._blur.Size=0 end
  return
 end
 local reduced=self._player:GetAttribute('EHReduceMotion')==true
 local ok,pref=pcall(function()return game.GuiService.ReducedMotionEnabled end);reduced=reduced or (ok and pref)
 local targetFOV=Config.IdleFOV+(reduced and 0 or (Config.WalkFOV-Config.IdleFOV)*self._weight+(Config.SprintFOV-Config.WalkFOV)*self._sprint)
 camera.FieldOfView+=(targetFOV-camera.FieldOfView)*blend
 if self._blur then
  self._blur.Parent=camera
  local turning=self._lastLook and math.acos(math.clamp(camera.CFrame.LookVector:Dot(self._lastLook),-1,1))/math.max(dt,.001) or 0
  self._lastLook=camera.CFrame.LookVector
  local inspecting=self._player:GetAttribute('EHInteractionState')=='Holding'
  local tier=MOTION_BLUR -- one standard (cinematic) motion blur for everyone
  local amount=(not reduced and not inspecting)and math.clamp(turning*tier[1]+self._sprint*tier[2],0,tier[3])or 0
  self._blur.Size+=(amount-self._blur.Size)*blend
 end
 -- Walk bob and mouse sway are handled by the character LocalScripts.
end
function Controller:Start()
 local role=Shared.Parent:GetAttribute('PlaceRole') or require(Shared.Config.PlaceConfig).Resolve(game.PlaceId,RunService:IsStudio(),workspace:GetAttribute('EHStudioPlaceRole'))
 if role~='Game' then return end
 self._originalFOV=workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView
 self._blur=self._scope:Add(Instance.new('BlurEffect'));self._blur.Name='BlackwaterMotionBlur';self._blur.Size=0;self._blur.Parent=workspace.CurrentCamera
 self._player:SetAttribute('EHMotionMode','Cinematic')
 self._scope:Add(game.GuiService.MenuOpened:Connect(function()self._menu=true end));self._scope:Add(game.GuiService.MenuClosed:Connect(function()self._menu=false end))
 local function add(p)
  self._scope:Add(p.CharacterAdded:Connect(function(c)self:_Attach(p,c)end))
  self._scope:Add(p.CharacterRemoving:Connect(function(c)local r=self._characters[p];if r and r.character==c then r.scope:Destroy();self._characters[p]=nil end end))
  if p.Character then self:_Attach(p,p.Character)end
 end
 self._scope:Add(Players.PlayerAdded:Connect(add));for _,p in Players:GetPlayers()do add(p)end
 self._scope:Add(Players.PlayerRemoving:Connect(function(p)local r=self._characters[p];if r then r.scope:Destroy();self._characters[p]=nil end end))
 self._scope:Add(RunService.Heartbeat:Connect(function(dt)self:_Audio(dt)end))
 RunService:BindToRenderStep('BlackwaterMotion',Enum.RenderPriority.Camera.Value+2,function(dt)self:_Camera(dt)end)
 self._scope:Add(function()RunService:UnbindFromRenderStep('BlackwaterMotion')end)
end
function Controller:Destroy()
 if self._scope then self._scope:Destroy()end
 for _,r in self._characters do r.scope:Destroy()end
 if self._originalFOV and workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView=self._originalFOV end
end
return table.freeze(Controller)