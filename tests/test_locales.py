"""Keep descriptions and every visible option complete in all UCP languages."""
import pathlib
import re
import unittest
import xml.etree.ElementTree as ET
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
LANGUAGES = {"en", "de", "fr", "ru", "hu", "tr", "ch", "es", "fa"}


class TestLocales(unittest.TestCase):
    def test_all_gui_languages_have_all_used_keys_and_a_short_description(self):
        options = (ROOT / "options.yml").read_text(encoding="utf-8")
        keys = set(re.findall(r"{{([^}]+)}}", options))
        self.assertEqual({p.stem for p in (ROOT / "locale").glob("*.yml")}, LANGUAGES)
        for lang in LANGUAGES:
            text = (ROOT / "locale" / (lang + ".yml")).read_text(encoding="utf-8")
            locale = yaml.safe_load(text)
            self.assertEqual(set(locale), keys, lang)
            self.assertTrue(all(isinstance(v, str) and v.strip() for v in locale.values()), lang)
            description = (ROOT / "locale" / ("description-" + lang + ".md")).read_text(encoding="utf-8")
            self.assertLess(len(description), 550, lang)
            self.assertIn("mapping/map_height.png", description)
            self.assertIn("mapping/map_tex.png", description)
            self.assertNotIn("\ufffd", text + description)

    def test_options_use_the_gui_schema_and_real_module_keys(self):
        data = yaml.safe_load((ROOT / "options.yml").read_text(encoding="utf-8"))
        self.assertEqual(data["meta"]["version"], "1.0.0")
        self.assertEqual({o["url"] for o in data["options"]},
                         {"map-png.palette", "map-png.snapshot-before-import"})
        for option in data["options"]:
            self.assertIn(option["display"], {"Choice", "Switch"})
        # Do not advertise the unfinished overwrite confirmation as functional.
        self.assertNotIn("confirm-overwrite", str(data))

    def test_store_package_includes_runtime_images_and_locales(self):
        entries = ET.parse(ROOT / "files.xml").findall("./files/file")
        sources = {e.attrib["src"] for e in entries}
        self.assertTrue({"init.lua", "definition.yml", "options.yml", "mappng", "resources", "locale"} <= sources)
        self.assertTrue(all((ROOT / src).exists() for src in sources))
        self.assertFalse({"tests", "tools", ".git", "IMPLEMENTATION_PLAN.md"} & sources)
