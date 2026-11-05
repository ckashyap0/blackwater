--!strict
-- Every saved-data store goes through here. Studio sessions use their own "StudioTest" scope, so a
-- playtest can never change a live balance, token count or leaderboard. Live servers use the default
-- scope, the same data they have always used. Studio therefore starts every account from empty.
local DataStoreService=game:GetService("DataStoreService")
local SCOPE=game:GetService("RunService"):IsStudio() and "StudioTest" or nil
local Stores={}
Stores.Scope=SCOPE
function Stores.Get(name:string):any return DataStoreService:GetDataStore(name,SCOPE) end
function Stores.GetOrdered(name:string):any return DataStoreService:GetOrderedDataStore(name,SCOPE) end
return table.freeze(Stores)
