local M={}
local function cf(a,k)return CFrame.new(a[1]*k,a[2]*k,a[3]*k,table.unpack(a,4,12))end
local function vec(a)return Vector3.new(table.unpack(a))end
function M.Run(apply,only)
 local root=workspace.BlackwaterAuthoring.Level4
 local lib=game.ServerStorage.ArtTools.BW28Normalized
 local backup=game.ServerStorage.BackupR30Floor4Meshes
 local report={}
 for _,template in lib:GetChildren()do
  local raw=template:GetAttribute('InstallManifest')
  if not raw then continue end
  local spec=game.HttpService:JSONDecode(raw)
  if only and spec.name~=only then continue end
  local row={models=0,meshes=0,hidden=0,skippedGroups=0,noAnchor=0}
  local candidates={}
  for _,m in root:GetDescendants()do if m:IsA('Model')and m.Name==spec.name and not m:GetAttribute('BW30Installed')then table.insert(candidates,m)end end
  for _,model in candidates do
   local all=model:GetDescendants();local anchor,k
   for _,p in all do
    if p:IsA('Part')and p.Name==spec.anchor.name and not p:GetAttribute('BW30Hidden')then
     local ratios=p.Size/vec(spec.anchor.size);local mean=(ratios.X+ratios.Y+ratios.Z)/3
     if math.max(math.abs(ratios.X-mean),math.abs(ratios.Y-mean),math.abs(ratios.Z-mean))<.006 then anchor=p;k=mean;break end
    end
   end
   if not anchor then row.noAnchor+=1;continue end
   local frame=anchor.CFrame*cf(spec.anchor.cf,k):Inverse()
   local plans={};local used={}
   for _,g in spec.groups do
    local found={};local good=true
    for _,sp in g.parts do
     local want=frame*cf(sp.cf,k);local chosen
     for _,p in all do
      if p:IsA('Part')and p.Name==sp.name and not used[p] and not p:GetAttribute('BW30Hidden')and not p:GetAttribute('Ref')and p.Material~=Enum.Material.Neon
       and (p.Size-vec(sp.size)*k).Magnitude<.035
       and (p.Position-want.Position).Magnitude<.045
       and p.CFrame.UpVector:Dot(want.UpVector)>.998 and p.CFrame.LookVector:Dot(want.LookVector)>.998 then chosen=p;break end
     end
     if not chosen then good=false;break end
     table.insert(found,chosen)
    end
    if good then for _,p in found do used[p]=true end;table.insert(plans,{mesh=g.mesh,parts=found})else row.skippedGroups+=1 end
   end
   if #plans==0 then continue end
   row.models+=1
   if apply then
    local old=model:Clone();old:SetAttribute('BackupOf',model:GetFullName());old.Parent=backup
    local visual=Instance.new('Model');visual.Name='BW30Visual';visual:SetAttribute('BlenderSource',spec.name);visual.Parent=model
    for _,plan in plans do
     local orig=assert(template:FindFirstChild(plan.mesh),plan.mesh);local mesh=orig:Clone()
     mesh.Size=orig.Size*k;mesh.CFrame=frame*cf({orig.CFrame:GetComponents()},k);mesh.Parent=visual
     for _,p in plan.parts do p:SetAttribute('BW30OriginalTransparency',p.Transparency);p:SetAttribute('BW30Hidden',true);p.Transparency=1;row.hidden+=1 end
    end
    local detail=template:FindFirstChild('BW28_'..spec.name..'__ServiceDetail')
    if detail and used[anchor]then local c=detail:Clone();c.Size=detail.Size*k;c.CFrame=frame*cf({detail.CFrame:GetComponents()},k);c.Parent=visual end
    model:SetAttribute('BW30Installed',true)
    if row.models%10==0 then task.wait()end
   end
   row.meshes+=#plans
  end
  report[spec.name]=row
 end
 return report
end
return M