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
		-- the inlets are shut and Filter 4 lifts over its weir: black water starts across the hall
		Filter4={letterbox=true,shots={
			{from='CamF4A',to='CamF4B',dur=4.5,ease='Quad',fov={60,50},shake=.12},
		}},
		-- the bypass is open: the clean channel in the office turns black, then the panel that says where it goes next
		Payoff={letterbox=true,shots={
			{from='CamPayA',to='CamPayA',dur=3.2,ease='Linear',fov={58,52}},
			{from='CamPayB',to='CamPayB',dur=3,ease='Linear',fov={50,44}},
		}},
	},
})
