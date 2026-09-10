"""Installing the buttons must leave menu 17's item list intact.

The first in-game run crashed on entering the editor: buttons.lua used
Menu:addMenuItem on an existing game menu, which overwrote the LAST_ENTRY
terminator, and the game walked off the end of the list.

The fake Menu below reproduces the ui-1.0.1 module's own Menu methods
(fromPointer's index setup, reallocateMenuItems, insertMenuItem,
addMenuItem) closely enough to show that difference, over a menu shaped like
the real menu 17: 15 items read out of the exe, then the terminator.
"""

import unittest

import lua_harness

# menuItemType of menu 17's items, as read from 0x005EE898.
MENU_17_TYPES = [
    0x00000006, 0x01000000, 0x02000003, 0x01000000, 0x02000002, 0x02000002,
    0x02000003, 0x02000003, 0x02000003, 0x02000003, 0x02000003, 0x02000003,
    0x02000003, 0x02000003, 0x02000003,
]

FAKE_UI = r"""
local LAST = 0x66

local function copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = copy(v) end
  return c
end

local Menu = {}
Menu.__index = Menu

-- ui-1.0.1 Menu:fromPointer: count and write index both at the terminator.
function Menu.fromTypes(types)
  local items = {}
  for i, t in ipairs(types) do
    items[i - 1] = { menuItemType = t, position = { position = { x = 0, y = 0 } } }
  end
  items[#types] = { menuItemType = LAST }
  return setmetatable({
    menuItems = items, menuItemsCount = #types, menuItemsIndex = #types, menu = {},
  }, Menu)
end

-- ui-1.0.1 Menu:reallocateMenuItems: double, zero-fill, mark 0..oldCount as
-- LAST_ENTRY, copy the old items over 0..oldCount-1.
function Menu:reallocateMenuItems()
  local oldCount, newCount = self.menuItemsCount, self.menuItemsCount * 2
  local new = {}
  for i = 0, newCount - 1 do new[i] = { menuItemType = 0 } end
  for i = 0, oldCount do new[i].menuItemType = LAST end
  for i = 0, oldCount - 1 do new[i] = copy(self.menuItems[i]) end
  self.menuItems, self.menuItemsCount = new, newCount
end

-- ui-1.0.1 Menu:insertMenuItem: shift index..writeIndex down one, then write.
function Menu:insertMenuItem(index, params)
  if self.menuItemsIndex >= self.menuItemsCount then self:reallocateMenuItems() end
  for i = self.menuItemsIndex, index, -1 do
    self.menuItems[i + 1] = copy(self.menuItems[i])
  end
  self.menuItems[index] = copy(params)
  self.menuItems[index].menuPointer = self.menu
  self.menuItemsIndex = self.menuItemsIndex + 1
end

-- ui-1.0.1 Menu:addMenuItem: write fields into the slot at the write index.
function Menu:addMenuItem(params)
  if self.menuItemsIndex >= self.menuItemsCount then self:reallocateMenuItems() end
  local item = self.menuItems[self.menuItemsIndex]
  item.menuPointer = self.menu
  for k, v in pairs(params) do item[k] = copy(v) end
  self.menuItemsIndex = self.menuItemsIndex + 1
  return self
end

fakeMenus = {}
Menu.fromID = function(_, id)
  local m = Menu.fromTypes(menu17Types)
  fakeMenus[id] = m
  return m
end

modules = { ui = { access = function() return { api = { ui = { Menu = Menu } } } end } }
INFO, WARNING, ERROR = "INFO", "WARNING", "ERROR"
logged = {}
log = function(level, message) logged[#logged + 1] = level .. " " .. message end

-- cffi stand-in: callbacks become opaque numbers, "unsigned long" casts pass through.
local nextHandle = 0x10000
fakeFfi = {
  cast = function(ctype, value)
    if type(value) == "function" then nextHandle = nextHandle + 4 return nextHandle end
    return value
  end,
}
"""


class TestButtonsInstall(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        types = self.lua.table_from({i + 1: t for i, t in enumerate(MENU_17_TYPES)})
        self.lua.globals().menu17Types = types
        self.lua.execute(FAKE_UI)
        self.buttons = lua_harness.load(self.lua, "mappng.ui.buttons")

    def install(self):
        g = self.lua.globals()
        added = self.buttons.install(g.fakeFfi, self.lua.table(), lambda mode, what: None)
        return added, g.fakeMenus[17]

    def walk(self, menu):
        """What the game sees: item types up to the first LAST_ENTRY, or None."""
        types = []
        for i in range(0, 200):
            item = menu["menuItems"][i]
            if item is None:
                return None  # ran off the end of the array without a terminator
            if item["menuItemType"] == 0x66:
                return types
            types.append(item["menuItemType"])
        return None

    def test_installs_four_buttons(self):
        added, _ = self.install()
        self.assertEqual(added, 4)
        errors = [m for m in self.lua.globals().logged.values() if m.startswith("ERROR")]
        self.assertEqual(errors, [])

    def test_item_list_stays_terminated(self):
        _, menu = self.install()
        types = self.walk(menu)
        self.assertIsNotNone(types, "menu 17 lost its LAST_ENTRY terminator")
        self.assertEqual(types[:15], MENU_17_TYPES, "the game's own items were disturbed")
        self.assertEqual(len(types), 19)

    def test_buttons_are_standalone_items(self):
        """No interaction-group flag, or MainButtons would render them."""
        _, menu = self.install()
        ours = [menu["menuItems"][i] for i in range(15, 19)]
        for item in ours:
            self.assertEqual(item["menuItemType"], 0x3)
            self.assertEqual(item["menuItemType"] & 0x03000000, 0)
            self.assertNotEqual(item["menuItemRenderFunction"]["address"], 0)
            self.assertNotEqual(item["menuItemActionHandler"]["address"], 0)

    def test_recorded_indices_point_at_our_items(self):
        _, menu = self.install()
        for entry in self.buttons.installed().values():
            item = menu["menuItems"][entry["itemIndex"]]
            self.assertEqual(item["callbackParameter"]["parameter"], entry["actionIndex"])

    def test_reposition_moves_our_items_only(self):
        _, menu = self.install()
        screen = self.buttons.installed()[1]["screen"]
        screen["offset"] = self.lua.table(x=5, y=7)
        self.assertEqual(self.buttons.reposition(17), 4)
        self.assertEqual(menu["menuItems"][15]["position"]["position"]["x"], 309 + 5)
        self.assertEqual(menu["menuItems"][15]["position"]["position"]["y"], 348 + 7)
        self.assertEqual(menu["menuItems"][14]["position"]["position"]["x"], 0)

    def test_addMenuItem_would_have_broken_the_menu(self):
        """Pins the root cause, so nobody switches back to addMenuItem."""
        Menu = self.lua.eval("modules.ui.access().api.ui.Menu")
        menu = Menu.fromTypes(self.lua.globals().menu17Types)
        for _ in range(4):
            menu.addMenuItem(menu, self.lua.table(menuItemType=0x3))
        self.assertIsNone(self.walk(menu), "addMenuItem left a terminator after all?")


if __name__ == "__main__":
    unittest.main()
