--!strict
-- Client-side shared crouch state (intentionally mutable, one table per client).
--   wanted  the local player's crouch request (MovementController writes it on input)
--   amount  0..1 smoothed crouch pose (CameraController springs it every frame)
return {wanted=false,amount=0}
