# Floor 3 (Filtration) triage, R42

Played 2026-11-17 in Studio, solo, through the debug skips: arrival, dosing room, filter hall, key hook, the chamber, three wheel turns, and the grey face. I took screenshots at each stop.

Not covered: 2 to 4 players, phones, and real E-key holds. The skips jump stages, so I didn't see the fan spin up or the beds drain in real time.

Severity: **S1** breaks the floor or its main scare. **S2** players will notice and it hurts the floor. **S3** polish.

## 1. Story: why it doesn't connect to the rest

| # | Sev | Weak point | Evidence |
|---|---|---|---|
| 1.1 | S1 | The floor never says what the bypass does. The story bible gives Level 3 one job: skip the filters so dirty water reaches the town. Nothing in the game tells the player that. | Marty's last line was "The filters are out of the line." The wheel sign reads "AUTHORISED KEY HOLDERS ONLY". No paper links the bypass to the town. |
| 1.2 | S1 | The 1996 report ends with "Nobody is to restore any part of it" and nothing comes of it. Players are doing exactly what the order forbids, and no one in the game reacts. | Old incident report, closing order. |
| 1.3 | S2 | Marty's voice changes with no bridge. On Floor 4 he's chatty ("Hello? ...This is Marty."). On Floor 3 he opens with "and you're late." There's no beat where he cools. | Config.Level4 Arrival vs Config.Level3 A1. |
| 1.4 | S2 | Mercer drops out. On Floor 4 he warns "don't answer him" and "There IS no manager." Floor 3 never mentions him, so the thread just stops. | Floor 4 ambient calls. Nothing on Floor 3. |
| 1.5 | S2 | Floor 4's staff record says Marty's file is from 1962. Floor 3 makes Voss a 1996 engineer. No paper explains the two dates. | Vault Story and Lore, Floor 4 lore. |
| 1.6 | S2 | Lind's log builds up Filter 4, but in the game Filter 4 looks and works like the other five. The only sign is a knock from its bed after the fourth inlet closes, and that inlet can be any of the six. | Old filter log. Level3Floor `_Knock('BedWater4')` at InletsClosed==4. |
| 1.7 | S2 | Story rule 4 says Marty "is always already there when the doors open." On Floor 3 he only talks over the PA, and he stands 50 studs away on a walkway. | Arrival. |
| 1.8 | S3 | Hale at the gatehouse is the 1996 apprentice, but only the report says so ("D. Hale"). Nothing on the floor hints that it's the same man. | Old incident report. Hale's lines in CheckInTalk. |
| 1.9 | S3 | Two devices. Marty hands over a walkie in the story, but the Floor 3 UI says "INTERCOM · LEVEL 3". | StarterGui.RadioLine Tag. |
| 1.10 | S3 | Capitalisation of floor numbers doesn't match: "Level Four" and "Level Five" on other floors, "Level three" and "Level two" here. | Config.Level3 A1, G2. |
| 1.11 | S2 | The split-up briefing is easy to miss. Marty only steps to the key hook while nobody is watching it, and D1 sends everyone straight there. A crew that gets there early may never see him, and then the key gets taken without his lines. | In my test, Marty never appeared at the hook (marty=nil) because my camera was on that spot the whole time. |

## 2. Repetition and tasks

Every job on the floor is "walk to it and hold E." The run has 13 holds, and 11 of them are the same action on identical consoles.

| # | Sev | Weak point |
|---|---|---|
| 2.1 | S1 | Inlets: six consoles, the same 5 s hold each, in any order, on a mirrored deck. That's 30 s of holding plus walking, with no decision to make. It's the core of the floor. |
| 2.2 | S2 | Dosing pumps: two switches side by side, 1.2 s each. It's filler. |
| 2.3 | S2 | Wheel: the same 4 s hold three times. |
| 2.4 | S2 | Header pressure: the crew stands still near a console and watches a bar. Solo, it latches with one press, so the solo split-up has nothing to do upstairs. |
| 2.5 | S2 | The light rule is only a punishment. Players never use the black water's pull toward light on purpose (bait it, steer it, read by it), even though the lock-out tag tells them how it works. |
| 2.6 | S2 | Nothing asks players to read or think. Floor 4 had a breaker order puzzle and a code. Floor 3 has no puzzle, no order to work out, and nothing to compare. |
| 2.7 | S3 | The fan job sits inside fog you can't see through (screenshot: flat ochre, the fan invisible). You find the switch by its outline, not by looking. |

### Replacement ideas, all from real filter-plant work

These are ideas only and none are built. Each one swaps a hold for a decision.

