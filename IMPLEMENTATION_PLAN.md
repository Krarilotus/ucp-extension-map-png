# `map-png` — Implementation Plan

UCP3 module that adds four buttons under the minimap of the map-editor map screens,
translating between the live map in memory and PNG files on disk.

| Button | Direction | Data |
| --- | --- | --- |
| Import height map | PNG → game | `HeightLayer` + `DefaultHeightLayer` |
| Export height map | game → PNG | `DefaultHeightLayer` |
| Import terrain map | PNG → game | `LogicLayer` + `Logic2Layer` |
| Export terrain map | game → PNG | `LogicLayer` + `Logic2Layer` |

---

## 0. The bundling question — answered

**Nothing needs to be bundled.** The current workflow shells out to `sourcehold`
(Python + pymem + numpy + OpenCV) which attaches to `Stronghold Crusader.exe` from
*outside* and pokes its memory. That is only necessary because the tool is an external
process.

A UCP module already runs **inside** the game process. Every read/write `sourcehold`
performs through `pymem` is a plain pointer dereference for us. Concretely:

* `sourcehold` walks the map-section address table at `0x00B92A58 … 0x00B93208`
  (16-byte `MapSectionAddress` records: `address, unknown, size, compressed, sectionId`)
  to find section `1045`, `1005`, `1003`, `1037`.
* Those sections are just fields of the `TileMapState` singleton at **`0x01A93208`**:

  | sourcehold section | `TileMapState` field | offset | type | length |
  | --- | --- | --- | --- | --- |
  | `1003` | `LogicLayer` | `0x00165160` | `int[80400]` | 321600 |
  | `1037` | `Logic2Layer` | `0x001B3FE0` | `byte[80400]` | 80400 |
  | `1005` | `HeightLayer` | `0x0029FA30` | `byte[80400]` | 80400 |
  | `1045` | `DefaultHeightLayer` | `0x002B3440` | `byte[80400]` | 80400 |

  (`OpenSHC/src/OpenSHC/Map/TileMapState.hpp`, `OpenSHC/Globals/DAT_TileMapState.hpp`)

  The two sources corroborate each other exactly: `sourcehold` hardcodes
  `futureMapOrientation = 0x01FE7AA8`, and `0x01A93208 + 0x5548A0` is `0x01FE7AA8`.
  So rather than hardcoding the base, `tilemap.lua` derives it from the section table
  and asserts every layer offset agrees. A version mismatch then fails loudly instead
  of writing 80400 tiles into the wrong allocation.

The only remaining external dependency is **PNG encode/decode**, and Windows ships that:
`gdiplus.dll` is loaded into every GUI process anyway. We call its flat C API through
the UCP `cffi` module — which is cffi-lua, not LuaJIT; see §7 for what that does and
does not give us. No Python, no OpenCV, no numpy, no extra DLL to build or sign.

> **Bonus over `sourcehold`:** because we are inside the process we can call the game's
> *own* refresh routines after an import (`forceUpdateLogicalAndMiscDisplayLayers`,
> `forceUpdateTextureTilemap`, `forceUpdateGFXLayers` at `TileMapState+0x55486C…0x554874`,
> and the `mapOrientation`/`DAT_FutureMapOrientation` pair at `+0x55489C`/`+0x5548A0`).
> That replaces the `force_redraw()` hack and the commented-out `post_process_raw_height()`
> mess in `sourcehold/tool/memory/map/height/__init__.py`.

---

## 1. Architecture

```
ucp-extension-map-png/
  definition.yml          module manifest (type: module)
  init.lua                enable/disable, wiring
  options.yml             user options (folder name, palette, overwrite prompt)
  mappng/
    paths.lua             locates + creates <game>/mapping/
    png/
      gdiplus.lua         FFI bindings for the GDI+ flat API
      init.lua            readPNG(path) -> {w,h,pixels}, writePNG(path, img)
    map/
      tilemap.lua         TileMapState pointer + typed layer views
      diamond.lua         serialized-tile-index <-> 400x400 square mapping
      palette.lua         the monsterfish1 palette + Logic1/Logic2 flag tables
      height.lua          importHeight / exportHeight
      terrain.lua         importTerrain / exportTerrain
      refresh.lua         force the game to redraw after an import
    ui/
      icons.lua           button icon resources
      buttons.lua         the four MenuItems + their render/action handlers
      filedialog.lua      vanilla-styled PNG picker modal
      screens.lua         which menus get the buttons, and where
  resources/icons/*.png   the four button graphics, 32x18 opaque 8-bit palette PNG
  tests/                  offline tests (lupa, Lua 5.4 -- the framework's own version)
```

