--!strict
-- R43: textures and sounds used by Utilities.SetPieceFX. Textures are Blender sprites uploaded in one batch
-- (vault Art Pipeline/scripts); an empty entry falls back to the engine's own particle texture.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Textures={Steam='',Spray='',Gas='',Spark='',Foam='',Mist='',WaterNormal='',WaterFoam=''},
	Sounds={
		BulbPop='rbxassetid://9116283546',   -- (torch off click, pitched; replace with a real pop)
		Alarm='',Hiss='',Roar='',Rumble='',Burst='',
	},
})
