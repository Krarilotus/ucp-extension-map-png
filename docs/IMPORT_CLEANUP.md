# Destructive import contract (implementation pending)

Both height and terrain imports must remove placed objects and structures before
applying the PNG. Show one localized warning below the PNG preview; do not repeat
it over the image. The warning must explicitly say that objects/structures will
be removed, without an extra save-first sentence. Preserve units. A layer snapshot cannot restore
entities and must not be presented as full-map undo.

Required sequence:

1. Resolve the selected PNG; decode it fully; validate dimensions and conversion
   into staging buffers. Invalid/missing PNGs must cause no map changes.
2. Validate the native cleanup bindings and current supported editor context.
3. After the user confirms the destructive import, perform native entity cleanup.
4. Verify no placed-entity references remain before copying staged map layers.
5. Invalidate rendering/navigation through the existing map refresh integration.

Do not zero entity arrays or use a whole-game reset. Preserve map type, scenario
events, map metadata and the non-imported layer except changes inherent in
removing structures. Do not leave a layer-only undo path that reintroduces object
flags without restoring their entities.

## Normal 1.41 research

- OpenSHC `TileMapState::eraseAreaWithBrush` at 0x508EC0 checks valid map/border
  tiles, removes trees/rocks via LandscapeState, deletes buildings through
  0x421990 and handles wall erasure through 0x4F9F00.
- It **marks units as logical state 3**, rather than synchronously unlinking them.
  Applying terrain immediately afterward is therefore not yet a verified cleanup.
- Do not call unit deletion or the full eraser: the requested scope explicitly
  preserves units. Building/landscape-specific cleanup requires separate validation.
- Brush size table 0xB48FF4 has counts 0,1,5,13,...; index 0 is not a single tile.
- UnitsState 0x1387F38 has 2500 records at offset 0x614, stride 0x490;
  logicalState is short offset 0x8C. These are normal-game-only references.

## Acceptance gate

Exercise trees, rocks, decorations, troops/animals, keeps, towers, walls, gates,
farms and linked structures, including multiple owners. Test each import layer,
both editor layouts, map reload and ordinary native map save. Confirm invalid PNG
and cancellation remove nothing. Save and reload the cleared map and check for
stale unit/building/navigation references. Never label clearing complete based
only on screenshots of disappearing sprites.

Current released test.1 and current runtime do NOT perform this cleanup. Do not
change the runtime warning to promise deletion until the native sequence is
implemented and verified. The existing warning remains accurate in the meantime.
