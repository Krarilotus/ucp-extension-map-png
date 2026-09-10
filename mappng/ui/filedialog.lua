-- The four operations share one native-styled PNG picker, not fixed paths.
local actions = require("mappng.actions")
local native = require("mappng.ui.nativepicker")
local M = { implemented = true }

function M.initialize(ffi, ui, png)
  native.initialize(ffi, ui.game, ui.manager, png)
end

function M.update() native.update() end
function M.cancel() native.cancel() end

function M.pick(mode, what, currentMapName, callback)
  native.open(mode, what, actions.folder(), actions.defaultName(currentMapName, what), callback)
end

return M