**Dependencies** (`definition.yml`):
`framework >= 3.0.7`, `ui >= 1.0.1`, `cffi ^1.0.0`, `luajit ^1.0.0`,
and `gmResourceModifier >= 0.2.0` (only for milestone 5, custom button graphics).

---

## 2. Milestones

### M1 — Map ↔ PNG core, no UI

Everything that replaces `sourcehold memory map get/set`, driven from the UCP console
so it can be validated before any UI exists.

1. **`mappng/map/tilemap.lua`** — walk the section table, derive the `TileMapState` base
   from it, cross-check it against every layer offset, and `ffi.cast` typed views.
2. **`mappng/map/diamond.lua`** — port `TileLocationTranslator` /
   `create_selection_matrix`. The game stores `80400` tiles in a diamond; the PNG is a
   `400x400` square. The mapping is:
   `i = row`, `j_adjusted = j + |((size/2)-1 if i < size/2 else size/2) - i|`.
   Precompute a flat `int32[80400]` lookup `serializedIndex -> squarePixelIndex` once at
   enable; both directions then cost one array read per tile.
   Pixels outside the diamond are black on export and ignored on import — matching
   `sourcehold`.
3. **`mappng/map/height.lua`**
   * *export*: `DefaultHeightLayer[k]` → grayscale byte at `lookup[k]`.
   * *import*: grayscale byte → **both** `DefaultHeightLayer` and `HeightLayer`
     (sourcehold writes `1045` and `1005`), then `refresh.lua`.
4. **`mappng/map/palette.lua`** — port `logic1`, `logic2` and the `monsterfish1` hex
   palette verbatim from `sourcehold/tool/memory/map/terrain/{logics,colors}.py`.
   Keep the file **RGB**, not BGR — sourcehold works in BGR only because OpenCV does.
   Cross-checked against `OpenSHC/Map/LogicHelpers/Logic1.hpp`; the flag values agree.
5. **`mappng/map/terrain.lua`**
   * *export*: for each `Logic1` flag in order, paint its palette colour; then overlay
     `Logic2` values where `L_DEFAULT_EARTH_OR_TEXTURE (0x8000)` is set. Same two-pass
     order as `get_terrain`, which is load-bearing — later flags overwrite earlier ones.
   * *import*: read existing `LogicLayer` first and keep only `L_BORDER (0x10)` /
     `L_BORDER_EDGE (0x20)` and the zero tiles, then OR in the flags for each matched
     colour and write `Logic2Layer`. Identical to `set_terrain`.
   * Unknown colours: `sourcehold` silently drops them. We log a warning with the count
     and the first offending pixel — silent corruption of a map is worse than a slow import.
6. **`mappng/map/refresh.lua`** — set the three `forceUpdate*` flags and copy
   `mapOrientation` into `DAT_FutureMapOrientation`.

**Exit criterion:** exporting a vanilla map and re-importing the PNG is a no-op
(round-trip byte-identical on `DefaultHeightLayer`, and on `LogicLayer` modulo the
flags the palette does not represent).

### M2 — PNG I/O via GDI+

`mappng/png/gdiplus.lua` binds the flat API:

```
GdiplusStartup / GdiplusShutdown
GdipCreateBitmapFromFile        (path is UTF-16 — MultiByteToWideChar via kernel32)
GdipGetImageWidth / GdipGetImageHeight
GdipBitmapLockBits / GdipBitmapUnlockBits   (PixelFormat32bppARGB = 0x0026200A)
GdipCreateBitmapFromScan0
GdipSaveImageToFile             (PNG encoder CLSID {557CF406-1A04-11D3-9A73-0000F81EF32E})
GdipDisposeImage
```

