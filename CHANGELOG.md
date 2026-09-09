# Changelog

## Unreleased

### Added
- Project scaffold: module manifest, options, CI and offline test harness.
- Map/PNG core: diamond<->square tile mapping, terrain flag and colour tables,
  height and terrain export/import. Verified against sourcehold-maps.
- GDI+ PNG bindings, `TileMapState` resolution and redraw, button creation and
  the `mapping` folder. Written, not yet exercised in the game.

### Known gaps
- The file picker is not implemented; imports and exports use a default file name.
- The button graphics have no GM slots assigned yet, so buttons draw a text label.
- The minimap coordinates on both editor screens still need to be measured.
