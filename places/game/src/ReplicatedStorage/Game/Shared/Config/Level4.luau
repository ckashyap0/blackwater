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
 ShowRadioSubtitles=false,
 -- what comes over the radios and the PA (who: 'Marty' calm/creepy, 'Mercer' a faint warning)
 Radio={
  Arrival={who='Marty',style='calm',delay=10,text="Hello? ...This is Marty. You made it to Level Four. Good. The control room's a mess. Fix it up, then keep going down. I'll be waiting."},
  DoorOpen={who='Marty',style='calm',text="Nice work. Oh, and don't read anything in the server room, okay? Old files. Mostly lies."},
  Tuned={who='Marty',style='creepy',text="There you are. You found my channel... You trust me, right? Everybody trusts Marty."},
  RebootHalf={who='Marty',style='glitch',text="Why are you turning it back ON? ...Leave it dark. It's nicer in the dark."},
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
})
