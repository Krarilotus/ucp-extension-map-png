# map-png

Import/export height and terrain PNGs below the map editor minimap. A fifth
native button refreshes the linked PNGs without reopening the picker; their
filenames appear to its left (height above terrain).

PNGs are 400×400. Choose files and export names in `<game>/mapping/`, created
automatically. Existing exports require confirmation before replacement.
Activate the module to use it; there are no customization-menu controls. The
default terrain palette is lossless. Imports preserve compatible objects and
mask their occupied tiles. Conflicting structures are removed with native
teardown, without rubble; units are not deleted. Layer-only undo is unavailable.
Linked filenames persist in `mapping/map-png-links.json` for saved maps. Missing
images invalidate their links. Native `.map` files are not modified to store links.
Live acceptance of the new cleanup is pending; see docs/LINKED_REFRESH.md.
The picker's Open folder button opens this mapping directory in Windows.
Import previews show the selected PNG; export initially previews the converted
map layer. The module uses Windows GDI+ and in-process map access; no Python
installation or external conversion executable is required by players.

The creator's transparent glyphs are cropped and enlarged by exact pixel
replication, then drawn inside the game's native button surround. No vanilla
image slots are replaced.

## Status

The current integration targets **normal Stronghold Crusader 1.41**, menu 17:
singleplayer scenario and multiplayer editor map properties. Other map-selection
and gameplay menus are not yet integrated. Do not use with Extreme.

Offline regression tests cover conversion round trips, palette compatibility,
PNG preview encoding, selection/overwrite state, localization coverage, icon
transparency and native control field names. The latest fixes for reload
positioning, picker previews, action labels and supplied artwork await live
acceptance. A passing offline suite does not establish native UI correctness.

See [testing](docs/TESTING.md), [picker acceptance](docs/PICKER_TEST.md), and the
[modder integration guide](docs/NATIVE_UI.md). The original design remains in
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md); it is not a completion report.
Stable store publication is pending live acceptance. The unsigned test prerelease
has [portable installation instructions](docs/PORTABLE_TEST.md).

See [credits and third-party provenance](CREDITS.md) for authors, retained license
notices. GPLv3 code licensing and Monsterfish_ artwork permission are recorded.

## Palettes

- `mappng` (default): lossless terrain round trips.
- `sourcehold`: compatible with the sourcehold/monsterfish1 palette. Shared
  colors lose distinctions between plateau levels and moat states.

## Development

```console
python -m pip install lupa==2.6 Pillow PyYAML
python tools/build_icons.py
python -m unittest discover -s tests -v
```

Tests execute pure Lua in Lua 5.4 with native game/FFI dependencies stubbed.
Rebuild icons only from `resources/icons/creator-v2/`; the older opaque originals
are retained for provenance, not runtime rendering.
