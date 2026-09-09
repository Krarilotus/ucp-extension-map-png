--- mappng/map/refresh.lua
---
--- Makes the game notice that the layers changed under it.
---
--- `sourcehold` can only nudge the renderer from outside by copying
--- `currentMapOrientation` into `futureMapOrientation`, which forces the map to
--- re-project. Its `post_process_raw_height` -- the block that tried to fix up
--- the logic, misc-display and changed layers by hand -- is commented out in
--- the Python source precisely because getting it right from outside is
--- guesswork.
---
--- Inside the process we can just set the flags the game itself uses:
--- `forceUpdate{LogicalAndMiscDisplayLayers,TextureTilemap,GFXLayers,MacroLayer}`
--- at `TileMapState+0x55486C..+0x554878`.
---
--- NOT YET VERIFIED IN GAME. The offsets are from OpenSHC and the base is
--- cross-checked in tilemap.lua, but which subset of these flags a height
--- import versus a terrain import actually needs is an M1 exit-criterion task.
--- Setting all of them is the conservative choice: worst case it costs one
--- extra frame of work.

local M = {}

--- Marks every tile as changed and asks the game to rebuild its derived layers.
---
---@param view table result of tilemap.open()
---@param options table|nil { changedLayer = boolean }
function M.invalidate(view, options)
  options = options or {}

  local flags = view.flags
  flags.logicalAndMiscDisplay[0] = 1
  flags.textureTilemap[0] = 1
  flags.gfxLayers[0] = 1
  flags.macroLayer[0] = 1

  if options.changedLayer then
    -- sourcehold writes 0x02 across the whole ChangedLayer for this.
    local changed = view.layers.changed
    for tile = 0, 80399 do
      changed[tile] = 2
    end
  end

  -- Re-project the map, which is what actually redraws the minimap preview.
  flags.futureMapOrientation[0] = flags.mapOrientation[0]
end

return M
