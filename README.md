# BlackWater

Scripts for the two BlackWater places, synced with [Rojo](https://rojo.space). Models, parts, lighting, UI layouts and MaterialService stay in Studio.

| Place | Place ID | Project | Port |
|---|---|---|---|
| Lobby "BlackWater" | 97536935253958 | `places/lobby` | 34872 |
| "Game" | 96605018559143 | `places/game` | 34873 |

## Setup

Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder. Run `rojo plugin install` once per machine.

## Daily use

1. Run `python tools/check_safety.py`. Do not connect if it fails.
2. Run `rojo serve places/lobby` or `rojo serve places/game`.
3. In Studio, open the Rojo plugin, enter the port and click Connect.
4. Read the patch Rojo shows. Accept only if you expect every change, and reject any removal you do not recognize.
5. Edit the `.luau` files. Rojo pushes saves to Studio. Commit with git.

## Rules that protect Studio content

- Every folder needs `init.meta.json` and every script needs `<Name>.meta.json`, each with `"ignoreUnknownInstances": true`. Without it, Rojo deletes Studio children it does not track, such as assets and the ScreenGui under `LoadingScreen`.
- `servePlaceIds` stops a project from connecting to the wrong place.
- Rojo syncs from files to Studio only. Script edits made in Studio are overwritten by the next file change, and they never reach git by themselves. Edit in files while Rojo is connected.
- Rojo reads scripts with LF line endings. The `SwayEffect` and `Shared/Constants` files in Game keep CRLF on disk, and Studio holds LF versions since the first Game connect. Rojo treats them as equal, so they show no change.
- Rojo renames the open DataModel to the project name, such as `BlackWater-Lobby`. It applies this rename without a prompt when nothing else changed. No script reads `game.Name`, and Studio resets the name when the place reopens.
- These are Team Create places. Rojo adds `ServerStorage.__Rojo_SessionLock` while connected. It has `Archivable` off and does not save. Script changes pushed by Rojo reach everyone in the session.
