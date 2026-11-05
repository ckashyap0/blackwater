--!nonstrict
-- NO POP-IN. Three layers keep models and textures from appearing late when you turn or look up:
--  1. every floor (and the yard, shaft and lift) is authored with ModelStreamingMode = Persistent,
--     so its parts reach this client as soon as the floor exists and are never streamed out;
--  2. every MeshPart on them uses RenderFidelity = Precise (no low-detail stand-in swapped in by
--     distance or angle);
--  3. this controller downloads every mesh, texture and material map a floor uses the moment the
--     floor appears in the shaft (during the lift ride, before the doors open), plus every
--     MaterialVariant at start, so nothing is fetched for the first time when it comes into view.
-- Anything already in the cache is skipped, so a floor is only ever warmed once per session.
--
-- SHADOW BUDGET. The floors are lit by dozens of lamps authored to cast shadows (Floor 4 alone has
-- ~70). Rendering all of them costs a lot on phones and only the nearest few are ever noticeable, so
-- only the SHADOW_BUDGET lamps closest to the camera cast shadows at any moment; the rest keep their
-- light and colour but skip the shadow pass. Lamps that were authored without shadows are never
-- touched, and moving through the floor hands shadows over smoothly (re-checked a few times a second).
local ContentProvider=game:GetService('ContentProvider')
local MaterialService=game:GetService('MaterialService')
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local SHADOW_BUDGET,SHADOW_RANGE=6,110
function Controller.new(player)return setmetatable({Name='AssetWarmupController',Dependencies={},_player=player,_seen={},_warmed=setmetatable({},{__mode='k'}),_shadow={}},Controller)end
-- remember every lamp on a floor that was authored to cast shadows
function Controller:_TrackShadows(root)
 for _,d in root:GetDescendants()do if d:IsA('Light') and d.Shadows and not self._shadow[d] then self._shadow[d]=true end end
end
function Controller:_ShadowStep()
 local cam=workspace.CurrentCamera;if not cam then return end
 local at=cam.CFrame.Position
 local near={}
 for l in self._shadow do
  local p=l.Parent
  if not p or not l:IsDescendantOf(workspace) then self._shadow[l]=nil
  else
   local pos=p:IsA('BasePart') and p.Position or (p:IsA('Attachment') and p.WorldPosition)
   local dist=pos and (pos-at).Magnitude or math.huge
   if dist<=SHADOW_RANGE and l.Enabled then table.insert(near,{l,dist}) elseif l.Shadows then l.Shadows=false end
  end
 end
 table.sort(near,function(a,b)return a[2]<b[2] end)
 for i,e in near do local want=i<=SHADOW_BUDGET;if e[1].Shadows~=want then e[1].Shadows=want end end
end
function Controller:Init()self._scope=Scope.new()end
local PROPS={
 MeshPart={'MeshId','TextureID'},SurfaceAppearance={'ColorMap','NormalMap','RoughnessMap','MetalnessMap'},
 Decal={'Texture'},Texture={'Texture'},MaterialVariant={'ColorMap','NormalMap','RoughnessMap','MetalnessMap'},
 SpecialMesh={'MeshId','TextureId'},ImageLabel={'Image'},ImageButton={'Image'},ParticleEmitter={'Texture'},
 Beam={'Texture'},Trail={'Texture'},Sound={'SoundId'},
}
function Controller:_Collect(root,list)
 local function take(inst)
  local p=PROPS[inst.ClassName];if not p then return end
  for _,k in p do
   local ok,v=pcall(function()return inst[k] end)
   -- (the instance itself is preloaded, not the id string: a bare id is fetched as an image, which
   -- fails for meshes and sounds)
   if ok and type(v)=='string' and v~='' and not self._seen[v] then self._seen[v]=true;if list[#list]~=inst then table.insert(list,inst) end end
  end
 end
 take(root)
 for _,d in root:GetDescendants()do take(d) end
end
-- downloads in small batches on its own thread: never blocks a frame or the game's own loading
function Controller:_Warm(root)
 if not root or self._warmed[root] then return end
 self._warmed[root]=true
 local list={};self:_Collect(root,list)
 if #list==0 then return end
 task.spawn(function()
  for i=1,#list,40 do
   local batch=table.move(list,i,math.min(i+39,#list),1,{})
   pcall(function()ContentProvider:PreloadAsync(batch)end)
   task.wait()
  end
 end)
end
function Controller:Start()
 -- every material map first (walls, floors, ceilings, props on every floor)
 self:_Warm(MaterialService)
 local function watchEnv(env)
  for _,c in env:GetChildren()do self:_Warm(c);self:_TrackShadows(c) end
  self._scope:Add(env.ChildAdded:Connect(function(c)
   -- (a floor arrives in pieces while it streams in: warm it once now and once it has settled)
   self:_Warm(c);self:_TrackShadows(c)
   task.delay(4,function()if c.Parent then self._warmed[c]=nil;self:_Warm(c);self:_TrackShadows(c) end end)
  end))
 end
 local acc=0
 self._scope:Add(game:GetService('RunService').Heartbeat:Connect(function(dt)acc+=dt;if acc>=.25 then acc=0;self:_ShadowStep() end end))
 task.spawn(function()
  local runtime=workspace:WaitForChild('Runtime',60);if not runtime then return end
  local env=runtime:FindFirstChild('DescentEnvironment') or runtime:WaitForChild('DescentEnvironment',120)
  if env then watchEnv(env) end
  self._scope:Add(runtime.ChildAdded:Connect(function(c)if c.Name=='DescentEnvironment' then watchEnv(c) end end))
 end)
end
function Controller:Destroy()if self._scope then self._scope:Destroy() end end
return table.freeze(Controller)
