-- UCP's own AOB extractor resolves code/data; no private scanner or fixed-address
-- fallback. Layout offsets remain a documented Crusader 1.41 ABI contract.
local M = {}
M.patterns = {
  placement = '8B 0C 85 I(? ? ? ?) 89 8E 58 49 55 00 53 B9 ? ? ? ? E8 ? ? ? ? 8B 14 85 I(? ? ? ?) 53 B9 ? ? ? ? 89 96 64 49 55 00',
  preview = '83 3D I(? ? ? ?) FF 0F 85 ? ? ? ? 39 2D I(? ? ? ?) 53 8B 1D ? ? ? ? 75 ? 81 C3 90 01 00 00 EB ? 81 C3 58 02 00 00 8B 35 ? ? ? ? 8B 3D I(? ? ? ?) 81 C6 F0 00 00 00',
  sections = '? ? ? ? 00 00 00 00 20 74 02 00 01 00 E9 03 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 09 04 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 EA 03',
  banner = '83 44 24 08 08 53 8B 5C 24 08 55 8B 6C 24 14 83 C3 08 83 ED 10 56 33 C0 57',
  inputRender = 'A1 ? ? ? ? 8B 0D ? ? ? ? 8B 15 ? ? ? ? 56 57 6A 05 03 C8 51 8B 0D ? ? ? ? 03 D1 52 50 51 B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ?',
  rowBackground = '8B 0D ? ? ? ? 56 57 0F BE 7C 24 10 83 E7 01 03 FF 83 CF 45 83 7C 24 0C 00',
  scrollRender = '8B 44 24 10 8B 4C 24 14 8B 54 24 08 6A 00 50 A1 ? ? ? ? 51 8B 0D ? ? ? ? 52 8B 15 ? ? ? ? 50 51 52 B9 ? ? ? ? E8 ? ? ? ? C3',
  arrowRender = '83 7C 24 04 00 B8 51 00 00 00 75 05 B8 55 00 00 00 83 3D ? ? ? ? 00 74 03 83 C0 01',
  trimText = '8B 44 24 08 8B 54 24 04 50 8B 44 24 10 8D 44 C0 12 52 8D 0C 81 E8 ? ? ? ? C2 0C 00',
  activate = '56 8B F1 83 7E 5C 00 75 22 A1 I(? ? ? ?) 85 C0 A3 I(? ? ? ?) C7 05 I(? ? ? ?) 01 00 00 00',
  pop = '8B 41 64 8B 51 68 56 8B 71 60 89 41 60 8B 41 6C 89 51 64 8B 51 70 89 41 68 33 C0',
  building = '55 56 8B 74 24 0C 8B C6 69 C0 2C 03 00 00 57 8B F9 8D 14 38 66 C7 82 E4 00 00 00 03 00 83 3D I(? ? ? ?) 00',
  tree = '56 57 8B 7C 24 0C 8B F1 57 B9 I(? ? ? ?) E8 ? ? ? ? 8B C7 69 C0 9C 00 00 00',
  rock = '56 8B 74 24 08 57 8B F9 56 B9 I(? ? ? ?) E8 ? ? ? ? C1 E6 05',
  wall = '55 56 8B 74 24 10 0F BF 2C 75 I(? ? ? ?) 57 8B F9 8D 4C 6D 00 8B C6 2B 04 8D I(? ? ? ?)',
  buildings = '51 8B 44 24 08 69 C0 2C 03 00 00 66 83 B8 I(? ? ? ?) 43 53 0F BF 98 ? ? ? ?',
  landscape = '53 55 56 8B 74 24 10 69 F6 9C 00 00 00 8B 86 I(? ? ? ?) 0F BF 9E ? ? ? ?',
  shape = '8B 94 00 I(? ? ? ?) 03 C0 89 91 8C 49 55 00 8B 90 ? ? ? ? 89 91 90 49 55 00',
  units = 'C7 05 I(? ? ? ?) I(? ? ? ?) C7 05 ? ? ? ? ? ? ? ? C7 05 ? ? ? ? ? ? ? ? C7 86 70 F0 53 00',
  -- `push edi / mov ecx, MinimapViewState / call triggerMinimapRedraw / mov eax, 2000`
  minimap = '57 B9 I(? ? ? ?) E8 I(? ? ? ?) B8 D0 07 00 00 B9',
  -- map-extensions owns the read/write entry hooks and allocation sizes.
  -- Observe inside the original body, after its trampoline rejoins execution.
  loadBegin = '89 44 24 14 89 5E 20 E8 ? ? ? ? 83 C4 04 3B C3 89 46 10',
  loadDone = '89 5E 10 8B 15 ? ? ? ? 83 C4 08 39 1D ? ? ? ? 89 1D ? ? ? ?',
  saveBegin = '89 44 24 1C 89 7E 20 89 6C 24 18 89 7C 24 14 89 7E 0C 89 7E 28 89 3B',
  saveDone = '83 C4 30 C7 46 10 00 00 00 00 5F 5E 5D 5B 83 C4 10 C2 04 00',
  newMap = '53 55 56 8B F1 57 33 FF 89 BE 1C 29 55 00 89 BE 20 29 55 00',
  -- UCP 3.0.7's @() reads the correct operand but omits the opcode's offset
  -- from the result. Capture the displacement with I() on all framework builds.
  resource = 'B9 I(? ? ? ?) E8 I(? ? ? ?) 53 68 00 80 00 00 50 E8 ? ? ? ? 8B F8 83 CD FF',
}
local LINKS = {loadBegin=true, loadDone=true, saveBegin=true, saveDone=true, newMap=true, resource=true}
local function find(name, pattern)
  -- The AOB cache can hold a later match; core.scanForAOB is uncached and
  -- returns the first match in the image. AOBExtract needs a capture, so it
  -- reads only captured patterns, at that first match.
  local aob = pattern:gsub('I%(', ''):gsub('%)', '')
  local ok, result = pcall(function()
    local first = core.scanForAOB(aob)
    if not first or not pattern:find('(',1,true) then return {first} end
    return {utils.AOBExtract(pattern, first, first)}
  end)
  assert(ok, 'map-png: native binding '..name..' failed: '..tostring(result))
  assert(result[1], 'map-png: native binding unavailable: '..name)
  assert(core.scanForAOB(aob, result[1] + 1) == nil, 'map-png: native binding ambiguous: '..name)
  return result
