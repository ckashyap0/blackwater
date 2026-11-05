--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Players=game:GetService("Players")
local Tags=game:GetService("CollectionService")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local HeldView=require(game.ReplicatedStorage.Game.Shared.Utilities.HeldView)
local Reveal=require(game.ReplicatedStorage.Game.Shared.Utilities.HudReveal)
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)
	return setmetatable({Name="InteractionController",Dependencies={"StateController","InputController"},_player=player,_gui=gui,_targets={}},Controller)
end
function Controller:Init(deps)
	self._state=deps.StateController;self._input=deps.InputController;self._scope=Scope.new()
	-- authored in StarterGui.InteractionHint (PromptStack > Prompt, HoldProgress > Fill) and
	-- StarterGui.InteractionReticle (AimCursor)
	local gui=AuthoredGui.Get(self._gui,"InteractionHint")
	local cursorGui=AuthoredGui.Get(self._gui,"InteractionReticle")
	local stack=gui:WaitForChild("PromptStack")
	self._hint=gui;self._stack=stack;self._stackLayout=stack:FindFirstChildOfClass("UIListLayout")
	self._stackHome={anchor=stack.AnchorPoint,position=stack.Position}
	self._label=stack:WaitForChild("Prompt");self._label.Text=""
	-- the hold bar sits on its own, always centred at the bottom of the screen under the prompt
	self._bar=gui:WaitForChild("HoldProgress");self._fill=self._bar:WaitForChild("Fill")
	self._barHome={anchor=self._bar.AnchorPoint,position=self._bar.Position}
	local cursor=cursorGui:WaitForChild("AimCursor")
	self._cursor=cursor;self._cursorBase=cursor.BackgroundTransparency
	-- Papers get their own prompt card (StarterGui.InteractionHint.PaperCard): key chip, a small
	-- 'PAPER · READ' eyebrow and the sheet's title. It glides in when you look at a paper, the
	-- chip fills while you hold, and it glides out again.
	self._card=gui:FindFirstChild("PaperCard");self._cardShow=0
end
local CARD_CREAM,CARD_AMBER=Color3.fromRGB(232,228,206),Color3.fromRGB(211,164,87)
-- prompt / hold bar / paper card size: 1.2 on a 1080p monitor, shrinking with the SMALLER of the screen's
-- height and width so phones (short and narrow) and tablets (narrow) get proportionally smaller text
-- Same uniform scale as the objective text (HudScale, 960x600 design size), so every HUD line keeps
-- the same proportions on PC, phone, tablet and console.
local HudScaleUtil=require(game.ReplicatedStorage.Game.Shared.Utilities.HudScale)
local PROMPT_SCALE={referenceSize=Vector2.new(960,600),min=.6,max=1.15,consoleBoost=1.15}
local function promptScale(cam)
	if not cam then return 1 end
	return HudScaleUtil.Factor(cam.ViewportSize,PROMPT_SCALE,HudScaleUtil.IsTenFoot())
end
function Controller:_PaperCard(target,dt,progress)
	local card=self._card;if not card then return end
	if target then self._cardTarget=target end
	local want=target and 1 or 0
	self._cardShow+=(want-self._cardShow)*(1-math.exp(-dt*(target and 22 or 14)))
	if self._cardShow<.01 and not target then card.Visible=false;self._cardTarget=nil;return end
	local t=self._cardTarget
	card.Visible=true
	local k=self._cardShow*Reveal.Alpha()
	card.GroupTransparency=1-k
	card.Position=UDim2.new(.5,0,1,-64+math.floor((1-self._cardShow)*8+.5))
	local cam=workspace.CurrentCamera
	local scale=card:FindFirstChild("HudScale");if scale and cam then scale.Scale=promptScale(cam)end
	local col=card:FindFirstChild("Text");local chip=card:FindFirstChild("KeyChip")
	if t and col then col.Title.Text=t:GetAttribute("LoreTitle") or "Loose paper" end
	local touch=UserInputService.PreferredInput==Enum.PreferredInput.Touch
	if chip then
		chip.Visible=not touch
		local prompt=self._input:GetPrompt("Interact") or "[E]"
		chip.Key.Text=string.match(prompt,"^%[(.-)%]") or "E"
		local p=math.clamp(progress or 0,0,1)
		chip.ChipFill.Size=UDim2.fromScale(1,p)
		chip.Key.TextColor3=p>.55 and Color3.fromRGB(20,20,18) or CARD_CREAM
	end
	if col then col.Position=UDim2.fromOffset(touch and 18 or 60,0);col.Size=UDim2.new(1,touch and -32 or -74,1,0) end
	local outline=card:FindFirstChild("Outline")
	if outline then local h=(progress or 0)>0 and 1 or 0;outline.Color=CARD_CREAM:Lerp(CARD_AMBER,h);outline.Transparency=.62-.3*h end
