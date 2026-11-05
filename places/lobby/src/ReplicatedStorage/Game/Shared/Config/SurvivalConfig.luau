--!strict
-- Active Chunk 6 defaults; tuning remains provisional until playtesting.
local Freeze = require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({ DesignStatus = "Provisional", DownedSeconds = 25,
	ReviveHoldSeconds = 4, RevivesPerFloor = 1, ProtectionSeconds = 3,
	ReturnPolicy = "NextFloor", SoloSelfRevive = false })