**Verified — see §7.** `ffi.load`, `__stdcall` and callbacks are all available. The WIC
fallback (a ~200-line native `mapImageIO.dll`, the pattern of
`ucp_gmResourceModifier/loadImageAsInterfaceResource.cpp`) is no longer needed.

Size handling: only `400x400` is accepted on import (the game's tile array is always
allocated at 400x400 regardless of the playable map size — this is why the editor shows
`400x400` in the corner and why `sourcehold` hardcodes it). Anything else is rejected
with a clear message rather than being scaled.

### M3 — The `mapping/` folder

`mappng/paths.lua`:
* Game directory = the directory of the running executable (`GetModuleFileNameA(NULL)`),
  which is where UCP already anchors `ucp/`.
* Ensure `<game>/mapping/` exists at module enable (`CreateDirectoryA`, ignore
  `ERROR_ALREADY_EXISTS`).
* Folder name configurable via `options.yml` (default `mapping`).
* All four dialogs are hard-scoped to that folder. No path traversal out of it.

### M4 — Buttons under the minimap

**Target screen — superseded, see §8.** Both screenshots are one menu,
`Menu_MapEditorProperties` (menu 17, `0x00B97148`); its items switch between the
singleplayer and multiplayer layouts. Menu 1002 (`Menu_EditScenario`) is the scenario
*event* editor and has no preview, so it is not a target. The preview position is read
out of the game binary rather than discovered at runtime; §8 has the evidence.

**Adding the items.** Same mechanism `extension-automarket` uses for its market button:

```lua
local Menu = modules.ui:access().api.ui.Menu
local menu = Menu:fromID(17)
menu:addMenuItem{
  menuItemType = 0x02000003,          -- NORMAL_ELEMENT | PART_OF_INTERACTION_GROUP
  menuItemRenderFunctionType = 0x1,
  position = { position = { x = ..., y = ... } },
  itemWidth = 32, itemHeight = 18,
  callbackParameter = { parameter = <0..3> },
  menuItemRenderFunction = { address = <ffi.cast'd render fn> },
  menuItemActionHandler  = { address = <ffi.cast'd action fn> },
}
```

`Menu:addMenuItem` reallocates the item array when full, so we do not have to patch the
game's static arrays. Registered from a `hooks.registerHookCallback('afterInit', ...)`
callback, as automarket does.

Note the `ui` module's `patches.setButtonPropertiesPatch()` is what makes custom button
properties stick — it is already applied when the `ui` module is enabled, and `ui` is our
dependency.

### M5 — Button graphics

Your four graphics are in `resources/icons/`:
`import_heightmap.png`, `export_heightmap.png`, `import_textures.png`,
`export_textures.png` — 32×18, 8-bit palette, fully opaque (no `tRNS`), with the grey
bevel already drawn in. So the icon *is* the whole button; no separate button background
needs to be rendered underneath, and no colour-key/alpha handling is required.

Path into the game:

1. `gmResourceModifier:LoadResourceFromImage(path)` — builds an interface-type resource
   from an image file via WIC, converting to the game's 16bpp format. Returns a resource id.
2. `gmResourceModifier:SetGm(gmID, imageInGm, resourceId, 0)` — points a GM image slot at
   our resource.
3. `game.Rendering.renderGM(textureRenderCore, gmID, imageID, x, y)` in the item's render
   function.

*Open item:* pick the four GM slots. Needs a pass over the interface GM files for four
32×18-or-larger images unused on these two screens. Until that is resolved, the render
function falls back to `renderTextToScreenConst` with a short label — same stopgap
automarket uses for its "Auto market" button — so M4 can be validated before M5 lands.

`tools/inspect_icons.py` verifies the four files stay 32×18 and opaque, so a later
redraw that silently changes the geometry is caught by the test suite rather than in-game.

### M6 — The file dialogs

A vanilla-styled `MenuModal` built with `modules.ui:access().api.ui.ModalMenu`, one
instance reused for all four actions (mode is a field on the module state).

