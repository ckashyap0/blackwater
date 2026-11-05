--!strict
-- Client-side shared stride clock (intentionally mutable, one table per client).
-- WalkEffect writes it every frame while driving the camera bob; the held-item view reads
-- it, so the camera and everything in the player's hands move on the same footfalls.
--   phase   continuous stride phase; a footfall lands at every multiple of pi (uneven spacing)
--   impact  0..1 spike that peaks at each footfall
--   moving  0..1 how much the player is walking; sprint 0..1 how much they are sprinting
--   updated os.clock() of the last write (readers fall back to their own motion if stale)
return {phase=0,impact=0,moving=0,sprint=0,step=0,updated=0}
