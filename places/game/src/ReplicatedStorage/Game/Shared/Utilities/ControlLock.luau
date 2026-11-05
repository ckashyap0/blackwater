--!nonstrict
-- Client-side control lock state (owned and driven by InputController, read by everything else).
-- While active the local player has no input at all: no walking, jumping or turning, no game
-- actions or tools, and the camera cannot be panned. It is on from the very first frame of a new
-- character and through every cutscene (waking up, the gate shots, the lift ride and crash), and
-- it only lets go once the cutscene has fully ended AND the camera is back in your own eyes -
-- at which moment body and view are squared up to the fixed facing for that moment (FacingFor).
local Lock={active=false,reason=nil,lastReason=nil,since=0,releasedAt=0}
local function flat(v)
 if typeof(v)~='Vector3' then return nil end
 v=Vector3.new(v.X,0,v.Z)
 return v.Magnitude>.05 and v.Unit or nil
end
Lock.Flat=flat
-- The one fixed direction the player faces when a lock ends: after the lift ride it is the lift
-- doors (EHCrashFacing); otherwise it is the facing the server spawned the character with
-- (EHFacing on the character, e.g. every surface spawn faces up the road toward the gate).
function Lock.FacingFor(player,reason)
 local c=player.Character
 -- (in the lift: the doors once the crash has turned everyone to face them; before that the view
 -- simply holds wherever it was when the ride began)
 if (reason or Lock.lastReason)=='Intro' then return flat(player:GetAttribute('EHCrashFacing')) end
 return flat(c and c:GetAttribute('EHFacing'))
end
-- a level view along a direction
function Lock.LevelRotation(dir)
 return CFrame.lookAt(Vector3.zero,dir).Rotation
end
return Lock