* **Layout** copies the game's Save dialog (your screenshot 3): title bar, name field on
  the left for save mode, scrollable name list on the right, `Speichern`/`Laden` +
  `Zurück` buttons. `borderStyle = 512` gives the red double border.
* **Listing files.** The game already has
  `ResourceManager::discoverMapFiles(const char* pattern)` at `0x00477EE0` — it takes a
  glob, `FindFirstFileA`s it, truncates each name at the first dot, sorts, and fills
  `loadedMapNames` / `mapFileCounter`. Calling it with `"mapping\\*.png"` gives us a
  sorted PNG list in the game's own format for free.
  *Caveat:* it also fills the shared `ResourceManager` map list. We snapshot and restore
  that state around the call so the real map browser is unaffected — verify this in
  testing; if it turns out to be entangled, do our own `FindFirstFileA` loop from FFI
  (~30 lines) and keep the vanilla list untouched.
* **Save mode** reuses `MenuTextInputState` for the filename field; default name is the
  current map name + `_height` / `_tex`, matching your
  `map_goldwaters_height.png` / `map_goldwaters_tex.png` convention.
* **Overwrite** raises the game's `YES_NO_DIALOG` (modal type 11) unless disabled in options.
* We allocate our own modal menu IDs through `ui`'s manager
  (`manager.getAvailableMenuID`) rather than reusing `SAVE_MAP (10)` / `LOAD_MAP (9)`,
  so the real map save/load path is never touched.

### M7 — Feedback and safety

* Progress: an import/export of 80400 tiles is a few ms; no progress bar needed, but the
  result gets a one-line confirmation in the bottom-left text display and a log line.
* Errors (bad size, unreadable PNG, unknown colours, no write permission) surface as a
  modal message rather than only in `ucp3.log`.
* Import is refused unless a map is actually loaded in the editor — guard on the editor
  state before touching `TileMapState`.
* Imports are not undoable by the game's editor undo. Documented; an optional
  "snapshot before import" (keep the previous layers in a Lua buffer, one level) is
  cheap and worth adding in M7.

### M8 — Tests, packaging, docs

* `tests/` mirrors `ucp_recorder`: `lupa` runs the pure-Lua logic (diamond mapping,
  palette round-trip, terrain flag composition) against fixtures, with the FFI and game
  layers stubbed. `unicorn` is not needed — we add no assembly.
* Round-trip fixture: a synthetic 80400-tile layer → PNG → back, asserted byte-identical.
* Palette test: every `logic1`/`logic2` name has a colour and no two names that can
  co-occur share one.
* CI: `.github/workflows/tests.yml` in the same shape as the recorder's.
* `docs/` gets a short user guide; `locale/description-en.md` for the UCP GUI.

---

## 3. Known open items

1. ~~**`ffi.load` availability** in the UCP `cffi` module~~ — confirmed, see §7.
2. **GM slots for the button icons** — gates M5b, not M5.
3. ~~**Exact menu ID + coordinates**~~ — resolved from the binary, see §8.
4. **`discoverMapFiles` side effects** on the shared map list — has a cheap fallback.
5. **Terrain import fidelity — resolved, see below.**
6. **Map size.** Only 400×400 is handled, as in `sourcehold`. If you ever want the
   smaller editor sizes to export cropped, that is a follow-up.

## 4. Out of scope

`sourcehold modify map --unlock` operates on `.map` files on disk, not on the live map,
and has no natural home under the minimap. If you want it, it belongs as a separate
button on the map-selection screen, and it is a different feature.

---

## 5. The monsterfish1 palette is lossy — and the default palette fixes it

Found while writing the round-trip test, and worth calling out because it silently
damages maps today.

`sourcehold`'s palette gives three names the same colour `#ae9467`
(`default_earth_or_texture`, `plateau_medium`, `plateau_high`) and three more the same
`#0000ff` (`moat_undug`, `moat_dug`, `moat`). On export that is only a cosmetic merge.
On import it is not: `set_terrain` builds its colour→name lookup with a Python dict
comprehension, so for each shared colour **the last name wins**. Concretely,
`bgr_palette[#ae9467]` is `plateau_high`, which means

> every plain earth tile in an imported terrain PNG comes back as a high plateau.

