# Changelog

## 0.1.1 test prerelease — 2026-09-11

- Put Import/Export first, Open folder second, and Back last in all four PNG
  submenus. Shared layout and native control order remain consistent.
- Package filenames now follow the module version in definition.yml.
- Nine concise localized store descriptions include the destructive import
  warning and one editor preview with localized alternative text.

## 0.1.0 test.4 — 2026-09-10

- Fix imports after entering map view on an empty map: the native building scan
  limit legitimately becomes zero. Keep allocation bounds and reject zero limits
  with active records. No cleanup checks are bypassed.
- Regression covers initial state, map-view transition, repeated imports and
  invalid/inconsistent limits. Native live acceptance remains pending.

## 0.1.0 test.3 — 2026-09-10

- Both PNG imports stage conversion before native structure/object cleanup.
- Reuse building, tree, rock and wall/decoration teardown; preserve units.
- Refuse occupied wall/decoration tiles before deletion; check remaining
  footprints before committing the PNG. Invalidate unsafe layer-only undo.
- Short localized deletion warning. Native live save/reload acceptance pending.

## 0.1.0 test.2 — 2026-09-10

- Remove customization-menu controls; module activation uses the existing defaults.
- Add localized Open folder above the picker confirmation/back buttons.
- Keep status text, filename and buttons in separate layout bounds.
- Warn in both import dialogs about bugs with placed objects and structures.
  Do not silently delete entities or claim layer snapshots are full-map backups.
- Extreme remains optional/unimplemented for native UI. Sourcehold and this
  module's map-layer reader recognize it, but that does not establish UI support.
- Automatic object/structure removal is still pending; units must be preserved.
  Test imports on disposable maps only. This build does not promise safe imports
  into populated maps.

## 0.1.0 test prerelease — 2026-09-10

- Four native-framed editor buttons for PNG height/terrain import and export.
- PNG file selection, editable export names, previews and overwrite confirmation.
- Native scrollbar, arrows, bounded filenames and centered action headings.
- Preserve native terminators, callback addresses and explicit control positions.
- Prioritize button hit targets over invisible vanilla controls in invasion layout.
- Reuse loaded game language/codepage; nine UCP locales plus Italian/Polish runtime labels.
- Include Monsterfish_ artwork credit, Photoshop-template contact note and third-party notices.
- Standalone unsigned module ZIP with portable test instructions; no external converter.

### Verification and limitations

99 offline tests pass locally. Local development logs show successful height/terrain
exports and height import. Latest UI/language refinements and another-PC operation
still require live acceptance. Only normal Crusader 1.41 editor properties (menu 17)
are integrated. Not a signed secure-build release; dependency activation is required.
Stable publication also awaits the attribution/license checks listed in CREDITS.md.
