--!nonstrict
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Places=require(Shared.Config.PlaceConfig)
local Crouch=require(Shared.Utilities.CrouchState)
local Crawl=require(Shared.Utilities.CrawlState)
local ScreenFade=require(Shared.Utilities.ScreenFade)
local GETUP_SECONDS=require(Shared.Utilities.IntroTimeline).GetUpSeconds
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local FP do
	local defaults={BodyFadeStartDegrees=50,BodyFadeEndDegrees=72,BodyFadeResponse=16,AlignStartDegrees=25,AlignEndDegrees=80,
		AlignResponse=14,EyeHeightOffset=.45,CrouchDrop=1.6,CrouchSpring=13,LookDownForwardShift=.42,LookDownDrop=.12,WallClearance=.3,ShowBodyOnLookDown=false}
	local module=Shared.Config:WaitForChild("FirstPersonConfig",10)
	local ok,config=pcall(function()return module and require(module)end)
	FP=setmetatable({},{__index=function(_,k)if ok and type(config)=="table"and config[k]~=nil then return config[k]end;return defaults[k]end})
end
local function smoothstep(x)x=math.clamp(x,0,1);return x*x*(3-2*x)end
local function pitchWeight(pitch,startDeg,endDeg)
	if endDeg<=startDeg then return pitch>=startDeg and 1 or 0 end
	return smoothstep((pitch-startDeg)/(endDeg-startDeg))
end
local Controller={};Controller.__index=Controller
-- Vent crawl camera: always first person. Once the climb carries you over the lip the eye eases
-- (never snaps) down to where your prone head really is - just in front of and above the face -
-- and follows it through a soft low-pass, so the slow sway of the crawl reads as a gentle bob and
-- never a shake. The eye is kept clear of the duct roof and walls, and the look is held to a band
-- you can actually manage lying on your front. Your body and legs are visible; your arms/hands (LTM 1, only in ducts) and the
-- head (and hats/hair) stay hidden so nothing blocks the lens.
local VENT_EYE_FOLLOW=7          -- how quickly the eye follows the head (1/s); lower = smoother
local VENT_PITCH_MIN,VENT_PITCH_MAX=math.rad(-55),math.rad(38)
local VENT_CLEAR=.32
local VENT_WALL=.42 -- how far the lens always stays inside the duct walls, roof and floor
local bodyPartNames={
 UpperTorso=true,LowerTorso=true,
 LeftUpperArm=true,LeftLowerArm=true,LeftHand=true,RightUpperArm=true,RightLowerArm=true,RightHand=true,
 LeftUpperLeg=true,LeftLowerLeg=true,LeftFoot=true,RightUpperLeg=true,RightLowerLeg=true,RightFoot=true,
 Torso=true,['Left Arm']=true,['Right Arm']=true,['Left Leg']=true,['Right Leg']=true,
}
local armPartNames={LeftUpperArm=true,LeftLowerArm=true,LeftHand=true,RightUpperArm=true,RightLowerArm=true,RightHand=true,['Left Arm']=true,['Right Arm']=true}
function Controller.new(player)return setmetatable({Name="CameraController",Dependencies={"InputController"},_player=player,_hidden={}},Controller)end
function Controller:Init(deps)
	self._input=deps.InputController;self._scope=Scope.new()
	self._role=Shared.Parent:GetAttribute("PlaceRole")or Places.Resolve(game.PlaceId,RunService:IsStudio(),workspace:GetAttribute("EHStudioPlaceRole"))
	self._original={mode=self._player.CameraMode,min=self._player.CameraMinZoomDistance,max=self._player.CameraMaxZoomDistance,icon=UIS.MouseIconEnabled}
	self._scope:Add(GuiService.MenuOpened:Connect(function()self._menu=true end))
	self._scope:Add(GuiService.MenuClosed:Connect(function()self._menu=false end))
	self._scope:Add(Shared.Parent:GetAttributeChangedSignal("PlaceRole"):Connect(function()self._role=Shared.Parent:GetAttribute("PlaceRole")or self._role end))
end
function Controller:_RestoreVisibility()
	for p,v in self._hidden do if p.Parent then p.LocalTransparencyModifier=v end end
	table.clear(self._hidden)
end
function Controller:_SetPartTransparency(part,transparency)
	if self._hidden[part]==nil then self._hidden[part]=part.LocalTransparencyModifier end
	transparency=math.clamp(transparency,0,1)
	if math.abs(part.LocalTransparencyModifier-transparency)>.005 then part.LocalTransparencyModifier=transparency end
