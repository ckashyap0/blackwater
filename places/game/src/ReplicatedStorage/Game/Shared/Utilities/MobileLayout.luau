--!strict
-- Coordinates are relative to the safe area, not the physical display/notch.
-- Right-thumb cluster, now that there is no jump button: two staggered columns hugging the
-- bottom-right corner, four evenly spaced rows (Flashlight, Sprint, Drop, Crouch from top to
-- bottom). Neighbours are always at least 1.5 button-widths apart, so nothing overlaps.
local Layout={}
function Layout.Get(width:number,height:number):any
 local diameter=math.clamp(height*.18,52,88)
 local margin=math.max(4,diameter*.08) -- the safe-area padding already keeps us off the curved corner
 local outer=width-margin-diameter/2      -- column nearest the right edge
 local inner=outer-diameter*1.36          -- second column
 local step=diameter*.76                  -- vertical spacing between the staggered rows
 local bottom=height-margin-diameter/2
 local row1,row2,row3,row4=bottom-3*step,bottom-2*step,bottom-step,bottom
 -- The wide TAKE/FIT prompt sits low and centred; on narrow screens where it would reach the
 -- cluster it is lifted above it instead.
 local interactY=height*.69
 local interactHalf=math.min(260,width*.55)/2
 if width*.5+interactHalf>inner-diameter/2-8 then interactY=math.min(interactY,row1-diameter/2-36)end
 return {
  diameter=diameter,
  Flashlight=Vector2.new(outer,row1),
  Sprint=Vector2.new(inner,row2),
  DropObjectiveItem=Vector2.new(outer,row3),
  Crouch=Vector2.new(inner,row4),
  Interact=Vector2.new(width*.5,interactY),
  Ping=Vector2.new(width*.5,diameter*.6+8),
  -- spectating has only these two, so they reuse the bottom of the thumb cluster
  SpectateNext=Vector2.new(outer,row3),
  SpectatePrevious=Vector2.new(inner,row4),
 }
end
return table.freeze(Layout)
