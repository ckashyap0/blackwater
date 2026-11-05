--!nonstrict
-- Client-side shared crawl state (one table per client, written only by CrawlController).
--   state   'Standing' | 'Vent' (inside a duct: lying down and crawling)
--   camera  NumberValue 0..1, tweened by CrawlController (TweenService): how far the eye has moved
--           down and forward to the prone head. CameraController reads it every frame.
--   scripted  true while HazardController moves the body along the climb-in / climb-out path
--   exiting   true from the moment the climb-out starts until the duct is left
local camera=Instance.new('NumberValue');camera.Name='CrawlCamera';camera.Value=0
return {state='Standing',camera=camera,changedAt=0,scripted=false,exiting=false}
