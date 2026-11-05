--!strict
-- Keeps on-screen UI sized consistently across phones, tablets, and desktop monitors by
-- driving a UIScale off the camera's ViewportSize relative to a 1080p baseline, instead of
-- relying on raw pixel offsets alone (which is why the UI used to look different per device).
local Module={}
local BASELINE=Vector2.new(1920,1080)
local MIN_SCALE,MAX_SCALE=.62,1.15
local function compute(viewport)
	if viewport.X<=0 or viewport.Y<=0 then return 1 end
	local scale=math.min(viewport.X/BASELINE.X,viewport.Y/BASELINE.Y)
	-- Raw min() punishes narrow phone viewports hard; soften toward 1 so text stays
	-- legible on small screens while desktop/tablet still scale close to linearly.
	scale=scale^.72
	return math.clamp(scale,MIN_SCALE,MAX_SCALE)
end
-- Attaches (or reuses) a live-updating UIScale on `gui`. Safe to call once per ScreenGui;
-- self-cleans when the gui is destroyed, so it's safe to call from any controller's Init.
function Module.Watch(gui)
	local scale=gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent=gui
	local conn
	local function refresh()
		local camera=workspace.CurrentCamera
		if camera then scale.Scale=compute(camera.ViewportSize) end
	end
	local function hook()
		if conn then conn:Disconnect() end
		local camera=workspace.CurrentCamera
		conn=camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		refresh()
	end
	hook()
	local camConn=workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	gui.Destroying:Connect(function()
		if conn then conn:Disconnect() end
		camConn:Disconnect()
	end)
	return scale
end
-- For panels authored once at a fixed pixel size against a "designed at 1280x720" canvas,
-- that should look IDENTICAL on every device -- just uniformly bigger or smaller, never
-- reflowed. Fits BOTH dimensions (min of the width and height ratios), not just height --
-- a portrait phone is narrow but tall, so scaling off height alone would blow the UI up way
-- past what the narrow width can actually fit (this was the "way too big on iPhone" bug).
-- Clamped so extreme screens don't get illegibly tiny or absurdly huge. Use this for centered
-- dialog-style panels; use Watch() above for HUD elements that should reflow instead.
-- compact (optional): {Width=,Height=,Below=} - a tighter canvas used on touch screens and on any screen
-- shorter than Below pixels, so phones and tablets get the panel nearly full-height (big enough to tap)
-- instead of the desktop's roomy 72%.
local UIS=game:GetService("UserInputService")
function Module.WatchDesignSize(gui,designWidth,designHeight,minScale,maxScale,compact)
	local scale=gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent=gui
	local lo,hi=minScale or .5,maxScale or 1.6
	local function refresh()
		local camera=workspace.CurrentCamera
		if camera and camera.ViewportSize.X>0 and camera.ViewportSize.Y>0 then
			local vp=camera.ViewportSize
			local w,h=designWidth,designHeight
			if compact and (vp.Y<(compact.Below or 760) or (UIS.TouchEnabled and not UIS.KeyboardEnabled)) then
				w,h=compact.Width or w,compact.Height or h
			end
			scale.Scale=math.clamp(math.min(vp.X/w,vp.Y/h),lo,hi)
		end
	end
	local conn
	local function hook()
		if conn then conn:Disconnect() end
		local camera=workspace.CurrentCamera
		conn=camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		refresh()
	end
	hook()
	local camConn=workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	gui.Destroying:Connect(function()
		if conn then conn:Disconnect() end
		camConn:Disconnect()
	end)
	return scale
end
return table.freeze(Module)
