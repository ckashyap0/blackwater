--!strict
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
 IntroSeconds=44,SwitchHoldSeconds=.65,InputCooldown=.3,MonsterEnabled=false,
 SwitchIds={'A','B','C'},CircuitStage=3,
 TrippedMessage='POWER LOST',RestoredMessage='POWER ON',
 FaultMessage="LIFT CAN'T GO UP\nIT CAN STILL GO DOWN\nESCAPE POD: LEVEL 1",
 -- the air tank target is rolled every round from these (PSI); %d in the task text is the target
 TankTargets={20,30,40,50},
 -- (R43 phase 4) job effort for the new verbs (InteractionService): turns for the valve, pulls for the levers
 Work={Valve=2,Switch=1,Gate=1.5},
 -- set-piece beats the floor stamps (Beat_<name>); every client plays these (SetPieceController)
 Beats={
  -- the line bleeds off through the valve body as it seats
  ValveShut={
   {fx='Burst',ref='IsolationValve',kind='Steam',seconds=4},
   {fx='Sound',ref='IsolationValve',sound='Hiss',volume=.45,speed=.7,life=4},
   {fx='Shake',amp=.15,seconds=.6,ref='IsolationValve'},
  },
  -- the third breaker: the lift circuits kick in
  PowerBack={
   {fx='Burst',refs={'SwitchA','SwitchB','SwitchC'},kind='Sparks',seconds=.3},
   {fx='Shake',amp=.2,seconds=.8},
   {fx='Sound',ref='SwitchB',id='rbxassetid://9112889325',volume=.5,speed=.8,life=4},
  },
  -- the shaft gate grinds up into its header (GateCut shows it; this is what you feel)
  GateOpen={
   {fx='Shake',amp=.25,seconds=2.4,at=.2},
   {fx='Sound',ref='ReturnGate',sound='Burst',volume=.6,speed=.6,life=3,at=2.2},
   {fx='Burst',ref='ReturnGate',kind='Mist',seconds=3,at=2.2},
  },
 },
 LinkItemId='BW5ReplacementLink',LinkSocketId='BW5DisconnectSocket',LinkKind='SupplyLink',
 -- The mop side task is retired: the job on this level is the lift. Spills are still a slip
 -- hazard for anyone who sprints through them, but there are no mops to take and no spill counter.
 -- (Set MopSideTask=true to bring the old optional task back.)
 MopSideTask=false,
 SideQuest={
  Id='Protocol04',
  Title='Protocol 04: Industrial Effluent Abatement',
  Description='Sanitize volatile chemical runoff, heavy lubricant residue, and organic bio-matter accumulations across primary deck sectors. Unattended fluid degradation corrodes lower-deck structural framing and fouls auxiliary drainage sumps. Note: Completion does not alter shift length, yield additional credits, or guarantee evacuation clearance.',
  Counter='Effluent Cleared: %d/%d',
  Equipment='Mops: Janitor Closet rack',
  Closed='Protocol 04 closed. Effluent Cleared: %d/%d',
  -- the HUD line (short, earlier wording); the long text above is only on the paper and terminals
  Short='Optional: grab a mop from the Janitor Closet (%d spill%s)',
  ShortWithMop='Mop up the spills (%d left)',
  ShortDone='All spills cleaned up',
 },
 -- Every job on this level is part of getting the broken lift running again.
 Tasks={
  {text='Stop the leak flooding the lift shaft: close the valve',target='IsolationValve'},
  {text='Find a spare fuse for the lift control box',target='ReplacementLink'},
  {text='Turn on the 3 lift power breakers',target='SwitchA'},
  {text="Charge the lift's air brakes to %d PSI",target='TankLock'},
  {text='Open the shaft gate from the control room',target='GateRelease'},
  {text='Get in the lift and test it: go down',target='LiftTestGuide'},
 },
})