end
function Controller:_Visibility(dt)
	dt=math.clamp(dt or 1/60,0,.1)
	local c=self._player.Character
	if c~=self._character then self:_RestoreVisibility();self._character=c;self._bodyLookWeight=0 end
	if not c then return end
	local context=self._input:GetContext()
	-- (the lift ride counts too: your own arms and body are never drawn over the lens in the dark
	-- cabin; only the crash and get-up show them, and HazardController draws those itself)
	if context=="Intro" then
		local p=self._player
		if p:GetAttribute("EHKnockStyle")=="Crash" and workspace:GetServerTimeNow()<(p:GetAttribute("EHKnockedUntil") or 0)+GETUP_SECONDS+.5 then return end
	end
	local supported=context=="Lobby"or context=="ActiveFloor"or context=="Transit"or context=="Intro"
	if not self._first or self._role~="Game"or not supported then
		self._bodyLookWeight=0;self._alignWeight=0;self._offsetTarget=nil;self:_RestoreVisibility();return
	end
	local camera=workspace.CurrentCamera
	if not camera then return end
	-- Degrees below the horizon; thresholds live in Shared.Config.FirstPersonConfig.
	local pitch=math.deg(math.asin(math.clamp(-camera.CFrame.LookVector.Y,-1,1)))
	-- No body in first person: everything on the character stays hidden at every angle.
	local showBody=FP.ShowBodyOnLookDown==true
	local fade=showBody and pitchWeight(pitch,FP.BodyFadeStartDegrees,FP.BodyFadeEndDegrees)or 0
	self._bodyLookWeight=(self._bodyLookWeight or 0)+(fade-(self._bodyLookWeight or 0))*(1-math.exp(-FP.BodyFadeResponse*dt))
	local align=showBody and pitchWeight(pitch,FP.AlignStartDegrees,FP.AlignEndDegrees)or 0
	self._alignWeight=(self._alignWeight or 0)+(align-(self._alignWeight or 0))*(1-math.exp(-FP.AlignResponse*dt))
	local reveal=math.clamp(self._bodyLookWeight,0,1)
	local humanoid=c:FindFirstChildOfClass("Humanoid")
	self._offsetTarget=self:_AlignedOffset(c,self._alignWeight)
	self:_ApplyBodyOffset(humanoid,true)
	for _,p in c:GetDescendants()do
		if p:IsA("BasePart")and (p.Parent==c or p:FindFirstAncestorOfClass("Accessory"))then
			local target=1
			if p.Parent==c and bodyPartNames[p.Name]then
				target=armPartNames[p.Name]and 1 or 1-reveal
			end
			-- lying in a duct: your arms, body and legs fade into view (you see your hands pull you
			-- along); the head and anything worn on it stay hidden so nothing sits in front of the lens
			-- (in a duct too: your own body stays completely hidden - everyone else still sees it)
			-- (and never ahead of the picture: shown parts fade in with the screen, see ScreenFade)
			if target<1 then target=math.max(target,ScreenFade.Black()) end
			self:_SetPartTransparency(p,target)
		end
	end
end
-- Slide the eye forward/down with pitch so the torso sits on the lower frame edge.
-- A short forward ray keeps the shifted eye from entering walls the player is hugging.
function Controller:_AlignedOffset(character,weight)
	local forward=FP.LookDownForwardShift*weight
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if forward>0 and root then
		local params=self._offsetParams
		if not params then params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true;self._offsetParams=params end
		params.FilterDescendantsInstances={character,workspace.CurrentCamera}
		local origin=root.CFrame:PointToWorldSpace(Vector3.new(0,1.5+FP.EyeHeightOffset,0))
		local hit=workspace:Raycast(origin,root.CFrame.LookVector*(forward+FP.WallClearance),params)
		if hit then forward=math.clamp(hit.Distance-FP.WallClearance,0,forward)end
	end
	return Vector3.new(0,FP.EyeHeightOffset-FP.LookDownDrop*weight,-forward)
