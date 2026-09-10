# PNG picker acceptance (Crusader 1.41)

The original request requires file selection, not fixed-name import/export.
The September 10 follow-up implements a separate registered modal and independent
PNG list. No vanilla map browser list or map-save callback is reused.

Native references: OpenSHC RenderTarget (screen/menu = 0), SaveMap/LoadMap modal
renderers, SaveMap filename renderer, UserTextHandler and MenuTextInputState.
The module owns its menu items and callback lifetimes. Opening snapshots the
native text-input state; Back, successful selection and external modal closure
restore it. Filenames are checked before conversion; export requires an extra
confirmation if the destination exists.

Offline tests do not establish native rendering or keyboard correctness.

Live checklist, in both singleplayer scenario and multiplayer/skirmish layouts:

1. All four supplied images appear inside the native buttons.
2. Import opens the localized action title (Import Heightmap or Import Terrain),
   with native centered typography, unobstructed crests and the mapping folder's
   PNG list. Selecting a file previews
   its pixels, not the game's cached minimap. No labels overlap the preview.
3. Back and Escape leave the map unchanged. Normal map save still works afterward.
4. Export opens the corresponding localized Export action with a conversion
   preview; edit a name, confirm, and verify the PNG is created under mapping.
5. Re-export prompts before overwriting. Back must not overwrite.
6. Select an exported PNG and import it; verify the map and minimap refresh.
7. Test scrolling with more than 16 PNGs, Unicode names, empty folder, deleted file,
   malformed PNG and wrong dimensions. Failures must not alter map layers.
8. Repeat for height and terrain, then restart and test native map save/load again.
9. Open folder opens this game's mapping directory (also with spaces/non-ASCII
   characters in its path), without confirming export/import or closing the picker.
   Reopen the picker to refresh its file list after changing files in Windows.
10. Both import dialogs visibly warn that import deletes objects/structures,
    before selecting or confirming a PNG. The warning must not overlap the preview,
    filename or buttons. Test removal and unit preservation on disposable maps,
    including ordinary save/reload. Layer-only undo is unavailable.

Store PR remains on hold until the requested live flow works. Action labels use
the installed game's language, not generic Load/Save. Back/confirmation strings
come from the game; extension GUI text has separate UCP locales.
