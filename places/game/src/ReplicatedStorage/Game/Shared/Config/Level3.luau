--!strict
-- LEVEL 3: FILTRATION (R43 rebuild). Shared by the server floor (Level3Floor, BlackWaterReach) and the client
-- (FiltrationController, SetPieceController, RadioLine, ObjectiveController). Design: vault Floors/Floor 3.md,
-- repo tasks/R43_active_redesign_plan.md.
-- The story job: take the filters out of the line so raw water goes through. Every stage pushes that along,
-- and the floor fights back: a drum splits, the wrong valve gasses you, Filter 4 overflows and floods the hall.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Stages={'Leak','Isolate','Beds','Filter4','Bypass','Lift'},
	KeyItemId='BW3BypassKey',KeySocketId='BW3WheelStand',KeyKind='BypassKey',
	Text={
		LeakValve='Shut the valve on the leaking drum',
		LeakFan='Pull the extract fan lever',
		Isolate='Close the ferric line valve',
		Beds='Close the filters in the order on the board (%d/5)',
		Filter4='Close Filter 4 by hand in the pipe gallery',
		KeyOnHook='Take the bypass key off the hook',
		KeyDropped='Pick up the bypass key',
		SentAbove='Take the key down the gallery hatch',
		SentKey='Put the key in the wheel stand',
		SentWheel='Turn the bypass wheel (%d/3)',
		CrewStart='Pump the header up at the console',
		CrewHold='Keep pumping the header (%d%%)',
		CrewAway='Pressure is dropping, get back on the pump (%d%%)',
		Lift='Get back to the lift',
		NoPressure="The wheel won't move without pressure.",
		HatchBusy="Someone's already down there.",
		NeedKey='You need the key to go down.',
		WrongLine='Wrong line. Check the tag colours against the placard.',
		WrongBed='Not that one. Check the board.',
		Stalled="It won't turn. Something's sitting on the valve.",
		ValveFirst='Shut the drum valve first.',
	},
	Holds={Bed=2.5,Header=1,Hatch=1,Key=.5,Socket=.8},
	-- work for the new job modes (InteractionService): turns for cranks, pulls for levers, strokes for pumps
	Work={BundValve=2,FanLever=1,IsoValve=1,F4Wheel=4,BypassWheel=3,Header=20},
	-- THE LIGHT RULE (BlackWaterReach). Distances in studs, speeds in studs per second.
	Light={
		Step=.2,SenseHead=45,SensePath=30,Creep=3,Linger=2,Retreat=1.5,
		Snuff=6,SnuffHeight=6,SnuffSeconds=.8,ClearDistance=14,ClearSeconds=6,
		FilmStamina=15,FilmHaze=.6,FilmSpeed=.8,
		InletRest=12,LiftRestBed=30,LiftRestGallery=40,
		RippleParts=12,RipplePartsTouch=6,RippleRange=40,RippleRangeTouch=20,
	},
	Fumes={Stamina=18,Haze=.8,HazeEmpty=1,RiseSeconds=1.5,ClearSeconds=3,EmptySpeed=.7,FanSpinUp=3,ThinSeconds=12,CoughMin=3,CoughMax=5},
	-- the wrong dosing valve: the fumes come back for a while
	Gas={WrongSurgeSeconds=9},
	-- header pressure is a pump now: 20 strokes fill it, it drains at Decay strokes a second, and the wheel
	-- needs WheelNeeds percent. A solo player's header latches once it reaches WheelNeeds.
	Header={WheelNeeds=60,Decay=1.1,PumpGap={min=.32,max=1.25}},
	Wheel={Turns=3},
	Bed={DropStuds=2,DropSeconds=8,ScourSeconds=6},
	-- the board lists the five running beds in a random order; Filter 4 is out of service
	Beds={Running={1,2,3,5,6},Surge=8,SurgeSeconds=10},
	-- Filter 4 overflows: the hall floods a stage every StageSeconds until its hand wheel is shut.
	-- At FailRise (Floors.RisingWater) the crew is pushed back to L3Checkpoint and the water drops to DropTo.
	Flood={FirstSeconds=18,StageSeconds=32,DropTo=2,DrainSeconds=14,StallDistance=10},
	Ladder={Seconds=1.6},
	-- seconds after the last wheel turn (BypassOpenAt); GreyFaceAt = BypassOpenAt + GreyDelay
	Grey={Delay=2.7,Hold=4,LineAt=3,Dark=.3,Empty=1.2,End=8,EyesAt=3.2,CompleteAfter=45},
	Knock={Gap=.38,Pause=1.1,Sound='rbxassetid://9116642648',Speed=.8,Volume=.5},
	HintSeconds=90,
	-- the floor's own fog (FiltrationController): darker than the station default so a dark hall stays dark at a
	-- distance instead of washing out grey, and longer so the lit beds read across the hall
	Lighting={FogStart=30,FogEnd=230,FogColor=Color3.fromRGB(6,8,8)},
	-- MARTY. One sentence, 90 characters or less. He names the next job and warns about nothing.
	Marty={
		A1={at=6,text="You took your time getting to Level Three."},
		A2={at=11,text="Dosing room's first on the left, start there."},
		B0={text="That's drum nine gone, shut its valve before you breathe much of it."},
		B1={text="Now the fan, the lever's on the back wall."},
		B2={text="Close off the ferric line, the tags tell you which valve."},
		C1={text="The board by the hall door says which filters to shut, and in what order."},
		C2={text="You don't need a light to turn a handle."},
		C3={text="Two more."},
		E1={text="Four's console is dead, there's a hand wheel for it down in the gallery."},
		E2={text="Back up, then try it again."},
		E3={text="That's four shut, it'll drain off."},
		D1={text="Meet me by the gallery stairs at the far end."},
		D7={text="You'll do."},
		D8={text="Three turns, and it won't budge unless they keep the pressure up."},
		F1={text="It's open, get back up to the lift."},
		G1={text="Nothing goes through the filters anymore, get in the lift."},
		G2={text="See you on Level Two, I'm already there."},
	},
	Hints={
		Leak="The drum valve's in the bund, down low by the split drum.",
		LeakFan="Fan lever, back wall, under the fan.",
		Isolate="Match the tag colours to the placard on the wall.",
		Beds="The board's on the wall by the hall door.",
		Filter4="Gallery stairs are at the far end of the deck.",
		Stalled="Get the water off that valve, it goes where the light is.",
		BypassKey="One of you takes the key, just one.",
		BypassPressure="Somebody has to keep pumping the header.",
		Lift="Lift's back the way you came.",
	},
	-- THE IMITATION. {name} is filled in by the server. Each line plays once per floor.
	Radio={
		S1={text="Turn your light on, we can't see you on the camera."},
		S2={text="We've got pressure up here, keep turning."},
		S3={text="Stay by the wheel, we're coming down."},
		S4={text="Who were you talking to?"},
		K1={text="I'm on the wheel, keep it steady up there."},
		K2={text="It's open, you can let go."},
		K3={text="I can hear you at the hatch."},
		R1={text="I'm still down here at the wheel, where did everyone go?"},
		-- solo: the player's own name, then the 1996 crew
		SoloS1={text="Put your light on, I can't see you."},
		SoloS2={who='T. Okafor',text="Voss, is that you on the wheel?"},
		SoloS3={who='R. Lind',text="He's not answering, pull him out of there."},
	},
	Stands={A='MartyMarker_L3CrossWalk',B='MartyMarker_L3KeyHook',C='MartyMarker_L3Booth',D='MartyMarker_L3Landing'},
	-- BEATS (Floors.BeatRunner stamps them; SetPieceController plays these effects on every screen)
	Beats={
		DrumBurst={
			{fx='Burst',ref='DrumLeak',kind='Gas',seconds=14},
			{fx='Burst',ref='DrumLeak',kind='Spray',seconds=1.4},
			{fx='Shake',amp=.35,seconds=.9,ref='DrumLeak'},
			{fx='Beacons',refs={'DosingBeacon1','DosingBeacon2'},seconds=40},
			{fx='Sound',ref='DrumLeak',sound='Burst',volume=.9,speed=.8,life=3},
			{fx='Sound',ref='DrumLeak',sound='Spray',volume=.7,speed=.9,life=6},
			{fx='Sound',ref='DrumLeak',sound='Hiss',volume=.45,speed=.8,life=14,loop=true},
			{fx='Sound',ref='DosingBeacon1',sound='Alarm',volume=.3,speed=.7,life=20},
		},
		WrongLine={
			{fx='Burst',ref='DrumLeak',kind='Gas',seconds=6},
			{fx='Shake',amp=.25,seconds=.6},
			{fx='Sound',ref='DrumLeak',sound='Hiss',volume=.5,speed=.9,life=6,loop=true},
		},
		BedSurge={
			{fx='Shake',amp=.3,seconds=1.2},
			{fx='Sound',ref='BedWater3',sound='Roar',volume=.7,speed=.8,life=5},
			{fx='Burst',refs={'BedWater1','BedWater2','BedWater3','BedWater5','BedWater6'},kind='Boil',seconds=3},
		},
		Filter4Surge={
			{fx='Beacons',refs={'HallBeacon1','HallBeacon2','HallBeacon3','F4WorkLamp','FloodLamp1','FloodLamp2','FloodLamp3','FloodLamp4'},seconds=240,keep=true},
			{fx='Shake',amp=.45,seconds=2.5,at=.8},
			{fx='Burst',ref='BedWater4',kind='Mist',seconds=20},
			{fx='Lights',refs={'BedGlow2_1','BedGlow2_2','BedGlow6_1','BedGlow6_2'},on=false,gap=.5,at=2.2,keep=true},
			{fx='Sound',ref='BedWater4',sound='Roar',volume=.8,speed=.6,life=9,at=.6},
			{fx='Sound',ref='HallBeacon2',sound='Alarm',volume=.4,speed=.7,life=24,at=.4},
		},
		ClearWaterTurns={
			{fx='Tint',ref='ClearWater',color=Color3.fromRGB(9,10,10),reflectance=0,seconds=5,at=1.2,keep=true},
			{fx='Burst',ref='ClearWater',kind='Mist',seconds=8,at=1},
			{fx='Sound',ref='ClearWater',sound='Gurgle',volume=.7,speed=.6,life=8,at=.8},
		},
		LightsDie={
			{fx='Lights',refs={'HB6','HB5','HB4','HB3','HB2','HB1'},on=false,gap=.7,sparks=true,keep=true},
			{fx='Lights',refs={'BedGlow5_1','BedGlow5_2','BedGlow3_1','BedGlow3_2','BedGlow1_1','BedGlow1_2'},on=false,gap=.5,at=1,keep=true},
			{fx='Shake',amp=.15,seconds=4},
		},
	},
	Sounds={
		squelch='rbxassetid://9118023324',static='rbxassetid://9117060042',
		click='rbxassetid://9118026602',lever='rbxassetid://9119630180',clunk='rbxassetid://9114533169',creak='rbxassetid://9116799448',
		crackle='rbxassetid://87751901232664',drip='rbxassetid://9120519525',heart='rbxassetid://176554627',
		torchOn='rbxassetid://9116283749',torchOff='rbxassetid://9116283546',gasp='rbxassetid://9114555843',
		motor='rbxassetid://9112889325',drone='rbxassetid://9112839813',
		-- found for this floor (Pro Sound Effects clips on the Creator Store); empty = fall back to the nearest one above
		lap='rbxassetid://9120570661',fan='rbxassetid://9114776167',fizz='rbxassetid://9119380766',
		cough='rbxassetid://9116457892',bulb='rbxassetid://9114592817',scour='rbxassetid://9125741935',
	},
})