end
function Controller:_ApplyBodyOffset(h,enabled)
	if h~=self._offsetHumanoid then
		local old=self._offsetHumanoid
		if old and old.Parent and self._originalCameraOffset then old.CameraOffset=self._originalCameraOffset end
		self._offsetHumanoid=h
		self._originalCameraOffset=h and h.CameraOffset or nil
	end
	if h and self._originalCameraOffset then
		local target=enabled and ((self._offsetTarget or Vector3.new(0,FP.EyeHeightOffset,0))-Vector3.new(0,FP.CrouchDrop*(self._crouchX or 0),0))or self._originalCameraOffset
		-- prone in a duct: the eye moves to your head (see _VentEye)
		local vw=enabled and (self._ventW or 0) or 0
		if vw>0 and self._ventEye then target=target:Lerp(self._ventEye,vw) end
		if (h.CameraOffset-target).Magnitude>1e-4 then h.CameraOffset=target end
	end
end
function Controller:_Crouch(dt,h)
	-- Critically damped spring: eases into and out of the crouch with no overshoot or snap,
	-- and picks up smoothly if the player changes their mind mid-motion. Fixed 120 Hz substeps
	-- keep it identical at any frame rate.
	local target=(Crouch.wanted and self._first and self._role=="Game" and h and h.Health>0)and 1 or 0
	local w=FP.CrouchSpring;local x,v=self._crouchX or 0,self._crouchV or 0
	local steps=math.max(1,math.ceil(dt*120));local s=dt/steps
	for _=1,steps do v+=(w*w*(target-x)-2*w*v)*s;x+=v*s end
	if math.abs(target-x)<1e-4 and math.abs(v)<1e-3 then x,v=target,0 end
	self._crouchX,self._crouchV=x,v;Crouch.amount=math.clamp(x,0,1)
end
function Controller:_Update(dt)
	dt=math.clamp(dt or 1/60,0,.1)
	local camera=workspace.CurrentCamera;if not camera then return end
	local p=self._player;local c=p.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
	-- lying down (only ever in a duct): how far the eye has moved down and forward to the
	-- prone head. CrawlController tweens it (TweenService, Sine in/out) so it glides, never snaps.
	self._ventW=math.clamp(Crawl.camera.Value,0,1)
	local context=self._input:GetContext();local lobby=self._role=="Lobby"
	self._first=not lobby and context~="Dead"and context~="Results"
	self:_Crouch(dt,h)
	self:_VentEye(dt,c,camera)
	self:_ApplyBodyOffset(h,self._role=="Game"and self._first)
	if lobby then
		p.CameraMode=Enum.CameraMode.Classic;p.CameraMaxZoomDistance=16;p.CameraMinZoomDistance=8
		camera.CameraType=Enum.CameraType.Custom;if h then camera.CameraSubject=h end
		UIS.MouseIconEnabled=true
	elseif self._first then
		-- first person everywhere in the run, ducts included
		-- (Oct 25) a freed cursor (Alt) keeps the normal first-person view and walking: only the mouse is let go
		local cursorOnly=p:GetAttribute("EHCursorFree")==true and p:GetAttribute("EHLoreOpen")~=true
		p.CameraMaxZoomDistance=.5;p.CameraMinZoomDistance=.5;p.CameraMode=cursorOnly and Enum.CameraMode.Classic or Enum.CameraMode.LockFirstPerson
		local cine=p:GetAttribute("EHCinematic")
		if cine~=nil and cine~="Return" then
			-- a short client cinematic (waking up on the surface) is driving the camera itself
			camera.CameraType=Enum.CameraType.Scriptable
		elseif p:GetAttribute("EHLoreOpen") then
            self._loreFrame=self._loreFrame or camera.CFrame;camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=self._loreFrame
		else self._loreFrame=nil;camera.CameraType=Enum.CameraType.Custom;if h then camera.CameraSubject=h end end
		local freeCursor=p:GetAttribute("EHLoreOpen")==true or p:GetAttribute("EHCursorFree")==true
		if freeCursor then UIS.MouseBehavior=Enum.MouseBehavior.Default end
		-- no system pointer anywhere in the run (surface boarding, the descent cinematic and every
		-- floor): only the game's own crosshair. It comes back for lore pages, menus and text boxes,
		-- and on the results/death screens (handled below). The lobby keeps its normal cursor.
		local customAim=UIS.PreferredInput==Enum.PreferredInput.KeyboardAndMouse
			and not freeCursor and self._menu~=true and UIS:GetFocusedTextBox()==nil
		UIS.MouseIconEnabled=not customAim and (UIS.PreferredInput==Enum.PreferredInput.KeyboardAndMouse or freeCursor or self._menu==true or UIS:GetFocusedTextBox()~=nil)
	else
		p.CameraMode=Enum.CameraMode.Classic;camera.CameraType=Enum.CameraType.Scriptable
		UIS.MouseIconEnabled=true;UIS.MouseBehavior=Enum.MouseBehavior.Default
	end
	script.Parent:SetAttribute("CameraContext",lobby and "Lobby"or context)
