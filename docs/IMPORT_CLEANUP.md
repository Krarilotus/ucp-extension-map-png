# Native import cleanup (live acceptance pending)

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

Released test.1/test.2 do NOT perform cleanup. The current working implementation
uses a shared staged transaction for both PNG imports and a native adapter:
0x421990 buildings and linked duplicates, 0x4F2070 trees, 0x4F2220 rocks,
0x4F9F00 wall tiles and decorations. The last routine invokes 0x4019D0 to schedule
decorations (entity types 10..15) for native deletion and clear their display flag.
Eraser effects are left to the engine's normal lifecycle.

Preflight checks supported build, signatures, record bounds and unit occupancy
before deleting anything. Units occupying wall/decorative tiles cause refusal.
Postconditions check active records, footprints and unit logical states before
committing staged PNG data. Building teardown may adjust workers' building-related
AI; preserving units does not mean every byte of their AI state remains unchanged.

This is not atomic rollback: a native postcondition failure may leave objects
removed, but the PNG is not applied and rendering is invalidated. Layer-only undo
is invalidated before deletion because it cannot resurrect objects safely.

Sourcehold's examples/process_wiping_sections.py only writes zero bytes into a
section; it does not perform live entity/owner/footprint bookkeeping. That is why
this adapter uses native teardown rather than section wiping. OpenSHC headers and
the normal 1.41 executable are the reference sources; CREDITS.md applies.

Offline tests and function signatures are checked. The live acceptance matrix
above is still required: do not label this fully verified safe yet.

## Empty-map transition regression (test.4)

BuildingsState+8 is a dynamic scan limit, not allocation capacity. Native
updateBuildings at 0x422E20 periodically writes zero at 0x422E60, then sets it to
highest active building ID + 1 at 0x422E85. An empty map therefore changes from
the initialization value 2000 to zero after entering map view. Accept 0..2000;
for zero, verify that no active building records exist. Continue scanning the
fixed 2000-record allocation. Do not reset the native counter or skip cleanup.
