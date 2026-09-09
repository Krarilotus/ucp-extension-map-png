# Changelog

## Unreleased

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

### Known gaps
- The file picker is not implemented; imports and exports use a default file name.
- The button graphics have no GM slots assigned yet, so buttons draw a text label.
- The minimap coordinates on both editor screens still need to be measured.
