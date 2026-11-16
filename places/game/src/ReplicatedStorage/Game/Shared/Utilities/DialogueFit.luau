--!nonstrict
-- DialogueFit (Nov 13, Ryan: 'dialogue boxes are being cut off - make sure they aren't').
-- Sizes a talk box to its line BEFORE it shows, exactly, on any screen: measures the full line with
-- TextService at the box's real width, grows the box upward (never taller than MAX_SHARE of the safe
-- screen height), then steps the text size down (to MIN_TS), and as a last resort turns on TextScaled -
-- so a line can never run past the bottom or side of its box on a phone, tablet, PC or console.
-- Fit(box, line, text, baseH, baseTS, chrome): chrome = box height that is not the line itself
-- (padding + speaker row). Returns the token; a newer call cancels an older one still measuring.
local TextService = game:GetService('TextService')
local M = {}
local MIN_TS, MAX_SHARE = 12, .42
local tokens = setmetatable({}, {__mode = 'k'})
local function scaleOf(box)
	local s = 1
	local a = box
	while a and a:IsA('GuiBase2d') do
		local u = a:FindFirstChildOfClass('UIScale'); if u then s *= u.Scale end
		a = a.Parent
	end
	return math.max(s, .05)
end
local function measure(line, text, size, width)
	local p = Instance.new('GetTextBoundsParams')
	p.Text = text; p.Font = line.FontFace; p.Size = size; p.Width = width; p.RichText = line.RichText
	local ok, v = pcall(TextService.GetTextBoundsAsync, TextService, p)
	return ok and v or nil
end
function M.Fit(box, line, text, baseH, baseTS, chrome)
	local tok = (tokens[box] or 0) + 1; tokens[box] = tok
	line.TextScaled = false; line.TextSize = baseTS
	box.Size = UDim2.new(box.Size.X.Scale, box.Size.X.Offset, 0, baseH)
	task.wait() -- one layout pass so AbsoluteSize is the real width
	if tokens[box] ~= tok then return end
	local s = scaleOf(box)
	local width = math.max(40, line.AbsoluteSize.X / s - 4)
	local gui = box:FindFirstAncestorWhichIsA('LayerCollector')
	local screenH = (gui and gui.AbsoluteSize.Y > 10) and gui.AbsoluteSize.Y or (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 720)
	local maxH = math.max(baseH, math.floor(screenH * MAX_SHARE / s))
	local cap = box:FindFirstChildOfClass('UISizeConstraint'); if cap then maxH = math.min(maxH, cap.MaxSize.Y) end
	local tsc = line:FindFirstChildOfClass('UITextSizeConstraint')
	local minTS = tsc and math.max(MIN_TS, tsc.MinTextSize) or MIN_TS
	local size = tsc and math.min(baseTS, tsc.MaxTextSize) or baseTS
	while size >= minTS do
		local b = measure(line, text, size, width)
		if tokens[box] ~= tok then return end
		if not b then break end
		local need = math.ceil(b.Y + chrome + 6)
		if need <= maxH then
			line.TextSize = size
			box.Size = UDim2.new(box.Size.X.Scale, box.Size.X.Offset, 0, math.max(baseH, need))
			return
		end
		size -= 2
	end
	-- still too long (or measuring failed): fill the tallest allowed box and let the engine scale it
	box.Size = UDim2.new(box.Size.X.Scale, box.Size.X.Offset, 0, maxH)
	line.TextScaled = true
end
return M
