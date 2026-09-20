-- UCP's own AOB extractor resolves code/data; no private scanner or fixed-address
-- fallback. Layout offsets remain a documented Crusader 1.41 ABI contract.
local M = {}
M.patterns = {
  building = '55 56 8B 74 24 0C 8B C6 69 C0 2C 03 00 00 57 8B F9 8D 14 38 66 C7 82 E4 00 00 00 03 00 83 3D I(? ? ? ?) 00',
  tree = '56 57 8B 7C 24 0C 8B F1 57 B9 I(? ? ? ?) @(E8 ? ? ? ?) 8B C7 69 C0 9C 00 00 00',
  rock = '56 8B 74 24 08 57 8B F9 56 B9 I(? ? ? ?) @(E8 ? ? ? ?) C1 E6 05',
  wall = '55 56 8B 74 24 10 0F BF 2C 75 I(? ? ? ?) 57 8B F9 8D 4C 6D 00 8B C6 2B 04 8D I(? ? ? ?)',
  buildings = '51 8B 44 24 08 69 C0 2C 03 00 00 66 83 B8 I(? ? ? ?) 43 53 0F BF 98 ? ? ? ?',
  landscape = '53 55 56 8B 74 24 10 69 F6 9C 00 00 00 8B 86 I(? ? ? ?) 0F BF 9E ? ? ? ?',
  shape = '8B 94 00 I(? ? ? ?) 03 C0 89 91 8C 49 55 00 8B 90 ? ? ? ? 89 91 90 49 55 00',
  units = 'C7 05 I(? ? ? ?) I(? ? ? ?) C7 05 ? ? ? ? ? ? ? ? C7 05 ? ? ? ? ? ? ? ? C7 86 70 F0 53 00',
  loadBegin = '83 EC 0C 53 56 8B F1 8B 46 20 33 DB 68 80 8D 5B 00',
  loadDone = '89 5E 10 8B 15 ? ? ? ? 83 C4 08 39 1D ? ? ? ? 89 1D ? ? ? ?',
  saveBegin = '83 EC 10 53 55 56 8B F1 8B 46 20 57 33 FF 33 ED 8D 5E 24',
  saveDone = '83 C4 30 C7 46 10 00 00 00 00 5F 5E 5D 5B 83 C4 10 C2 04 00',
  newMap = '53 55 56 8B F1 57 33 FF 89 BE 1C 29 55 00 89 BE 20 29 55 00',
  resource = 'B9 I(? ? ? ?) @(E8 ? ? ? ?) 53 68 00 80 00 00 50 E8 ? ? ? ? 8B F8 83 CD FF',
}
local cached
function M.resolve()
  if cached then return cached end
  local found = {}
  for name, pattern in pairs(M.patterns) do
    -- AOBExtract in framework 3.0.7 expects at least one capture (including in
    -- its diagnostic formatter); plain function signatures use core.AOBScan.
    found[name] = pattern:find('(',1,true) and {utils.AOBExtract(pattern)} or {core.AOBScan(pattern)}
    assert(found[name][1], 'map-png: native binding unavailable: '..name)
  end
  local r = {functions={}, hooks={}}
  for _, kind in ipairs({'building','tree','rock','wall'}) do r.functions[kind]=found[kind][1] end
  r.base=found.tree[2]
  assert(r.base==found.rock[2], 'map-png: inconsistent native map bases')
  r.noRubble=found.building[2]
  assert(r.noRubble==r.base+0x5549A4, 'map-png: unknown destruction layout')
  r.buildings=found.buildings[2]-0xE6
  r.landscape=found.landscape[2]-0x84
  r.units=found.units[2]
  r.unitCapacity=found.units[3]
  assert(r.unitCapacity>0 and r.unitCapacity<=10000,'map-png: unknown unit capacity')
  r.rowY, r.rows, r.shapes=found.wall[2], found.wall[3], found.shape[2]
  r.resource, r.resourceName=found.resource[2],found.resource[3]
  for _, name in ipairs({'loadBegin','loadDone','saveBegin','saveDone','newMap'}) do r.hooks[name]=found[name][1] end
  cached=r
  return r
end
return M
