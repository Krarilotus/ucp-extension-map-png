# Credits and third-party provenance

Map PNG is maintained by **Krarilotus**. Credit for the underlying projects and
research remains with their authors; this module does not claim their work.

## Runtime dependencies (installed separately by UCP)

- **Unofficial Crusader Patch team and contributors** — UCP3 framework, extension
  loading and hooks: https://github.com/UnofficialCrusaderPatch/UnofficialCrusaderPatch3
- **gynt and contributors** — UCP `ui`, `cffi` and `luajit` modules. The UI module
  provides native menu definitions, registration and rendering bindings:
  https://github.com/gynt/ucp-extension-ui . The test build uses Krarilotus's
  ui-1.0.1 fix fork; that does not replace the original authorship credit.
  cffi-lua and LuaJIT retain their upstream authorship and licenses in their own
  distributions; their binaries are not bundled in Map PNG.
- **Microsoft** — Windows GDI+ and Win32 APIs used for PNG and Unicode file I/O.
  These are system components, not bundled software.
- **Firefly Studios** — Stronghold Crusader and its original interface artwork,
  fonts, menu implementation and game assets. The extension invokes the installed
  game's routines; it does not distribute standalone game assets. The store's
  documentation preview is an unmodified user-supplied gameplay screenshot
  showing that original interface, not a replacement game asset.

## Adapted code, data and research references

- **Gynt and sourcehold contributors** — map-layer research, tile-coordinate
  translation reference and terrain logic tables:
  https://github.com/sourcehold/sourcehold-maps . `mappng/map/palette.lua` ports
  `sourcehold/tool/memory/map/terrain/logics.py`; the lossless palette changes
  colliding colors. **monsterfish1** is credited for the compatible terrain
  palette. The checked-out repository's LICENSE is GPL version 3, included in
  `licenses/sourcehold-GPL-3.0.txt`. Its setup.py still advertises MIT; do not use
  that conflicting classifier to discard the repository's license notice.
- **OpenSHC/sourcehold contributors** — reverse-engineered native menu layouts,
  calling conventions, map-layer structures and rendering references:
  https://github.com/sourcehold/OpenSHC . GPL version 3 in the inspected checkout;
  no OpenSHC DLL or game executable is bundled.
- **TheRedDaemon** — GDI+ interface-image conversion and pixel-format research in
  https://github.com/UnofficialCrusaderPatch/ucp_gmResourceModifier . Its MIT notice
  is retained in `licenses/gmResourceModifier-MIT.txt`. Map PNG renders its owned
  TGX buffers directly and no longer requires gmResourceModifier at runtime.
  Also credited for `ucp_textResourceModifier`, used as the reference for the
  loaded TextManager language marker and codepage fields:
  https://github.com/UnofficialCrusaderPatch/ucp_textResourceModifier .

## Button artwork

**Monsterfish_** — creator of the four PNG button illustrations (artwork credit
confirmed by Krarilotus). The creator-v2 PNGs were supplied by Krarilotus in
`ucp modding on streoids (2).zip`. Original pixels are preserved in
`resources/icons/creator-v2/`; runtime versions crop transparent padding, scale
2x by nearest-neighbor and threshold alpha for the native TGX format.

Contact **Monsterfish_** for an easy-to-edit offline Photoshop template.

On 2026-09-11, Krarilotus confirmed that Monsterfish_ is involved and that use of
the supplied artwork in this extension's release is approved. This records the
maintainer's confirmation of release permission, not a blanket license for other
uses or a new license for Firefly's original assets. The artwork-permission gate
for this release is resolved; attribution and the template contact remain.

On 2026-09-11, Krarilotus relayed gynt's clarification that sourcehold is GPLv3
and approved GPLv3 for Map PNG's code. See LICENSE and COPYING.md. The conflicting
MIT package classifier is not relied upon. Both licensing gates are resolved.
