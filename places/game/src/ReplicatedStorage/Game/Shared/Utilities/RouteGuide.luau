--!nonstrict
-- Dijkstra over authored, named waypoints. Visibility is supplied by the caller.
local Route={}
function Route.Next(nodes,start,goal,visible)
 local first,last;local nearStart,nearGoal=math.huge,math.huge
 for name,node in nodes do
  local a=(node.position-start).Magnitude;local b=(node.position-goal).Magnitude
  if a<nearStart and visible(start,node.position)then first=name;nearStart=a end
  if b<nearGoal and visible(goal,node.position)then last=name;nearGoal=b end
 end
 if visible(start,goal)then return goal end
 if not first or not last then return nil end
 local distance={[first]=0};local previous={};local done={}
 while true do
  local current,best=nil,math.huge
  for name,value in distance do if not done[name] and value<best then current=name;best=value end end
  if not current then return nil end
  if current==last then break end
  done[current]=true
  for _,name in nodes[current].links do
   local nextNode=nodes[name]
   if nextNode and not done[name] then
    local cost=best+(nextNode.position-nodes[current].position).Magnitude
    if cost<(distance[name] or math.huge) then distance[name]=cost;previous[name]=current end
   end
  end
 end
 local path={last};local cursor=last
 while cursor~=first do cursor=previous[cursor];if not cursor then return nil end;table.insert(path,1,cursor)end
 -- Skip visible intermediate nodes, never cut through a wall or shut gate.
 for i=#path,1,-1 do local pos=nodes[path[i]].position;if visible(start,pos)and (pos-start).Magnitude>6 then return pos end end
 return nodes[first].position
end
return table.freeze(Route)
