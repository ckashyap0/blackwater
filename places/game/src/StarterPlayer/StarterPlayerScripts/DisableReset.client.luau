local StarterGui=game:GetService("StarterGui")
for _=1,40 do
	if pcall(StarterGui.SetCore,StarterGui,"ResetButtonCallback",false) then break end
	task.wait(.25)
	
end
