-- Floor 4 kit skinning (Nov 9): mesh name suffix "__Key" -> an existing uploaded SurfaceAppearance (BW4_SALibrary)
local MAP={
 Beige={'Term4_Plastic'},PlasticAged={'Term4_Plastic'},
 Cream={'Batten_Body',Color3.fromRGB(240,232,212)},PaintCream={'Batten_Body',Color3.fromRGB(240,232,212)},
 PanelBeige={'SteelDesk__P_PaintCream'},
 Grey={'SvcPanel_Dead'},PaintGrey={'SvcPanel_Dead'},
 Console={'SvcPanel_Dead',Color3.fromRGB(150,170,160)},
 Blue={'OilDrum__P_PaintBlue'},
 DarkSteel={'Kiosk_Frame'},Charcoal={'Kiosk_Frame'},DarkPlastic={'Kiosk_Frame'},
 Galv={'WasteBin__P_Galv'},Steel={'Kiosk_Metal'},Chrome={'Kiosk_Metal'},
 Wood={'Kiosk_Inside'},Cardboard={'PalletLoad__P_Cardboard'},Paper={'Desk_Paper'},Cork={'NoticeBoard_Cork'},
 Rubber={'MaintCart__P_Rubber'},
 CableRed={'MaintCart__P_Rubber',Color3.fromRGB(200,60,50)},CableBlue={'MaintCart__P_Rubber',Color3.fromRGB(60,100,200)},
 CableYellow={'MaintCart__P_Rubber',Color3.fromRGB(220,180,50)},CableGreen={'MaintCart__P_Rubber',Color3.fromRGB(60,160,80)},
 CableGrey={'MaintCart__P_Rubber',Color3.fromRGB(150,150,150)},
 Brass={'Ext2_Brass'},Copper={'MopSink_Copper'},Green={'GateReleaseHousing'},Yellow={'Gantry_Yellow'},
 Red={'GasCylinders__P_PaintRed'},WhiteDirty={'Batten_Body'},Ceramic={'Kiosk_Plinth'},
 HeavyRust={'OilDrum__P_HeavyRust'},Plate={'Tex_DiamondPlate'},PaintGreen={'GasCylinders__P_PaintGreen'},
 WoodWorn={'ShopChair__P_WoodWorn'},Clad={'Swatch_Clad'},
}
local GLOW={Lamp=Color3.fromRGB(255,214,150),Amber=Color3.fromRGB(255,150,40),GreenLamp=Color3.fromRGB(60,230,90),RedLamp=Color3.fromRGB(230,40,30),BlueLamp=Color3.fromRGB(70,150,255)}
local M={MAP=MAP}
function M.Skin(root)
 local lib=game.ServerStorage.BW4_SALibrary
 for _,p in root:GetDescendants() do if p:IsA('MeshPart') then
  local k=p.Name:match('__([%w]+)$')
  local e=k and MAP[k]
  if e then
   for _,c in p:GetChildren() do if c:IsA('SurfaceAppearance') then c:Destroy() end end
   local sa=lib:FindFirstChild(e[1]) if sa then sa:Clone().Parent=p end
   p.Color=e[2] or Color3.new(1,1,1) p.Material=Enum.Material.Plastic
  elseif k and GLOW[k] then p.Material=Enum.Material.Neon p.Color=GLOW[k]
  elseif k=='Glass' then p.Material=Enum.Material.Glass p.Color=Color3.fromRGB(20,26,28) p.Transparency=.15 p.Reflectance=.08
  elseif k=='Water' then p.Material=Enum.Material.Glass p.Color=Color3.fromRGB(150,190,215) p.Transparency=.35
  elseif k=='Fabric' then p.Material=Enum.Material.Fabric p.Color=Color3.fromRGB(70,82,98)
  elseif k=='Screen' then p.Material=Enum.Material.Glass p.Color=Color3.fromRGB(30,45,40) p.Transparency=0 p.Reflectance=.15
  end
  p.CanCollide=false p.CanTouch=false
 end end
end
return M
