# R43: Make BlackWater active (game systems + Floor 3 rebuild)

## Context
The owner played Floor 3 and called the whole game passive: you walk to boxes and hold E. They want:
- a storyline that is happening around you while you play;
- short cutscenes between moments;
- new kinds of tasks;
- visuals people stop and stare at.

Their answers (2026-11-17):
- The rising black water threat is in.
- Cutscenes are a mix: 4-5 short camera cuts, otherwise the player keeps control.
- Keep the Floor 3 rooms and redo everything else.
- The town only sees the black water at the end (Floor 1), so Floor 3 shows its consequence inside the plant.
- Overhaul general mechanics where needed, not just Floor 3.

Every system below is built for the whole game. Floor 3 is where it ships first. Floors 5 and 4 get it in phase 4.

## Phase 1: shared systems

1. **Cinematic director**
   - New client module `Utilities/Cinematic.luau`. It plays a shot list from config: a camera rig from Refs, then a path of points, duration, ease, shake, fades and an optional letterbox.
   - The server fires a shot by stamping `CinematicAt` and `CinematicId` on the floor. Every client plays the shot in sync and blocks movement while it runs.
   - Built from the existing GateCut pattern: black fade, `RequestStreamAroundAsync`, `EHCinematic`, server time.
   - Config: `Config.Cinematics` (floor -> shots).
   - Reuses `GateCut.luau`, `ScreenFade.luau`, `ControlLock.luau` and `HudReveal` (which already hides the HUD on `EHCinematic`).
   - Later, `GateCut` becomes a thin wrapper over this.
2. **Beat timeline**
   - New server `Floors/BeatRunner.luau`. A floor lists beats (`when = stage/progress/time/zone entered`, `do = event`). Example events: light cascade, pipe burst, alarm, knock, Marty move, cinematic, water stage.
   - A matching client `Controllers/BeatController.luau` draws the beats from replicated `Beat<Name>At` stamps.
   - This replaces the hand-written timers in Level3Floor, so the next floors get scripted events for free.
3. **New interaction verbs**
   - `InteractionService` defs get a `mode` field:
     - `Hold`: today's behaviour.
     - `Crank`: progress only while the player keeps turning, by mouse drag, stick or touch circle. The client sends rate-limited ticks and the server caps speed.
     - `Pump`: tap in rhythm. Taps inside the beat window count.
     - `Lever`: pull down and hold past a notch.
     - `Sync`: N players must hold linked targets within 0.6 s of each other.
   - `InteractionController` shows a per-mode prompt.
   - A first-person hand rig grips wheels and levers, generalised from the VentScrewController hand. A new `Utilities/HandRig.luau` holds the poses.
   - Server checks stay in `InteractionService._Validate`.
4. **Rising water plus push-back**
   - New server `Floors/RisingWater.luau` and client presentation. It works by zones: a server-owned level per zone that rises through stages. Lamps under the surface die, and the stamina drain and speed modifier reuse `CharacterService.DrainStamina` and `SetSpeedModifier`.
   - If the water reaches the fail line, the push-back runs: black fade, the crew moves to a checkpoint anchor (new FloorRefs `Checkpoint<n>`), the water drops back one stage, and a Marty line plays.
   - Nobody is downed and nothing catches anyone.
5. **Visual tech**
   - Water surface module: an animated textured plane with a Blender normal and foam set, scrolling UVs via Texture offset.
   - Light shafts: Beam god rays.
   - A particle kit: steam, spray, air-scour boil, gas plume, sparks.
   - Emergency beacon cascades.
   - Camera shake through `CameraController`.
   - All tiered through `MobilePerf`.
   - Textures from Blender only: new `bw3_water.py` in the vault Art Pipeline, uploaded as one batch.

## Phase 2: Floor 3 rebuilt on top (same rooms)

| Stage | What happens | Verb | Wow moment |
|---|---|---|---|
| Arrival | **Cut 1 (5 s):** the doors open and the camera pushes out over six lit beds. Filter 4 is black and still. Marty is already on the far walkway (story rule 4). | none | Pale green bed glow under sodium lamps, one bed that reflects nothing |
| Dosing | Drum 9 splits as you walk in. Hiss, a gas plume rolls across the floor, amber beacons spin. One player cranks the isolation valve shut while another pulls the fan starter lever. | Crank + Lever | Fan spins up and pulls the plume out through a shaft of light |
| Beds | A service board says which beds are running and the order to close them, lead filter last. Each closed bed air-scours: the surface erupts white and drains to show the media. A wrong order makes every bed surge. | Read + Hold | Six boiling beds lighting the hall |
| Filter 4 | **Cut 2 (4 s):** Filter 4 lifts over its weir in a smooth black sheet. Lamps on that side drown one by one. The rising water starts. Its console is dead, so the crew closes its hand wheel in the gallery underneath. One player baits the water with a lamp at the far drain while another cranks in the dark. Too slow and the push-back runs. | Crank + bait | Black water swallowing lights |
| Bypass | Key, hatch, split-up as now. The header holds by pumping in time with the knock signal, and the imitation sends fake knocks. The wheel is one long crank that stalls when pressure dips. The grey face gets fixed framing (window raised to his eye line) and lighting (bulb aimed at his face, a warm fill from the front). | Pump + Crank | The grey face, now seen properly |
| Payoff | **Cut 3 (6 s):** the camera rides the clear-water channel. Blue water darkens to black as the bypass flow arrives. The mimic panel lights up: "CLEAR WATER TANK -> TOWN MAIN: VALVE SHUT (LEVEL 1)". This shows the consequence inside the plant and sets up the ending. | none | Clean water turning black |
| Escape | The lamps fail in a cascade from the far end toward the lift, and the darkness snuffs flashlights. Get to the lift. **Cut 4 (3 s):** doors closing, Marty at the rail as the lights die behind him. Roof knocks on the ride. | Move | Darkness chasing you to the lift |

- **Files:** rewrite `Floors/Level3Floor.luau` on BeatRunner, RisingWater and the new verbs. Update `Config.Level3`, `Controllers/FiltrationController.luau` and `Utilities/MartyGrey.luau` (framing and light).
- **New authoring in `BlackwaterAuthoring.Level3`:** service board, Filter 4 hand wheel in the gallery, clear-water channel and mimic panel, checkpoints, camera rigs. Keep the room shells.
- **Text:** every new line goes through the humanizer skill.

## Phase 3: sound and polish
- Gas hiss, alarm, air-scour roar, flood rumble and the fan. These are Creator Store audio, and the empty Sounds entries are filled.
- A by-eye Play pass with the RenderStepped camera trick.

## Phase 4: Floors 5 and 4 adopt the systems
- Swap their hold-only jobs for the fitting verbs: Floor 5 valve -> Crank, Floor 4 breakers -> Lever.
- Add 1-2 cinematic cuts each, for example the Floor 4 core restart.
- Move GateCut onto Cinematic.
- Models stay untouched.

## Verification
- **Dev checks:** new ones for each system (verb validation and rate caps, RisingWater stages and push-back, BeatRunner ordering, Cinematic config refs), plus Level3Checks rewritten for the new flow. Run with `RunDevChecks`. The current baseline is 192/202, and those 10 failures are older ones, not ours.
- **Playtest:** ElevatorDebug skip to Floor 3. New `L3:` debug commands for each stage. Screenshots of every wow moment and cut with the forced Scriptable camera, at runtime brightness.
- **Not testable here:** 2-4 players (Studio's multi-client test needs the owner) and phones (check the MobilePerf tiers by attribute).
- **Git:** commit per phase (R43a to R43d) and checksum-sync Studio into git before each push. The owner publishes both places.
