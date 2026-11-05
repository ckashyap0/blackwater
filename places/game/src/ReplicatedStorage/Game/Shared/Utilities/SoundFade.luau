--!nonstrict
-- Never cut a sound dead: Sound:Stop() mid-waveform clicks, and in a cutscene it reads as the audio
-- breaking. Out() tweens the volume down (Sine-out, so the tail is soft) and only then stops (or
-- destroys) the sound; In() starts it silent and tweens it up. A newer fade on the same sound
-- replaces the older one, so fades can be re-triggered safely.
local TweenService=game:GetService('TweenService')
local SoundFade={}
local running=setmetatable({},{__mode='k'})
local function cancel(s)local tw=running[s];if tw then running[s]=nil;tw:Cancel()end end
-- then: 'Stop' (default), 'Pause' or 'Destroy'
function SoundFade.Out(s,seconds,thenDo)
 if not s or not s.Parent then return end
 seconds=seconds or .35;thenDo=thenDo or 'Stop'
 cancel(s)
 local function finish()
  if not s.Parent then return end
  if thenDo=='Destroy' then s:Destroy() elseif thenDo=='Pause' then s:Pause() else s:Stop() end
 end
 if not s.IsPlaying or s.Volume<=.001 or seconds<=0 then finish();return end
 local base=s:GetAttribute('FadeBaseVolume') or s.Volume
 s:SetAttribute('FadeBaseVolume',base)
 local tw=TweenService:Create(s,TweenInfo.new(seconds,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Volume=0})
 running[s]=tw
 tw.Completed:Connect(function(state)
  if running[s]~=tw then return end
  running[s]=nil
  if state==Enum.PlaybackState.Completed then finish();if s.Parent then s.Volume=base end end
 end)
 tw:Play()
 return tw
end
function SoundFade.In(s,volume,seconds)
 if not s or not s.Parent then return end
 cancel(s)
 volume=volume or s:GetAttribute('FadeBaseVolume') or s.Volume
 s:SetAttribute('FadeBaseVolume',volume)
 s.Volume=0;if not s.IsPlaying then s:Play()end
 local tw=TweenService:Create(s,TweenInfo.new(seconds or .25,Enum.EasingStyle.Sine,Enum.EasingDirection.In),{Volume=volume})
 running[s]=tw;tw:Play()
 return tw
end
return table.freeze(SoundFade)
