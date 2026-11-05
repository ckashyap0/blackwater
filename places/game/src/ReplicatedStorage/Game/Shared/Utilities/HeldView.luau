--!nonstrict
-- Client-side bridge between the input that drops an item (InteractionController) and the
-- first-person hand view that shows it (EquipmentController).
--   BeginDrop()  hides the held item this frame, starts the local fall from exactly where it was
--                in the hand, and returns that CFrame (or nil if nothing is visibly held).
return {BeginDrop=nil}
