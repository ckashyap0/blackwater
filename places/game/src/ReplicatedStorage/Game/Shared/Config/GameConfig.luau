--!strict
-- Blueprint values; tuning is centralized here, not applied to characters yet.
local Freeze = require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({ MinPlayers = 1, MaxRunPlayers = 4, FloorOrder = {5,4,3,2,1},
	TargetRunSeconds = {1200,1500}, TransitSeconds = {8,10},
	-- (R43) 24/12: cranking and pumping report effort four times a second on top of aim and keepalives
	Network = { Burst = 24, RefillPerSecond = 12, MaxRequestId = 2147483647,
		ReadyRetrySeconds = 1, ReadyAttempts = 15, WaitForInstanceSeconds = 15 },
	DevelopmentStatusInStudio = false })
