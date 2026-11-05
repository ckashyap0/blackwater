--!strict
-- The one timing definition for the elevator intro (doors start opening at 44 s). The server owns the clock
-- (IntroElapsed on the cabin); clients only sample it and animate presentation from it.
-- No dialogue, captions or PA voice: the ride is just the lift, the shaft and the skip button.
--  0-7.5  eyes open slowly on the crew in their cabin slots (one heavy blink); after surface boarding
--         the clock resumes here, eyes already open
--  7.5-25.5 an ordinary ride down (18 s): steady motor, the shaft sliding past the inspection
--         opening (counterweight passes at 20)
-- 25.5-28.5 the failure, out of nowhere: three seconds of shaking that rises EXPONENTIALLY, a run
--         of ever heavier knocks, the lights stutter
-- 28.5   a heavy, sudden crash: the cabin slams down, everyone is thrown onto their backs, the lids
--         slam shut, lights die, heavy heartbeat
-- 28.5-29.5 black
-- 29.5-37 on the floor, looking up at the cabin ceiling (7.5 s): the eyes open very slowly and
--         deliberately, close briefly and open again; ear ringing, heartbeat and heavy blur.
--         While the screen is black everyone is turned to face the lift doors.
-- 37-40.5 a long, heavy head nod as you come round, then getting up (3.5 s, full body animation)
-- 44     the doors begin to open, slowly (6.75 s): every overlay and prompt is already gone
local Intro={Duration=51.5,IntroSeconds=44,DoorsAt=44,DoorSeconds=6.75,ImpactAt=28.5,BlackoutAt=28.6,BlackHold=1,RevealAt=29.5,RevealEnd=34.6,SlamSeconds=.22,
 GetUpAt=37,GetUpSeconds=3.5,GetUpEnd=40.5,
 -- the dialogue box and skip button fade out (and stop taking input) over the 1.5 s before the shake
 UiFadeSeconds=1.5,
 -- heavy mechanical sounds right before the crash: the cable mechanism groans, the brake clamps
 -- crank, then the crash itself (seconds relative to ImpactAt)
 GroanAt=-1.7,CrankAt=-.38,
 OpenCoverStart=1,OpenCoverEnd=7.5,DescentStart=3.5,CruiseAt=6,StrainAt=25.5,CounterweightPassAt=20,ShaftSpeed=3,
 -- knocks during the shake: {seconds before ImpactAt, strength}, growing exponentially
 Thuds={{2.75,.14},{2.2,.22},{1.7,.34},{1.25,.52},{.85,.78},{.48,1.5},{.16,2.2}}}
-- On-screen lines during the ride. Empty on purpose: the intro has no dialogue now.
Intro.Captions={}
-- Hook for the guide NPC (Marty) later on: lines he says during the ride, as
-- {at=seconds, line='...'}. Nothing reads or plays these yet - the intro runs exactly the same
-- whether this is empty or not, until an NPC dialogue system is wired up to it.
Intro.NpcCues={}
function Intro.AllSkipped(participants:any,votes:any):boolean
	local count=0
	for key,p in participants do
		if p.connectionState=="Connected" then
			count+=1
			if not votes[tostring(key)] then return false end
		end
	end
	return count>0
end
-- Live skip tally for the vote UI: connected crew who voted, and connected crew in total.
function Intro.SkipTally(participants:any,votes:any):(number,number)
	local voted,total=0,0
	for key,p in participants do
		if p.connectionState=="Connected" then
			total+=1
			if votes[tostring(key)] then voted+=1 end
		end
	end
	return voted,total
end
local function ease(a:number):number a=math.clamp(a,0,1);return a*a*(3-2*a) end
-- Shake intensity 0..1 over the five seconds before the crash, exponential (e^(5u)-1)/(e^5-1).
local SHAKE_CURVE=5
function Intro.Shake(t:number):number
	if t<Intro.StrainAt or t>=Intro.ImpactAt then return 0 end
	local u=(t-Intro.StrainAt)/(Intro.ImpactAt-Intro.StrainAt)
	return (math.exp(SHAKE_CURVE*u)-1)/(math.exp(SHAKE_CURVE)-1)
