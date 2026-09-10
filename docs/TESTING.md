# Testing the buttons

## 1. Install

```console
python tools/deploy.py "S:/Projects/Harness/recorder-investigation/game-test"
```

Copies the module to `ucp/modules/map-png-0.1.0/` and adds it to `ucp-config.yml`
(backing the config up first). The install must be a **Developer** build of UCP —
check `ucp/ucp-version.yml` for `build: Developer` — because the module is unsigned.

Dependencies must already be present in `ucp/modules/`: `cffi`, `luajit`, `ui`,
`gmResourceModifier`.

## 2. Launch and look at the log

Launch **`Stronghold Crusader.exe`, not `Stronghold_Crusader_Extreme.exe`**. The
button layout was read out of Crusader 1.41, the same version `sourcehold`
supports. Extreme has the same map-layer layout, and `tilemap.lua` finds it through
Extreme's own section table, but the row's layout globals are only known for 1.41:
under Extreme the row sits where a 400x400 singleplayer map puts it and does not
follow the map.

Open the map editor and go to the map screen. In `ucp3.log`, next to the exe, you
want:

```
map-png: using <game>\mapping
map-png: added 4 buttons to menu 17 (map-editor-properties), first at menu-local (309,348), layout sp:400 from game
```

`layout sp:400 from game` means the row was placed from the game's own layout
values. `from default` means the build was not recognised and the row assumes a
400x400 singleplayer map — expect it to be off on anything else.

## 3. Check the row sits under the preview

The position is read out of the game binary, not guessed, so it should be right the
first time. What to check:

* **Singleplayer map:** the four icons sit in a row directly under the preview,
  spanning its width.
* **Multiplayer map:** the preview is further right, and the row moves with it.
* **Smaller map (e.g. 160x160):** the preview shrinks, and the row follows it up.

The external probe prints where each icon should be, in screen coordinates, while
the game runs:

```console
python tools/probe_running_game.py
```

If the row is off by a few pixels, correct it live and report the numbers — a
correction means one of the facts in `mappng/ui/screens.lua` is wrong:

```lua
local s = modules['map-png']:access().screens
s.probe(17)            -- log the live layout and every icon position
s.nudge(17, 0, -2)     -- move the row by (dx, dy)
```

## 4. Test the conversion

Until the file dialog exists, the buttons use a default name in `<game>/mapping/`.

The safe first test is **export**, which only reads:

1. Load a map in the editor.
2. Click export height, then export terrain.
3. Check `<game>/mapping/` for `map_height.png` and `map_tex.png`, both 400x400.

Then the round trip, which is the real exit criterion:

4. Click import height and import terrain without editing the PNGs.
5. The map should be unchanged. If the terrain shifts, either the palette or the
   redraw flags are wrong.

Import keeps one undo snapshot:

```lua
modules['map-png']:access().actions.undo("height")
modules['map-png']:access().actions.undo("terrain")
```

## What is expected to be wrong on the first run

* The buttons draw a **text label**, not your artwork — the GM slots for the icons
  are not assigned yet (`icons.SLOTS` is nil).
* If the row is off, step 3 says how to measure and correct it.
* Both dialogs are stubbed, so file names are not selectable yet.
