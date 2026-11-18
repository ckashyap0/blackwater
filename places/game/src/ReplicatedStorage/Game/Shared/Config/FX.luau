--!strict
-- R43: textures and sounds used by Utilities.SetPieceFX. Textures are Blender sprites uploaded in one batch
-- (vault Art Pipeline/scripts); an empty entry falls back to the engine's own particle texture.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	-- vault Art Pipeline/scripts/bw3_fx_sprites.py -> Downloads/BlackWaterModels/BW3/fx (R43 phase 3, group decals)
	Textures={
		Steam='rbxassetid://130962452304332',Spray='rbxassetid://99429879688548',Gas='rbxassetid://122627297073145',
		Spark='rbxassetid://136074685451715',Foam='rbxassetid://112567743731276',Mist='rbxassetid://78219970583637',
		WaterNormal='',WaterFoam='', -- not used yet: the flood surfaces keep the Ripple texture
	},
	-- Pro Sound Effects library clips (free on the Creator Store, licensed for every experience). Beats name them
	-- with sound='<key>'.
	Sounds={
		BulbPop='rbxassetid://9114592817',  -- Glass Breaks 12
		Alarm='rbxassetid://9125898704',    -- siren, high-low, interior (play it slow: an old plant siren)
		Hiss='rbxassetid://9116496074',     -- medium pressure air release
		Spray='rbxassetid://9120591722',    -- water spray on metal, high pressure
		Burst='rbxassetid://9116887596',    -- metal tank impact, booming
		Roar='rbxassetid://9125741935',     -- pipe water rush, heavy flow
		Rumble='rbxassetid://9120549625',   -- waterfall, background roar (loops)
		Lap='rbxassetid://9120570661',      -- water lap under a dock, inside a cave (loops)
		Gurgle='rbxassetid://9113603652',   -- bubbles, liquid gurgle, high to low
	},
})
