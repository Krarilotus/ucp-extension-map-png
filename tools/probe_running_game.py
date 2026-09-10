"""Read-only check of a running Stronghold Crusader, from outside the process.

Run it with the game open on the map editor screen:

    python tools/probe_running_game.py

It does what `mappng/map/tilemap.lua` does before its first write -- walk the
map-section table, derive the TileMapState base, cross-check it against every
layer offset -- and additionally reads the editor layout globals, so the
button row's position can be checked without the UCP console.

Nothing is written. The process is opened with VM_READ only.
"""

import ctypes
import json
import struct
import sys
from ctypes import wintypes

# Same constants as mappng/map/tilemap.lua and mappng/ui/screens.lua.
SECTION_TABLES = {
    # sourcehold: read_address_list_shc / read_address_list_shce
    "Stronghold Crusader.exe": (0x00B92A58, 0x00B93208),
    "Stronghold_Crusader_Extreme.exe": (0x00B92BE8, 0x00B93398),
}
SUPPORTED = "Stronghold Crusader.exe"

OFFSETS = {
    "LogicLayer": 0x00165160,
    "Logic2Layer": 0x001B3FE0,
    "HeightLayer": 0x0029FA30,
    "DefaultHeightLayer": 0x002B3440,
    "mapOrientation": 0x0055489C,
    "futureMapOrientation": 0x005548A0,
}
SECTIONS = {
    1003: ("LogicLayer", 321600),
    1037: ("Logic2Layer", 80400),
    1005: ("HeightLayer", 80400),
    1045: ("DefaultHeightLayer", 80400),
}
EXPECTED_BASE = 0x01A93208  # OpenSHC DAT_TileMapState, Crusader 1.41

MINIMAP_VIEW_STATE = 0x01A31610  # OpenSHC DAT_MinimapViewState

# Same as mappng/ui/screens.lua: read out of MenuView_MapEditorProperties_DoEveryFrame.
EDITOR_GLOBALS = {"previewSuppressed": 0x01FE7CBC, "multiplayerLayout": 0x01FE9244,
                  "mapSize": 0x01FE7C14}
MENU_ORIGIN = {"x": 0x00F2B3A0, "y": 0x00F2B3A4}
HALF_BY_SIZE = {160: 80, 200: 100, 300: 75, 400: 100}


def editor_row(values):
    """Menu-local icon positions, the same arithmetic as screens.iconPosition."""
    variant = "mp" if values["multiplayerLayout"] else "sp"
    size = values["mapSize"] or 400
    half = HALF_BY_SIZE.get(size, 100)
    centre_x, centre_y = (600 if variant == "mp" else 400), 240
    return {
        "layout": "%s:%d" % (variant, size),
        "previewShown": values["previewSuppressed"] in (-1, 0xFFFFFFFF),
        "icons": [(centre_x - 126 + i * 64 + 4, centre_y + half + 8)
                  for i in range(4)],
    }


PROCESS_VM_READ = 0x0010
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
TH32CS_SNAPPROCESS = 0x00000002


def parse_section_table(data):
    """16-byte MapSectionAddress records -> {sectionId: (address, size)}."""
    sections = {}
    for offset in range(0, len(data) - 15, 16):
        address, _unknown, size, _compressed, section_id = struct.unpack_from(
            "<IIIhh", data, offset)
        if section_id != 0 and address != 0:
            sections[section_id] = (address, size)
    return sections


def derive_base(sections):
    """Mirror of tilemap.resolveBase. Returns (base, problems)."""
    problems, base = [], None
    for section_id, (field, expected_size) in sorted(SECTIONS.items()):
        if section_id not in sections:
            problems.append("section %d missing" % section_id)
            continue
        address, size = sections[section_id]
        if size != expected_size:
            problems.append("section %d has size %d, expected %d"
                            % (section_id, size, expected_size))
            continue
        candidate = address - OFFSETS[field]
        if base is None:
            base = candidate
        elif candidate != base:
            problems.append("section %d implies base 0x%X, others 0x%X"
                            % (section_id, candidate, base))
    return base, problems


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD), ("th32DefaultHeapID", ctypes.c_void_p),
        ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", ctypes.c_long),
        ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_wchar * 260),
    ]


