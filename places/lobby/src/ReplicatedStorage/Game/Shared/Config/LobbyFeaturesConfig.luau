--!strict
-- Lobby extras: the group prompt and the secret room behind the SECRET door.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	-- Blackwater Productions (roblox.com/share/g/281081000)
	GroupId=281081000,
	-- First-visit prompt is shown once per player, ever. Changing this key re-prompts everyone once.
	FirstVisitStore="EHFirstVisitV1",
	FirstVisitDelaySeconds=4,
	-- Circle pad: seconds before the same player can be prompted by it again
	CircleCooldownSeconds=12,
	SecretRoom={
		-- Owning this gamepass opens the SECRET door (for that player only).
		GamePassId=2005827746,
		-- How long the doors stay open after the player walks away (seconds)
		CloseDelaySeconds=2.5,
		-- Group members at or above this rank get in (255 = group owner only).
		MinGroupRank=255,
		-- Always allowed (PandaPenguin472).
		AllowUserIds={2403347306},
	},
})
