--- mappng/ui/icons.lua
---
--- Gets the four button graphics into the game's renderer.
---
--- `resources/icons/*.png` are 32x18, 8-bit palette, fully opaque, with the
--- bevel already drawn in -- so the icon is the entire button and nothing needs
--- to be composited underneath it.
---
--- Route: gmResourceModifier converts a PNG into an interface-type resource via
--- WIC (`LoadResourceFromImage`), `SetGm` points a GM image slot at it, and the
--- item's render function draws that slot with `renderGM`.
---
--- NOT YET RESOLVED: which GM slots to use. Needs a pass over the interface GM
--- files for four images that are at least 32x18 and unused on the map editor
--- screens. Until then `available()` returns false and buttons.lua falls back
--- to text labels, which is enough to place and wire the buttons.

local M = {}

M.ICON_FILES = {
  import_heightmap = "ucp/modules/map-png/resources/icons/import_heightmap.png",
  export_heightmap = "ucp/modules/map-png/resources/icons/export_heightmap.png",
  import_textures = "ucp/modules/map-png/resources/icons/import_textures.png",
  export_textures = "ucp/modules/map-png/resources/icons/export_textures.png",
}

--- Short labels used by the text fallback.
M.LABELS = {
  import_heightmap = "H in",
  export_heightmap = "H out",
  import_textures = "T in",
  export_textures = "T out",
}

-- TODO(discovery): { gmID = ..., imageID = ... } per action key.
M.SLOTS = nil

local state = { resources = {}, ready = false }

function M.available()
  return state.ready
end

--- Loads the four PNGs and binds them to their GM slots.
---@return boolean ok
function M.load()
  if M.SLOTS == nil then
    log(WARNING, "map-png: no GM slots assigned for the button icons yet, "
      .. "falling back to text labels")
    return false
  end

  local gm = modules.gmResourceModifier

  for key, path in pairs(M.ICON_FILES) do
    local resourceId = gm:LoadResourceFromImage(path)
    if resourceId == nil or resourceId < 0 then
      log(ERROR, string.format("map-png: could not load icon %s", path))
      M.unload()
      return false
    end
    state.resources[key] = resourceId

    local slot = M.SLOTS[key]
    if not gm:SetGm(slot.gmID, slot.imageID, resourceId, 0) then
      log(ERROR, string.format("map-png: could not bind icon %s to gm %d/%d",
        key, slot.gmID, slot.imageID))
      M.unload()
      return false
    end
  end

  state.ready = true
  return true
end

function M.unload()
  local gm = modules.gmResourceModifier
  for key, resourceId in pairs(state.resources) do
    local slot = M.SLOTS and M.SLOTS[key]
    if slot then
      gm:SetGm(slot.gmID, slot.imageID, -1, -1)
    end
    gm:FreeGm1Resource(resourceId)
  end
  state.resources = {}
  state.ready = false
end

--- The GM slot for an action key, or nil while the fallback is in use.
function M.slot(key)
  if not state.ready then
    return nil
  end
  return M.SLOTS[key]
end

return M