end
local cached
function M.resolve()
  if cached then return cached end
  local found = {}
  for name, pattern in pairs(M.patterns) do
    if not LINKS[name] and name ~= 'minimap' then found[name] = find(name, pattern) end
  end
  local r = {functions={}, ui={}}
  r.sections=found.sections[1]
  r.placement=found.placement[2]-0x5DC
  assert(found.placement[3]==r.placement+0x794,'map-png: unknown building placement layout')
  r.preview={previewSuppressed=found.preview[2],multiplayerLayout=found.preview[3],mapSize=found.preview[4]}
  for _,name in ipairs({'banner','inputRender','rowBackground','scrollRender','arrowRender','trimText','activate','pop'}) do r.ui[name]=found[name][1] end
  r.input=found.activate[2]; r.menuInput=found.activate[3]-0x88
  assert(found.activate[4]==r.input+12,'map-png: unknown text input layout')
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
  -- The editor's land tools redraw the minimap through this trigger. Without
  -- it, imports still work and only the minimap keeps its old image.
  local redraw, redrawError = pcall(function()
    local site = find('minimap', M.patterns.minimap)
    assert(site[2]==r.base-0x61BF8, 'map-png: unknown minimap layout')
    local rel=site[3]
    if rel>=0x80000000 then rel=rel-0x100000000 end
    r.minimap = {state=site[2], redraw=site[1]+11+rel}
  end)
  if not redraw then log(WARNING, 'map-png: minimap redraw off: '..tostring(redrawError)) end
  -- Linked refresh is optional; plain PNG import/export does not need its sites.
  local linked, linkError = pcall(function()
    local links = {}
    for name in pairs(LINKS) do links[name] = find(name, M.patterns[name]) end
    local rel=links.resource[3]
    if rel>=0x80000000 then rel=rel-0x100000000 end
    r.resource, r.resourceName=links.resource[2],links.resource[1]+10+rel
    -- The getter indexes the resource manager's path array and returns its
    -- current path. Verify the full leaf, including its argument-free return.
    local getter = {0x8B,0x81,0xC4,0x0B,0,0,0x69,0xC0,0xE9,0x03,0,0,
      0x8D,0x84,0x08,0xE0,0xAE,0x07,0,0xC3}
    for i,b in ipairs(getter) do
      assert(core.readByte(r.resourceName+i-1)==b,'map-png: unknown file name getter')
    end
    r.hooks = {}
    for _, name in ipairs({'loadBegin','loadDone','saveBegin','saveDone','newMap'}) do r.hooks[name]=links[name][1] end
  end)
  if not linked then r.hooks, r.linkError = nil, linkError end
  cached=r
  return r
end
return M
