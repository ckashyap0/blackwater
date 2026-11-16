# Prompt for Fable 5.2 (Claude Code): Floor 3 design guide

Copy everything below the line into a new Claude Code session opened in `C:\Users\chinm\blackwater`, with the model set to Fable 5.2.

---

You are writing the design guide ("manifesto") for **Floor 3 of BlackWater**, a Roblox co-op horror game for 1 to 4 players, aged 13+. This round is **design only**. Do not build, edit or publish anything in Studio, and do not change any game scripts. Read-only Studio MCP calls are fine. The guide must be detailed enough that a later session can build the floor from it without asking you anything.

## 1. Read first (in this order)

1. `CLAUDE.md` in this repo. It is the project rulebook and wins on any conflict.
2. The story bible: `C:\Users\chinm\Downloads\BlackWater — Story Bible & Guide Script.md`. This is the owner's full story. Read all of it, especially "The presence and black water", "Story arc by level", "Notes and papers" and "Endings".
3. The vault at `C:\Users\chinm\OneDrive\Documents\Blackwater Vault`:
   - `00 Home.md`
   - `Project/Story and Lore.md`, `Project/Monster - The Normal Man.md`, `Project/Owner Taste.md`, `Project/Working Rules.md`, `Project/Run Flow.md`, `Project/Consolidation Conflicts.md`
   - `Floors/Floor 5.md`, `Floors/Floor 4.md`, `Floors/Floors 3-1.md`
   - `Gotchas.md`
   - `Assets/Models/BW_Marty_M4_README.md`
4. The game code, to see how a finished floor is put together. Read them; do not copy them blindly.
   - Server: `places/game/src/ServerScriptService/GameServer/Floors/Level4Floor.luau`, `Level5Floor.luau`, `SlipHazards.luau`, and `Services/ElevatorService.luau` (look for `EncounterId` routing and the floor order).
   - Shared: `places/game/src/ReplicatedStorage/Game/Shared/Config/Level4.luau` and `Level5.luau` (tasks, objective text, radio lines), `Utilities/MartyPeek.luau` and `Utilities/MartyTalk.luau`, `Contracts/FloorContract`.
   - Client: `Controllers/ControlRoomController.luau`, `HazardController.luau`, `LoreController.luau`, `ObjectiveController.luau`.
5. Optional, read-only: `list_roblox_studios`, then look at the Game place (96605018559143). Check `Workspace.BlackwaterAuthoring.Level3` (currently grey placeholder parts), plus Level4 and Level5 for scale, ceiling heights, lighting and prop density. Never touch `BW28_*` or `BlackWater_Floor4_Props`.

## 2. Decisions already made by the owner (do not reopen these)

- **Floor order stays as the bible has it:** 5 Maintenance, 4 Intake, 3 **Filtration**, 2 Chemicals, 1 Main valve. This follows how a real treatment plant works: intake, filter, chemical treatment, distribution.
- **Floor 3 also gets a hazardous-substance feel.** Real filtration uses coagulant chemicals (for example alum or ferric chloride) to clump dirt before the filters. So Floor 3 can have a dosing room, labelled chemical drums, warning signs, spills and fumes. Floor 2 stays the big chemical-treatment floor (storage tanks, the lab, sample BW-96), so do not use up Floor 2's material here.
- **Story job on Floor 3:** the crew skips or bypasses the filters, so dirty water gets through. As on every floor, the repair quietly helps the presence.
- **Black water rule for Floor 3: light.** It creeps toward flashlights and puts them out. Players choose between seeing and hiding. There is no chase yet; the first chase is on Floor 2.
- **Marty on Floor 3 is cold.** He sends one player off alone to a valve. His face is briefly visible: **grey, wet at the mouth.** This is the floor where the grey face fully lands. The Floor 5 peek (R40) already shows a smirk and brief grey flicks, so Floor 3 must go clearly further, not repeat it.
- **Key beat: the split-up.** While one player is alone, the radio imitates the rest of the crew, speaking lines under real players' names that they never said.
- **Key paper:** the 1996 incident report (Water Authority): the pumps restarted with nobody at the panel, Voss is listed as missing, and survivors said "he was still talking to us on the radio." Like every note, it must set up the beat that follows it.
- **The year is November 1996 everywhere.** Some Floor 4 records say 1962; flag those for correction rather than following them.
- **Marty's rules from the bible still hold:**
  - He never lies about how to do a job.
  - He never warns about danger.
  - He is never seen moving.
  - He is never in the lift with you.
  - He does not touch the water before Floor 2.
  - He hurts no one before Floor 1.
- **His current look** is the M4 model: light-blue short-sleeve work shirt, MARTY patch, lanyard and badge, khaki trousers. It is not the bible's hi-vis vest and hard hat.
- **Taste (from CLAUDE.md):** grounded, dim, worn and quietly uncanny. Practical lights only. Props sit on the ground. Pipes connect, with flange caps. Clean, centred HUD text with short Quart fades. Short objectives, darker lore, light gore.

## 3. Questions

Before writing, ask the owner at most 4 multiple-choice questions, with the recommended option first, and only about real design choices the sources leave open. Likely candidates:
- what a **solo** player gets instead of the split-up
- whether flashlights can be relit
- roughly how long the floor should take
- how the hazardous-substance mechanic works (for example, fumes that drain stamina, or a spill you have to route around)

If the owner is away, take the recommended options and list them as assumptions at the top of the guide.

## 4. What the guide must contain