The same happens to `#0000ff`, where every moat state collapses onto `moat`.

There is a second, quieter consequence. `logics.py` has no `moat_undug` entry in
`logic1` at all — it never needed one, because the collision meant the name could never
be looked up. Any palette that separates the moat states hits `logic1["moat_undug"] ==
nil` and clears the tile's logic1 entirely. `mappng/map/palette.lua` adds
`moat_undug = 0x8000`, matching how every other logic2-distinguished terrain is stored.

So the module ships two palettes:

* **`mappng`** (default) — monsterfish1 with the six colliding names given distinct
  colours. `test_roundtrip.py::test_identity_with_default_palette` asserts that
  game → PNG → game is an identity across every terrain type.
* **`sourcehold`** — monsterfish1 exactly, for exchanging PNGs with the Python tool.
  Its collisions are asserted in `test_palette.py` rather than left implicit, and its
  tie-break is made explicit (plain earth wins `#ae9467`, not `plateau_high`) so at
  least the common case survives.

`test_roundtrip.py::test_sourcehold_palette_loses_plateaus` pins the lossy behaviour, so
nobody later "fixes" the compatibility palette and breaks compatibility.

---

## 6. Build status

| Milestone | State |
| --- | --- |
| M1 map ↔ PNG core | **done, tested offline** |
| M2 PNG I/O via GDI+ | written, not yet run in the game |
| M3 `mapping/` folder | written, not yet run in the game |
| M4 buttons | written; position read from the binary (§8), not yet run in the game |
| M5 button graphics | icons in place; needs GM slots, text fallback active |
| M6 file dialogs | not started; falls through to a default file name |
| M7 feedback and safety | partial (undo snapshot, unknown-colour report) |
| M8 tests, packaging, docs | tests and CI in place |

48 offline tests pass (`python -m unittest discover -s tests`). They cover the tile
mapping tile-for-tile against sourcehold's own formula, the flag tables against
`logics.py`, both palettes, height and terrain round trips, and the icon geometry the
button layout depends on.

**Next three things, in order:**

1. ~~Confirm `ffi.load` works from the UCP `cffi` module~~ — confirmed, see §7.
2. Launch plain `Stronghold Crusader.exe`, open the editor map screen, and check the row sits under the preview in both the singleplayer and multiplayer layouts. Placement is derived (§8); this confirms it.
3. Export a vanilla map, re-import it, and confirm the map is unchanged. That validates
   M1 through M4 end to end.

---

## 7. FFI capability check — confirmed

The one thing the whole GDI+ approach rested on. Checked against the cffi module's
own source rather than assumed.