end
function Controller:_Send(action,id,epoch)
	epoch=epoch or self._player:GetAttribute("EHCharacterEpoch")
	if type(epoch)~="number" or epoch<1 then return false end
	local payload={characterEpoch=epoch};if id then payload.interactionId=id end
	return self._state:SendAction(action,payload)
end
function Controller:_Cancel()
	if self._localHold and self._localHold.target:GetAttribute("EHKeycardReader") then pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.KeycardSwipe).Cancel()end) end
	self._localHold=nil
	-- let go with the bar (all but) full: the server counts that as finished, so the bar stays full
	-- and closes with the completion instead of vanishing as if the job had been abandoned
	local finished=self._holding~=nil and (self._progress or 0)>=.95
	if self._holding then self:_Send("EndInteraction",self._holding.id,self._holding.epoch);self._holding=nil end
	if finished then
		self._released=false;self._wasHolding=false;self._progress=1;self._progressHold=.3
		return
	end
	-- let go early: the bar is gone this frame, without waiting for the server to confirm
	self._released=true;self:_HideProgress()
end
function Controller:_HideProgress()
	self._progress=0;self._progressHold=0;self._progressId=nil;self._wasHolding=false
	if self._bar then self._bar.BackgroundTransparency=1;self._fill.BackgroundTransparency=1;self._fill.Size=UDim2.fromScale(0,1)end
