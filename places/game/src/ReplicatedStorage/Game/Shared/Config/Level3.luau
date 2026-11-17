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
  Fumes='Turn on the extract fan in the dosing room',
  Dosing='Shut off the dosing pumps (%d/2)',
  Inlets='Close the filter inlets (%d/6)',
  KeyOnHook='Take the bypass key off the hook',
  KeyDropped='Pick up the bypass key',
  SentAbove='Take the key down the gallery hatch',
  SentKey='Put the key in the wheel stand',
  SentWheel='Turn the bypass wheel (%d/3)',
  CrewStart='Get header pressure up at the console',
  CrewHold='Stay at the console to hold pressure (%d%%)',
  CrewAway='Pressure is dropping, get back to the console (%d%%)',
  Lift='Get back in the lift',
  NoPressure="The wheel won't move without pressure.",
  HatchBusy="Someone's already down there.",
  NeedKey='You need the key to go down.',
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
  A1={at=6,text="You took your time getting to Level Three."},
  A2={at=11,text="Somebody split a drum in there, mind the fumes."},
  B1={text="Kill both dosing pumps before that stuff gums up the pipes."},
  C1={text="Every bed has its own console on the walkway, shut all six."},
  C2={text="You don't need a light to turn a handle."},
  C3={text="Split up, you'll get the last three done quicker."},
  D1={text="Meet me by the gallery stairs at the far end."},
  D7={text="You'll do."},
  D8={text="Three turns, and it won't budge unless they keep the pressure up."},
  F1={text="It's open, get back up to the lift."},
  G1={text="Nothing goes through the filters anymore, get in the lift."},
  G2={text="See you on Level Two, I'm already there."},
 },
 Hints={
  Fumes="Fan switch is on the back wall, behind the drums.",
  Dosing="The pump switches are by the two big tanks.",
  Inlets="Check the walkway, every bed has a console.",
  BypassKey="One of you takes the key, just one.",
  BypassPressure="Somebody has to stay on the header console.",
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
