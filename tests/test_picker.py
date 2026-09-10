"""PNG selection must never fall through to an unchosen default import."""
import unittest
import lua_harness


class TestPicker(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.picker = lua_harness.load(self.lua, "mappng.ui.picker")
        self.paths = lua_harness.load(self.lua, "mappng.paths")

    def model(self, mode="import", names=("z.png", "a.PNG", "map.map", "../bad.png")):
        return self.picker.new(mode, "height", "C:\\game\\mapping",
                               self.lua.table_from(names), "map_height")

    def test_import_starts_without_a_selection(self):
        p = self.model()
        self.assertEqual(p.name, "")
        self.assertEqual(p.confirm(p, lambda _: True), (None, "invalid_name"))

    def test_only_pngs_and_safe_names_are_listed_in_sorted_order(self):
        self.assertEqual(list(self.model().names.values()), ["a.PNG", "z.png"])

    def test_selection_preserves_original_filename_and_extension(self):
        p = self.model()
        self.assertEqual(p.select(p, 1), "a.PNG")
        self.assertEqual(p.confirm(p, lambda _: True), "a.PNG")

    def test_deleted_selection_does_not_import(self):
        p = self.model()
        p.select(p, 1)
        self.assertEqual(p.confirm(p, lambda _: False), (None, "missing_file"))

    def test_export_accepts_a_new_name(self):
        p = self.model("export")
        p.edit(p, "new landscape")
        self.assertEqual(p.confirm(p, lambda _: False), "new landscape")

    def test_existing_export_requires_second_confirmation(self):
        p = self.model("export")
        self.assertEqual(p.confirm(p, lambda _: True), (None, "overwrite"))
        self.assertEqual(p.confirm(p, lambda _: True), "map_height")

    def test_editing_or_selecting_resets_overwrite_confirmation(self):
        p = self.model("export")
        p.confirm(p, lambda _: True)
        p.edit(p, "different")
        self.assertEqual(p.confirm(p, lambda _: True), (None, "overwrite"))
        p.select(p, 1)
        self.assertEqual(p.confirm(p, lambda _: True), (None, "overwrite"))

    def test_scrolling_cannot_go_outside_list(self):
        p = self.model(names=tuple(f"{i:03}.png" for i in range(40)))
        p.scroll(p, 100)
        self.assertEqual(p.offset, 24)
        self.assertEqual(p.select(p, 16), "039.png")
        p.scroll(p, -100)
        self.assertEqual(p.offset, 0)

    def test_unsafe_or_reserved_names_are_rejected(self):
        for name in ("", ".png", "..", "../map", "C:map", "a\\b", "a/b",
                     "a*", "a?", 'a"', "a<", "a>", "a|", "a\x00b", "a\n",
                     "map.", "map ", "CON", "nul.png", "COM1.png", "LPT9"):
            with self.subTest(name=name):
                p = self.model("export")
                p.edit(p, name)
                self.assertEqual(p.confirm(p, lambda _: False), (None, "invalid_name"))

    def test_png_extension_is_added_once(self):
        self.assertEqual(self.paths.resolve("mapping", "Map.PNG"), "mapping\\Map.PNG")
        self.assertEqual(self.paths.resolve("mapping", "Map"), "mapping\\Map.png")

    def test_utf8_filename_is_preserved(self):
        self.assertEqual(self.paths.resolve("mapping", "Höhenkarte"), "mapping\\Höhenkarte.png")
