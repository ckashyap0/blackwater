--!strict
-- The game's real (dark) lighting. The place file itself is saved with bright Lighting so the map is
-- easy to see while building in Studio; ServerScriptService.RuntimeLighting applies these values the
-- moment a playtest or live server starts. Light sources (spot/point/surface lights, lamps,
-- lanterns) are never touched by either side.
-- These are the exact settings the game was tuned with. For a fully pitch-black ambient, set
-- Ambient and OutdoorAmbient to Color3.fromRGB(0,0,0).
local RuntimeLighting={
	Lighting={
		-- Oct 18: a little brighter overall (Ryan: "too dark"); pools of light still carry the rooms
		Ambient=Color3.fromRGB(33,36,31),
		OutdoorAmbient=Color3.fromRGB(24,27,23),
		Brightness=1,
		ClockTime=0,
		GeographicLatitude=0,
		ExposureCompensation=.18,
		EnvironmentDiffuseScale=.32,
		EnvironmentSpecularScale=.1,
		GlobalShadows=true,
		ShadowSoftness=.2,
		FogStart=2,
		FogEnd=95,
		FogColor=Color3.fromRGB(38,46,47),
		ColorShift_Top=Color3.new(0,0,0),
		ColorShift_Bottom=Color3.new(0,0,0),
	},
	-- post effects under Lighting: name -> properties (Enabled included)
	Effects={
		BlackwaterGrade={Enabled=true,Brightness=.015,Contrast=.18,Saturation=-.16,TintColor=Color3.fromRGB(236,244,232)},
		FixtureBloom={Enabled=true,Intensity=.2,Size=22,Threshold=1.5},
	},
	-- what Studio shows while you edit (saved in the place file; applied by hand, never at runtime)
	EditPreview={
		Ambient=Color3.fromRGB(170,170,170),
		OutdoorAmbient=Color3.fromRGB(170,170,170),
		Brightness=3,
		ClockTime=14,
		ExposureCompensation=0,
		EnvironmentDiffuseScale=.8,
		EnvironmentSpecularScale=.3,
		FogStart=0,
		FogEnd=100000,
	},
}
return table.freeze(RuntimeLighting)
