# Linked refresh (0.2.0)

Status: 0.2.0 release candidate, integration implemented; live acceptance pending.
The refresh control, sidecar lifecycle and selective native adapter are wired to
the shared import transaction. Unit tests cover transaction failures, link state,
conflicts and teardown; executable-backed tests run UCP's real AOBExtract against
normal and Extreme fixtures. These are not a substitute for a live map test.
Computer-use testing was attempted on 2026-09-20 but the native pipe was unavailable.

## Design

Keep the existing four native buttons. A fifth native button, using the supplied
refresh glyph, sits underneath the rightmost button. Two clipped filename lines
sit to its left: height first, textures second. Empty links are not displayed.
Successful imports replace only their corresponding link; exports do not link.
Refresh rereads both linked files, so an external image editor can update them.

Use one import pipeline for the picker and refresh:

1. Resolve and decode every selected PNG; validate dimensions and convert into
   temporary layer buffers. A missing/invalid second image changes nothing.
2. Snapshot object identities and complete footprints. Compute conflicts against
   the proposed combined height/terrain, not two sequential imports.
3. Expand deletions across native linked-building groups and connected protected
   structures. Preserve all four live layer values underneath retained objects.
4. Run native teardown only for selected records. Suppress rubble using the
   native editor mechanism; never zero record tables or temporarily hide units.
5. Verify selected records are gone, retained identities remain, and unit logical
   states did not change. Then commit staged layers and invalidate the preview.
6. Update links only after successful completion.

Links persist across restarts (user-confirmed). They must belong to a map lifecycle, not a preview, the picker filename or the
static TileMapState address. A load/new-map boundary must prevent accidentally
refreshing another map with the previous map's files. Persistence across game
restarts uses a verified saved-map identity and a separate versioned sidecar;
do not modify the native .map format. Missing images invalidate their individual
links permanently until imported again. If one image disappears just before
refresh, abort that refresh rather than silently importing only the other layer.

## Compatibility policy

Unchanged footprints survive. Cosmetic texture changes underneath retained
objects are masked, including their runtime occupancy flags and raised height.
Height changes and changes to structural terrain (water, marsh, rocks, deposits,
moats/pitch) conflict. Farms also depend on fertile ground. This is deliberately
a conservative policy, not a claim to reproduce every native placement rule.
Unknown/incomplete footprints must fail before deletion, never trigger a
whole-map cleanup fallback. Units are not deleted.

Protected structures: stockpiles, keeps, campgrounds/campfires and keep doors.
Use native linked IDs first. Additional connections must be proven from actual
footprint adjacency and ownership, not “all buildings belonging to this player”.

## Native evidence and release gates

Crusader 1.41 only, as in 0.1.2. OpenSHC supplies names/types; verify executable
instructions before installing hooks or calling addresses.

- `0x421990`: destroy building and linked duplicates; native group field +0x2A8.
- `TileMapState + 0x5549A4` (`0x1FE7BAC`): native no-rubble destruction switch;
  destruction resets it, so scope and restore it for each operation.
- `0x4FB8E0` / `0x4FB970`: native tree/rock footprint clearing. Tree footprint
  extends beyond its central landscape-layer reference; scanning that layer alone
  is insufficient.
- Native placement validators inspect live layers and mutate scratch state; do
  not run them against half-applied imports.

Before a release: prove load/new/save identity boundaries; test connected keep
parts, farms, rocks, trees, walls occupied by units, and rubble; test missing or
invalid second PNG; check both SP and MP geometry and all localized strings.
Publish 0.2.0 through a new Store PR, leaving 0.1.2 untouched. Until these gates
pass, any PR/build must be explicitly marked draft/test, not release-ready.
