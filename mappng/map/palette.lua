--- mappng/map/palette.lua
---
--- Terrain flag <-> colour tables.
---
--- `logic1` / `logic2` are ported verbatim from
--- `sourcehold/tool/memory/map/terrain/logics.py` and cross-checked against
--- `OpenSHC/src/OpenSHC/Map/LogicHelpers/Logic1.hpp` and `Logic2.hpp` -- the
--- flag values agree.
---
--- Two palettes are shipped:
---
--- * `sourcehold` is the monsterfish1 palette, byte-for-byte what
---   `sourcehold memory map get/set terrain` uses. It is *lossy on import*:
---   `default_earth_or_texture`, `plateau_medium` and `plateau_high` all share
---   `#ae9467`, and Python's dict inversion makes the last name win, so every
---   plain earth tile comes back as `plateau_high`. The same happens to
---   `moat_undug` / `moat_dug` / `moat`, which all share `#0000ff` and collapse
---   onto `moat`. Kept for interoperability with existing PNGs.
---
--- * `mappng` is the default. Identical to monsterfish1 except that the
---   colliding names get their own colours, which makes a
---   game -> PNG -> game round trip an identity.

local M = {}

--- Logic1 bit flags, by name.
M.logic1 = {
  none = 0,
  default_earth_or_texture = 0x8000,

  ocean = 0x1,
  plain1_and_farm = 0x4,
  plain2_and_pitch = 0x8,

  border = 0x10,
  border_edge = 0x20,

  rocks = 0x80,

  moat_dug = 0x4000,

  -- These are distinguished by logic2, not logic1; they all sit on the
  -- "default earth or texture" bit.
  --
  -- `moat_undug` is absent from sourcehold's table. It never needed an entry
  -- there because monsterfish1 gives it the same colour as `moat`, so the
  -- dict inversion dropped the name before it could be looked up. With a
  -- palette that separates the two, importing an undug moat would otherwise
  -- clear the tile's logic1 entirely.
  moat_undug = 0x8000,
  oasis_grass = 0x8000,
  thick_scrub = 0x8000,
  scrub = 0x8000,
  driven_sand = 0x8000,
  beach = 0x8000,
  plateau_high = 0x8000,
  plateau_medium = 0x8000,
  earth_and_stones = 0x8000,

  boulders = 0x20000,
  pebbles = 0x40000,
  iron = 0x80000,
  river = 0x100000,
  ford = 0x200000,
  crenel_variation = 0x400000,
  marsh = 0x20000000,
  moat = 0x40000000,
  oil = 0x80000000,
}

--- Logic1 flags in the order the exporter must paint them.
---
--- This order is load-bearing: later entries overwrite earlier ones, so it
--- reproduces the iteration order of `logic1_vk` in `get_terrain`. `none` is
--- omitted because masking against 0 never matches.
M.logic1PaintOrder = {
  { flag = 0x8000, name = "default_earth_or_texture" },
  { flag = 0x1, name = "ocean" },
  { flag = 0x4, name = "plain1_and_farm" },
  { flag = 0x8, name = "plain2_and_pitch" },
  { flag = 0x10, name = "border" },
  { flag = 0x20, name = "border_edge" },
  { flag = 0x80, name = "rocks" },
  { flag = 0x4000, name = "moat_dug" },
  { flag = 0x20000, name = "boulders" },
  { flag = 0x40000, name = "pebbles" },
  { flag = 0x80000, name = "iron" },
  { flag = 0x100000, name = "river" },
  { flag = 0x200000, name = "ford" },
  { flag = 0x400000, name = "crenel_variation" },
  { flag = 0x20000000, name = "marsh" },
  { flag = 0x40000000, name = "moat" },
  { flag = 0x80000000, name = "oil" },
}

--- Logic2 values, by name. Note `moat_undug` is 3, not a single bit: logic2 is
--- compared by equality, not masked.
M.logic2 = {
  none = 0,
  thick_scrub = 0x80,
  driven_sand = 0x40,
  beach = 0x20,
  oasis_grass = 0x10,
  plateau_high = 0x8,
  plateau_medium = 0x4,
  moat_undug = 0x3,
  earth_and_stones = 0x2,
  scrub = 0x1,
}

