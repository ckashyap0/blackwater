local A=workspace.BlackwaterAuthoring
local L4,L5=A.Level4,A.Level5
local P={cache={}}
local FLOOR=-130
local function ex(list) local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances=list rp.RespectCanCollide=false return rp end
function P.analyse(m)
 local cf,sz=m:GetBoundingBox() local rp=ex({m}) local best,bd=nil,1e9
 for _,ax in {Vector3.xAxis,-Vector3.xAxis,Vector3.zAxis,-Vector3.zAxis} do local w=cf:VectorToWorldSpace(ax) local half=math.abs(ax.X)*sz.X/2+math.abs(ax.Z)*sz.Z/2 local r=workspace:Raycast(cf.Position,w*(half+3),rp) if r and r.Instance.Transparency<1 and r.Distance-half<bd then bd=r.Distance-half best=ax end end
 local d=workspace:Raycast(cf.Position,Vector3.new(0,-40,0),rp) local fy=d and d.Position.Y or (cf.Position.Y-sz.Y/2)
 return best,(cf.Position.Y-sz.Y/2)-fy,bd
end
function P.src(name,root)
 if P.cache[name] then return P.cache[name] end
 local m for _,r in root and {root} or {game.ServerStorage.BW_ModelKitF4,L5.PropCollections,L5.Machinery,L4.Dressing} do m=r:FindFirstChild(name,true) if m then break end end
 assert(m,'no src '..name)
 local back,h,gap=P.analyse(m) P.cache[name]={m=m,back=back,h=h,gap=gap} return P.cache[name]
end
local function yawFor(back,dir) return math.atan2(-dir.Z,dir.X)-math.atan2(-back.Z,back.X) end
function P.clash(m,exclude)
 local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Exclude
 local list={m,L4.Architecture} for _,e in exclude or {} do table.insert(list,e) end op.FilterDescendantsInstances=list
 local t={} for _,p in m:GetDescendants() do if p:IsA('BasePart') and p.Transparency<1 then for _,h in workspace:GetPartBoundsInBox(p.CFrame,p.Size*.85,op) do if h.Transparency<1 then local mm=h:FindFirstAncestorWhichIsA('Model') t[(mm and mm.Name or h.Name)]=true end end end end
 local s={} for k in t do s[#s+1]=k end return s
end
function P.place(name,folder,at,dir,opt)
 opt=opt or {}
 local s=P.src(name,opt.root) local m=s.m:Clone()
 local bcf,sz=s.m:GetBoundingBox() local pivRel=bcf:ToObjectSpace(s.m:GetPivot())
 local back=s.back or Vector3.xAxis
 local yaw=dir and yawFor(back,dir) or math.rad(opt.yaw or 0)
 local depth=math.abs(back.X)*sz.X+math.abs(back.Z)*sz.Z
 local y=(opt.floorY or FLOOR)+(opt.h or s.h or 0)+sz.Y/2
 local pos
 if dir then local r=workspace:Raycast(Vector3.new(at.X,opt.rayY or -127.5,at.Z),dir*30,ex({L4.Services,L4.LightingGroups,L4.Dressing,L4.Interactables}))
  if not r then m:Destroy() return 'nohit '..name end
  local hp=r.Position-dir*(depth/2+(opt.gap or .04)) pos=Vector3.new(hp.X,y,hp.Z)
 else pos=Vector3.new(at.X,y,at.Z) end
 m:PivotTo(CFrame.new(pos)*CFrame.Angles(0,yaw,0)*pivRel) m.Parent=folder
 local c=P.clash(m,{L4.Services,L4.LightingGroups})
 if #c>0 and not opt.force then m:Destroy() return 'CLASH '..name..' with '..table.concat(c,',') end
 return 'ok '..name..string.format(' @%.1f,%.1f',pos.X,pos.Z),m
end
return P
