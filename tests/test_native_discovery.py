"""Exercise UCP's real AOBExtract against supported executable fixtures."""
import os
from pathlib import Path
import re
import struct
import unittest
import lua_harness
from test_tilemap_binary import GAME_DIR, PEImage

FRAMEWORK = Path(os.environ.get('MAPPNG_UCP_CODE',
    'S:/Projects/UCP/UnofficialCrusaderPatch3/content/ucp/code'))


@unittest.skipUnless((FRAMEWORK / 'utils.lua').exists(), 'UCP source fixture absent')
class NativeDiscovery(unittest.TestCase):
    def resolve(self, filename):
        path = GAME_DIR / filename
        if not path.exists(): self.skipTest('game fixture absent')
        pe = PEImage(path)
        lua = lua_harness.runtime()
        def scan(pattern, *unused):
            regex = re.compile(b''.join(b'.' if t == '?' else re.escape(bytes([int(t,16)]))
                for t in pattern.split()), re.DOTALL)
            matches=[]
            for address, size, raw_size, offset in pe.sections:
                # Game executable code sections; data patterns must not count.
                if address >= 0x600000: continue
                matches += [address+m.start() for m in regex.finditer(pe.data[offset:offset+raw_size])]
            if len(matches)!=1: raise AssertionError(f'{len(matches)} matches: {pattern}')
            return matches[0]
        core = lua.table_from({
            'AOBScan':scan,
            'readInteger':lambda a: struct.unpack('<i', pe.read(a,4))[0],
            'readBytes':lambda a,n:lua.table_from(list(pe.read(a,n))),
        })
        lua.globals().core=core
        lua.execute("package.loaded.core=core; log=function() end; VERBOSE=0")
        lua.globals().utils=lua.execute((FRAMEWORK/'utils.lua').read_text())
        return lua, lua_harness.load(lua,'mappng.native').resolve()

    def test_classic(self):
        lua,r=self.resolve('Stronghold Crusader.exe')
        self.assertEqual(r.base,0x1A93208)
        self.assertEqual(r.buildings,0xF98520)
        self.assertEqual(r.landscape,0xF2CC38)
        self.assertEqual(r.units,0x1387F38)
        self.assertEqual(r.hooks.loadBegin,0x474A20)
        self.assertEqual(r.hooks.saveDone,0x47491E)

    def test_extreme(self):
        lua,r=self.resolve('Stronghold_Crusader_Extreme.exe')
        self.assertEqual(r.base,0x2526708)