end
-- Where the eye sits while you lie in a duct, as a CameraOffset (root space). Self-calibrating: it
-- reads where the camera module put the focus last frame, so it lands exactly on the head whatever
-- the avatar's size, then low-passes it so the crawl's sway is a gentle bob.
function Controller:_VentEye(dt,c,camera)
	if (self._ventW or 0)<.001 or not c then self._ventEye=nil;self._ventEyeW=nil;self._ventHead=nil;return end
	local root=c:FindFirstChild("HumanoidRootPart");local head=c:FindFirstChild("Head");local h=c:FindFirstChildOfClass("Humanoid")
	if not root or not head or not h then return end
	local params=self._ventParams
	if not params then params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true;self._ventParams=params end
	params.FilterDescendantsInstances={c,camera}
	-- The eye is pinned to the BODY, not the head: the prone pose turns the head toward where you look,
	-- so riding the head made the view slide sideways whenever you looked around while lying still.
	-- Once you are lying down, the head's place is taken once (centred on the body) and held there.
	local live=root.CFrame:PointToObjectSpace(head.Position)
	local headPos=head.Position
	if self._ventHead or ((self._ventW or 0)>=.99 and not Crawl.scripted) then
		local vh=self._ventHead
		-- (Oct 25) The eye stays where your head was when you lay down: that spot is kept as a WORLD offset
		-- along the duct from the middle of the body. So the view never slides back after the climb-in,
		-- and when the body turns round to crawl the other way the eye doesn't swing from one end of the
		-- body to the other (that swing read as a sudden speed-up).
		if not vh then
			local w=root.CFrame:VectorToWorldSpace(Vector3.new(live.X,0,live.Z));w=Vector3.new(w.X,0,w.Z)
			vh={y=live.Y,w=w,k=1};self._ventHead=vh
		end
		vh.k=1
		headPos=root.CFrame:PointToWorldSpace(Vector3.new(0,vh.y,0))+vh.w
	end
	-- just in front of and above the face, along the way the body lies
	local eye=headPos+Vector3.new(0,.22,0)
	-- keep it inside the duct: clear of the roof, and never through a wall (ray from the chest)
	local up=workspace:Raycast(eye,Vector3.new(0,VENT_CLEAR+1,0),params)
	if up and up.Distance<VENT_CLEAR then eye-=Vector3.new(0,VENT_CLEAR-up.Distance,0) end
	local from=root.Position+Vector3.new(0,eye.Y-root.Position.Y,0)
	local reach=eye-from
	if reach.Magnitude>.05 then
		local hit=workspace:Raycast(from,reach+reach.Unit*VENT_CLEAR,params)
		if hit then eye=from+reach.Unit*math.max(0,hit.Distance-VENT_CLEAR) end
	end
	-- the module's focus without our offset, then the offset that puts the lens on the eye
	local current=h.CameraOffset
	local base=camera.Focus.Position-root.CFrame:VectorToWorldSpace(current)
	-- (Oct 25) eased in WORLD space, then expressed in the body's frame: easing it in the body's own frame made the
	-- eye wander ~0.4 studs every time the body turned round (the old offset trailed the new one round the turn)
	local wantW=eye-base
	if not self._ventEyeW then self._ventEyeW=wantW else self._ventEyeW=self._ventEyeW:Lerp(wantW,1-math.exp(-dt*VENT_EYE_FOLLOW)) end
	self._ventEye=root.CFrame:VectorToObjectSpace(self._ventEyeW)