1. **Isolate the dosing line, not two switches.** The coagulant runs in a stained line with three valves, each with a faded tag. Trace the orange stain from the split drum to the right valve. Pick the wrong one and the fumes surge back.
2. **The service board, then the beds.** A whiteboard in the filter office lists which beds are in service, out for backwash, or tagged "4: DO NOT TOUCH". Players close only the beds that are running, in the order the board gives (lead filter last). A wrong order kicks the head loss gauge, and every reach surges.
3. **Filter 4 by hand.** Its console is dead. Its inlet has a hand wheel down in the pipe gallery under the bed, right beside its drain. One player has to work it in the dark while another holds a lamp at the far drain as bait to pull the black water away. That puts the light rule to work and pays off Lind's log.
4. **Header pressure by the knock signal.** The header holds by pumping a hand lever in time. The sent player knocks three times on the pipe when ready, and the crew pumps on that. The imitation sends fake knocks too, so the crew has to decide whether to trust what they hear.
5. **Solo header.** The solo player wedges the lever with a tool from the gallery, which they have to find, so solo keeps the walk away from the wheel.
6. **Wheel.** Turning it is one long hold that pauses whenever pressure dips. Three identical holds become one fight.

## 3. Visuals and staging

| # | Sev | Weak point | Seen |
|---|---|---|---|
| 3.1 | S1 | The black water can't be seen. The hall is near black, the beds don't show, and the film is matte black on a dark deck. The floor's signature effect is invisible even with the torch on. It needs contrast: lit bed water with a glint, and pale wet concrete for the film to cross. | Hall screenshots, torch on and off. |
| 3.2 | S1 | Grey face: the booth window frames Marty's chest and badge, with his mouth at the top edge. Marty is 7.5 studs tall and the window sits too low. | Eye-level shot from the wheel. |
| 3.3 | S1 | Grey face: the booth bulb is a SpotLight pointing straight down from above his head (range 11, brightness 1.6). His face stays dark, and I only saw the rig after raising Ambient. | Same shot. |
| 3.4 | S2 | The wheel fills the screen and hides the booth window behind it at the moment the face appears. | Chamber shot. |
| 3.5 | S2 | In solo, Okafor's intercom line ("Voss, is that you on the wheel?") plays during the face, so the box covers the bottom of the screen. | Grey face shot. |
| 3.6 | S2 | The landing is a bright beige tiled corridor that looks like Floor 5. The ceiling lamp is a flat white square. Nothing says water plant until the dosing room. | Arrival shot. |
| 3.7 | S2 | The fumes are one flat ochre wall. There's no depth, and you can't see the room's shapes even at 20 studs. | Dosing shot with fumes. |
| 3.8 | S3 | The dosing room floor stain is too orange and too big. It covers most of the floor and reads as paint. | Dosing shot, fan on. |
| 3.9 | S3 | The dosing room tube lamp hangs at an angle in mid-air. | Same shot. |
| 3.10 | S3 | "TORCH OUT" is small red text at the very bottom. It's easy to miss, and the snuff is the floor's rule. | Key hook shot. |
| 3.11 | S3 | The objective still reads "Turn the bypass wheel (3/3)" through the whole grey face. | Grey face shot. |
| 3.12 | S3 | The six inlet consoles are identical boxes. Only their small labels differ. | Hall shot. |
| 3.13 | S3 | The crosshair sits on the "LEVEL 3 FILTRATION" sign when the doors open. | Arrival shot. |

## 4. Text

| # | Sev | Weak point |
|---|---|---|
| 4.1 | S2 | 11 of the 20 spoken lines use the same "X, so Y" shape ("Pressure's holding, so keep turning", "That's it open, so go back up"). That's the main AI tell. |
| 4.2 | S2 | Marty's second line repeats the objective word for word, and so does the dosing hint. |
| 4.3 | S2 | The papers lean on staged fragments: "Grey. Not pale. Grey.", "They did not lose his voice.", "It was empty." Every paper ends on a punchline. |
| 4.4 | S3 | Stiff phrasing: "which is the wrong wall, and has been reported", "Somebody take the key, and I mean one of you", "Clear as day", "for any reason, on anyone's instruction". |
| 4.5 | S3 | "Get back to the console! Pressure is dropping": no other objective uses an exclamation mark. |
| 4.6 | S3 | The talk at the hook: "One of you takes the key down, because the hatch holds one." reads like a manual. |

I rewrote all of the text in R42 (see the commit). The rewrite also covers 1.1 and 1.2. The report now says untreated water reached the town in 1996, the wheel sign says the bypass feeds raw water to the town main, and Marty's last line says nothing goes through the filters now. It also covers part of 1.6 and 1.8: Lind's log now mentions the knocking from under Filter 4 and names Hale.

## 5. Not checked

Multiplayer timing, phones, sound levels, the CAM 07 monitor on the crew's side, and whether the reveal line (R1) lands after the climb in real play.
