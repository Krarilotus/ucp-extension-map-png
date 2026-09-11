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
            self.assertLess(len(description), 750, lang)
            previews = re.findall(r'!\[([^\]]+)\]\(([^)]+)\)', description)
            self.assertEqual(len(previews), 1, lang)
            self.assertTrue(previews[0][0], lang)
            self.assertTrue(previews[0][1].endswith('/resources/store-preview.png'), lang)
            self.assertTrue((ROOT / 'resources/store-preview.png').is_file())
            self.assertNotIn('mapping/', description)
            self.assertIn("Monsterfish_", description, lang)
            self.assertIn("Photoshop", description, lang)
            self.assertNotIn("\ufffd", text + description)

    def test_options_use_the_gui_schema_and_real_module_keys(self):
        data = yaml.safe_load((ROOT / "options.yml").read_text(encoding="utf-8"))
        self.assertEqual(data["meta"]["version"], "1.0.0")
        self.assertEqual(data["options"], [], "Module activation must not add customization controls")
        for option in data["options"]:
            self.assertIn(option["display"], {"Choice", "Switch"})
        # Overwrite confirmation is mandatory, not a user-disableable option.
        self.assertNotIn("confirm-overwrite", str(data))

    def test_store_package_includes_runtime_images_and_locales(self):
        entries = ET.parse(ROOT / "files.xml").findall("./files/file")
        sources = {e.attrib["src"] for e in entries}
        self.assertTrue({"init.lua", "definition.yml", "options.yml", "mappng", "resources", "locale"} <= sources)
        self.assertTrue({"CREDITS.md", "licenses"} <= sources)
        self.assertTrue(all((ROOT / src).exists() for src in sources))
        self.assertFalse({"tests", "tools", ".git", "IMPLEMENTATION_PLAN.md"} & sources)
