# GamerGrill handoff: 0.2.1 load-crash candidate

Everything needed to build this candidate is committed on
`fix/load-crash-0.2.1` in
https://github.com/Krarilotus/ucp-extension-map-png.
No access to Khaleesi or its filesystem is needed. Game executables, maps,
savegames and the UCP test installation must come from GamerGrill itself.

## Scope and publication gate

Verify the computer name is **GamerGrill** before desktop actions. Do not repeat
any T3 shutdown or computer-use configuration changes from the previous machine.
Use the documented computer-use runtime and any available desktop ownership
queue; finish calls and release ownership before stopping.

Keep module version **0.2.1**. Fix the regression minimally; retain working PNG
conversion, native buttons, localization, artwork and selective object cleanup.
Do not update Store PR #49 or the published downloads until actual PC tests pass:
https://github.com/UnofficialCrusaderPatch/UCP3-extensions-store/pull/49
The PR targets `3.0.7` and remains draft. Existing UI 1.0.1 is unchanged.

## Report and candidate repair

Monsterfish_ reports existing editor maps AND ordinary savegames crash on load,
whereas creating new maps works. Structure/tree/shadow PNG handling reportedly
works. The published `v0.2.1-rc.1` candidate has this reported regression.

This branch removes the extra CFFI native filename-getter invocation from the
load/save detours. Instead, observe EAX after the game's own getter call, copy
through the NUL terminator with a 1001-byte bound, and skip map identity work for
non-.map files (including .sav). It also updates the AoB sites and regression
tests. It preserves compatibility with map-extensions' entry hooks/allocation
patches. Runtime discovery uses UCP helpers; no fixed-address fallback.

This is a candidate, NOT a confirmed crash fix. 176 offline tests passed on the
previous machine, including both executable fixtures. No live acceptance has
been performed. Investigate further if actual evidence disproves the hypothesis.

## Obtain, test and build (PowerShell)

Choose any local working directory. Python 3.14 was used for the recorded tests.
The Python dependencies are development-only; the installed module needs no Python.

```powershell
git clone --branch fix/load-crash-0.2.1 https://github.com/Krarilotus/ucp-extension-map-png.git
cd ucp-extension-map-png
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m unittest discover -s tests
.\.venv\Scripts\python.exe tools/package_test.py
```

Output: `dist/map-png-0.2.1.zip`. The packager includes all runtime assets and
verifies every archive entry against source, then prints its SHA256. Do not use
the old rc.1 download as though it contained this repair.

Binary discovery tests need local fixtures; without them they are SKIPPED, not
passed. Before rerunning tests, set `MAPPNG_GAME_DIR` to GamerGrill's game folder
containing `Stronghold Crusader.exe` and optionally `Stronghold_Crusader_Extreme.exe`.
Set `MAPPNG_UCP_CODE` to a local framework source directory containing `utils.lua`.
For a reproducible framework fixture, clone
https://github.com/UnofficialCrusaderPatch/UnofficialCrusaderPatch3 and checkout
`02a7a6bc8ab956a91fc752e8c8ed215c149855e7`; use its `content/ucp/code` directory.
These environment variables override historical machine-specific test defaults.
Report missing fixtures/skips honestly.

## Install and live-test

Read `docs/PORTABLE_TEST.md` first. Locate the correct game and active UCP config;
back them up without replacing unrelated mods/settings. Use UCP 3.0.7 Developer
for the unsigned ZIP; do not disable signature/security checks. Place the ZIP
directly in `ucp/modules/`, keep its exact name, and activate Map PNG 0.2.1 after
its dependencies. Move duplicate/old Map PNG copies outside that folder.
Existing dependencies: ui >=1.0.1, cffi ^1.0.0, luajit ^1.0.0.
UI test build if needed:
https://github.com/Krarilotus/ucp-extension-ui/releases/tag/test-d3a807cfee70

Use disposable copies, not important maps/saves. Record module/build identity,
game/UCP versions, relevant ucp3.log entries and screenshots/crash evidence.

1. Reproduce the old crash if safe; compare with Map PNG disabled if needed.
2. Load existing scenario/invasion and multiplayer editor maps repeatedly.
   Enter map view, return to properties, save, reload and load a different map.
3. Load ordinary savegames, including after prior editor use.
4. Create new maps; test all four PNG actions, picker, previews and button layout.
5. Test linked refresh with one and both images, Save As, restart persistence,
   different-map isolation, missing files and invalid second PNGs.
6. Verify compatible structures/trees remain, conflicting connected structures
   disappear without rubble, and units survive. Save/reload the resulting map.

Native cleanup has no full rollback: a postcondition failure may leave objects
removed even when the PNG is not committed. Do not label populated-map safety or
Extreme support established from screenshots or offline discovery alone.

## After reliable live acceptance

Commit/push any further repairs and record the actual live results. Keep module
version 0.2.1; use a new immutable candidate tag such as `v0.2.1-rc.2`, not a
rewritten rc.1 tag. Build/upload the tested ZIP and verify the remote checksum.
Update existing Store PR #49's recipe version/SHA/tag and description/download
links. The Store branch is `release/map-png-0.2.0` despite its current 0.2.1 title.
Do not merge/sign on behalf of maintainers. Retain all localization and credits,
including Monsterfish_. The old Store preview shows four buttons; replace it
with a real tested screenshot if available, not a mockup.