**The module is not LuaJIT.** `modules.cffi` is a build of
[cffi-lua](https://github.com/q66/cffi-lua) — a libffi-based FFI for stock Lua, aiming
at LuaJIT-FFI compatibility. UCP uses the fork `gynt/cffi-lua`, branch `ucp-extension`,
which adds only two commits: a try/except workaround for an access violation during GC
of cdata, and a settings interface for the debug options in `options.yml`. No API is
removed.

**The full API is reachable.** `init.lua` defines a reduced `CFFIInterface` class
(cdef, cast, addressof, new, sizeof, copy, fill, tonumber) but never returns it — it
exists for the language server. The accessor is:

```lua
local dll = require("cffi.dll")
function cffi:cffi() return dll end
```

so `modules.cffi:cffi()` hands back the raw cffi-lua table, including everything the
wrapper does not list.

| Needed for | Available |
| --- | --- |
| `ffi.load("gdiplus")`, `ffi.load("kernel32")` | yes — `clib = cffi.load(name [, global])`, plus `cffi.C` |
| `__stdcall` in a cdef (the game is 32-bit, so this is not optional) | yes — the parser maps `__stdcall` → `C_FUNC_STDCALL`; `__cdecl`, `__thiscall` and `__fastcall` too, and `__attribute__((stdcall))` syntax |
| Callbacks for the button render/action handlers | yes — callback objects with `cb:free()` / `cb:set(func)` |
| `ffi.string` for `GetModuleFileNameA`'s buffer | yes — `cffi.string(ptr [, len])` |

**Two caveats that came out of the same check:**

1. **`registerObject` does not exist in the main Lua state.** It is a global defined in
   the luajit module's `common/code.lua`, so it is only there inside a LuaJIT state.
   `extension-automarket` can call it because its callbacks live in one; ours do not.
   `buttons.lua` anchors its callbacks in a module-local table instead. Letting a
   callback be collected while the game still holds the pointer is a crash, so this
   mattered.

2. **cffi-lua callbacks are libffi closures**, heavier than LuaJIT's. The button render
   function runs every frame. If that shows up as a cost, the fallback is the route
   automarket already proves: move the callbacks into a LuaJIT state via
   `modules.ui:createMenuFromFile` and drive them with `ui:sendEvent`. Worth watching,
   not worth pre-optimising.

Known cffi-lua limitations (bitfields, passing unions, structs containing unions) do not
apply — every structure we touch is a flat array of scalars.

---

## 8. Where the preview is — read from the binary

Earlier revisions of this plan guessed at the minimap position: first a 128-px preview
inferred from the mockup's proportions, then `MinimapViewState.x/y` at runtime. Both
were wrong. The answer is in `Stronghold Crusader.exe` itself, and every step below was
read out of it with a disassembler, cross-checked against OpenSHC's names.

**Menu 17 is both screens.** The `Menu::Menu` call sites (`push <items>; mov ecx,
<menu>; call 0x004F4100`; the callee starts with the `ui` module's `51 53 8B D9`
signature) put menu 17's items at `0x005EE898`. They match both screenshots:
"Karte speichern" (100,420), "Szenario bearbeiten" (450,420), "Zur Karte" (450,520),
the two round icons (240,490)/(310,490), and the multiplayer list box with its
scrollbar. Menu 1002's items are a 20-row event list.

**The preview is a MenuView frame callback, not a menu item.** `0x0042E0D0` is pushed
as the every-frame function for menu `0x11` on MenuView `0x00B98134` (`0x0059A490`),
and OpenSHC names it `MenuView_MapEditorProperties_DoEveryFrame`. It draws through
`MinimapViewState::renderMinimapEditor(x, y, w, h)` (`0x004B7530`):

```
0x0042E423  cmp [0x1FE9244], 0        ; singleplayer vs multiplayer layout
0x0042E42A  ebx = origin.x + (== 0 ? 0x190 : 0x258)    ; 400 or 600
0x0042E440  esi = origin.y + 0xF0                        ; 240
0x0042E446  edi = [0x1FE7C14] (0 -> 400)                 ; map size, also the "%dx%d" label
            switch on size: 160 -> 160x160, 200 -> 200x200,
                            300 -> 150x150, 400 -> 200x200, each centred on (ebx, esi)
0x0042E416  whole block skipped unless [0x1FE7CBC] == -1
```

**Menu-local coordinates are the preview's frame.** Every MenuView prepare stores the
resolution-dependent origin into both the menu (`mov [menu+4], ecx; mov [menu+8], eax`)
and `0x00F2B3A0/A4`, and the item render loop computes `ButtonX = menu.x + item.x`,
`ButtonY = menu.y + item.y` (`0x004F4A26`). An item at menu-local (x, y) is therefore
drawn at the same origin the preview uses, at every resolution. `MainButtons` draws
straight at `ButtonX/Y`, confirming nothing else is added.

**The row.** Four equal slots across the preview width, icons centred in them, 8 px
below the preview — the mockup's strip starts 3 px under it and is 28 px tall. On a
400×400 map: x = 309/359/409/459 (singleplayer) or 509/559/609/659 (multiplayer),
y = 348. The render function re-reads the layout every frame and moves the row when
the map type or size changes, and hides it whenever the preview is not drawn.

Your icons are exactly 64% of the mockup's 50×28 slots (32×18). They fit every map
size (the narrowest slot is 37 px, on a 300×300 map). 50×28 artwork would fill the
slots edge to edge on 200- and 400-size maps, if you want that look.

The three globals have no OpenSHC names yet; `previewSuppressed`, `multiplayerLayout`
and `mapSize` are ours. They are only read on Crusader 1.41, the build they came from.