end
function Controller:_Target()
	local context=self._input:GetContext()
	if context~="ActiveFloor" and context~="Transit" then return nil end
	if (self._player:GetAttribute("EHProtectionUntil") or 0)>workspace:GetServerTimeNow() then return nil end
	local character=self._player.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
	local camera=workspace.CurrentCamera;if not root or not camera then return nil end
	local ray=camera:ViewportPointToRay(camera.ViewportSize.X*.5,camera.ViewportSize.Y*.5)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
	-- invisible blocking volumes (e.g. around the valve station) never hide what is behind them
	local ignore={character,camera};for _,v in Tags:GetTagged("EHInvisibleCollider") do table.insert(ignore,v) end
	params.FilterDescendantsInstances=ignore;params.RespectCanCollide=false
	local hit=workspace:Raycast(camera.CFrame.Position,ray.Direction*12,params)
	-- an invisible target that is switched off (e.g. a vent opening whose cover is still on) never
	-- hides what is behind it
	for _=1,3 do
		if not (hit and self._targets[hit.Instance] and hit.Instance.Transparency>=1 and hit.Instance:GetAttribute("EHInteractionEnabled")~=true) then break end
		table.insert(ignore,hit.Instance);params.FilterDescendantsInstances=ignore
		hit=workspace:Raycast(camera.CFrame.Position,ray.Direction*12,params)
	end
	if not hit then return nil end
	-- Mops hang (or lie) close together and their grab boxes are generous: of all the mop grab boxes
	-- the aim passes through, take the one whose mop is closest to the aim line - the mop you are
	-- actually looking at, not whichever box the ray happened to enter first.
	if hit.Instance.Name=="MopHitbox" then
		local o,d=camera.CFrame.Position,ray.Direction.Unit
		local best,bestD=hit.Instance,math.huge
		for cand in self._targets do
			if cand.Name=="MopHitbox" and cand.Parent and cand:IsDescendantOf(workspace) and cand:GetAttribute("EHInteractionEnabled")==true then
				local l=cand.CFrame:PointToObjectSpace(o);local ld=cand.CFrame:VectorToObjectSpace(d);local h=cand.Size/2
				-- does the aim line pass through this box (within reach)?
				local t0,t1=0,12
				for _,ax in {"X","Y","Z"} do
					local p,v,e=l[ax],ld[ax],h[ax]
					if math.abs(v)<1e-6 then if math.abs(p)>e then t0=math.huge end
					else local a,b=(-e-p)/v,(e-p)/v;if a>b then a,b=b,a end;t0=math.max(t0,a);t1=math.min(t1,b) end
				end
				if t0<=t1 then
					-- distance from the aim line to the mop's own centre line (its long axis)
					local c=cand.Position;local axis=cand.CFrame.UpVector
					local w=c-o;local along=w:Dot(d);local perp=(w-d*along)
					local dist=(perp-axis*perp:Dot(axis)).Magnitude
					if dist<bestD then best,bestD=cand,dist end
				end
			end
		end
		hit={Instance=best,Position=hit.Position}
	end
	local target=self._targets[hit.Instance] and hit.Instance or nil
	if not target then
		for candidate in self._targets do
			if candidate:IsDescendantOf(workspace) and candidate:GetAttribute("EHInteractionEnabled")
				and candidate:GetAttribute("EHInteractionType")=="Revive" and candidate.Parent
				and hit.Instance:IsDescendantOf(candidate.Parent) then target=candidate;break end
		end
	end
	-- (Nov 3) a target marked EHWholeModel (the car's GET IN) is used from ANY part of its model you aim at -
	-- the doors, the bonnet, the wheels, the roof - not only from inside its hit box
	if not target then
		for candidate in self._targets do
			if candidate:GetAttribute("EHWholeModel") and candidate.Parent and candidate:IsDescendantOf(workspace) and candidate:GetAttribute("EHInteractionEnabled")==true
				and hit.Instance:IsDescendantOf(candidate.Parent) then target=candidate;break end
		end
	end
	if not target or not target:IsDescendantOf(workspace) or target:GetAttribute("EHInteractionEnabled")~=true then return nil end
	-- some prompts only make sense for you right now: RETURN MOP shows only while you carry a mop
	if target:GetAttribute("EHNeedsMop") and not self._player:GetAttribute("EHCarryingMop") then return nil end
	-- (Nov 3) and a slot that asks for an item (EHNeedsKind, e.g. the gate card reader) only while you carry one
	local needs=target:GetAttribute("EHNeedsKind");if needs and self._player:GetAttribute("EHCarriedKind")~=needs then return nil end
	-- Inside a duct the only prompt is the cover of the duct you are in (to push it out from the
	-- inside). CLIMB IN, screws and everything in the rooms around stay hidden until you are out.
	local inVent=self._player:GetAttribute("EHInVent")
	if inVent~=nil then
		local id=tostring(target:GetAttribute("EHInteractionId"))
		if id:sub(1,12)~="BW5VentCover" or id:sub(13,13+#tostring(inVent)-1)~=tostring(inVent) then return nil end
	end
	-- (a whole-model target is measured to the spot you aim at, so the ends of a long car work too)
	local at=target:GetAttribute("EHWholeModel") and hit.Position or target.Position
	if (root.Position-at).Magnitude>(target:GetAttribute("EHMaximumDistance") or 8) then return nil end
	return target
end
function Controller:_Render()
	local p=self._player;self._target=self:_Target()
	self._input:SetAvailable("Interact",self._target~=nil)
	local state=p:GetAttribute("EHInteractionState")
	-- after you let go the server may still say Holding for a moment; the bar ignores that
	local holding=state=="Holding" and not self._released
	-- A local hold (the surface gate: EHLocalHold names the remote to fire when it completes). The
	-- bar fills on this screen; letting go, looking away or walking off cancels it.
	local lh=self._localHold
	if lh then
		if self._target~=lh.target or lh.target:GetAttribute("EHInteractionEnabled")~=true then
			if lh.target:GetAttribute("EHKeycardReader") then require(game.ReplicatedStorage.Game.Shared.Utilities.KeycardSwipe).Cancel() end
			self._localHold=nil;self:_HideProgress();lh=nil
		else
			local u=math.clamp((os.clock()-lh.started)/lh.duration,0,1)
			self._bar.BackgroundTransparency=0;self._fill.BackgroundTransparency=0;self._fill.Size=UDim2.fromScale(u,1)
			if u>=1 then
				self._localHold=nil
				local network=game.ReplicatedStorage.Game:FindFirstChild("Network");local remote=network and network:FindFirstChild(lh.remote)
				if remote then remote:FireServer() end
				self._progress=1;self._progressHold=.18;self._wasHolding=false
			end
		end
	end
	-- The fill advances every frame at the hold rate and is only gently steered toward the server
	-- clock, so it glides continuously and never jumps backwards.
	local now=os.clock();local dt=math.clamp(now-(self._lastRender or now),0,.1);self._lastRender=now
	if holding then
		self._wasHolding=true
		local duration=math.max(.01,p:GetAttribute("EHInteractionDuration") or 1)
		local started=p:GetAttribute("EHInteractionStarted") or workspace:GetServerTimeNow()
		local id=tostring(p:GetAttribute("EHActiveInteraction"))..tostring(started)
		local target=math.clamp((workspace:GetServerTimeNow()-started)/duration,0,1)
		if self._progressId~=id then self._progressId=id;self._progress=target end
		local predicted=self._progress+dt/duration
		predicted+=(target-predicted)*(1-math.exp(-dt*5))
		self._progress=math.clamp(math.max(predicted,self._progress),0,1)
		-- picking something up: it goes into your hand the instant the bar is full, on this screen,
		-- without waiting for the server's answer to come back (EquipmentController shows it)
		local h=self._holding
		if h and self._progress>=.999 and p:GetAttribute("EHPredictCarry")~=h.id then
			local t=self._target
			if t and t:GetAttribute("EHInteractionId")==h.id and t:GetAttribute("EHInteractionType")=="Pickup" then
				p:SetAttribute("EHPredictCarry",h.id);p:SetAttribute("EHPredictCarryAt",os.clock())
			end
		end
	else
		if self._wasHolding then
			-- only a finished hold lingers (full bar for a beat); a released or refused one vanishes
			self._wasHolding=false
			if state=="Completed" and not self._released then self._progressHold=.18 else self:_HideProgress() end
		end
		if self._progressHold and self._progressHold>0 then
			self._progressHold-=dt;self._progress=math.min(1,(self._progress or 0)+dt*6)
		else self._progressId=nil end
	end
	local shown=holding or (self._progressHold or 0)>0 or self._localHold~=nil
	-- (kept in the layout and faded rather than hidden, so the prompt above never shifts)
	self._bar.BackgroundTransparency=shown and 0 or 1;self._fill.BackgroundTransparency=shown and 0 or 1
	-- (a job that keeps its progress between holds - mopping a spill - starts the bar where it left off)
	local base=math.clamp(self._progressBase or 0,0,.999)
	if shown and not self._localHold then self._fill.Size=UDim2.fromScale(base+(1-base)*(self._progress or 0),1)end
	local context=self._input:GetContext()
	self._cursor.Visible=(context=="ActiveFloor"or context=="Transit") and p:GetAttribute("EHLoreOpen")~=true
	self._cursor.Position=UDim2.fromScale(.5,.5)
	self._cursor.BackgroundTransparency=1-(1-self._cursorBase)*Reveal.Alpha()
	self._cursor.BackgroundColor3=self._target and Color3.fromRGB(113,211,145)or Color3.fromRGB(225,228,211)
	local lines={}
	local paper=self._target and self._card and self._target:GetAttribute("EHInteractionType")=="Paper" and self._target or nil
	-- (the card steps aside while the sheet itself is open in the reader)
	pcall(self._PaperCard,self,p:GetAttribute("EHLoreOpen")~=true and paper or nil,dt,(paper and shown) and self._progress or 0)
	-- a paper's hold shows in its key chip, not in the bar
	if paper then self._bar.BackgroundTransparency=1;self._fill.BackgroundTransparency=1 end
	if self._target then
  local action=self._target:GetAttribute('EHInteractionLabel')or 'Use'
  -- one zone, one prompt: the mop station reads RETURN MOP while you are carrying a mop
  local withMop=self._target:GetAttribute('EHLabelWithMop')
  if withMop and p:GetAttribute('EHCarryingMop') then action=withMop end
  self._input:SetTouchCaption('Interact',action)
  if game.UserInputService.PreferredInput==Enum.PreferredInput.Touch and not paper then table.insert(lines,action) end
  if game.UserInputService.PreferredInput~=Enum.PreferredInput.Touch and not paper then
   local prompt=self._input:GetPrompt('Interact')or '[E] Interact'
   local key=string.match(prompt,'^%[(.-)%]')or 'E'
   -- (the key chip in front is balanced by padding on the other side - _CentrePrompt - so the
   -- action itself sits dead centre over the hold bar, at any screen size)
   local chip='['..key..']  '
   self._chip=chip
   table.insert(lines,chip..action)
  end
 end
	local carried=p:GetAttribute("EHCarriedKind");if carried=="SupplyLink"then carried="Fuse"end
	-- no drop button while holding the mop (it only goes back on its rack)
	self._input:SetAvailable("DropObjectiveItem",carried~=nil and p:GetAttribute("EHCarryingMop")==nil)
	-- No "Fuse / G / Drop" line while carrying: the item's name only shows as the task prompt.
	if #lines==0 and self._message and os.clock()<(self._messageUntil or 0) and not (self._target and self._target:GetAttribute('EHLabelWithMop')~=nil) then table.insert(lines,self._message) end
	self._label.RichText=false
	self._label.Text=table.concat(lines,"\n")
	self:_CentrePrompt(nil) -- the whole line ([E] + action) is centred over the hold bar (Ryan, Oct 19)
	self._chip=nil
	self:_PlaceStack()
end
-- The hold bar and the prompt text always sit dead centre at the bottom of the screen, straight above
-- the stamina bar, on every device (phones and tablets included - they used to follow the Interact
-- button, which put them off to one side).
-- The prompt and the hold bar scale with the screen (like the paper card) so they keep their size on
-- phones, tablets and big monitors, and a lone "[E]  Take fuse" line is padded on the right by the
-- key chip's own width, so the action - not the whole line - is what sits centred over the bar.
function Controller:_CentrePrompt(chip)
	local cam=workspace.CurrentCamera
	local s=promptScale(cam)
	for _,g in {self._stack,self._bar} do
		local sc=g:FindFirstChild("HudScale") or Instance.new("UIScale");sc.Name="HudScale";sc.Parent=g
		if math.abs(sc.Scale-s)>.001 then sc.Scale=s end
	end
	local pad=self._label:FindFirstChild("ChipBalance")
	if not pad then pad=Instance.new("UIPadding");pad.Name="ChipBalance";pad.Parent=self._label end
	local w=0
	if chip then
		local meas=self._measure
		if not meas then
			meas=self._label:Clone();for _,c in meas:GetChildren() do c:Destroy() end
			meas.Name="PromptMeasure";meas.Text="";meas.TextTransparency=1;meas.TextStrokeTransparency=1;meas.BackgroundTransparency=1
			meas.AutomaticSize=Enum.AutomaticSize.None;meas.Size=UDim2.fromOffset(1000,48);meas.Position=UDim2.fromOffset(-3000,-3000);meas.Parent=self._hint
			self._measure=meas
		end
		if meas.Text~=chip then meas.Text=chip end
		w=meas.TextBounds.X
	end
	if pad.PaddingRight.Offset~=w then pad.PaddingRight=UDim.new(0,w) end
	-- touch: the action text is the same centred prompt as on PC; the Interact button becomes an
	-- invisible tap zone laid over it (it used to draw its own text, shifted by the safe area)
	local btn=self._input._buttons and self._input._buttons.Interact
	if btn and btn.Parent and game.UserInputService.PreferredInput==Enum.PreferredInput.Touch then
		if btn:IsA("TextButton") and btn.TextTransparency~=1 then btn.TextTransparency=1 end
		local par=btn.Parent;local pp=par:FindFirstChildOfClass("UIPadding")
		local origin=par.AbsolutePosition+(pp and Vector2.new(pp.PaddingLeft.Offset,pp.PaddingTop.Offset) or Vector2.zero)
		local c=self._label.AbsolutePosition+self._label.AbsoluteSize/2
		local want=UDim2.fromOffset(math.floor(c.X-origin.X+.5),math.floor(c.Y-origin.Y+.5))
		if btn.Position~=want then btn.Position=want end
	end
end
function Controller:_PlaceStack()
	local stack,layout,home=self._stack,self._stackLayout,self._stackHome
	if stack.AnchorPoint~=home.anchor or stack.Position~=home.position or self._bar.Position~=self._barHome.position then
		stack.AnchorPoint=home.anchor;stack.Position=home.position
		if layout then layout.VerticalAlignment=Enum.VerticalAlignment.Bottom end
		self._label.LayoutOrder=1
		self._bar.AnchorPoint=self._barHome.anchor;self._bar.Position=self._barHome.position
	end
end
function Controller:Start()
	for _,t in Tags:GetTagged("EHInteractable") do if t:IsA("BasePart") then self._targets[t]=true end end
	self._scope:Add(Tags:GetInstanceAddedSignal("EHInteractable"):Connect(function(t) if t:IsA("BasePart") then self._targets[t]=true end end))
	self._scope:Add(Tags:GetInstanceRemovedSignal("EHInteractable"):Connect(function(t) self._targets[t]=nil end))
	self._scope:Add(self._input:Register("Interact",function(state)
		if state=="Begin" then self._target=self:_Target();self._message=nil end -- (doing something else clears the last notice)
		if state=="Begin" and self._target and type(self._target:GetAttribute("EHLocalHold"))=="string" then
			-- (Oct 25) the works gate's card reader: only the keycard holder can swipe
			local KS=self._target:GetAttribute("EHKeycardReader") and require(game.ReplicatedStorage.Game.Shared.Utilities.KeycardSwipe)
			if KS and not KS.Allowed() then KS.Toast("You need the SITE KEYCARD - whoever checked in at the gatehouse has it",4);return end
			self._released=false;self._progressHold=0;self._progressBase=0
			self._localHold={target=self._target,started=os.clock(),duration=math.max(.1,self._target:GetAttribute("EHHoldDuration") or 1),remote=self._target:GetAttribute("EHLocalHold")}
			if KS then KS.Begin(self._target) end
		elseif state=="Begin" and self._target then
			local id=self._target:GetAttribute("EHInteractionId");local epoch=self._player:GetAttribute("EHCharacterEpoch")
			self._progressBase=self._target:GetAttribute("EHProgressBase") or 0
			if self:_Send("BeginInteraction",id,epoch) then self._holding={id=id,epoch=epoch};self._elapsed=0;self._released=false;self._progressHold=0 end
		elseif state=="End" or state=="Cancel" then self:_Cancel() end
	end))
	self._scope:Add(self._input:Register("DropObjectiveItem",function(state)
		if state=="Begin" then
			self:_Cancel()
			if self._player:GetAttribute("EHCarryingMop") then return end -- the mop cannot be dropped
			local epoch=self._player:GetAttribute("EHCharacterEpoch")
						if type(epoch)~="number" or epoch<1 or not self._player:GetAttribute("EHCarriedItem") then return end
			-- The hand view releases the item this frame and reports where it left the hand.
			local frame=HeldView.BeginDrop and HeldView.BeginDrop() or nil
			self._state:SendAction("DropObjectiveItem",{characterEpoch=epoch,frame=frame})
		end
	end))
	-- Picking up a mop: a 4 s reminder in the usual notification line at the bottom of the screen.
	self._scope:Add(self._player:GetAttributeChangedSignal("EHCarryingMop"):Connect(function()
		if self._player:GetAttribute("EHCarryingMop") then
			-- (once per mop: never again after a cancelled return or anything else you do with it)
			if os.clock()-(self._mopRemindAt or -1e9)>90 then
				self._message="Put the mop back in the Janitor Closet when you're done.";self._messageUntil=os.clock()+4;self._mopRemindAt=os.clock()
			end
		else
			if self._message and self._message:find("mop back",1,true) then self._message=nil end
		end
	end))
	-- short notices from other controllers on this client (e.g. "No room to stand up here.")
	self._scope:Add(self._player:GetAttributeChangedSignal("EHLocalNotice"):Connect(function()
		local text=self._player:GetAttribute("EHLocalNotice")
		if type(text)=="string" and text~="" then self._message=text;self._messageUntil=os.clock()+1.8;self._player:SetAttribute("EHLocalNotice",nil) end
	end))
	self._scope:Add(self._player:GetAttributeChangedSignal("EHInteractionSerial"):Connect(function()
		local state=self._player:GetAttribute("EHInteractionState")
		if state=="Completed" or state=="Rejected" or state=="Canceled" then self._holding=nil end
		-- a finished job: the bar runs to full and closes (whether or not the key is still held)
		if state=="Completed" then self._released=false;self._progress=math.max(self._progress or 0,.98);self._progressHold=math.max(self._progressHold or 0,.18);self._wasHolding=false end
		if state=="Canceled" or state=="Rejected" then if (self._progressHold or 0)>0 and not self._localHold then self:_HideProgress() end end
		if state=="Rejected" or state=="Canceled" then self._player:SetAttribute("EHPredictCarry",nil) end
		if state=="Rejected" then
			local reason=self._player:GetAttribute("EHInteractionReason")
			self._message=({NeedsMop="Grab a mop from the Janitor Closet first.",NoMop="You're not carrying a mop.",HandsFull="Your hands are full.",MopInHand="Your hands are full. Put the mop back in the Janitor Closet.",Knocked="Get back on your feet first.",PressureUnbalanced="Set the receiver to the PSI on your task first.",CompressorOff="Start the compressor first.",SealCheck="Run the seal check first.",AlreadyCarrying="Your hands are full.",WrongItemKind="That doesn't go there.",Busy="A teammate is using this.",OutOfRange="Move closer.",Occluded="Something's in the way.",ObjectiveIncomplete="Finish the jobs on this level first.",CrewOutside="Everyone needs to be in the lift.",RescueRequired="Revive your teammate first.",AwaitingReconnect="Waiting for your crew to reconnect.",DoorUnavailable="Wait for the doors."})[reason] or "You can't use that yet."
			self._messageUntil=os.clock()+(reason=="MopInHand" and 3.5 or 1.8)
		end
	end))
	self._scope:Add(RunService.Heartbeat:Connect(function(dt)
		self._elapsed=(self._elapsed or 0)+dt
		if self._holding and self._elapsed>=.5 then self._elapsed=0;self:_Send("ContinueInteraction",self._holding.id,self._holding.epoch) end
		self._renderElapsed=(self._renderElapsed or 0)+dt
		-- every frame: a prompt appears the instant you look at something (no delay, no fade)
		self._renderElapsed=0;self:_Render()
	end))
	self:_Render()
end
function Controller:Destroy()
	self:_Cancel();if self._scope then self._scope:Destroy() end;table.clear(self._targets)
end
return table.freeze(Controller)
