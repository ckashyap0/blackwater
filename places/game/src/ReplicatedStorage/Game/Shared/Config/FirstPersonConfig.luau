--!strict
-- First-person body framing and look-down reveal tuning. All angles are degrees
-- BELOW the horizon (0 = looking straight ahead, 90 = looking straight down).
return table.freeze({
	-- The player has no visible body in first person: looking down stays clean.
	-- Set true to restore the look-down body reveal and edge alignment below.
	ShowBodyOnLookDown=false,

	-- Body fade-in. The body stays hidden until the camera pitches past Start and
	-- is fully visible at End. Raise Start to delay the reveal further.
	BodyFadeStartDegrees=50,
	BodyFadeEndDegrees=72,
	BodyFadeResponse=16, -- exponential smoothing rate (higher = snappier)

	-- Edge alignment. As the player looks down, the eye point slides forward and
	-- slightly down so the torso settles against the lower frame edge instead of
	-- sitting in the middle of the view.
	AlignStartDegrees=25,
	AlignEndDegrees=80,
	AlignResponse=14,
	CrouchDrop=.5, -- how far the eye lowers when fully crouched (studs)
	CrouchSpring=13, -- crouch/stand speed (critically damped; higher = snappier)
	EyeHeightOffset=.45, -- base Humanoid.CameraOffset.Y (unchanged from before)
	LookDownForwardShift=.42, -- studs forward at full down-look
	LookDownDrop=.12, -- studs down at full down-look
	WallClearance=.3, -- never push the eye closer than this to a wall
})