--- Logic2 values in exporter paint order (`logic2_vk` iteration order, `none`
--- skipped). Only applied where logic1 has `default_earth_or_texture` set.
M.logic2PaintOrder = {
  { value = 0x80, name = "thick_scrub" },
  { value = 0x40, name = "driven_sand" },
  { value = 0x20, name = "beach" },
  { value = 0x10, name = "oasis_grass" },
  { value = 0x8, name = "plateau_high" },
  { value = 0x4, name = "plateau_medium" },
  { value = 0x3, name = "moat_undug" },
  { value = 0x2, name = "earth_and_stones" },
  { value = 0x1, name = "scrub" },
}

--- monsterfish1, as shipped by sourcehold-maps.
M.palettes = {
  sourcehold = {
    none = "#000000",
    default_earth_or_texture = "#ae9467",
    plateau_medium = "#ae9467",
    plateau_high = "#ae9467",

    border = "#ff0000",
    border_edge = "#dd0000",
    plain1_and_farm = "#cccccc",
    plain2_and_pitch = "#eeeeee",
    marsh = "#475937",
    oil = "#314235",
    boulders = "#c3bdb4",
    pebbles = "#978f80",

    rocks = "#675335",

    iron = "#9e4f00",
    ford = "#567c71",
    river = "#427068",

    moat_undug = "#0000ff",
    moat_dug = "#0000ff",
    moat = "#0000ff",
    ocean = "#1e4a44",
    oasis_grass = "#47540b",
    thick_scrub = "#6a692b",
    scrub = "#937e44",
    earth_and_stones = "#7c7059",

    driven_sand = "#b79453",
    beach = "#deb977",
  },
}

--- The default palette: monsterfish1 with the five colliding names separated so
--- that importing an exported PNG reproduces the map exactly.
do
  local mappng = {}
  for name, hex in pairs(M.palettes.sourcehold) do
    mappng[name] = hex
  end
  mappng.plateau_medium = "#c0a678"
  mappng.plateau_high = "#d2b889"
  mappng.moat_undug = "#3333ff"
  mappng.moat_dug = "#0000cc"
  mappng.moat = "#0000ff"
  M.palettes.mappng = mappng
end

M.DEFAULT_PALETTE = "mappng"

---@param hex string `#rrggbb`
---@return number r, number g, number b
function M.hexToRGB(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- Packs a colour into a single integer key, for exact-match lookups.
function M.packRGB(r, g, b)
  return (r << 16) | (g << 8) | b
end

--- Builds the two lookup directions for a palette.
---
--- `nameToColour` is used on export (every name that has a colour paints it).
--- `colourToName` is used on import. Where several names share a colour the
--- *first* in `preferenceOrder` wins, so the collapse is explicit and
--- deterministic instead of depending on table iteration order the way the
--- Python original does.
---
---@param paletteName string key into M.palettes
---@return table resolved { nameToColour = {...}, colourToName = {...}, collisions = {...} }
function M.resolve(paletteName)
  local hexes = M.palettes[paletteName]
  if hexes == nil then
    error(string.format("unknown palette: %s", tostring(paletteName)))
  end

  -- Names that must win a colour collision, most specific first. Anything not
  -- listed keeps whichever name claimed the colour first, in sorted order.
  local preferenceOrder = {
    "default_earth_or_texture",
    "moat",
    "moat_dug",
    "moat_undug",
    "plateau_medium",
    "plateau_high",
  }
  local preference = {}
  for i, name in ipairs(preferenceOrder) do
    preference[name] = i
  end

  local names = {}
  for name in pairs(hexes) do
    names[#names + 1] = name
  end
  table.sort(names)

  local nameToColour, colourToName, collisions = {}, {}, {}
  for _, name in ipairs(names) do
    local r, g, b = M.hexToRGB(hexes[name])
    local key = M.packRGB(r, g, b)
    nameToColour[name] = { r = r, g = g, b = b, key = key }

    local held = colourToName[key]
    if held == nil then
      colourToName[key] = name
    else
      collisions[#collisions + 1] = { colour = hexes[name], names = { held, name } }
      local heldRank = preference[held] or math.huge
      local ourRank = preference[name] or math.huge
      if ourRank < heldRank then
        colourToName[key] = name
      end
    end
  end

  return {
    name = paletteName,
    nameToColour = nameToColour,
    colourToName = colourToName,
    collisions = collisions,
  }
end

return M
