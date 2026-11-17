--!strict
-- R43: camera cuts per floor (EncounterId -> cut id -> cut). Played by Utilities.Cinematic; started on the server
-- with Cinematic.Play(floorModel, id). Marker parts are invisible parts in the floor's authoring model with a
-- Ref attribute; their CFrame is the camera pose. Keep cuts short (3-8 s): the player loses control meanwhile.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Level3={
		-- the doors open onto the filter hall: a slow push out over the beds
		Arrival={letterbox=true,shots={
			{from='CamArrivalA',to='CamArrivalB',dur=5,ease='Sine',fov={55,62},caption='LEVEL 3   FILTRATION'},
		}},
	},
})
