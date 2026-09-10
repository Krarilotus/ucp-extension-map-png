# Changelog

## Unreleased

### Store preview 0.1.0
- Use the four supplied images inside native game buttons, with matching click areas.
- Preserve menu terminators and real cffi callback addresses; contain callback errors.
- Draw on the interface surface instead of the unused surface zero.
- Add concise descriptions and working settings in all nine UCP languages.
- Use the current GUI options schema and namespace settings under `map-png`.
- Package runtime files, artwork and locales explicitly for the UCP store.
- File selection and overwrite confirmation remain unfinished; fixed-name exports overwrite existing PNGs.

### Added
- Project scaffold: module manifest, options, CI and offline test harness.
- Map/PNG core: diamond<->square tile mapping, terrain flag and colour tables,
  height and terrain export/import. Verified against sourcehold-maps.
- GDI+ PNG bindings, `TileMapState` resolution and redraw, button creation and
  the `mapping` folder. Written, not yet exercised in the game.

### Verified
- The `cffi` module is a build of cffi-lua (fork `gynt/cffi-lua`, branch
  `ucp-extension`), and `modules.cffi:cffi()` returns the raw library rather than
  the reduced wrapper. `ffi.load`, `__stdcall`, callbacks and `ffi.string` are all
  available, so the GDI+ approach holds and the WIC fallback DLL is not needed.

### Fixed
- `buttons.lua` no longer calls `registerObject`, which is a LuaJIT-state global and
  does not exist in the framework's main Lua state. Callbacks are anchored in a
  module-local table instead; without this the game would eventually call a
  collected callback.

### Changed
- The button row is placed from facts read out of Stronghold Crusader 1.41 rather
  than estimated. Both editor map screens are menu 17; the preview is drawn by
  `MenuView_MapEditorProperties_DoEveryFrame` around (400 or 600, 240) in
  menu-local coordinates, and its size follows the map size. The row follows
  layout and map-size changes live and hides whenever the preview is not drawn.
  See the plan, §8.
- Menu 1002 is no longer targeted; it is the scenario event editor.
- Corrected two earlier assumptions: the preview is 200x200 on a 400x400 map, not
  128x128, and `MinimapViewState.x/y` is not the editor preview's position.
- `tilemap.lua` resolves `TileMapState` through each known section table and
  accepts one only if the full cross-check passes. Under Extreme it now finds the
  relocated base deliberately; before, it did so by the accident of overlapping
  tables, contrary to what the docs claimed.
- `tools/deploy.py` keeps `ucp-config.yml`'s line endings, and
  `tools/probe_running_game.py` checks a running game read-only.

### Known gaps
- The file picker is not implemented; imports and exports use a default file name.
- Live verification of the latest native button artwork and conversions is pending.
