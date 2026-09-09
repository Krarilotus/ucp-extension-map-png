# Map PNG Import/Export

Adds four buttons under the minimap on the map editor screens for translating between
the map you are editing and PNG files:

- import height map
- export height map
- import terrain map
- export terrain map

PNGs are read from and written to a `mapping` folder in your game directory, which is
created automatically.

Height maps are grayscale, one pixel per tile. Terrain maps use one colour per terrain
type. Both are 400x400, matching the map grid.

Nothing is installed alongside the game: the conversion runs inside Stronghold Crusader
and uses the PNG support Windows already provides.
