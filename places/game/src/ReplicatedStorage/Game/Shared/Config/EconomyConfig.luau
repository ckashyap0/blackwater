--!strict
-- Blueprint values; tuning is centralized here, not applied to characters yet.
local Freeze = require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({ DesignStatus = "Provisional", FloorRewards = {
	[5]=10, [4]=20, [3]=25, [2]=30, [1]=35 }, EscapeBonus = 40,
	PersistentStatUpgrades = false, OutfitUnlocks = false })