end
-- How stunned you are after the crash: 1 from the impact while you lie there, easing out through
-- the get-up and for 1.5 s after (blur, ringing and heartbeat all follow it).
function Intro.Dazed(t:number):number
	if t<Intro.ImpactAt then return 0 end
	if t<Intro.GetUpAt then return 1 end
	local u=(t-Intro.GetUpAt)/(Intro.GetUpEnd+1.5-Intro.GetUpAt)
	if u>=1 then return 0 end
	return 1-ease(u)^.8
end
-- 1 = eyes closed (screen covered), 0 = fully open.
-- A soft window 0..1..0 between a and b (used for the heavy, half-awake blinks).
local function bump(x:number,a:number,b:number):number
	if x<=a or x>=b then return 0 end
	return math.sin((x-a)/(b-a)*math.pi)
end
-- Waking curve for 0..1 progress: lids part slowly, sag closed once or twice, then open fully.
local function groggy(a:number,droops:{{number}},power:number):number
	a=math.clamp(a,0,1)
	local open=ease(a)^power
	local sag=0
	for _,d in droops do sag+=bump(a,d[1],d[2])*d[3] end
	return math.clamp(1-open+sag*(1-a*.6),0,1)
end
-- After the crash: open slowly (most of the way), close again briefly, then open fully.
-- The first opening is long and deliberate (3 s, barely parting at first) - the cinematic
-- reveal - and the second sweeps the lids right off the screen (see ArrivalController._Lids).
local function doubleBlink(s:number):number
	if s<3 then return 1-.82*ease(s/3)^1.6 end                 -- slow, deliberate first opening
	if s<3.45 then return .18+.82*ease((s-3)/.45) end          -- the lids drop shut
	if s<3.75 then return 1 end                                  -- a beat with them closed
	if s<5.1 then return 1-ease((s-3.75)/1.35)^.9 end           -- open again, fully
	return 0
end
function Intro.Cover(t:number):number
	if t<Intro.OpenCoverStart then return 1 end
	if t<Intro.OpenCoverEnd then return groggy((t-Intro.OpenCoverStart)/(Intro.OpenCoverEnd-Intro.OpenCoverStart),{{.36,.56,.3}},.85) end
	-- the crash slams the lids shut in SlamSeconds and holds black for the rest of BlackHold
	if t<Intro.ImpactAt then return 0 end
	if t<Intro.ImpactAt+Intro.SlamSeconds then return ((t-Intro.ImpactAt)/Intro.SlamSeconds)^.6 end
	if t<Intro.RevealAt then return 1 end
	if t<Intro.RevealEnd then return doubleBlink(t-Intro.RevealAt) end
	return 0
end
-- Normalised cabin speed: ramps in, cruises, labours under strain, stops dead at the crash.
function Intro.Speed(t:number):number
	if t<Intro.DescentStart or t>=Intro.ImpactAt then return 0 end
	if t<Intro.CruiseAt then return (t-Intro.DescentStart)/(Intro.CruiseAt-Intro.DescentStart) end
	if t<Intro.StrainAt then return 1 end
	return .8
end
-- Distance travelled (in speed-seconds) - the exact integral of Speed, so every client agrees.
function Intro.Travel(t:number):number
	local ramp=Intro.CruiseAt-Intro.DescentStart
	if t<=Intro.DescentStart then return 0 end
	if t<Intro.CruiseAt then local d=t-Intro.DescentStart;return d*d/(2*ramp) end
	local cruise=ramp/2
	if t<Intro.StrainAt then return cruise+(t-Intro.CruiseAt) end
	local strained=cruise+(Intro.StrainAt-Intro.CruiseAt)
	return strained+.8*(math.min(t,Intro.ImpactAt)-Intro.StrainAt)
end
-- Cabin lighting: steady, then stuttering harder and harder through the shake, out at the crash.
function Intro.CabinPowered(t:number):boolean
	if t>=Intro.BlackoutAt then return false end
	if t<Intro.StrainAt then return true end
	local k=Intro.Shake(t)
	local n=math.sin(t*11.3)+math.sin(t*23.7+1.3)*.6+math.sin(t*5.1)*.5
	return n<1.9-k*1.6
end
return table.freeze(Intro)
