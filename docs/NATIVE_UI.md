# Native map-tool integration

This implementation targets normal Crusader 1.41. Offline tests are regression
checks, not proof that native rendering, keyboard input or map transitions work.

## Boundaries

`screens.lua` owns verified menu geometry and the four action identities.
`controls.lua` owns the native item schema and drawing-surface restoration.
`buttons.lua` registers anchored callbacks once and dispatches actions.
`picker.lua` owns file selection and overwrite confirmation without game memory.
`nativepicker.lua` adapts that state to a native modal and filename input.
`pickerlayout.lua` is the shared geometry contract for the list and scrollbar.
`preview.lua` converts image pixels to TGX without touching map memory.
`actions.lua` alone dispatches map-layer conversions; PNG previews do not import.
`paths.lua` confines filenames to the mapping directory and handles Windows Unicode.
`i18n.lua` selects concise action labels from the installed game's text language.

Reuse these layers when adding a screen. Do not copy the four handlers or create
another file browser, conversion backend or icon-to-action mapping.

## Native invariants

- Insert before `LAST_ENTRY` (0x66); never replace a live menu's terminator.
- Standalone controls use type 3, not a vanilla interaction group's flags.
- Put new standalone controls before existing groups when their hitboxes overlap
  hidden vanilla controls. Menu::handleMenuItems (0x4F6280) stops at the first hit
  (0x4F6424..0x4F642D). Not rendering a vanilla control does not remove its hitbox.
  Menu 17's multiplayer list and Edit control intercept the SP height row if it
  is appended. Preserve all original items, callback parameters and group order.
- Explicit positions require **`ucId_0x30 = -1`**. That is the installed UI
  header's exact field name. OpenSHC's `ucID` spelling is not interchangeable:
  cffi ignores that unknown initializer key and leaves zero. Menu reload then
  resolves control zero through vanilla layout tables and moves it to (0,0).
  Read the field back after allocation; test against the real header.
- Coordinates are menu-local; the engine adds the menu origin. Never add screen
  offsets twice. Re-evaluate verified layout globals when map size/type changes.
- Draw on menu surface 0 and restore the previous surface even after errors.
- Text renderer font parameters are IDs, not pixel sizes. The font table has
  20 entries (0..19); ID 20 reads beyond it and renders garbage. Native SaveMap's
  header helper (0x475CC0) uses ID 15, centered alignment 1 and color 0xC2F0EB.
  Keep action icons on their buttons, not over the header's native crests.
- Keep callbacks, menu arrays and image buffers alive while native code can use
  them. Catch errors at every native callback boundary. Disable callbacks before
  unloading artwork; re-enable without duplicating items.
- Verify native function signatures, calling conventions and code bytes before
  binding. Use `ffi.tonumber` for cffi function pointers.
- Snapshot and restore native filename input on success, cancellation and external
  modal closure. Do not reuse native map-save callbacks or map-file list state.
- Native LoadMap draws a cached **game map**, not the selected PNG. Own the content
  area and render decoded PNG pixels. Keep labels outside the preview rectangle.
- Header artwork (0x468FE0) adds its own 8px inset and always draws 64px high;
  its last parameter does not resize it. Pass the modal origin, not an inset twice.
- Reuse native type-6/render-type-4 scrollbar handling and SaveLoadMap's pure
  scrollbar renderer (0x492C60). Adapt only its event protocol to the PNG model;
  never call the vanilla action handler (0x492BA0), which changes map-list globals.
  Arrows use 0x469290; filename trimming uses 0x469F50 on a display-only copy.
  Cache trimmed labels per dialog instead of allocating them every render frame.
- Require valid filenames, dimensions and complete decoding before map writes;
  require a separate confirmation before replacing an existing export.

## Screen coverage and extension contract

Currently registered: menu 17, editor map properties, both singleplayer scenario
and multiplayer layouts, including re-entry after loading a map. Latest fixes
still require live acceptance. This is not yet coverage of every map menu.

Before registering another menu, establish all of the following:

1. Whether its displayed map is the live editable tile map or merely a cached
   selection preview. A selected file is not evidence that live memory holds it.
2. Its preview geometry, visibility conditions, menu-local origin and reserved
   space for four native controls at every supported resolution/map size.
3. What loading, changing selection and returning from a modal do to item positions,
   pointers, text state and the underlying map. Register once, not on each entry.
4. Which operations are safe. File-selection screens need a separately verified
   map-file backend or an explicit load transition before imports are enabled.
5. Layout, reload, cancellation, conversion and native-save regression tests.

Known separate contexts: menu 31 (new-map size) has a different preview centre;
menu 12 is the landscaping toolbar; menu 20 (lobby) and menu 35 (selection) can
display cached previews. Do not register them with menu 17's geometry/backend.
Menu 1002 is the scenario event editor and has no map preview.

## Artwork and localization

`resources/icons/creator-v2` preserves the supplied transparent PNGs. Run
`tools/build_icons.py` to crop transparent padding, scale exactly 2x and encode
555/565 TGX. Native TGX uses binary transparency, thresholded at alpha 128.
No generated strokes, gray bevels or replacement vanilla image slots are used.
The script also produces `docs/artwork-review.png` showing native-size and enlarged
glyphs. Import arrows point from file to layer; export reverses the direction.

Runtime action labels cover en/de/fr/ru/hu/tr/ch/es/fa plus native Italian/Polish;
UCP descriptions cover its nine GUI languages. Read the loaded TextManager's
language marker (group 6, entry 0, also used by textResourceModifier.GetLanguage),
then fall back to the existing framework data.version.getGameLanguage function.
Loaded text takes priority because translated installations can retain an English
executable ID. TextManager's codepage field is authoritative when recognized;
language-specific defaults are only fallback. Filesystem paths stay Unicode.
Native font coverage and long-label fit must be checked in-game per language.
Do not silently substitute the host Windows locale for the game's language.
