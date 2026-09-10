"""Installs the module into a UCP3 game folder for testing.

Copies the module as an unpacked folder (`ucp/modules/map-png-<version>/`),
which a Developer build of UCP loads without a signature, and adds the two
entries `ucp-config.yml` needs to activate it.

    python tools/deploy.py "S:/path/to/game"
    python tools/deploy.py "S:/path/to/game" --no-config   # copy files only

The config is backed up next to itself before being touched.
"""

import argparse
import datetime
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Copied verbatim into the installed module folder.
PAYLOAD = ["init.lua", "definition.yml", "options.yml", "mappng", "resources", "locale"]

# The module has to load after the ones it depends on.
AFTER = "ui"


def module_version():
    text = (ROOT / "definition.yml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\S+)", text, re.MULTILINE)
    if not match:
        raise SystemExit("could not read version from definition.yml")
    return match.group(1)


def copy_module(game, version):
    target = game / "ucp" / "modules" / ("map-png-%s" % version)
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)

    for entry in PAYLOAD:
        source = ROOT / entry
        if not source.exists():
            raise SystemExit("missing from the repository: %s" % entry)
        if source.is_dir():
            shutil.copytree(source, target / entry)
        else:
            shutil.copy2(source, target / entry)

    return target


def patch_config(game, version):
    """Adds the modules entry and the load-order entry, if not already there.

    Done as text rather than through a YAML round trip on purpose: the file
    uses an anchor (`config-full: &id001` / `config-sparse: *id001`) that most
    YAML writers would expand into two copies.
    """
    config = game / "ucp-config.yml"
    if not config.exists():
        print("no ucp-config.yml at %s, skipping config" % config)
        return False

    # Keep the file's own line endings. Text mode would silently turn an
    # LF-only config into CRLF on Windows and rewrite every line of it.
    raw = config.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")
    if re.search(r"^\s*- extension: map-png\s*$", text, re.MULTILINE):
        print("map-png already in load-order, leaving the config alone")
        return False

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = config.with_suffix(".yml.bak-%s" % stamp)
    shutil.copy2(config, backup)
    print("backed up config to %s" % backup.name)

    # 1. modules entry, inserted just before the plugins block.
    modules_entry = "    map-png:\n      config: {}\n"
    updated, count = re.subn(r"^  plugins:$", modules_entry + "  plugins:", text,
                            count=1, flags=re.MULTILINE)
    if count == 0:
        raise SystemExit("could not find the 'plugins:' block in ucp-config.yml")

    # 2. load-order entry, immediately after the module we must follow.
    pattern = r"(^  - extension: %s\n    version: [^\n]*\n)" % re.escape(AFTER)
    entry = r"\1  - extension: map-png\n    version: %s\n" % version
    updated, count = re.subn(pattern, entry, updated, count=1, flags=re.MULTILINE)
    if count == 0:
        raise SystemExit(
            "could not find '- extension: %s' in load-order; add map-png by hand"
            % AFTER)

    config.write_bytes(updated.replace("\n", newline).encode("utf-8"))
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", help="the game folder, containing ucp/")
    parser.add_argument("--no-config", action="store_true",
                        help="copy the files but do not touch ucp-config.yml")
    args = parser.parse_args()

    game = pathlib.Path(args.game).resolve()
    if not (game / "ucp").is_dir():
        raise SystemExit("%s does not look like a UCP install (no ucp/ folder)" % game)

    version = module_version()
    target = copy_module(game, version)
    print("installed to %s" % target)

    if not args.no_config:
        if patch_config(game, version):
            print("activated map-png %s in ucp-config.yml" % version)

    print("\nNow: launch 'Stronghold Crusader.exe' (not Extreme), open the map")
    print("editor, and check ucp3.log next to the exe for")
    print("  'map-png: added 4 buttons to menu ...'")


if __name__ == "__main__":
    sys.exit(main())
