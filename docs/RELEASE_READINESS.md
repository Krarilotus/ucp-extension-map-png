# 0.2.0 release candidate

Refresh, per-map sidecar links, selective cleanup and updated localized warnings
are implemented. 139 automated tests pass at the initial integration checkpoint;
native AoB discovery is checked with UCP's real helper against normal and Extreme
executables. The existing UI still requires its UCP 1.0.1 dependency.

Live acceptance remains open: computer-use's native pipe failed twice on
2026-09-20. Do not merge the Store PR or call this build live-tested until map
load/save/restart links, missing-file refresh, populated maps, connected keeps,
farms, units, rubble and both menu layouts pass. The current store screenshot is
from 0.1.x and shows the original four controls, not the new refresh row.

## Historical 0.1.2 handoff

Completed: unique module/package version; action/folder/back order; nine concise
store descriptions with localized warning and image alt text; one real editor
screenshot; existing runtime language selection and third-party notices.
The screenshot shows the editor button row, not the changed picker layout.
UCP GUI's Markdown image renderer uses max-width: 100%, so the 526x404 preview
fits the description pane without added HTML or duplicated instructions.

Local tests cover all nine store locales and eleven runtime label sets, but are
not native-language proofreading or visual font acceptance.

## Release status

- Krarilotus accepted existing testing and waived another live run solely for
  the button-order change. No additional automated live test is claimed.
  Cross-PC/font and comprehensive cleanup save/reload coverage are not independently
  established; retain those limitations when describing validation.
- GPLv3 approved by Krarilotus after relaying gynt's clarification; LICENSE and
  COPYING.md record it and retain the sourcehold GPL notice.
  Artwork permission for this release was confirmed by Krarilotus on 2026-09-11;
  see CREDITS.md. It is no longer an open release gate.
- The store 3.0.7 merge triggers build/sign/release; verify published assets.
- Upstream UI PR gynt/ucp-extension-ui#6 remains open. The store currently pins
  the existing UI 1.0.1 fix fork. Switch back to gynt's equivalent after release;
  a maintainer may approve the temporary fork independently.

Extreme support and menus outside editor properties are not advertised features
of this release. Do not imply that importing arbitrary populated maps is verified
safe until the live matrix passes. If native postconditions fail, cleanup may
already have removed objects even though the PNG itself is not applied.
