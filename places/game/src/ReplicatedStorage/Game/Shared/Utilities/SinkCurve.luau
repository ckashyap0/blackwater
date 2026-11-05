-- Black-water sink level, shared by the server (SlipHazards) and every client (HazardController) so
-- they always agree. Everything is a pure function of three attributes on the sink model:
-- WaterOn, WaterChangedAt (server clock) and WaterLevelAt (level 0..1 at that moment).
--  * Filling: the stream has to land first (FillDelay), then the flow builds up over FlowRamp
--    seconds and the basin fills like a real one under a steady tap: at an even pace (the same
--    amount of water every second), easing off only in the last part as the overflow slot near the
--    rim starts taking water away - it settles just under the rim and never spills.
--  * Draining: Torricelli's law - the deeper the water, the harder it pushes down the plughole -
--    so it drops quickly at first, then gently slows to a last thin film, reaching empty in
--    DrainSeconds.
local Sink={FillDelay=.55,FlowRamp=.8,FillRate=.085,Knee=.82,DrainSeconds=16,DrainRamp=.35}
local function ramped(s,r)
 -- time that has 'counted' once the flow has built up from nothing over r seconds
 if s<=0 then return 0 end
 return s-r*(1-math.exp(-s/r))
end
-- even filling up to the knee, then a smooth approach to the rim (same slope at the join)
local function knee(raw)
 local k=Sink.Knee;local w=1-k
 if raw<=k then return raw end
 return k+w*(1-math.exp(-(raw-k)/w))
end
local function unknee(l)
 local k=Sink.Knee;local w=1-k
 if l<=k then return l end
 return k-w*math.log(math.max(1e-6,1-(l-k)/w))
end
function Sink.Level(on,l0,e)
 l0=math.clamp(l0 or 0,0,1)
 if not e then return l0 end
 e=math.max(0,e)
 if on then
  local t=ramped(e-Sink.FillDelay,Sink.FlowRamp)
  local l=knee(unknee(l0)+Sink.FillRate*t)
  return l>.998 and 1 or l
 end
 local t=ramped(e,Sink.DrainRamp)
 local r=math.sqrt(l0)-t/Sink.DrainSeconds
 return r>0 and r*r or 0
end
function Sink.FromModel(m,serverNow)
 local at=m:GetAttribute('WaterChangedAt')
 return Sink.Level(m:GetAttribute('WaterOn')==true,m:GetAttribute('WaterLevelAt'),at and serverNow-at)
end
return Sink
