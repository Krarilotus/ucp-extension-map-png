"""The game must never be handed a NULL function pointer.

The second in-game crash faulted at offset 0x00000000: the game called our
render function through an address of 0. buttons.lua had converted the
callback address with Lua's built-in tonumber, which on stock Lua 5.4 cannot
read a cffi-lua cdata and returns nil, leaving the field zero.
"""

import unittest

from test_buttons import ButtonsBase, MENU_17_TYPES


class TestCallbackAddresses(ButtonsBase):
    def test_every_item_gets_a_real_address(self):
        _, menu = self.install()
        callbacks = self.lua.globals().fakeCallbacks
        for i in range(15, 19):
            item = menu["menuItems"][i]
            for field in ("menuItemRenderFunction", "menuItemActionHandler"):
                address = item[field]["address"]
                self.assertIsInstance(address, int, "%s of item %d is not a number" % (field, i))
                self.assertNotEqual(address, 0, "%s of item %d is NULL" % (field, i))
                self.assertIsNotNone(callbacks[address], "%s of item %d points nowhere" % (field, i))

    def test_without_ffi_tonumber_the_menu_is_left_alone(self):
        g = self.lua.globals()
        added = self.buttons.install(g.fakeFfiWithoutTonumber, g.workingGame,
                                     lambda mode, what: None)
        self.assertEqual(added, 0)

        menu = g.fakeMenus[17]
        types = []
        i = 0
        while menu["menuItems"][i]["menuItemType"] != 0x66:
            types.append(menu["menuItems"][i]["menuItemType"])
            i += 1
        self.assertEqual(types, MENU_17_TYPES, "menu 17 was modified despite the failure")

        errors = self.logged("ERROR")
        self.assertTrue(any("no function address" in m for m in errors), errors)


if __name__ == "__main__":
    unittest.main()
