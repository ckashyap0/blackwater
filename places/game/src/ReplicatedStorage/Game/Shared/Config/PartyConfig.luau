--!strict
-- Active party/admission defaults.
local Freeze = require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({ MinCapacity = 1, MaxCapacity = 4, DefaultCapacity = 4,
	AccessModes = {"Public","FriendsOfHost"}, ArrivalTimeoutSeconds = 45,
	AutoStartWhenFull = false })
