"""Build a deterministic, unsigned module ZIP from the store's files.xml."""
from pathlib import Path
import hashlib
import zipfile
import xml.etree.ElementTree as ET
import yaml

ROOT = Path(__file__).resolve().parents[1]


def package(destination):
    entries = {}
    for entry in ET.parse(ROOT / "files.xml").findall("./files/file"):
        source = ROOT / entry.attrib["src"]
        target = Path(entry.attrib.get("target", ".")) / source.name
        files = sorted(source.rglob("*")) if source.is_dir() else [source]
        for file in files:
            if not file.is_file():
                continue
            archive = target / file.relative_to(source) if source.is_dir() else target
            name = archive.as_posix()
            assert not name.startswith("/") and ".." not in archive.parts
            assert name not in entries, name
            entries[name] = file
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, file in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (2026, 9, 10, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, file.read_bytes())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert "definition.yml" in archive.namelist()
        for name, file in entries.items():
            assert archive.read(name) == file.read_bytes(), name
    print(destination)
    print("Verified", len(entries), "files; SHA256", hashlib.sha256(destination.read_bytes()).hexdigest())


if __name__ == "__main__":
    definition = yaml.safe_load((ROOT / 'definition.yml').read_text(encoding='utf-8'))
    package(ROOT / "dist" / f"{definition['name']}-{definition['version']}.zip")
