--!nonstrict
local Policy={}
function Policy.Eligible(observerId,runId,candidateId,candidateRun,life,connected,hasCharacter)
	return runId~=nil and runId~=false and observerId~=candidateId and runId==candidateRun
		and life=="Alive" and connected and hasCharacter
end
function Policy.Select(ids,current,direction)
	if #ids==0 then return nil end
	local index=table.find(ids,current)
	if not index then return ids[1] end
	return ids[((index-1+(direction or 0))%#ids)+1]
end
return table.freeze(Policy)
