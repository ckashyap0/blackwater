--!nonstrict
-- ObjectiveSources (Oct 25): objectives that do not come from a floor's TaskText (e.g. the surface
-- yard's keycard step). ObjectiveController shows the first registered source that returns one, in
-- the same top task bar with the same white outlines, whenever no floor task is active.
--   ObjectiveSources.Register('Keycard',function(player) return {key=yard,text='...',targets={model}} end)
-- key: any instance that identifies the scene (a new key clears the line, like a new floor).
local S={list={}}
function S.Register(name,fn)
 for _,e in S.list do if e.name==name then e.fn=fn;return end end
 table.insert(S.list,{name=name,fn=fn})
end
function S.Current(player)
 for _,e in S.list do local ok,r=pcall(e.fn,player);if ok and r and r.key and r.text then return r end end
 return nil
end
return S
