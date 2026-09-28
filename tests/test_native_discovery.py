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
        def scan(pattern, *unused):
            regex = re.compile(b''.join(b'.' if t == '?' else re.escape(bytes([int(t,16)]))
                for t in pattern.split()), re.DOTALL)
            matches=[]
            for address, size, raw_size, offset in pe.sections:
                matches += [address+m.start() for m in regex.finditer(pe.data[offset:offset+raw_size])]
            if len(matches)!=1: raise AssertionError(f'{len(matches)} matches: {pattern}')
            return matches[0]
        core = lua.table_from({
            'AOBScan':scan,
            'readInteger':lambda a: struct.unpack('<i', pe.read(a,4))[0],
            'readSmallInteger':lambda a: struct.unpack('<h', pe.read(a,2))[0],
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
        self.assertEqual(r.hooks.loadBegin,0x474A70)
        self.assertEqual(r.hooks.saveBegin,0x474677)
        self.assertEqual(r.hooks.saveDone,0x47491E)
        self.assertEqual(r.sections,0xB92A58)
        self.assertEqual(r.ui.scrollRender,0x492C60)
        self.assertEqual(r.input,0x1652740)
        self.assertEqual(r.menuInput,0x11265A8)
        self.assertEqual(r.placement,0x5B7974)
        self.assertEqual(r.preview.previewSuppressed,r.base+0x554AB4)
        self.assertEqual(r.preview.multiplayerLayout,r.base+0x55603C)
        self.assertEqual(r.preview.mapSize,r.base+0x554A0C)

    def test_extreme(self):
        lua,r=self.resolve('Stronghold_Crusader_Extreme.exe')
        self.assertEqual(r.base,0x2526708)
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
        lua.execute("core={AOBScan=function() error('not found') end}; utils={}")
        native=lua_harness.load(lua,'mappng.native')
        native.patterns=lua.table_from({'loadBegin':'AA BB CC'})
        with self.assertRaisesRegex(Exception,'native binding loadBegin failed:.*not found'):
            native.resolve()

    def test_detours_cover_whole_non_branching_instructions(self):
        import capstone
        decoder=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_32)
        for filename in ('Stronghold Crusader.exe','Stronghold_Crusader_Extreme.exe'):
            _, bindings=self.resolve(filename)
            pe=PEImage(GAME_DIR/filename)
            for name,span in dict(newMap=5,loadBegin=6,loadDone=9,saveBegin=5,saveDone=10).items():
                address=bindings.hooks[name]
                instructions=list(decoder.disasm(pe.read(address,span),address))
                self.assertEqual(sum(i.size for i in instructions),span,(filename,name))
                self.assertTrue(all(not i.mnemonic.startswith(('j','call','ret','loop')) for i in instructions))

    def test_filename_observation_sites_follow_same_native_getter(self):
        for filename in ('Stronghold Crusader.exe','Stronghold_Crusader_Extreme.exe'):
            _, bindings=self.resolve(filename)
            pe=PEImage(GAME_DIR/filename)
            targets=[]
            receivers=[]
            for name in ('loadBegin','saveBegin'):
                site=bindings.hooks[name]
                # MOV ECX, resource; CALL getter; observation point. The native
                # caller has already resolved EAX; no second getter call needed.
                before=pe.read(site-10,10)
                self.assertEqual(before[0],0xB9)
                self.assertEqual(before[5],0xE8)
                receivers.append(struct.unpack('<I',before[1:5])[0])
                targets.append(site+struct.unpack('<i',before[6:10])[0])
            self.assertEqual(receivers[0],receivers[1])
            self.assertEqual(targets[0],targets[1])
            self.assertEqual(pe.read(targets[0],20),bytes.fromhex(
                '8B 81 C4 0B 00 00 69 C0 E9 03 00 00 8D 84 08 E0 AE 07 00 C3'))

    def test_map_extensions_entry_hooks_and_allocation_patch_do_not_hide_buttons(self):
        for filename in ('Stronghold Crusader.exe','Stronghold_Crusader_Extreme.exe'):
            _, original=self.resolve(filename)
            read,write=original.hooks.loadBegin,original.hooks.saveBegin
            # map-extensions hooks five entry bytes. Older recorder variants can
            # hook ten. Neither owns these interior observation sites.
            pe=PEImage(GAME_DIR/filename)
            def locate(data):
                matches=[va+offset for va,_,rawsize,raw in pe.sections
                         for offset in [pe.data[raw:raw+rawsize].find(data)] if offset>=0]
                self.assertEqual(len(matches),1)
                return matches[0]
            read_entry=locate(bytes.fromhex('83 EC 0C 53 56 8B F1 8B 46 20'))
            write_entry=locate(bytes.fromhex('83 EC 10 53 55 56 8B F1 8B 46 20'))
            read_malloc=locate(bytes.fromhex('68 80 8D 5B 00 89 44 24 14'))+1
            write_malloc=locate(bytes.fromhex('68 80 8D 5B 00 89 44 24 1C'))+1
            patches={read_entry:b'\xe9\0\0\0\0'+b'\x90'*5,
                     write_entry:b'\xe9\0\0\0\0'+b'\x90'*5,
                     read_malloc:struct.pack('<I',0x1000000),
                     write_malloc:struct.pack('<I',0x1000000)}
            _, resolved=self.resolve(filename,patches)
            self.assertEqual(resolved.hooks.loadBegin,read)
            self.assertEqual(resolved.hooks.saveBegin,write)
            self.assertEqual(resolved.ui.banner,original.ui.banner)
