"""Exercise UCP's real AOBExtract against supported executable fixtures."""
import os
from pathlib import Path
import re
import struct
import unittest
import lua_harness
from test_tilemap_binary import GAME_DIR, PEImage

FRAMEWORK = Path(os.environ.get('MAPPNG_UCP_CODE', ''))


@unittest.skipUnless(os.environ.get('MAPPNG_UCP_CODE') and (FRAMEWORK / 'utils.lua').exists(),
                     'UCP source fixture absent')
class NativeDiscovery(unittest.TestCase):
    def resolve(self, filename, patches=None):
        path = GAME_DIR / filename
        if not path.exists(): self.skipTest('game fixture absent')
        pe = PEImage(path)
        if patches:
            pe.data=bytearray(pe.data)
            for address, data in patches.items():
                for va, size, raw_size, offset in pe.sections:
                    if va<=address<va+raw_size:
                        start=offset+address-va
                        pe.data[start:start+len(data)]=data
                        break
                else: self.fail('patch outside image')
        lua = lua_harness.runtime()
        def matches(pattern):
            regex = re.compile(b''.join(b'.' if t == '?' else re.escape(bytes([int(t,16)]))
                for t in pattern.split()), re.DOTALL)
            return [address+m.start() for address, size, raw_size, offset in pe.sections
                    for m in regex.finditer(pe.data[offset:offset+raw_size])]
        def scan(pattern, *unused):
            found=matches(pattern)
            if len(found)!=1: raise AssertionError(f'{len(found)} matches: {pattern}')
            return found[0]
        core = lua.table_from({
            'AOBScan':scan,
            'readByte':lambda a: pe.read(a,1)[0],
            'readInteger':lambda a: struct.unpack('<i', pe.read(a,4))[0],
            'readSmallInteger':lambda a: struct.unpack('<h', pe.read(a,2))[0],
            'readBytes':lambda a,n:lua.table_from(list(pe.read(a,n))),
        })
        lua.globals().core=core
        lua.execute("package.loaded.core=core; log=function() end; VERBOSE=0")
        lua.globals().utils=lua.execute((FRAMEWORK/'utils.lua').read_text())
        bindings = lua_harness.load(lua,'mappng.native').resolve()
        if not patches:
            pattern = "B9 I(? ? ? ?) @(E8 ? ? ? ?) 53 68 00 80 00 00 50 E8 ? ? ? ? 8B F8 83 CD FF"
            match, resource, legacy = lua.globals().utils.AOBExtract(pattern)
            displacement = struct.unpack('<i', pe.read(match + 6, 4))[0]
            self.assertEqual(bindings.resource, resource)
            self.assertEqual(bindings.resourceName, match + 10 + displacement)
            self.assertEqual(pe.read(bindings.resourceName, 20),
                             bytes.fromhex('8B 81 C4 0B 00 00 69 C0 E9 03 00 00 8D 84 08 E0 AE 07 00 C3'))
            source = (FRAMEWORK / 'utils.lua').read_text()
            expected_error = 0 if '5 + address + (group.start - 1)' in source else 5
            self.assertEqual(bindings.resourceName - legacy, expected_error)
        return lua, bindings

    def test_classic(self):
        lua,r=self.resolve('Stronghold Crusader.exe')
        self.assertEqual(r.base,0x1A93208)
        self.assertEqual(r.buildings,0xF98520)
        self.assertEqual(r.landscape,0xF2CC38)
        self.assertEqual(r.units,0x1387F38)
        self.assertEqual(r.hooks.loadBegin,0x474A31)
        self.assertEqual(r.hooks.saveBegin,0x474498)
        self.assertEqual(r.hooks.saveDone,0x47491E)
        self.assertEqual(r.sections,0xB92A58)
        self.assertEqual(r.ui.scrollRender,0x492C60)
        self.assertEqual(r.input,0x1652740)
        self.assertEqual(r.menuInput,0x11265A8)
        self.assertEqual(r.placement,0x5B7974)
        self.assertEqual(r.preview.previewSuppressed,r.base+0x554AB4)
        self.assertEqual(r.preview.multiplayerLayout,r.base+0x55603C)
        self.assertEqual(r.preview.mapSize,r.base+0x554A0C)
        self.assertEqual((r.minimap.state,r.minimap.redraw),(0x1A31610,0x4B5300))

    def test_extreme(self):
        lua,r=self.resolve('Stronghold_Crusader_Extreme.exe')
        self.assertEqual(r.base,0x2526708)
        self.assertEqual((r.minimap.state,r.minimap.redraw),(0x24C4B10,0x4B5470))
        self.assertEqual(r.preview.previewSuppressed,r.base+0x554AB4)
        self.assertEqual(r.preview.multiplayerLayout,r.base+0x55603C)
        self.assertEqual(r.preview.mapSize,r.base+0x554A0C)

    def test_native_building_profiles_fit_adapter_contract(self):
        for filename in ('Stronghold Crusader.exe','Stronghold_Crusader_Extreme.exe'):
            _, bindings=self.resolve(filename)
            pe=PEImage(GAME_DIR/filename)
            for kind in range(1,110):
                values={offset:struct.unpack('<i',pe.read(bindings.placement+offset+kind*4,4))[0]
                        for offset in (0x5DC,0x794,0xB04,0xE74,0x102C)}
                self.assertLessEqual(abs(values[0x5DC]),255)
                self.assertTrue(0<=values[0x794]<=255)
                self.assertIn(values[0xB04],(0,1))
                self.assertIn(values[0xE74],(0,1,2))
                self.assertIn(values[0x102C],(0,1))

    def test_missing_binding_error_names_the_failed_site(self):
        lua=lua_harness.runtime()
        lua.execute("core={AOBScan=function() error('AOB not found') end}; utils={}")
        native=lua_harness.load(lua,'mappng.native')
        native.patterns=lua.table_from({'banner':'AA BB CC'})
        with self.assertRaisesRegex(Exception,'native binding banner: not found'):
            native.resolve()

    def test_detours_cover_whole_non_branching_instructions(self):
        import capstone
        decoder=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_32)
        for filename in ('Stronghold Crusader.exe','Stronghold_Crusader_Extreme.exe'):
            _, bindings=self.resolve(filename)
            pe=PEImage(GAME_DIR/filename)
            for name,span in dict(newMap=5,loadBegin=7,loadDone=9,saveBegin=7,saveDone=10).items():
                address=bindings.hooks[name]
                instructions=list(decoder.disasm(pe.read(address,span),address))
                self.assertEqual(sum(i.size for i in instructions),span,(filename,name))
                self.assertTrue(all(not i.mnemonic.startswith(('j','call','ret','loop')) for i in instructions))

    def test_map_extensions_entry_hooks_and_allocation_patch_do_not_hide_buttons(self):
        for filename in ('Stronghold Crusader.exe','Stronghold_Crusader_Extreme.exe'):
            _, original=self.resolve(filename)
            read,write=original.hooks.loadBegin,original.hooks.saveBegin
            # map-extensions hooks five entry bytes. Older recorder variants can
            # hook ten. Neither owns these interior observation sites.
            patches={read-17:b'\xe9\0\0\0\0'+b'\x90'*5,
                     write-24:b'\xe9\0\0\0\0'+b'\x90'*5,
                     read-4:struct.pack('<I',0x1000000),
                     write-4:struct.pack('<I',0x1000000)}
            _, resolved=self.resolve(filename,patches)
            self.assertEqual(resolved.hooks.loadBegin,read)
            self.assertEqual(resolved.hooks.saveBegin,write)
            self.assertEqual(resolved.ui.banner,original.ui.banner)
