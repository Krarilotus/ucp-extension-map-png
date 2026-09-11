import unittest
import lua_harness


class TestPickerLayout(unittest.TestCase):
    def test_list_and_native_scrollbar_stay_inside_modal_and_below_header(self):
        lua = lua_harness.runtime()
        layout = lua_harness.load(lua, "mappng.ui.pickerlayout")
        self.assertGreater(layout.listY - 1, layout.headerBottom)
        self.assertLess(layout.bottom, layout.height - 8)
        self.assertLess(layout.scrollX + layout.scrollWidth, layout.width - 8)
        self.assertEqual(layout.trackY, layout.rowsY + 20)
        self.assertEqual(layout.trackY + layout.trackHeight, layout.bottom - 20)
        self.assertEqual(layout.bottom - layout.rowsY, layout.pageSize * layout.rowHeight)
        self.assertLessEqual(layout.filenameY + 32, layout.statusY)
        self.assertLessEqual(layout.statusY + 18, layout.confirmY)
        self.assertLess(layout.confirmY + layout.buttonHeight, layout.folderY)
        self.assertLess(layout.folderY + layout.buttonHeight, layout.backY)
        self.assertLessEqual(layout.previewY + layout.importPreviewSize, layout.warningY)
        self.assertLess(layout.warningY + 36, layout.filenameY)
        self.assertLess(layout.backY + layout.buttonHeight, layout.height - 8)

    def test_native_scroll_protocol_clamps_drag_arrows_and_empty_lists(self):
        lua = lua_harness.runtime()
        picker = lua_harness.load(lua, "mappng.ui.picker")
        for count in (0, 1, 16, 17, 100):
            model = picker.new("import", "height", "C:/game/mapping",
                               lua.table_from([f"{i}.png" for i in range(count)]), "map_height")
            minimum, maximum, current = (lua.table_from({0: 0}) for _ in range(3))
            def event(code):
                model.nativeScroll(model, code, minimum, maximum, current)
            event(1)
            limit = max(0, count - 16)
            self.assertEqual((minimum[0], maximum[0], current[0]), (0, limit, 0))
            current[0] = 10000
            event(3)
            self.assertEqual((model.offset, current[0]), (limit, limit))
            event(6)
            self.assertEqual(model.offset, limit)
            current[0] = -10
            event(3)
            event(5)
            self.assertEqual(model.offset, 0)
            event(7)
            self.assertEqual(current[0], 15)
            event(4)
            self.assertEqual(current[0], model.offset)
