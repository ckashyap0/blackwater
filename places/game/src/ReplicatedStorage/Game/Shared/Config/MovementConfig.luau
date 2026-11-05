--!strict
-- Initial tuning defaults used by the server-owned character controller.
local Freeze = require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({ WalkSpeed = 12, SprintSpeed = 18, CrouchSpeed = 6, VentCrawlSpeed = 5, MaxStamina = 100,
	SprintDrainPerSecond = 20, RegenerationDelay = 1.5, RegenerationPerSecond = 12.5,
	RestartThreshold = 20 })
