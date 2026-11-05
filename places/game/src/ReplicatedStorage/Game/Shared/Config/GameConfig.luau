--!strict
-- Blueprint values; tuning is centralized here, not applied to characters yet.
local Freeze = require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({ MinPlayers = 1, MaxRunPlayers = 4, FloorOrder = {5,4,3,2,1},
	TargetRunSeconds = {1200,1500}, TransitSeconds = {8,10},
	Network = { Burst = 16, RefillPerSecond = 8, MaxRequestId = 2147483647,
		ReadyRetrySeconds = 1, ReadyAttempts = 15, WaitForInstanceSeconds = 15 },
	DevelopmentStatusInStudio = false })