end
-- Runs right after the camera module has placed the camera: in a duct the look is held to a band
-- you can manage lying on your front (no looking straight up through your own back).
-- The real inside of a duct (half-extents in the VentVolume's axes): the volume box is drawn a
-- little larger than the sheet metal, so the walls are measured once with rays from its centre.
function Controller:_DuctInside(vol)
	self._ducts=self._ducts or setmetatable({},{__mode='k'})
	local known=self._ducts[vol];if known then return known end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=false
	local ignore={vol,workspace.CurrentCamera};for _,pl in game.Players:GetPlayers()do if pl.Character then table.insert(ignore,pl.Character)end end
	params.FilterDescendantsInstances=ignore
	local cf=vol.CFrame;local h=vol.Size/2
	local function inside(axis,len)
		local best=len
		for _,s in {1,-1}do local hit=workspace:Raycast(cf.Position,axis*s*(len+.5),params);if hit then best=math.min(best,hit.Distance)end end
		return best
	end
	known=Vector3.new(inside(cf.RightVector,h.X),inside(cf.UpVector,h.Y),h.Z)
	self._ducts[vol]=known
	return known
end
-- Climbing into / out of a duct the body is moved along a scripted path once per physics step, and
-- the duct's hard wall lets go the moment you start climbing out. The lens position is low-passed
-- through those moments (rotation untouched, so looking around stays instant), then handed back
-- once it has caught up: no snap, teleport or physics-step judder as you drop out and stand up.
function Controller:_SmoothTransition(dt)
	local camera=workspace.CurrentCamera
	if not camera or camera.CameraType~=Enum.CameraType.Custom or not self._first or self._role~="Game" then self._smoothPos=nil;return end
	if Crawl.scripted then self._smoothUntil=os.clock()+.35 end
	local pos=camera.CFrame.Position
	-- (the climb-out curve is already smooth: just follow it, ready to glide on once it hands back)
	if Crawl.exitPath then self._smoothPos=pos;return end
	local on=os.clock()<(self._smoothUntil or 0)
	if not on and not self._smoothPos then return end
	if not self._smoothPos then
		if not on then return end
		-- start from where the lens was actually drawn last frame (it may have been held inside the duct's
		-- walls), so letting go of that hold glides instead of jumping
		local from=self._drawnPos
		self._smoothPos=(from and (from-pos).Magnitude<4) and from or pos
	end
	if (pos-self._smoothPos).Magnitude>8 then self._smoothPos=on and pos or nil;return end
	self._smoothPos=self._smoothPos:Lerp(pos,1-math.exp(-math.clamp(dt or 1/60,0,.1)*(on and 15 or 22)))
	if not on and (pos-self._smoothPos).Magnitude<.01 then self._smoothPos=nil;return end
	camera.CFrame=CFrame.new(self._smoothPos)*camera.CFrame.Rotation
end
-- Climbing out of a duct the eye follows its own curve (HazardController sets Crawl.exitPath): from
-- where the lens is to standing eye height over the landing spot, leaving at the crawl's speed and
-- arriving at rest (a cubic Hermite curve), then the normal camera takes over with a short glide.
function Controller:_ExitPath()
	local ep=Crawl.exitPath
	local camera=workspace.CurrentCamera
	if not ep or not camera then return end
	local c=self._player.Character;local root=c and c:FindFirstChild("HumanoidRootPart")
	local u=(os.clock()-ep.t0)/ep.dur
	if u>=1 or not root or camera.CameraType~=Enum.CameraType.Custom or not self._first then
		Crawl.exitPath=nil
		self._smoothUntil=math.max(self._smoothUntil or 0,os.clock()+.3)
		return
	end
	if not ep.from then
		-- (the curve starts one frame back, so this very frame already carries on moving)
		ep.t0=math.min(ep.t0,os.clock()-(self._lastDt or 1/60));u=(os.clock()-ep.t0)/ep.dur
		ep.from=self._drawnPos or camera.CFrame.Position
		-- exactly where the normal camera will be once you stand there (your standing eye, measured)
		local off=self._standOff or Vector3.new(0,2,0)
		local to=ep.to+((typeof(ep.rot)=="CFrame") and ep.rot:VectorToWorldSpace(off) or off)
		ep.target=to
		-- leaves at the crawl's own speed (capped so the curve can never overshoot the landing)
		local flat=Vector3.new(ep.vel.X,0,ep.vel.Z)*ep.dur
		local reach=Vector3.new(to.X-ep.from.X,0,to.Z-ep.from.Z).Magnitude*2.95
		if flat.Magnitude>reach then flat=flat.Magnitude>1e-3 and flat.Unit*reach or Vector3.zero end
		ep.m0=flat
	end
	-- toward the end the goal slides onto where the normal camera really is right now (your body as it
	-- actually lands), so handing back control is seamless
	local off=self._standOff or Vector3.new(0,2,0)
	local live=root.Position+root.CFrame:VectorToWorldSpace(off)
	local w=math.clamp((u-.5)/.5,0,1);w=w*w*(3-2*w)
	local goal=ep.target:Lerp(live,w)
	local u2,u3=u*u,u*u*u
	local pos=ep.from*(2*u3-3*u2+1)+ep.m0*(u3-2*u2+u)+goal*(-2*u3+3*u2)
	camera.CFrame=CFrame.new(pos)*camera.CFrame.Rotation
end
-- Crawling in a duct: the lens rides the body's velocity and eases onto it (so the physics-step
-- judder between frames never shows), with a slight crawl bob that fades out when you stop.
function Controller:_CrawlSmooth(dt)
	local camera=workspace.CurrentCamera
	local c=self._player.Character;local root=c and c:FindFirstChild("HumanoidRootPart")
	if not Crawl.volume or Crawl.scripted or not camera or not root or camera.CameraType~=Enum.CameraType.Custom or not self._first or (self._ventW or 0)<.5 then
		self._crawlPos=nil;self._crawlAmp=0;return
	end
	dt=math.clamp(dt or 1/60,1/240,.1)
	-- Roblox's first-person camera sits half a stud BEHIND its focus, so turning the view swings the lens
	-- round that point - in a duct that read as the view gliding while you lay still. The lens is put
	-- back on a spot that doesn't depend on where you look: the same distance behind the focus, along
	-- the way your body lies.
	local focus=camera.Focus.Position
	local d=(camera.CFrame.Position-focus).Magnitude
	local bf=root.CFrame.LookVector;bf=Vector3.new(bf.X,0,bf.Z);bf=bf.Magnitude>.05 and bf.Unit or Vector3.new(0,0,-1)
	-- (Oct 25) the half-stud back from the focus is taken along a FIXED direction (the way the duct ran when you
	-- lay down), not the body's facing: the body turning round to crawl back no longer throws the lens
	local vh=self._ventHead;if vh and vh.w and vh.w.Magnitude>.05 then bf=vh.w.Unit end
	local target=d<2 and (focus-bf*d) or camera.CFrame.Position
	local vel=root.AssemblyLinearVelocity;vel=Vector3.new(vel.X,0,vel.Z)
	local s=self._crawlPos
	if not s or (target-s).Magnitude>1.5 then s=target else s=(s+vel*dt):Lerp(target,1-math.exp(-dt*9)) end
	self._crawlPos=s
	local still=self._player:GetAttribute("EHReduceMotion")==true
	local pace=still and 0 or math.clamp(vel.Magnitude/5,0,1)
	local a=(self._crawlAmp or 0);a+=(pace-a)*(1-math.exp(-dt*6));if a<.003 then a=0 end;self._crawlAmp=a
	self._crawlPhase=((self._crawlPhase or 0)+vel.Magnitude*dt*2.5)%(math.pi*4)
	local ph=self._crawlPhase
	local rot=camera.CFrame.Rotation
	local bob=Vector3.new(0,(math.abs(math.sin(ph))*.05-.025)*a,0)+rot.RightVector*(math.sin(ph*.5)*.025*a)
	camera.CFrame=CFrame.new(s+bob)*rot*CFrame.Angles(0,0,math.rad(math.sin(ph*.5)*.35*a))
