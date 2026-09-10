"""Installing the buttons must leave menu 17's item list intact, and running
their callbacks must never raise into the game.

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

-- cffi-lua stand-in. Like the real thing on stock Lua 5.4, a scalar cast
-- returns a cdata that the built-in tonumber cannot read (it returns nil);
-- only ffi.tonumber converts it. The Lua function behind each callback stays
-- callable for tests, keyed by its address.
local nextHandle = 0x10000
local Cdata = {}
fakeCallbacks = {}
fakeFfi = {
  cast = function(ctype, value)
    if type(value) == "function" then
      nextHandle = nextHandle + 4
      fakeCallbacks[nextHandle] = value
      return setmetatable({ handle = nextHandle }, Cdata)
    end
    if getmetatable(value) == Cdata then
      return setmetatable({ handle = value.handle }, Cdata)
    end
    return value
  end,
  tonumber = function(value)
    if getmetatable(value) == Cdata then return value.handle end
    return tonumber(value)
  end,
}
-- The same, minus ffi.tonumber: what the buttons would see if it were missing.
fakeFfiWithoutTonumber = { cast = fakeFfi.cast }
assert(tonumber(fakeFfi.cast("unsigned long", fakeFfi.cast("t", function() end))) == nil,
  "the stand-in must reproduce cffi-lua: plain tonumber cannot read a cdata")

-- A game whose rendering layer blows up on first touch.
brokenGame = { Rendering = setmetatable({}, { __index = function() error("boom") end }) }

-- A game whose rendering layer records what it was asked to draw.
drawn = {}
workingGame = { Rendering = {
  ButtonState = { x = 274, y = 343, width = 60, height = 32, interacting = 0 },
  pDrawBufferChoiceValue = { [0] = 1 },
  textManager = "tm", textureRenderCore = "trc",
  renderTextToScreenConst = function(tm, text, x, y) drawn[#drawn + 1] = { text = text, x = x, y = y } end,
  renderGM = function() end,
  renderButtonBackground = function() end,
} }
"""


