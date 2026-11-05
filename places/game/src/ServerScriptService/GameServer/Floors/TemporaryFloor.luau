--!nonstrict
-- Behaviour for the authored service floors (Level4..Level1): one objective panel per floor.
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local Floor={};Floor.__index=Floor
function Floor.new(model,number)return setmetatable({Model=model,Number=number,_state="Inactive",_stopped=false},Floor)end
function Floor:Prepare(context)
	assert(not self._context,"Already prepared");self._context=context
	local panel=assert(Refs.Find(self.Model,"ObjectivePanel"),"Missing ObjectivePanel")
	context.RegisterInteraction({interactionId="TemporaryObjective",target=panel,interactionType="Panel",holdDuration=1,
		label=self.Number==1 and "Use the escape panel" or "Turn on the power panel",
		allowedRunPhases=self.Number==1 and {FinaleActive=true} or {FloorActive=true},
		canUse=function()return self._state=="Active" and not context.IsSuspended(),"Unavailable"end,
		complete=function(player)
			if self._state~="Active" then return false,"Inactive" end
			local ok,reason
			if self.Number==1 then ok,reason=context.Escape(player)else ok,reason=context.CompleteObjective()end
			if ok then self._state="Completed";panel.Color=Color3.fromRGB(104,152,112)end
			return ok,reason
		end})
end
function Floor:Activate()assert(self._context and not self._stopped);self._state="Active"end
function Floor:GetObjectiveSnapshot()return {status=self._state}end
function Floor:OnParticipantStateChanged(snapshot)self._participants=snapshot.participants end
function Floor:Stop()self._stopped=true;self._state="Stopped"end
function Floor:Destroy()self:Stop();if self.Model then self.Model:Destroy()end end
return table.freeze(Floor)