end
function Controller:_VentCamera(dt)
	self._lastDt=math.clamp(dt or 1/60,1/240,.1)
	pcall(self._CrawlSmooth,self,dt)
	local ok,err=pcall(self._VentClamp,self)
	if not ok then warn(err) end
	-- standing eye height (above the root), measured whenever you are simply standing up
	local camera=workspace.CurrentCamera
	local c=self._player.Character;local root=c and c:FindFirstChild("HumanoidRootPart")
	if camera and root and self._first and (self._ventW or 0)<.001 and Crouch.amount<.01 and not Crawl.exitPath then
		local off=root.CFrame:VectorToObjectSpace(camera.CFrame.Position-root.Position)
		if off.Y>.5 and off.Y<4 and off.Magnitude<4 then self._standOff=self._standOff and self._standOff:Lerp(off,.1) or off end
	end
	ok,err=pcall(self._ExitPath,self);if not ok then warn(err) end
	-- smoothing runs last, on the lens as it will be drawn
	pcall(self._SmoothTransition,self,dt)
end
function Controller:_VentClamp()
	local vw=self._ventW or 0
	local camera=workspace.CurrentCamera
	if vw<.02 or not camera or camera.CameraType~=Enum.CameraType.Custom or not self._first or self._role~="Game" then return end
	-- Hard wall: while you are in a duct the lens is always kept inside the duct's own volume
	-- (shrunk by more than the camera's near plane), so turning round - or the body swinging when
	-- you turn to crawl the other way - can never push the view into or through a wall.
	local vol=Crawl.volume
	if vol and vol.Parent then
		local cf0=camera.CFrame
		local l=vol.CFrame:PointToObjectSpace(cf0.Position);local half=self:_DuctInside(vol)-Vector3.new(VENT_WALL,VENT_WALL,VENT_WALL)
		-- an end whose cover is off is open: the lens may carry on out of it (no stop at the mouth)
		local zLo,zHi=-math.max(0,half.Z),math.max(0,half.Z)
		local route=vol:FindFirstAncestorWhichIsA("Model")
		while route and not route:GetAttribute("EntryFrameA") do route=route.Parent and route.Parent:FindFirstAncestorWhichIsA("Model") end
		if route then
			for _,E in {"A","B"} do
				local fr=route:GetAttribute("EntryFrame"..E)
				if typeof(fr)=="CFrame" and route:GetAttribute("Cover"..E.."OpenAt")~=nil then
					if vol.CFrame:PointToObjectSpace(fr.Position).Z>0 then zHi=half.Z+4 else zLo=-half.Z-4 end
				end
			end
		end
		local c=Vector3.new(math.clamp(l.X,-math.max(0,half.X),math.max(0,half.X)),math.clamp(l.Y,-math.max(0,half.Y),math.max(0,half.Y)),math.clamp(l.Z,zLo,zHi))
		if (c-l).Magnitude>1e-4 then camera.CFrame=CFrame.new(vol.CFrame:PointToWorldSpace(c))*cf0.Rotation end
		-- the lens being held at the duct's end (crawling out of an open end): ease the stop and the
		-- climb-out that follows instead of halting dead
		if (c-l).Magnitude>.02 then self._smoothUntil=math.max(self._smoothUntil or 0,os.clock()+.35) end
	end
	if vw<.5 then return end
	local cf=camera.CFrame;local look=cf.LookVector
	local flat=Vector3.new(look.X,0,look.Z);flat=flat.Magnitude>1e-3 and flat.Unit or Vector3.new(0,0,-1)
	local pitch=math.asin(math.clamp(look.Y,-1,1))
	local clamped=math.clamp(pitch,VENT_PITCH_MIN,VENT_PITCH_MAX)
	if math.abs(clamped-pitch)>1e-4 then
		look=flat*math.cos(clamped)+Vector3.new(0,math.sin(clamped),0)
		camera.CFrame=CFrame.lookAt(cf.Position,cf.Position+look)
	end
end
function Controller:Start()
	RunService:BindToRenderStep("EHCamera",Enum.RenderPriority.Camera.Value+1,function(dt)self:_Update(dt)end)
	RunService:BindToRenderStep("EHVentCamera",Enum.RenderPriority.Camera.Value+2,function(dt)
		local ok,err=pcall(self._VentCamera,self,dt);if not ok then warn(err)end
		local cam=workspace.CurrentCamera;self._drawnPos=cam and cam.CFrame.Position
	end)
	self._scope:Add(function()RunService:UnbindFromRenderStep("EHVentCamera")end)
	RunService:BindToRenderStep("EHVisibility",Enum.RenderPriority.Camera.Value+7,function(dt)self:_Visibility(dt)end)
	self._scope:Add(function()RunService:UnbindFromRenderStep("EHCamera");RunService:UnbindFromRenderStep("EHVisibility")end)
	self:_Update()
end
function Controller:Destroy()
	if self._scope then self._scope:Destroy()end
	self._first=false;self:_Visibility();self:_ApplyBodyOffset(nil,false);UIS.MouseIconEnabled=self._original.icon
	local p=self._player;p.CameraMode=self._original.mode;p.CameraMaxZoomDistance=self._original.max;p.CameraMinZoomDistance=self._original.min
	if workspace.CurrentCamera then workspace.CurrentCamera.CameraType=Enum.CameraType.Custom end
end
return table.freeze(Controller)