def find_game(kernel32):
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    entry = PROCESSENTRY32W()
    entry.dwSize = ctypes.sizeof(entry)
    found = []
    try:
        ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while ok:
            if entry.szExeFile in SECTION_TABLES:
                found.append((entry.th32ProcessID, entry.szExeFile))
            ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return found


def main():
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.ReadProcessMemory.argtypes = [
        wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
        ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]

    games = find_game(kernel32)
    if not games:
        raise SystemExit("no Stronghold Crusader process is running")
    if len(games) > 1:
        raise SystemExit("more than one game process running: %s" % games)
    pid, exe = games[0]

    handle = kernel32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION,
                                  False, pid)
    if not handle:
        raise SystemExit("cannot open process %d (error %d)" % (pid, ctypes.get_last_error()))

    def read(address, size):
        buffer = ctypes.create_string_buffer(size)
        got = ctypes.c_size_t()
        if not kernel32.ReadProcessMemory(handle, address, buffer, size, ctypes.byref(got)) \
                or got.value != size:
            raise OSError("read of %d bytes at 0x%X failed" % (size, address))
        return buffer.raw

    def integer(address):
        return struct.unpack("<i", read(address, 4))[0]

    report = {"pid": pid, "exe": exe, "supported": exe == SUPPORTED}
    try:
        start, end = SECTION_TABLES[exe]
        sections = parse_section_table(read(start, end - start))
        base, problems = derive_base(sections)
        report["tileMapStateBase"] = None if base is None else "0x%08X" % base
        report["problems"] = problems
        report["baseMatchesOpenSHC"] = base == EXPECTED_BASE

        if exe == SUPPORTED and base is not None and not problems:
            report["mapOrientation"] = integer(base + OFFSETS["mapOrientation"])
            editor = {name: integer(address) for name, address in EDITOR_GLOBALS.items()}
            report["editorGlobals"] = editor
            report["menuOrigin"] = {k: integer(a) for k, a in MENU_ORIGIN.items()}
            report["row"] = editor_row(editor)
            # Read-only evidence for controls drifting after map/menu changes.
            menu_address = 0x00B97148
            menu = struct.unpack("<17I", read(menu_address, 68))
            report["editorMenu"] = {"items": hex(menu[0]), "origin": menu[1:3]}
            report["editorItems"] = []
            for index in range(64):
                values = struct.unpack("<20I", read(menu[0] + index * 80, 80))
                report["editorItems"].append({"index": index, "type": hex(values[0]),
                    "position": values[1:3], "size": values[3:5],
                    "render": hex(values[7]), "action": hex(values[5]),
                    "ucID": struct.unpack("<h", read(menu[0] + index * 80 + 0x30, 2))[0],
                    "parent": hex(values[19])})
                if values[0] == 0x66:
                    break
            report["modalStack"] = struct.unpack("<6i", read(0x1126604, 24))
    finally:
        kernel32.CloseHandle(handle)

    print(json.dumps(report, indent=2))

    if not report["supported"]:
        print("\nThis is %s. the button layout was read from Crusader 1.41; launch "
              "'Stronghold Crusader.exe' for the test." % exe, file=sys.stderr)
        return 1
    if report["problems"]:
        print("\nThe section table does not match; do NOT import on this build.",
              file=sys.stderr)
        return 1

    row, origin = report["row"], report["menuOrigin"]
    print("\nWith the editor map screen open, the icons should be at screen")
    print("positions %s (menu-local plus origin %d,%d)."
          % ([(x + origin["x"], y + origin["y"]) for x, y in row["icons"]],
             origin["x"], origin["y"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
