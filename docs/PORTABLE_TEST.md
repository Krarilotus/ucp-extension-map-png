# Portable test installation

Target: normal **Stronghold Crusader 1.41**, with **UCP 3.0.7 Developer**.
This is an unsigned test module, not a complete game or framework installer.
Do not install over your only copy of important maps.

1. Close the game. Place `map-png-0.1.0.zip` directly in `<game>/ucp/modules/`.
   Do not extract it and do not put the ZIP inside another map-png directory.
   Move aside any older unpacked `map-png-0.1.0` folder or same-version ZIP first.
2. Install the dependencies: `ui` 1.0.1, `cffi` 1.0.0 and `luajit` 1.0.0.
   UI test build: https://github.com/Krarilotus/ucp-extension-ui/releases/tag/test-d3a807cfee70
   Its own dependencies must also be satisfied. The UCP launcher normally handles
   dependencies for store-installed extensions; this prerelease is not yet in it.
3. Enable Map PNG in the UCP configuration. Copying a ZIP only makes it available;
   it does not activate a module. In an existing manually managed `ucp-config.yml`,
   merge these entries (do not replace your entire configuration):

   ```yaml
   # Under config-full -> modules:
   map-png:
     config: {}

   # In load-order, AFTER luajit, cffi and ui:
   - extension: map-png
     version: 0.1.0
   ```

   Preserve the file's existing `config-sparse`/`config-full` arrangement. If they
   are independent rather than YAML aliases, keep the module selection consistent.
4. Start `Stronghold Crusader.exe`, not Extreme. Open the test map in the editor's
   scenario or multiplayer properties screen. `mapping/` is created automatically.
5. Export height and terrain to fresh names. Select the resulting PNGs for import.
   Check the native heading, preview, list bounds, scrollbar and overwrite prompt.
   Check invasion height buttons, returning after map load, and ordinary map save.

No Python, sourcehold installation, external conversion executable, or artwork
download is needed on the test PC. Runtime files and icons are inside the ZIP.

**Secure builds:** this unsigned ZIP is not a signed store release. Do not disable
signature checks or fabricate a `.sig`. Wait for maintainer review and the store's
signing pipeline for ordinary secure-build installation.

**Verification status:** offline tests and local exports/import-height succeeded
during development. The latest scrollbar, invasion-click and language refinements
still need full live acceptance; cross-PC operation has not been established.
Coverage is editor properties (menu 17), not every map-selection/gameplay menu.
Report game/UCP versions, game language, screenshots and relevant `ucp3.log` errors.
See CREDITS.md for attribution and open release-license checks.
