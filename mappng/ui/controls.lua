-- Construction contract for module-owned, explicitly positioned menu items.
-- Vanilla Menu::Constructor_Menu sets ucID=-1 for these. Items appended after
-- that constructor MUST do the same: otherwise loadMenuElements resolves the
-- zero-initialized ucID through the vanilla control table and moves them to 0,0.
local M = { TYPE = 3, LAST_ENTRY = 0x66 }

function M.item(bounds, renderAddress, actionAddress, parameter)
  return {
    menuItemType = M.TYPE, ucId_0x30 = -1, menuItemRenderFunctionType = 1,
    position = { position = { x = bounds.x, y = bounds.y } },
    itemWidth = bounds.width, itemHeight = bounds.height,
    callbackParameter = { parameter = parameter or 0 },
    menuItemRenderFunction = { address = renderAddress },
    menuItemActionHandler = { address = actionAddress },
  }
end

function M.verify(item)
  -- Read back the installed ABI field, not just the Lua initializer table.
  -- cffi-lua silently ignores unknown table keys (OpenSHC calls this ucID).
  assert(item.ucId_0x30 == -1, "map-png: native control ID was not initialized")
end

-- SaveMap's header helper at 0x475CC0 uses font ID 15, alignment 1,
-- colour 0xC2F0EB and a centred baseline offset of 22 from the modal top.
-- Font IDs index TextManager.fontSizeClassArray[20]; they are NOT pixel sizes.
function M.dialogHeading(rendering, banner, label, x, y, width)
  -- The native routine applies its own 8px inset and fixed 64px artwork.
  banner(rendering.pencilRenderCore, x, y, width, 64)
  rendering.renderTextToScreenConst(rendering.textManager, label,
    x + width // 2, y + 22, 1, 0xC2F0EB, 15, false, 0)
end

function M.onMenuSurface(rendering, fn)
  local previous = rendering.pDrawBufferChoiceValue[0]
  rendering.pDrawBufferChoiceValue[0] = 0 -- RT_SCREEN_MENU, not RT_MAP_GAME (1)
  local ok, err = pcall(fn)
  rendering.pDrawBufferChoiceValue[0] = previous
  if not ok then error(err, 0) end
end

return M
