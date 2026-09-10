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
addresses are for Crusader 1.41, the same version `sourcehold` supports. Under
Extreme the buttons still appear, but an import or export refuses to run: the
section-table cross-check in `tilemap.lua` fails before anything is written.

Open the map editor and go to the map screen. In `ucp3.log`, next to the exe, you
want:

```
map-png: using <game>\mapping
map-png: added 4 buttons to menu 17 (map-editor-properties) at (x,y), position from ...
```

`position from` tells you which tier resolved the row:

| source | meaning |
| --- | --- |
| `override` | the numbers written into `SCREENS` in `mappng/ui/screens.lua` |
| `MinimapViewState` | read live from the game at `0x01A31610` |
| `fallback` | nothing was known; the row is parked somewhere visible |

## 3. Put the row in the right place

The buttons can be moved with the screen open — no restart per guess. From the
UCP console:

```lua
local s = modules['map-png']:access().screens
s.probe(17)                      -- log MinimapViewState + every menu item
s.setMinimap(17, 336, 232, 128)  -- minimap x, y, height
s.nudge(17, -4, 0)               -- fine adjustment
```

`probe` dumps the menu's items; the two existing round buttons under the minimap
are the anchor. Their y is the row's y, and the leftmost one's x lines up with the
preview's left edge.

When it looks right, write the numbers into `SCREENS` in `mappng/ui/screens.lua`
and redeploy. Then repeat for menu 1002.

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
* The row may be in the wrong place — that is what step 3 is for.
* Both dialogs are stubbed, so file names are not selectable yet.