Write it to the vault as `Floors/Floor 3.md` (frontmatter `title`, `tags: [blackwater, floor, design]`, `status: design`) and update `Floors/Floors 3-1.md` to link to it. Sections:

1. **One-paragraph pitch** and the floor's single emotional goal: what players should feel walking out.
2. **Where it sits in the story.** What players know arriving from Floor 4, what they learn here, and what they carry to Floor 2. Check against the bible table and say plainly where the guide differs and why.
3. **Layout.** A room-by-room plan for the filtration hall with sizes in studs and ceiling heights, matching the Floor 4/5 scale you measured:
   - arrival from the lift
   - filter beds or galleries
   - coagulant dosing room
   - pipe gallery
   - the isolated valve room for the split-up
   - the return to the lift
   Add a simple ASCII map. Mark sightlines for scares and where Marty can stand unseen.
4. **Tasks, in order.** For each: its objective text (short, like Floors 4/5), how it works in co-op and solo, what it changes in the world, the time budget, and which existing system it reuses (MechanismController, HazardController, FixtureController, SlipHazards, and so on).
5. **The light rule.** Exact behaviour:
   - how close black water must get to a flashlight to put it out, and how fast
   - how it is shown: no shine in the flashlight, ripples with nothing touching it
   - counterplay
   - how it reads in multiplayer
   - performance limits on phones (see `Utilities/MobilePerf`)
6. **Hazardous substances.** What exists, how it looks, how it hurts (stamina or blur, no gore), and warning signage text. Keep it clearly below Floor 2's chemical material.
7. **Marty's beats.** A script table like the bible's Level 5 table: id, trigger (using attributes the game can track), where he stands, and the line. Each line one sentence, 90 characters or less. Radio lines marked (R).
8. **The split-up and radio imitation.** Exactly how one player is chosen and isolated, which lines the fake radio plays and under whose names, when the trick is revealed, and the solo fallback. It must work for 2, 3 and 4 players without anyone getting stuck.
9. **The grey-face moment.** Placement, staging, timing, lighting and sound. It must clearly go further than the Floor 5 peek (`Utilities/MartyPeek.luau`), and it must be explained by a note the players can find just before it.
10. **Papers and lore.** Each paper's title, author, full text (preview line plus READ ALL text), location, and what it sets up. The 1996 incident report is required.
11. **Sound.** The knock signal (3, pause, 3), ambience, and stingers. Prefer sounds already used in the game; list any new ones needed.
12. **Art and props.** Materials, lighting plan (practical lights only), a prop list with what can come from existing Blender kits (`ServerStorage.ArtTools`, vault `Assets/Models`) versus what needs new Blender work. Textures come from Blender only, imported as one batch.
13. **Pacing and scares.** A minute-by-minute pacing curve. Remember the owner's direction: only one real jumpscare in the game so far (Floor 5). Say what Floor 3's peak is and why it is not a cheap jumpscare.
14. **Technical plan.**
    - The new files and how they plug in: `Floors/Level3Floor.luau`, `Config/Level3.luau`, client controllers (added to the client Bootstrap in both `need(...)` and `Lifecycle.new`, plus the `require` line), authored StarterGui screens (UI is authored, never code-built), `EncounterId` routing in ElevatorService, and attributes with the `EH` prefix.
    - Every new folder needs `init.meta.json` and every new script needs `<Name>.meta.json` with `"ignoreUnknownInstances": true`.
    - Studio-only debug helpers go behind `RunService:IsStudio()` as server-only BindableFunctions.
15. **Testing plan.**
    - Dev checks under `GameServer.Development`.
    - An `ElevatorDebug` path to reach Floor 3.
    - What to verify with 1, 2 and 4 players.
    - What to screenshot in Play mode (edit-mode lighting lies).
16. **Risks and open decisions.**
17. **Fixes the guide finds elsewhere**, such as the 1962 dates or Marty's Floor 4 reboot line that contradicts the story. List them; do not fix them this round.

## 5. Finish with an implementation prompt

The last section of the guide must be a ready-to-paste prompt, titled **"Implementation prompt (R-next)"**, that a later Claude Code session can run to build Floor 3 from this guide. That prompt must:

- name the round as the next R number and tell the builder to commit before any big change, as CLAUDE.md requires
- tell the builder to read `CLAUDE.md`, this guide, the story bible and the vault notes first
- tell the builder to ask at most 4 design questions up front, then build without stopping for low-risk choices
- list the build steps in order, each with a "done means" check:
  1. layout greybox
  2. art pass
  3. tasks
  4. the light rule
  5. hazards
  6. Marty beats
  7. the split-up and radio
  8. the grey face
  9. papers
  10. sound
  11. UI
  12. ElevatorService routing
  13. dev checks
- repeat the hard rules:
  - no partial Rojo trees
  - check the script hash before pushing and sync any Studio drift into git first, because the owner and a collaborator edit live in Studio
  - never touch `BW28_*` or `BlackWater_Floor4_Props`
  - no coin debug tools on the owner's account
  - never break someone else's playtest
- require play-testing with the ElevatorDebug floor skip, checking the console, confirming Floor 2 loads after Floor 3, and Play-mode screenshots
- end with "remind the owner to publish BOTH places, and say whether anything was actually saved or published"

## 6. Writing style for the guide

Plain, direct and specific. Short sentences. Exact numbers (studs, seconds, volumes) wherever the builder will need them. No filler. Where you are unsure, mark it **[UNCLEAR]** and say what would settle it.

When done, report in a few lines: where the guide is, the assumptions you made, the open questions, and the contradictions you found.