class ButtonsBase(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        types = self.lua.table_from({i + 1: t for i, t in enumerate(MENU_17_TYPES)})
        self.lua.globals().menu17Types = types
        self.lua.execute(FAKE_UI)
        self.buttons = lua_harness.load(self.lua, "mappng.ui.buttons")
        self.clicks = []

    def install(self, game=None, on_click=None):
        g = self.lua.globals()
        on_click = on_click or (lambda mode, what: self.clicks.append((mode, what)))
        added = self.buttons.install(g.fakeFfi, game or g.workingGame, on_click)
        return added, g.fakeMenus[17]

    def logged(self, level):
        return [m for m in self.lua.globals().logged.values() if m.startswith(level)]

    def callback(self, menu, index, field):
        address = menu["menuItems"][index][field]["address"]
        return self.lua.globals().fakeCallbacks[address]


class TestButtonsInstall(ButtonsBase):
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
        self.assertEqual(self.logged("ERROR"), [])

    def test_reenable_does_not_duplicate_native_items(self):
        _, menu = self.install()
        before = self.walk(menu)
        self.buttons.disable()
        self.callback(menu, 0, "menuItemActionHandler")(1)
        self.callback(menu, 0, "menuItemRenderFunction")(1)
        self.assertEqual(self.clicks, [])
        self.assertEqual(len(self.lua.globals().drawn), 0)
        added, _ = self.install()
        self.assertEqual(added, 4)
        self.assertEqual(self.walk(menu), before)
        self.callback(menu, 0, "menuItemActionHandler")(1)
        self.assertEqual(self.clicks, [("import", "height")])

    def test_item_list_stays_terminated(self):
        _, menu = self.install()
        types = self.walk(menu)
        self.assertIsNotNone(types, "menu 17 lost its LAST_ENTRY terminator")
        self.assertEqual(types[4:], MENU_17_TYPES, "the game's own items were disturbed")
        self.assertEqual(len(types), 19)

    def test_buttons_are_standalone_items(self):
        """No interaction-group flag, or MainButtons would render them."""
        _, menu = self.install()
        for i in range(0, 4):
            item = menu["menuItems"][i]
            self.assertEqual(item["menuItemType"], 0x3)
            self.assertEqual(item["menuItemType"] & 0x03000000, 0)
            self.assertNotEqual(item["menuItemRenderFunction"]["address"], 0)
            self.assertNotEqual(item["menuItemActionHandler"]["address"], 0)

    def test_native_menu_reload_does_not_replace_our_positions(self):
        _, menu = self.install()
        for i in range(0, 4):
            item = menu["menuItems"][i]
            original = (item.position.position.x, item.position.position.y)
            # Menu::loadMenuElements at 0x4F69D0 resolves ucID >= 0 through
            # the vanilla layout table. Zero-initialized appended items broke.
            self.assertEqual(item.ucId_0x30, -1)
            for _ in range(3):
                if (item.ucId_0x30 or 0) >= 0:
                    item.position.position.x = item.position.position.y = 0
            self.assertEqual((item.position.position.x, item.position.position.y), original)

    def test_invisible_vanilla_sp_hitboxes_do_not_swallow_height_clicks(self):
        _, menu = self.install()
        # Original menu17 items 2 and 9 remain hit-testable in SP despite
        # their group renderer omitting them. These are measured native bounds.
        for original, x, y, w, h in [(2, 50, 100, 365, 280), (9, 270, 342, 120, 30)]:
            item = menu.menuItems[original + 4]
            item.position.position.x, item.position.position.y = x, y
            item.itemWidth, item.itemHeight = w, h
        for action in range(4):
            item = menu.menuItems[action]
            x = item.position.position.x + item.itemWidth // 2
            y = item.position.position.y + item.itemHeight // 2
            hits = []
            for index in range(19):
                target = menu.menuItems[index]
                p = target.position.position
                if p.x <= x < p.x + (target.itemWidth or 0) and p.y <= y < p.y + (target.itemHeight or 0):
                    hits.append(index)
            self.assertEqual(hits[0], action, 'native traversal stops at first hit')
            if action < 2:
                self.assertIn(6, hits, 'fixture must reproduce the hidden overlap')
            self.callback(menu, hits[0], "menuItemActionHandler")(action + 1)
        self.assertEqual(self.clicks, [("import", "height"), ("export", "height"),
                                      ("import", "terrain"), ("export", "terrain")])

    def test_install_logs_what_the_game_will_read(self):
        self.install()
        items = [m for m in self.logged("INFO") if "map-png: item [" in m]
        self.assertEqual(len(items), 4)
        self.assertIn("type=0x3", items[0])

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
        self.assertEqual(menu["menuItems"][0]["position"]["position"]["x"], 274 + 5)
        self.assertEqual(menu["menuItems"][0]["position"]["position"]["y"], 343 + 7)
        self.assertEqual(menu["menuItems"][18]["position"]["position"]["x"], 0)

    def test_addMenuItem_would_have_broken_the_menu(self):
        """Pins the root cause, so nobody switches back to addMenuItem."""
        Menu = self.lua.eval("modules.ui.access().api.ui.Menu")
        menu = Menu.fromTypes(self.lua.globals().menu17Types)
        for _ in range(4):
            menu.addMenuItem(menu, self.lua.table(menuItemType=0x3))
        self.assertIsNone(self.walk(menu), "addMenuItem left a terminator after all?")


class TestCallbacksNeverRaise(ButtonsBase):
    def test_original_artwork_matches_all_four_actions_inside_native_buttons(self):
        self.lua.execute('''
          local icons = require("mappng.ui.icons")
          icons.available = function() return true end
          chrome, pictures = {}, {}
          workingGame.Rendering.renderButtonBackground = function(_, blend, target)
            chrome[#chrome+1] = {blend=blend, target=target}
          end
          icons.draw = function(key, rendering, x, y)
            assert(rendering.pDrawBufferChoiceValue[0] == 0)
            pictures[#pictures+1] = {key=key, x=x, y=y}
          end
        ''')
        _, menu = self.install()
        expected = [("import_heightmap", "import", "height"),
                    ("export_heightmap", "export", "height"),
                    ("import_textures", "import", "terrain"),
                    ("export_textures", "export", "terrain")]
        for i, (key, mode, what) in enumerate(expected):
            self.callback(menu, i, "menuItemRenderFunction")(i+1)
            self.callback(menu, i, "menuItemActionHandler")(i+1)
            pic = self.lua.globals().pictures[i+1]
            self.assertEqual((pic.key, pic.x, pic.y), (key, 278, 348))
        self.assertEqual(self.clicks, [(mode, what) for _, mode, what in expected])
        self.assertEqual(len(self.lua.globals().chrome), 4)
        self.assertEqual(len(self.lua.globals().drawn), 0, "artwork was replaced by text")
        self.assertEqual(self.logged("ERROR"), [])

    def test_render_failure_restores_the_callers_drawing_surface(self):
        self.lua.execute('''
          workingGame.Rendering.pDrawBufferChoiceValue[0] = 2
          workingGame.Rendering.renderButtonBackground = function() error("draw failed") end
        ''')
        _, menu = self.install()
        self.callback(menu, 0, "menuItemRenderFunction")(1)
        self.assertEqual(self.lua.globals().workingGame.Rendering.pDrawBufferChoiceValue[0], 2)
        self.assertTrue(any("draw failed" in m for m in self.logged("ERROR")))

    def test_render_draws_the_label(self):
        _, menu = self.install()
        self.callback(menu, 0, "menuItemRenderFunction")(1)
        drawn = list(self.lua.globals().drawn.values())
        self.assertEqual(len(drawn), 1)
        self.assertEqual(drawn[0]["text"], "H in")
        self.assertEqual(self.logged("ERROR"), [])

    def test_render_error_is_contained_and_logged(self):
        g = self.lua.globals()
        _, menu = self.install(game=g.brokenGame)
        render = self.callback(menu, 0, "menuItemRenderFunction")
        for _ in range(10):
            render(1)  # must not raise into the caller -- that caller is the game
        errors = self.logged("ERROR")
        self.assertEqual(len(errors), self.buttons.LOGGED_FAILURES, "failures not rate-limited")
        self.assertIn("boom", errors[0])
        self.assertIn("render import_heightmap", errors[0])

    def test_step_markers_stop_after_the_first_calls(self):
        _, menu = self.install()
        render = self.callback(menu, 0, "menuItemRenderFunction")
        for _ in range(10):
            render(1)
        markers = [m for m in self.logged("INFO") if "[render import_heightmap #" in m]
        self.assertTrue(markers, "no step markers logged")
        self.assertTrue(all("#%d]" % n in "".join(markers) for n in (1, 2, 3)))
        self.assertFalse(any("#4]" in m for m in markers), "markers not limited")
        self.assertIn("calling renderTextToScreenConst", "".join(markers))

    def test_click_runs_the_action(self):
        _, menu = self.install()
        self.callback(menu, 1, "menuItemActionHandler")(2)
        self.assertEqual(self.clicks, [("export", "height")])

    def test_click_error_is_contained(self):
        def explode(mode, what):
            raise RuntimeError("action exploded")
        _, menu = self.install(on_click=explode)
        self.callback(menu, 0, "menuItemActionHandler")(1)
        self.assertTrue(any("click import_heightmap failed" in m for m in self.logged("ERROR")))


if __name__ == "__main__":
    unittest.main()
