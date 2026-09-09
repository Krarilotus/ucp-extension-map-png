--- mappng/ui/filedialog.lua
---
--- The vanilla-styled PNG picker.
---
--- NOT IMPLEMENTED YET -- this is milestone M6. Until it lands, `pick()` falls
--- straight through to a default file name so the buttons work end to end and
--- M4 can be validated on its own.
---
--- The plan for the real thing:
---
--- * One `ModalMenu` built with `modules.ui:access().api.ui.ModalMenu`, reused
---   for all four actions, with `borderStyle = 512` for the red double border.
---   Laid out like the game's Save dialog: title bar, name field on the left in
---   save mode, scrollable name list on the right, confirm and back buttons.
---
--- * The file list comes from `ResourceManager::discoverMapFiles` at
---   `0x00477EE0`. It takes a glob, `FindFirstFileA`s it, truncates each name at
---   the first dot and sorts the result into `loadedMapNames`/`mapFileCounter`.
---   Calling it with `mapping\*.png` gives a sorted PNG list in the game's own
---   format for free.
---
---   Caveat: it fills the shared ResourceManager map list, so the surrounding
---   state has to be snapshotted and restored or the real map browser will show
---   PNG names. If that turns out to be entangled, do our own FindFirstFileA
---   loop over the FFI instead -- about thirty lines, and it leaves the vanilla
---   list alone.
---
--- * Save mode reuses `MenuTextInputState` for the name field.
---
--- * Modal IDs are allocated through the ui module's manager
---   (`manager.getAvailableMenuID`) rather than reusing SAVE_MAP (10) or
---   LOAD_MAP (9), so the real map save/load path is never touched.

local actions = require("mappng.actions")

local M = {}

M.implemented = false

--- Asks the user for a file name.
---
---@param mode string "import" or "export"
---@param what string "height" or "terrain"
---@param currentMapName string|nil
---@param callback fun(name:string|nil) called with nil if the user cancels
function M.pick(mode, what, currentMapName, callback)
  if not M.implemented then
    local name = actions.defaultName(currentMapName, what)
    log(WARNING, string.format(
      "map-png: the file dialog is not implemented yet, using '%s.png' in %s",
      name, actions.folder()))
    callback(name)
    return
  end

  error("map-png: filedialog.pick reached an unimplemented path")
end

return M
