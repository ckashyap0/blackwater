--!strict
-- LEVEL 4: MAIN CONTROL ROOM. Shared by the server floor (Level4Floor) and the client
-- (ControlRoomController / ObjectiveController). All player-facing text is plain and short.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
 KeycardItemId='BW4Keycard',KeycardSocketId='BW4CardReader',KeycardKind='Keycard',
 -- the jobs on the crew's list once the server room is open (any order, any crew member)
 Jobs={
  {id='Upload',name='Upload the security logs',room='Server Room',target='UploadTerminal',label='UPLOAD LOGS'},
  {id='Wires',name='Fix the wiring',room='Wiring Room',target='WirePanel',label='FIX WIRES'},
  {id='Breakers',name='Flip the breakers in order',room='Control Room walkway',target='BreakerHit',label='FLIP'},
  {id='Dials',name='Line up the pump dials',room='Control Room',target='DialDesk',label='SET DIALS'},
  {id='Radio',name='Tune the radio',room='Monitoring',target='RadioSet',label='TUNE RADIO'},
 },
 Text={
  Keycard='Find the keycard (check the Break Room and Monitoring)',
  KeycardIn='Find the keycard (check the %s)', -- (Nov 13) the room it turned up in this round
  KeycardCarried='Put the keycard in the Server Room door',
  KeycardTeammate='Help your teammate get the keycard to the Server Room door',
  Jobs='Do the jobs on your list (%d/%d)',
  Reboot='Restart the system: press the big button in the Core Room',
  Rebooting='Stay close to the core while it restarts (%d%%)',
  RebootAlone='Get back to the core! It stops without you (%d%%)',
  Lift='Get in the lift and go down',
 },
 RebootSeconds=28,RebootRadius=16,RebootDrain=1.5, -- % lost per second while nobody is near
 DialTolerance=7,UploadSeconds=6,
 -- RADIO CALLS (scaffolding kept for a later pass). The calls still fire on the server and the
 -- radios still squelch and murmur in the world; the on-screen subtitle box is OFF for now (owner
 -- R26: it made things worse). Flip ShowRadioSubtitles back to true to bring the UI back.
 -- (R41, owner Nov 16: subtitles back on)
 ShowRadioSubtitles=true,
 -- what comes over the radios and the PA (who: 'Marty' calm/creepy, 'Mercer' a faint warning)
 Radio={
  Arrival={who='Marty',style='calm',delay=10,text="Hello? ...This is Marty. You made it to Level Four. Good. The control room's a mess. Fix it up, then keep going down. I'll be waiting."},
  DoorOpen={who='Marty',style='calm',text="Nice work. The server room's full of old files. They should have cleared those out years ago."},
  Tuned={who='Marty',style='creepy',text="There you are. You found my channel... Keep it tuned here. It's easier when you can hear me."},
  RebootHalf={who='Marty',style='glitch',text="There it goes... Don't stop now. Stay close until it's all the way back on."},
  RebootDone={who='Marty',style='creepy',text="...Fine. Come down, then. I'm always one floor down."},
  Ambient={
   {who='Mercer',style='faint',text="...if you can hear this... don't answer him..."},
   {who='???',style='faint',text='...3:12... 3:12... 3:12...'},
   {who='Mercer',style='faint',text="...he isn't the manager. There IS no manager..."},
   {who='Marty',style='creepy',text='...I can hear you working. Keep going.'},
   {who='???',style='faint',text='(water, dripping... something breathing)'},
  },
 },
 RadioFrequencies={91.3,96.5,99.1,102.7,104.7,106.9},
 -- (R43 phase 4) breakers are pulled down (Lever job, InteractionService); pulls per breaker
 Work={Breaker=.6},
 -- the core restart cut (Config.Cinematics.Level4.CoreRestart): its length, and when the core lights come up in it
 CoreCutSeconds=6.2,CoreLightsAt=1.4,
 -- set-piece beats the floor stamps (Beat_<name>); every client plays these (SetPieceController)
 Beats={
  -- halfway through the restart the core strains
  RebootHalf={
   {fx='Shake',amp=.2,seconds=1},
   {fx='Burst',ref='CoreCap',kind='Steam',seconds=3},
   {fx='Sound',ref='CoreCap',sound='Hiss',volume=.4,speed=.9,life=3},
  },
  -- the core catches: plays under the cut
  CoreOnline={
   {fx='Shake',amp=.18,seconds=1.6,at=1.2}, -- (gentle: a shake rolls the camera inside the cut)
   {fx='Sound',ref='RebootZone',id='rbxassetid://9112889325',volume=.7,speed=.7,life=6,at=1},
   {fx='Burst',ref='CoreCap',kind='Steam',seconds=5,at=1.4},
   {fx='Sound',ref='RebootZone',sound='Burst',volume=.5,speed=.8,life=3,at=1.4},
  },
 },
})
