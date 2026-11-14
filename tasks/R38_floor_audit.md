# R38 audit: Floors 5 and 4 (2026-11-13)

Source: Studio scan of `BlackwaterAuthoring.Level5` and `Level4`. The scan counted visible, non-mesh parts per prop group: total parts, number of copies, how many are blocks, and how many are thin.
Level 5: about 7,600 parts and 740 meshes. Level 4: about 4,200 parts and 2,080 meshes.
Rule used: flat things built from blocks (walls, bays, panels, cubicles) are fine. Curved, soft or rounded things built from blocks are the problem.

## Ranked fixes (most visible / most off-theme first)

| # | Prop group | Floor | Parts x copies | Problem | Fix |
|---|---|---|---|---|---|
| 1 | LiveWire (spark wires) | 4 | 184 x 8 | 23 square rubber blocks per wire, chained at angles. Reads as stairs, not cable. Sits on the main scare path. | Blender: one sagging cable mesh per wire, frayed copper end. Keep the spark emitters on the end Attachment. |
| 2 | ControlRoomTasks UI | 4 | 123 frames | Floating web "Window": BuilderSans/Arial, 31 rounded corners. | Restyle as a CRT terminal: square edges, mono phosphor font, scanlines, slight glow. Keep every frame and button. |
| 3 | ControlRoomHud (JobList, RestartBar, Toast) | 4 | 28 frames | Same web look as #2. | Same terminal styling, lighter touch. |
| 4 | PipeBracket | 5 | 1127 x 161 | All blocks. Appears on every pipe run, so it is seen everywhere. | Blender: one bracket mesh (U-clamp + base plate), swap all 161 copies. |
| 5 | DanglingWires / Clutter_DanglingWires | 5, 4 | 229 (F5), 190 (F4) | Cylinder chains with visible joints. | Blender: hanging cable meshes (3 variants), swap all copies. |
| 6 | Elbow | 5 | 748 x 44 | 264 block pieces faking a bend. | Blender: 90-degree pipe elbow with flanges, scaled per diameter. |
| 7 | TeeFitting, GateValve, PipeHanger | 5 | 163 / 142 / 99 | Block-built round fittings. | Blender: tee, gate valve (handwheel), hanger rod. |
| 8 | Conduit_* runs | 4 | ~300 total | Cylinder/block mix; bends are faceted. | Blender: conduit bend mesh + straight piece. |
| 9 | RV_KBCable (keyboard cables) | 4 | 180 x 9 | 20 cylinders per cable. | Blender: coiled cable mesh. |
| 10 | Mop, Strap_FireExtinguisher | 5, 4 | 96 / 66 | Cylinder stacks. Small but close to the eye. | Blender props (low priority). |

## Leave as is (flat, reads fine)
ConcreteBay16, FloorBay16, Duct, VentCover, VentGrate, DoorJambBay, DistributionCubicle_*, DrainChannel, CornerFill(s), ServiceCorridors, BreakerPanel, WorkOrderShelf.

## Order of work proposed
1. Rows 1 to 3 first (biggest visible win, smallest job). Blender subagent for the wire mesh; terminal restyle done in Studio.
2. Rows 4 to 7 as one Blender batch (pipe kit), imported via Open Cloud, swapped with `ServerStorage.BackupR38` copies.
3. Rows 8 to 10 if time allows.
Not checked: how the floors look in Play (no screen capture this pass).
