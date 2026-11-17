--!strict
-- LEVEL 3: FILTRATION. Shared by the server floor (Level3Floor, BlackWaterReach) and the client
-- (FiltrationController, RadioLine, ObjectiveController). Design guide: vault Floors/Floor 3.md.
-- The crew shuts off the dosing pumps, closes the six filter inlets and opens the bypass, so raw
-- water runs past the filters. Black water creeps along the floor drains toward lit flashlights.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
 Stages={'Fumes','Dosing','Inlets','Bypass','Lift'},
 KeyItemId='BW3BypassKey',KeySocketId='BW3WheelStand',KeyKind='BypassKey',
 Text={
  Fumes='Start the extract fan in the dosing room',
  Dosing='Shut off the dosing pumps (%d/2)',
  Inlets='Close the filter inlets (%d/6)',
  KeyOnHook='Take the bypass key from the hook',
  KeyDropped='Pick up the bypass key',
  SentAbove='Take the key down the hatch in the pipe gallery',
  SentKey='Put the key in the wheel stand',
  SentWheel='Turn the bypass wheel (%d/3)',
  CrewStart='Start header pressure at the console',
  CrewHold='Hold header pressure at the console (%d%%)',
  CrewAway='Get back to the console! Pressure is dropping (%d%%)',
  Lift='Get in the lift and go down',
  NoPressure='No pressure. The wheel will not move.',
  HatchBusy='The hatch holds one.',
  NeedKey='Only the key holder goes down.',
 },
 Holds={Fan=2.5,Pump=1.2,Inlet=5,Header=1,HeaderSolo=3,Wheel=4,Hatch=1,Key=.5,Socket=.8},
 -- THE LIGHT RULE (BlackWaterReach). Distances in studs, speeds in studs per second.
 Light={
  Step=.2,SenseHead=45,SensePath=30,Creep=3,Linger=2,Retreat=1.5,
  Snuff=6,SnuffHeight=6,SnuffSeconds=.8,ClearDistance=14,ClearSeconds=6,
  FilmStamina=15,FilmHaze=.6,FilmSpeed=.8,
  InletRest=12,LiftRestBed=30,LiftRestGallery=40,
  RippleParts=12,RipplePartsTouch=6,RippleRange=40,RippleRangeTouch=20,
 },
 Fumes={Stamina=18,Haze=.8,HazeEmpty=1,RiseSeconds=1.5,ClearSeconds=3,EmptySpeed=.7,FanSpinUp=3,ThinSeconds=12,CoughMin=3,CoughMax=5},
 Header={FillPerSecond=10,DrainPerSecond=4,Radius=14,WheelNeeds=60},
 Wheel={Turns=3},
 Bed={DropStuds=2,DropSeconds=8},
 Ladder={Seconds=1.6},
 -- seconds after the last wheel turn (BypassOpenAt); GreyFaceAt = BypassOpenAt + GreyDelay
 Grey={Delay=2.7,Hold=4,LineAt=3,Dark=.3,Empty=1.2,End=8,EyesAt=3.2,CompleteAfter=45},
 Knock={Gap=.38,Pause=1.1,Sound='rbxassetid://9116642648',Speed=.8,Volume=.5},
 HintSeconds=90,
 -- MARTY. One sentence, 90 characters or less. He names the next job, tells the truth about it
 -- and warns about nothing. No names and no "rookies" on this floor.
 Marty={
  A1={at=6,text="Level three, filtration, and you're late."},
  A2={at=11,text="Dosing room, first door on the left: start the extract fan."},
  B1={text="Now shut off both dosing pumps, or the bypass line gums up."},
  C1={text="Six filter beds, six consoles: close every inlet."},
  C2={text="You don't need a light to turn a handle."},
  C3={text="Three left, and you work faster apart."},
  D1={text="Come to the gallery stairs at the south end of the hall."},
  D7={text="Good, you'll do."},
  D8={text="Three full turns, and it only moves while they hold pressure."},
  F1={text="That's it open, so go back up to the lift."},
  G1={text="The filters are out of the line, so get in the lift."},
  G2={text="Level two, and I'm already there."},
 },
 Hints={
  Fumes="Extract fan, dosing room, far wall.",
  Dosing="Two pump switches, beside the day tanks.",
  Inlets="The consoles are on the centre deck, one for each bed.",
  BypassKey="Somebody take the key, and I mean one of you.",
  BypassPressure="Hold the header console, or the wheel stays where it is.",
  Lift="The lift is back the way you came.",
 },
 -- THE IMITATION. {name} is filled in by the server. Each line plays once per floor.
 Radio={
  S1={text="Turn your light on so we can see you on the camera."},
  S2={text="Pressure's holding, so keep turning."},
  S3={text="We're coming down to you, so stay by the wheel."},
  S4={text="Who were you talking to?"},
  K1={text="I'm at the wheel, so hold it steady."},
  K2={text="It's open, so you can let go now."},
  K3={text="I can hear you all at the hatch."},
  R1={text="I'm still at the wheel, so don't leave me down here."},
  -- solo: the player's own name, then the 1996 crew
  SoloS1={text="Turn your light on so I can see you."},
  SoloS2={who='T. Okafor',text="Voss, is that you on the wheel?"},
  SoloS3={who='R. Lind',text="He's not answering, so pull him out."},
 },
 Stands={A='MartyMarker_L3CrossWalk',B='MartyMarker_L3KeyHook',C='MartyMarker_L3Booth'},
 Sounds={
  squelch='rbxassetid://9118023324',static='rbxassetid://9117060042',
  click='rbxassetid://9118026602',lever='rbxassetid://9119630180',clunk='rbxassetid://9114533169',creak='rbxassetid://9116799448',
  crackle='rbxassetid://87751901232664',drip='rbxassetid://9120519525',heart='rbxassetid://176554627',
  torchOn='rbxassetid://9116283749',torchOff='rbxassetid://9116283546',gasp='rbxassetid://9114555843',
  motor='rbxassetid://9112889325',drone='rbxassetid://9112839813',
  -- found for this floor (free Creator Store audio); empty = fall back to the nearest existing sound
  lap='',fan='',fizz='',cough='',bulb='',
 },
})
