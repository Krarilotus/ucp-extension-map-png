import unittest
import lua_harness


class ImportPlan(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.lua.execute('''
          planner=require('mappng.map.importplan')
          old={height={},defaultHeight={},logic1={},logic2={}}
          proposed={height={},defaultHeight={},logic1={},logic2={}}
          for i=0,9 do
            old.height[i]=7; old.defaultHeight[i]=2
            old.logic1[i]=0x8400; old.logic2[i]=0
            proposed.height[i]=2; proposed.defaultHeight[i]=2
            proposed.logic1[i]=0x8000; proposed.logic2[i]=0x40
          end
          objects={a={kind='building',type=1,owner=1,tiles={1,2}}}
          function neighbours(i) return {i-1,i+1} end
          profile={limit=200,difference=12,rocky=0,marsh=0,moat=0}
          function plan() return planner.build(old,proposed,objects,10,neighbours,function() return profile end) end
        ''')

    def check(self, code):
        self.lua.execute(code)

    def test_cosmetic_changes_preserve_all_layers_under_building(self):
        self.check('''local p=plan(); assert(p.keep.a and not p.remove.a)
          planner.mask(p,old,proposed)
          assert(proposed.height[1]==7 and proposed.logic1[1]==0x8400)
          assert(proposed.logic2[1]==0 and proposed.logic2[0]==0x40)''')

    def test_small_height_change_within_native_tolerance_is_masked(self):
        self.check('''proposed.defaultHeight[2]=3
          local p=plan(); assert(p.keep.a)
          planner.mask(p,old,proposed); assert(proposed.defaultHeight[2]==2)''')

    def test_uniform_height_change_does_not_imply_uneven_foundation(self):
        self.check('''proposed.defaultHeight[1]=10; proposed.defaultHeight[2]=10
          assert(plan().keep.a)''')

    def test_removed_obstruction_does_not_delete_object(self):
        self.check('old.logic1[2]=old.logic1[2]|0x80; assert(plan().keep.a)')

    def test_new_cliff_outside_footprint_removes_object(self):
        self.check('proposed.defaultHeight[3]=23; assert(plan().remove.a)')

    def test_diagonal_edge_and_connected_group_are_rechecked(self):
        self.check('''objects.a.group=9
          objects.b={kind='building',type=1,group=9,tiles={6}}
          function neighbours(i,diagonals)
            if i==2 and diagonals then return {8} end
            return {}
          end
          proposed.defaultHeight[8]=23
          local p=plan(); assert(p.remove.a and p.remove.b and not next(p.mask))''')

    def test_cliff_threshold_and_preexisting_edge(self):
        self.check('''proposed.defaultHeight[3]=22; assert(plan().keep.a)
          old.defaultHeight[3]=23; proposed.defaultHeight[3]=23
          assert(plan().keep.a)''')

    def test_cliff_uses_ground_not_building_raised_surface(self):
        self.check('old.height[1]=80; old.height[2]=80; assert(plan().keep.a)')

    def test_retained_neighbour_mask_prevents_false_cliff(self):
        self.check('''objects.b={kind='building',type=1,tiles={3}}
          proposed.defaultHeight[3]=23
          local p=plan(); assert(p.keep.a and p.keep.b)''')

    def test_deleting_neighbour_rechecks_exposed_cliff(self):
        self.check('''objects.b={kind='building',type=1,tiles={3}}
          proposed.defaultHeight[3]=23; proposed.logic1[3]=1
          local p=plan(); assert(p.remove.a and p.remove.b)''')

    def test_height_limit_not_just_height_delta(self):
        self.check('''proposed.defaultHeight[1]=201; proposed.defaultHeight[2]=201
          assert(plan().remove.a)''')

    def test_native_marsh_exception_and_moat_exception(self):
        self.check('''profile.marsh=1; proposed.logic1[1]=0x20000000; assert(plan().keep.a)
          profile.moat=1; proposed.logic1[1]=0x40000000; assert(plan().keep.a)''')

    def test_resource_building_requires_resource_not_just_any_flag_change(self):
        self.check('''objects.a.type=5
          old.logic1[1]=0x80000; old.logic1[2]=0x80000
          proposed.logic1[1]=0x80000; proposed.logic1[2]=0x80000
          assert(plan().keep.a)
          proposed.logic1[2]=0x8000; assert(plan().remove.a)''')

    def test_change_any_footprint_tile_removes_whole_object(self):
        self.check('proposed.defaultHeight[2]=16; assert(plan().remove.a)')

    def test_reimporting_exported_raised_height_preserves_building(self):
        self.check('proposed.defaultHeight[2]=7; assert(plan().keep.a)')

    def test_hard_terrain_conflicts(self):
        for flag in (1, 0x10, 0x20, 0x80, 0x100000, 0x200000, 0x20000000):
            self.check(f'proposed.logic1[2]={flag}; assert(plan().remove.a)')

    def test_native_rocky_exception(self):
        self.check('profile.rocky=1; proposed.logic1[1]=0x80; assert(plan().keep.a)')

    def test_deposits_are_not_generic_building_obstructions(self):
        for flag in (0x4000, 0x20000, 0x80000, 0x80000000):
            self.check(f'proposed.logic1[2]={flag}; assert(plan().keep.a)')

    def test_native_linked_group_is_all_or_nothing(self):
        self.check('''objects.a.group=8
          objects.b={kind='building',type=1,owner=2,group=8,tiles={7}}
          proposed.defaultHeight[1]=16
          local p=plan(); assert(p.remove.a and p.remove.b)''')

    def test_connected_keep_parts_not_all_owner_buildings(self):
        self.check('''objects.a.type=40
          objects.b={kind='building',type=71,owner=1,tiles={3}}
          objects.c={kind='building',type=10,owner=1,tiles={4}}
          objects.d={kind='building',type=55,owner=1,tiles={8}}
          objects.e={kind='building',type=10,owner=2,tiles={5}}
          proposed.logic1[1]=1
          local p=plan(); assert(p.remove.a and p.remove.b and p.remove.c)
          assert(p.keep.d and p.keep.e)''')

    def test_fertile_ground_matters_for_farms(self):
        self.check('''objects.a.type=30; old.logic1[2]=4
          assert(plan().remove.a)''')

    def test_tree_full_footprint_is_checked(self):
        self.check('''objects.a={kind='tree',tiles={1,2,3}}
          proposed.logic1[3]=1; assert(plan().remove.a)''')

    def test_undug_moat_is_not_cosmetic(self):
        self.check('proposed.logic2[2]=3; assert(plan().remove.a)')

    def test_invalid_or_missing_footprint_fails_closed(self):
        self.check('objects.a.tiles={}; assert(not pcall(plan))')
        self.check('objects.a.tiles={10}; assert(not pcall(plan))')
        self.check('objects.a.tiles={1,1}; assert(not pcall(plan))')

    def test_mixed_overlapping_footprints_fail_before_mutation(self):
        self.check('''objects.b={kind='tree',tiles={2,3}}
          proposed.defaultHeight[1]=16
          assert(not pcall(plan)); assert(old.height[1]==7)''')
