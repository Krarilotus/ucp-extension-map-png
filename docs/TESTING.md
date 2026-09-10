# Testing the current build

## Install

Close the test game before replacing its module.

```console
python tools/deploy.py "S:/Projects/Harness/test-builds/map-png-test"
```

The unsigned module needs a Developer UCP build and its dependencies from
`definition.yml`. Launch **Stronghold Crusader.exe**, normal 1.41, not Extreme.
The native dialog bindings reject incompatible code.

## Position and artwork regression

Load the test map and open editor map properties. Repeat with singleplayer and
multiplayer map types and each available map size.

- Four distinct glyphs must appear inside native surrounds below the minimap.
- Left to right: import height, export height, import terrain, export terrain.
- The 252px row stays centred below the preview, even when the preview is smaller.
- Leaving, loading another map and returning must not move controls to (0,0).
- Opening a modal must hide the underlying row and block its actions.
- Hover and pressed states must come from the native button renderer.

The read-only probe reports expected icon positions and actual native items:

```console
python tools/probe_running_game.py
```

For a 400×400 map, first icon coordinates relative to the menu origin are
(278,348) in singleplayer and (478,348) in multiplayer. Each inserted control must
have `ucId_0x30 == -1`, nonzero render/action pointers, and a retained terminator.
Inspect `ucp3.log` for callback failures as well as initialization messages.

## Selection and conversion

Follow [the full picker checklist](PICKER_TEST.md). Start with export, which
does not change the map. Choose a fresh name for each layer and inspect the PNGs.
Then import those exports and verify the selected layer matches using the default
lossless palette. Objects/structures are removed; units remain. Cancelled or invalid
imports must not change map layers or remove objects.

Layer-only undo is unavailable after destructive cleanup. Follow the native
cleanup checks in [IMPORT_CLEANUP.md](IMPORT_CLEANUP.md), including occupied-wall
preflight refusal and save/reload checks with multiple types of placed objects.

Finally test the game's ordinary map save/load, including keyboard input and
returning to the properties menu. Check language labels and filename input in
each supported language; offline string coverage does not verify game fonts.

## Release gate

The latest source passes offline regression tests but has not passed this live
checklist. Keep the store PR on hold until the complete flow passes. Coverage of
other map menus remains separate work; see [NATIVE_UI.md](NATIVE_UI.md).
