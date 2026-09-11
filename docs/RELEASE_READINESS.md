# 0.1.1 release handoff

Completed: unique module/package version; action/folder/back order; nine concise
store descriptions with localized warning and image alt text; one real editor
screenshot; existing runtime language selection and third-party notices.
The screenshot shows the editor button row, not the changed picker layout.
UCP GUI's Markdown image renderer uses max-width: 100%, so the 526x404 preview
fits the description pane without added HTML or duplicated instructions.

Local tests cover all nine store locales and eleven runtime label sets, but are
not native-language proofreading or visual font acceptance.

## Remaining gates

- Live testing: dedicated normal-game 0.1.1 installation is prepared. Startup
  stops at UCP's developer-mode security consent dialog; the user must handle
  that prompt. No live acceptance is claimed for this build.
- Test empty-map entry/return/import and populated-map cleanup, unit preservation,
  save/reload, both editor layouts and the swapped picker buttons. Cross-PC
  installation/activation and native font rendering also require acceptance.
- Record the module's release license;
  retain sourcehold GPL notice and review its conflicting MIT package metadata.
  Artwork permission for this release was confirmed by Krarilotus on 2026-09-11;
  see CREDITS.md. It is no longer an open release gate.
- Store maintainers must review, build/sign and merge the draft 3.0.7 PR.
- Upstream UI PR gynt/ucp-extension-ui#6 remains open. The store currently pins
  the existing UI 1.0.1 fix fork. Switch back to gynt's equivalent after release;
  a maintainer may approve the temporary fork independently.

Extreme support and menus outside editor properties are not advertised features
of this release. Do not imply that importing arbitrary populated maps is verified
safe until the live matrix passes. If native postconditions fail, cleanup may
already have removed objects even though the PNG itself is not applied.
