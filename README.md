# map-png

A UCP3 module for Stronghold Crusader that adds four buttons under the minimap on the
map editor screens:

| | |
| --- | --- |
| ![](resources/icons/import_heightmap.png) | import height map |
| ![](resources/icons/export_heightmap.png) | export height map |
| ![](resources/icons/import_textures.png) | import terrain map |
| ![](resources/icons/export_textures.png) | export terrain map |

PNGs live in `<game directory>/mapping/`, which the module creates on first run.

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the design and the current
state of each milestone.

## Why this exists

The same conversion is possible today with [sourcehold-maps][sourcehold]:

```console
sourcehold memory map set height  --input "map_goldwaters_height.png"
sourcehold memory map set terrain --input "map_goldwaters_tex.png"
sourcehold memory map get terrain --output output.png
sourcehold memory map get height  --output output_height.png
```

That works, but it means a second command prompt, a Python install with numpy, OpenCV
and pymem, and remembering which map layer is which. It also has to attach to the
running game from outside and poke its memory through `pymem`.

A UCP module runs *inside* the game, so none of that is needed. **Nothing is bundled**:
the map layers are ordinary pointer dereferences, and PNG encoding uses `gdiplus.dll`,
which is already part of Windows.

## Status

Working and tested offline:

* the diamond ↔ square tile mapping, verified tile-for-tile against sourcehold's
  `TileLocationTranslator`
* the terrain flag ↔ colour tables, verified against `logics.py` and OpenSHC's
  `Logic1.hpp` / `Logic2.hpp`
* height and terrain export/import, round-trip tested

Written but not yet run in the game:

* the GDI+ PNG bindings
* locating `TileMapState` and forcing the redraw
* the buttons themselves

Not written yet:

* the file picker (`mappng/ui/filedialog.lua` falls through to a default name)
* the GM slots for the button graphics (the buttons draw a text label until then)

## Palettes

Two are available, selected in the UCP GUI:

* **`mappng`** (default) — a lossless round trip.
* **`sourcehold`** — the monsterfish1 palette, byte-for-byte compatible with existing
  sourcehold PNGs. It gives plain earth and both plateau levels the same `#ae9467`, and
  all three moat states the same `#0000ff`, so importing an exported map does not give
  the map back. Use it only when you need to exchange PNGs with the Python tool.

## Development

```console
python -m pip install lupa==2.6
python -m unittest discover -s tests -v
```

The tests run the module's pure-Lua files in a real Lua 5.4 runtime — the same version
the UCP framework uses — with the game and FFI layers stubbed out.

[sourcehold]: https://github.com/sourcehold/sourcehold-maps
