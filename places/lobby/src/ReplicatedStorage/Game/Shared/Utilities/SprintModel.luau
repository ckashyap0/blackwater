--!nonstrict
local C=require(script.Parent.Parent.Config.MovementConfig)
local Model={}
function Model.New() return {stamina=C.MaxStamina,exhausted=false,rest=0,sprinting=false} end
function Model.Step(state,dt,wants,moving,allowed,modifier)
	assert(type(dt)=="number" and dt==dt and dt>=0 and dt<math.huge,"Invalid delta")
	assert(type(modifier)=="number" and modifier==modifier and modifier>=0 and modifier<=2,"Invalid modifier")
	local s=table.clone(state)
	if s.exhausted and s.stamina>=C.RestartThreshold then s.exhausted=false end
	local sprint=allowed and wants and moving and not s.exhausted and s.stamina>0
	if sprint then
		s.stamina=math.max(0,s.stamina-C.SprintDrainPerSecond*dt)
		s.rest=0
		if s.stamina==0 then s.exhausted=true end
	else
		local before=s.rest
		s.rest+=dt
		local regeneration=math.max(0,s.rest-C.RegenerationDelay)-math.max(0,before-C.RegenerationDelay)
		s.stamina=math.min(C.MaxStamina,s.stamina+C.RegenerationPerSecond*regeneration)
	end
	s.sprinting=sprint and not s.exhausted
	return s,(s.sprinting and C.SprintSpeed or C.WalkSpeed)*modifier
end
return table.freeze(Model)
