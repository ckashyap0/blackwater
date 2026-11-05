--!strict
-- One shared clock for bringing the on-screen game UI back after a cutscene (stepping out of the
-- lift after the crash). Begin() starts it; every HUD piece multiplies its own opacity by Alpha(),
-- so the controls, stamina, task line, aim dot and the flashlight's light all come up together.
local Reveal={}
local Lock=require(script.Parent:WaitForChild('ControlLock'))
local startAt:number?=nil
local length=1.6
function Reveal.Begin(seconds:number?)
	startAt=os.clock();length=seconds or 1.6
end
function Reveal.Active():boolean
	return startAt~=nil and os.clock()-startAt<length
end
-- Camera cutscenes: whenever the camera is taken away from your eyes (waking up, the gate shot -
-- the EHCinematic attribute), the whole HUD (stamina bar, flashlight, controls, task line, aim dot)
-- glides out together as the camera starts to pull back, and glides back in as it returns. Time
-- based, so it is the same at any frame rate however many HUD pieces ask in one frame.
local FADE_OUT,FADE_IN=.35,.6
local cine=1
local cineClock:number?=nil
local function cinematicAlpha():number
	local now=os.clock()
	local dt=cineClock and math.clamp(now-cineClock,0,.1) or 0
	cineClock=now
	local player=game:GetService('Players').LocalPlayer
	-- (also hidden for the whole control lock: the HUD only comes back with control, after the
	-- camera is home - see ControlLock)
	local away=(player~=nil and player:GetAttribute('EHCinematic')==true) or (Lock :: any).active==true
	if away then cine=math.max(0,cine-dt/FADE_OUT) else cine=math.min(1,cine+dt/FADE_IN) end
	return cine*cine*(3-2*cine)
end
-- 0 (hidden) .. 1 (fully shown), eased at both ends
function Reveal.Alpha():number
	local c=cinematicAlpha()
	if not startAt then return c end
	local u=math.clamp((os.clock()-startAt)/length,0,1)
	if u>=1 then startAt=nil;return c end
	return u*u*(3-2*u)*c
end
return Reveal
