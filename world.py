"""World data, infinite chunked terrain generation, meshing and save/load.

Pure Python — no Ursina import here, so this module can be unit-tested
without opening a window.
"""
import json
import math
import random
from collections import deque
from pathlib import Path

from blocks import (BLOCK_DEFS, BLOCKS, BLOCK_TILES, TRANSPARENT, TRANSLUCENT, NON_SOLID, LIGHT_EMIT,
                    UNBREAKABLE, PLANTS_NEED_SOIL, WATER, LAMP, GLASS, CUBE, CROSS, SLAB, STAIR, FENCE, LADDER,
                    DOOR, BED, TORCH, CARPET, DOORS, WOODS, FLOWERS, SLATE, LIMESTONE, RUBY_ORE, SAPPHIRE_ORE,
                    AMETHYST_ORE, QUARTZ_ORE, LEAFY_BUSH, BERRY_BUSH, DRY_BUSH)

CHUNK_SIZE = 16
MAX_HEIGHT = 320
SURFACE_OFFSET = 180       # the surface sits this far above the bedrock: ~190 layers of underground
WATER_LEVEL = 11 + SURFACE_OFFSET
TREE_CHANCE = 0.012
COAL_ORE = 13
MAX_LIGHT = 15
CAVE_THRESHOLD = 0.016     # bigger = more/wider caves
CAVE_GRID = 4              # cave noise is sampled every N blocks and interpolated
CAVE_FLOOR = 4             # caves never cut into the bedrock layers below this
SNOW_LINE = 27 + SURFACE_OFFSET   # mountain tops above this are snowy with pine trees
# underground layers (absolute y)
BEDROCK_TOP = 4            # y=0 is solid bedrock, y 1..3 random bedrock
SLATE_LINE = 88            # dark slate below about this (ragged boundary, +-6)
BASALT_LINE = 120          # basalt blobs below this (multiple of 4: decided per 8x4x8 blob)
LIMESTONE_LINE = 160       # limestone blobs from here up (multiple of 4)
CAVERN_TOP = 120           # big caverns below this
CAVERN_MID = 62            # ... most common around this height
CAVERN_LIMIT = 0.78        # cavern noise above this (plus more away from CAVERN_MID) is hollow
SAVE_VERSION = 4           # saves before version 4 were made when the surface was SURFACE_OFFSET lower

# Texture atlas layout: ATLAS_COLS x ATLAS_COLS tiles, read left-to-right, top-to-bottom.
ATLAS_COLS = 32
_BASE_TILES = [
    "grass_top", "grass_side", "dirt", "stone",
    "log_side", "log_top", "leaves", "sand",
    "planks", "brick", "bedrock", "water",
    "lamp", "glass", "coal_ore", "stick", "coal",
    "wood_pickaxe", "stone_pickaxe", "wood_axe", "stone_axe",
    "raw_meat", "cooked_meat", "apple",
]
ITEM_TILES = [
    "iron_ingot", "copper_ingot", "tin_ingot", "gold_ingot", "bronze_ingot", "diamond", "bucket", "water_bucket",
    "iron_pickaxe", "diamond_pickaxe", "iron_axe", "diamond_axe",
    "wood_shovel", "stone_shovel", "iron_shovel", "diamond_shovel",
    "wood_sword", "stone_sword", "iron_sword", "diamond_sword",
    "ruby", "sapphire", "amethyst", "quartz",
    "wood_hoe", "stone_hoe", "iron_hoe", "diamond_hoe", "seeds", "wheat", "bread", "carrot",
    "star_shard", "sky_key", "storm_core",
    "egg", "feather", "raw_fish", "cooked_fish", "cart", "observer_face", "observer_out_off", "observer_out_on", "thrower_face", "lava_bucket", "milk_bucket", "cake", "chest_cart", "glass_bottle", "water_bottle", "potion_swift",
    "potion_heal", "potion_night", "potion_leap", "potion_fire", "potion_water",
]
TILES = list(_BASE_TILES)
for _tiles in BLOCK_TILES.values():
    for _t in _tiles:
        if _t not in TILES:
            TILES.append(_t)
TILES += [t for t in ITEM_TILES if t not in TILES]
assert len(TILES) <= ATLAS_COLS * ATLAS_COLS, "texture atlas is full"
NEIGHBOURS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))

# (normal, brightness) — simple fake lighting so cube edges are visible.
FACES = [
    ((0, 1, 0), 1.00),
    ((0, -1, 0), 0.55),
    ((1, 0, 0), 0.82),
    ((-1, 0, 0), 0.82),
    ((0, 0, 1), 0.68),
    ((0, 0, -1), 0.68),
]


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _face_corners(normal):
    """Corners (as two triangles) of a unit-cube face, front-facing in Ursina, plus tile UVs.

    Ursina's built-in Quad (normal -Z, visible from the default camera) has
    cross(v1 - v0, v2 - v0) pointing opposite to its normal, so we match that.
    Side faces get v along +Y so textures stay upright.
    """
    u_axis, v_axis = [axis for axis in range(3) if normal[axis] == 0]
    corners = []
    for du, dv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        c = [normal[0] * 0.5, normal[1] * 0.5, normal[2] * 0.5]
        c[u_axis] = du * 0.5
        c[v_axis] = dv * 0.5
        corners.append(tuple(c))
    if _dot(_cross(_sub(corners[1], corners[0]), _sub(corners[2], corners[0])), normal) > 0:
        corners.reverse()

    def uv(c):
        if normal[1] != 0:
            return (c[0] + 0.5, c[2] + 0.5)
        horizontal = 2 if normal[0] != 0 else 0
        return (c[horizontal] + 0.5, c[1] + 0.5)

    order = (0, 1, 2, 2, 3, 0)
    return [corners[i] for i in order], [uv(corners[i]) for i in order]


FACE_VERTS = [(normal, shade) + tuple(_face_corners(normal)) for normal, shade in FACES]


def tile_uv(tile, u, v, inset=0.01):
    """Map a (u, v) in 0..1 inside a tile to atlas UVs (Panda3D: v=0 is the image bottom)."""
    index = TILES.index(tile)
    col, row = index % ATLAS_COLS, index // ATLAS_COLS
    u = inset + u * (1 - 2 * inset)
    v = inset + v * (1 - 2 * inset)
    return ((col + u) / ATLAS_COLS, 1 - (row + 1 - v) / ATLAS_COLS)


# Pre-computed atlas UVs per (block id, face index).
_FACE_UVS = {
    (block_id, i): [tile_uv(tiles[0] if normal[1] > 0 else tiles[2] if normal[1] < 0 else tiles[1], u, v)
                    for u, v in uvs]
    for block_id, tiles in BLOCK_TILES.items()
    for i, (normal, _shade, _corners, uvs) in enumerate(FACE_VERTS)
}


# ---------------------------------------------------------------- noise
def _hash(x, z, seed):
    n = (x * 374761393 + z * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return (n ^ (n >> 16)) / 0xFFFFFFFF


def _smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(x, z, seed):
    x0, z0 = math.floor(x), math.floor(z)
    tx, tz = _smooth(x - x0), _smooth(z - z0)
    a = _hash(x0, z0, seed)
    b = _hash(x0 + 1, z0, seed)
    c = _hash(x0, z0 + 1, seed)
    d = _hash(x0 + 1, z0 + 1, seed)
    top = a + (b - a) * tx
    bottom = c + (d - c) * tx
    return top + (bottom - top) * tz


def _hash3(x, y, z, seed):
    n = (x * 374761393 + y * 1103515245 + z * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return (n ^ (n >> 16)) / 0xFFFFFFFF


def value_noise3(x, y, z, seed):
    x0, y0, z0 = math.floor(x), math.floor(y), math.floor(z)
    tx, ty, tz = _smooth(x - x0), _smooth(y - y0), _smooth(z - z0)

    def lerp(a, b, t):
        return a + (b - a) * t

    def edge(i, j):
        return lerp(_hash3(x0 + i, y0 + j, z0, seed), _hash3(x0 + i, y0 + j, z0 + 1, seed), tz)

    return lerp(lerp(edge(0, 0), edge(0, 1), ty), lerp(edge(1, 0), edge(1, 1), ty), tx)


def cave_density(x, y, z, seed):
    """Two noise fields; where both are near 0.5 at once we get long winding tunnels."""
    a = value_noise3(x / 14, y / 9, z / 14, seed + 300) - 0.5
    b = value_noise3(x / 14, y / 9, z / 14, seed + 600) - 0.5
    return a * a + b * b


def cavern_density(x, y, z, seed):
    """Big caverns deep down, on the same scale as cave_density (below CAVE_THRESHOLD = hollow):
    a low-frequency blob noise whose threshold rises away from CAVERN_MID."""
    t = (y - CAVERN_MID) / (CAVERN_TOP - CAVERN_MID)
    limit = CAVERN_LIMIT + 0.18 * t * t
    c = value_noise3(x / 32, y / 16, z / 32, seed + 900)
    return CAVE_THRESHOLD + (limit - c) * 0.25


def fbm(x, z, seed, octaves=4):
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for i in range(octaves):
        total += value_noise(x * freq, z * freq, seed + i * 101) * amp
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm


# ---------------------------------------------------------------- world
class World:
    """An endless world. Chunks are generated on demand from the seed and can be
    unloaded again; player edits are kept separately so they survive both."""

    def __init__(self, seed=None):
        self.seed = random.randint(0, 999_999) if seed is None else seed
        self.blocks = {}          # (x, y, z) -> block id, for loaded chunks only
        self.chunks = {}          # (cx, cz) -> set of (x, y, z)
        self.changes = {}         # player edits: (cx, cz) -> {(x, y, z): id (0 = removed)}
        self.lamps = set()        # positions of light-emitting blocks in loaded chunks
        self._columns = {}        # cache: (cx, cz) -> {(x, z): (top solid y, water surface y)}
        self.time_of_day = 0.2    # 0 = sunrise, 0.25 = noon, 0.5 = sunset, 0.75 = midnight
        self.player_data = {}     # inventory etc., stored by the game in the save file
        self.containers = {}      # chest contents: (x, y, z) -> list of slots
        self._climate = {}        # cache: (x, z) -> column noise results

    # -- basic access
    @staticmethod
    def chunk_key(x, z):
        return (x // CHUNK_SIZE, z // CHUNK_SIZE)

    def get(self, x, y, z):
        return self.blocks.get((x, y, z), 0)

    def _put(self, pos, block_id):
        key = self.chunk_key(pos[0], pos[2])
        if block_id:
            self.blocks[pos] = block_id
            self.chunks[key].add(pos)
        elif pos in self.blocks:
            del self.blocks[pos]
            self.chunks[key].discard(pos)
        if block_id in LIGHT_EMIT:
            self.lamps.add(pos)
        else:
            self.lamps.discard(pos)

    def set(self, x, y, z, block_id, force=False, flood=True):
        """Player edit. Returns the loaded chunk keys whose mesh must be rebuilt.
        force: allow removing unbreakable blocks (creative, buckets). flood: let water flow in."""
        pos = (x, y, z)
        key = self.chunk_key(x, z)
        if not 0 <= y < MAX_HEIGHT or key not in self.chunks:
            return set()
        old = self.get(*pos)
        if block_id == 0 and old in UNBREAKABLE and not force:
            return set()
        self._edit(pos, block_id)
        touched = [pos]
        if block_id == 0:
            if old in DOORS:                       # a door is two blocks: remove the other half too
                other = (x, y - 1, z) if DOORS[old]["top"] else (x, y + 1, z)
                if self.get(*other) in DOORS:
                    self._edit(other, 0)
                    touched.append(other)
            above = (x, y + 1, z)                  # plants, torches, cactus and reeds need something below
            while self.get(*above) in PLANTS_NEED_SOIL | {50, 60}:
                self._edit(above, 0)
                touched.append(above)
                above = (above[0], above[1] + 1, above[2])
            if flood:
                touched += self._flood(pos)
        # neighbours across a chunk border also need a rebuild
        return {k for (tx, _, tz) in touched
                for k in (self.chunk_key(tx + dx, tz + dz) for dx, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)))
                if k in self.chunks}

    def bulk_set(self, changes):
        """Apply many edits at once (creative building tools). Cells in unloaded chunks or
        outside the height range are skipped. Returns (chunk keys to rebuild, {pos: previous id})."""
        previous = {}
        for pos, block_id in changes.items():
            x, y, z = pos
            if not 0 <= y < MAX_HEIGHT or self.chunk_key(x, z) not in self.chunks:
                continue
            old = self.blocks.get(pos, 0)
            if old == block_id:
                continue
            previous[pos] = old
            self._edit(pos, block_id)
        keys = set()
        for x, _, z in previous:
            for dx, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                k = self.chunk_key(x + dx, z + dz)
                if k in self.chunks:
                    keys.add(k)
        return keys, previous

    def _edit(self, pos, block_id):
        self._put(pos, block_id)
        self._columns.pop(self.chunk_key(pos[0], pos[2]), None)
        self.changes.setdefault(self.chunk_key(pos[0], pos[2]), {})[pos] = block_id

    def _flood(self, start, limit=64):
        """Let water flow into a freshly emptied space (sideways and down, never up)."""
        def wet_neighbour(p):
            x, y, z = p
            return any(self.get(*n) == WATER for n in ((x + 1, y, z), (x - 1, y, z), (x, y, z + 1), (x, y, z - 1), (x, y + 1, z)))

        if not wet_neighbour(start):
            return []
        filled, queue = [], [start]
        while queue and len(filled) < limit:
            p = queue.pop(0)
            x, y, z = p
            if self.get(*p) or self.chunk_key(x, z) not in self.chunks or not 0 < y < MAX_HEIGHT:
                continue
            self._edit(p, WATER)
            filled.append(p)
            queue += [(x, y - 1, z), (x + 1, y, z), (x - 1, y, z), (x, y, z + 1), (x, y, z - 1)]
        return filled

    # -- generation
    def height_at(self, x, z):
        return self._column_climate(x, z)[0]

    def _column_climate(self, x, z):
        """(height, desert?, tree?, tree kind, forest density) of a column, cached: these noise
        lookups are asked for many times per column while generating."""
        cached = self._climate.get((x, z))
        if cached:
            return cached
        seed = self.seed
        hills = fbm(x / 28, z / 28, seed)
        mountains = fbm(x / 90, z / 90, seed + 7) ** 2
        h = int(3 + hills * 12 + mountains * 22) + SURFACE_OFFSET
        desert = WATER_LEVEL + 1 < h < SNOW_LINE - 3 and fbm(x / 140, z / 140, seed + 31, 2) > 0.6
        forest = fbm(x / 60, z / 60, seed + 41, 2)
        tree = (not desert and h > WATER_LEVEL
                and _hash(x, z, seed + 777) < TREE_CHANCE * (0.6 + 1.6 * forest))
        kind = "oak"
        if h >= SNOW_LINE - 3:
            kind = "pine"
        elif tree:
            kind = self._tree_species(x, z, h, forest)
        if len(self._climate) > 400_000:
            self._climate.clear()
        result = self._climate[(x, z)] = (h, desert, tree, kind, forest)
        return result

    def _tree_species(self, x, z, h, forest):
        """Which broadleaf tree grows here: dry land near deserts gets ashwood, deep forests
        ebony, and big patches of maple, cherry and birch are spread around the rest."""
        seed = self.seed
        if WATER_LEVEL + 1 < h < SNOW_LINE - 3 and fbm(x / 140, z / 140, seed + 31, 2) > 0.47:
            return "ashwood"                     # savanna around the deserts
        if forest > 0.6 and _hash(x, z, seed + 779) < 0.55:
            return "ebony"
        if fbm(x / 50, z / 50, seed + 43, 2) > 0.56:
            return "birch"
        patch = fbm(x / 64, z / 64, seed + 47, 2)
        if patch > 0.58:
            return "maple"
        if patch < 0.4:
            return "cherry"
        return "oak"

    def has_tree(self, x, z):
        return self._column_climate(x, z)[2]

    def is_desert(self, x, z):
        return self._column_climate(x, z)[1]

    def tree_kind(self, x, z):
        return self._column_climate(x, z)[3]

    def ensure_chunk(self, key):
        """Generate a chunk (and re-apply the player's edits in it) if it isn't loaded."""
        if key in self.chunks:
            return False
        cx, cz = key
        x0, z0 = cx * CHUNK_SIZE, cz * CHUNK_SIZE
        seed = self.seed
        rock = self._rock
        cells = {}
        surface = {}
        for x in range(x0, x0 + CHUNK_SIZE):
            for z in range(z0, z0 + CHUNK_SIZE):
                h = self.height_at(x, z)
                beach = h <= WATER_LEVEL + 1
                desert = self.is_desert(x, z)
                snowy = h >= SNOW_LINE
                if desert:
                    top_block, filler = 6, 6
                elif beach:
                    top_block, filler = 6, 6
                    if h < WATER_LEVEL - 1:              # sea floor: patches of clay and gravel
                        r = _hash(x >> 2, z >> 2, seed + 61)
                        top_block = filler = 15 if r < 0.25 else 14 if r < 0.4 else 6
                else:
                    top_block, filler = (16 if snowy else 1), 2
                rock_top = h - 6 if desert else h - 3    # deserts have sandstone under the sand
                slate = self.slate_line(x, z)
                cells[(x, 0, z)] = 9
                for y in range(1, h + 1):
                    if y < BEDROCK_TOP and _hash3(x, y, z, seed + 5) < (BEDROCK_TOP - y) * 0.2:
                        b = 9                                # ragged bedrock floor
                    elif y < rock_top:
                        b = rock(x, y, z, slate)
                    elif y < h - 3:
                        b = 20
                    elif y < h:
                        b = filler
                    else:
                        b = top_block
                    cells[(x, y, z)] = b
                for y in range(h + 1, WATER_LEVEL + 1):
                    cells[(x, y, z)] = WATER
                surface[(x, z)] = (h, top_block, desert)
        self.blocks.update(cells)                    # no generated terrain block emits light
        self.chunks[key] = set(cells)
        self._carve_caves(key)
        self._plants(key, surface)
        # trees near the border overlap neighbouring chunks; each chunk keeps only its part
        for tx in range(x0 - 2, x0 + CHUNK_SIZE + 2):
            for tz in range(z0 - 2, z0 + CHUNK_SIZE + 2):
                if self.has_tree(tx, tz):
                    self._tree(tx, self.height_at(tx, tz) + 1, tz, key, self.tree_kind(tx, tz))
        for pos, b in self.changes.get(key, {}).items():
            self._put(pos, b)
        return True

    def slate_line(self, x, z):
        """Below this y the rock is dark slate instead of stone (a wavy, ragged boundary)."""
        seed = self.seed
        return SLATE_LINE - 6 + int(value_noise(x / 16, z / 16, seed + 81) * 9) + int(_hash(x, z, seed + 82) * 3)

    # ores: (block, chance band, deepest y it can appear at). Common ores reach up to the
    # surface, rare ones only appear deep down.
    ORES = [(COAL_ORE, 0.050, MAX_HEIGHT), (26, 0.064, 205), (27, 0.074, 205), (25, 0.086, 150), (28, 0.091, 64),
            (29, 0.094, 24), (14, 0.104, MAX_HEIGHT),   # gravel pockets
            (RUBY_ORE, 0.107, 40), (SAPPHIRE_ORE, 0.110, 40), (AMETHYST_ORE, 0.115, 90), (QUARTZ_ORE, 0.121, 160)]
    ORE_LIMIT = ORES[-1][1]

    def _rock(self, x, y, z, slate):
        """Underground block: stone (slate deep down) with patches of other rock, and ore clusters by depth."""
        seed = self.seed
        r = _hash3(x >> 1, y >> 1, z >> 1, seed + 55)          # 2x2x2 cells decide ore clusters
        if r < self.ORE_LIMIT:
            for block_id, band, max_y in self.ORES:
                if r < band:
                    if y <= max_y and _hash3(x, y, z, seed + 56) < 0.6:
                        return block_id
                    break
        v = _hash3(x >> 3, y >> 2, z >> 3, seed + 71)          # big blobs of other rock types
        if v < 0.08:
            return 18                                             # granite
        if v < 0.15 and y < BASALT_LINE:
            return 19                                             # basalt, deeper down
        if v < 0.19:
            return 21                                             # marble
        if v < 0.25 and y >= LIMESTONE_LINE:
            return LIMESTONE                                      # pale limestone, nearer the surface
        if y < slate:
            return SLATE                                          # a deep layer of dark slate
        return 3

    def _plants(self, key, surface):
        """Grass tufts, flowers, ferns, mushrooms, reeds by the water and cacti in deserts."""
        seed = self.seed
        flowers = FLOWERS
        for (x, z), (h, top_block, desert) in surface.items():
            y = h + 1
            if self.get(x, h, z) != top_block or self.get(x, y, z) or self.has_tree(x, z):
                continue                                          # carved away, under water or a trunk spot
            r = _hash(x, z, seed + 91)
            if desert:
                if r < 0.012:
                    for dy in range(1 + int(_hash(x, z, seed + 92) * 3)):
                        self._put((x, y + dy, z), 60)
                elif r < 0.03:
                    self._put((x, y, z), DRY_BUSH)
                continue
            if top_block == 6 and h == WATER_LEVEL + 1 and r < 0.25:
                near_water = any(self.height_at(x + dx, z + dz) <= WATER_LEVEL
                                 for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if near_water:
                    for dy in range(1 + int(_hash(x, z, seed + 93) * 3)):
                        self._put((x, y + dy, z), 59)
                continue
            if top_block != 1:
                continue
            forest = self._column_climate(x, z)[4]
            if r < 0.10:
                self._put((x, y, z), 51)
            elif r < 0.135:
                # flowers grow in patches of one kind, with a few strays of any kind
                pick = _hash(x >> 3, z >> 3, seed + 96) if _hash(x, z, seed + 94) < 0.75 else _hash(x, z, seed + 97)
                self._put((x, y, z), flowers[int(pick * len(flowers))])
            elif r < 0.135 + 0.05 * forest:
                self._put((x, y, z), 52)
            elif r < 0.14 + 0.05 * forest and forest > 0.5:
                self._put((x, y, z), 57 if _hash(x, z, seed + 95) < 0.4 else 58)
            elif r < 0.155 + 0.05 * forest:
                self._put((x, y, z), BERRY_BUSH if _hash(x, z, seed + 98) < 0.3 else LEAFY_BUSH)
            elif r < 0.16 + 0.05 * forest and forest < 0.45:
                self._put((x, y, z), 951 if _hash(x, z, seed + 99) < 0.5 else 952)   # wild pumpkins and melons

    def _carve_caves(self, key):
        """Hollow out tunnels everywhere and big caverns deep down. Noise is sampled on a coarse
        grid and interpolated, and grid cells whose corners are all solid are skipped."""
        g = CAVE_GRID
        cx, cz = key
        x0, z0 = cx * CHUNK_SIZE, cz * CHUNK_SIZE
        seed = self.seed
        cols = {}
        for x in range(x0, x0 + CHUNK_SIZE):
            for z in range(z0, z0 + CHUNK_SIZE):
                h = self.height_at(x, z)
                # keep a solid roof under the sea / lakes and under tree trunks
                if h <= WATER_LEVEL + 2:
                    top = h - 4
                elif self.has_tree(x, z):
                    top = h - 1
                else:
                    top = h
                cols[(x, z)] = top
        ymax = max(cols.values())
        n = CHUNK_SIZE // g
        grid = {}
        for i in range(n + 1):
            for k in range(n + 1):
                for j in range(ymax // g + 2):
                    gx, gy, gz = x0 + i * g, j * g, z0 + k * g
                    d = cave_density(gx, gy, gz, seed)
                    if gy < CAVERN_TOP:
                        d = min(d, cavern_density(gx, gy, gz, seed))
                    grid[(i, j, k)] = d
        for i in range(n):
            for k in range(n):
                for j in range(ymax // g + 1):
                    c = [grid[(i + a, j + b, k + d)] for a in (0, 1) for b in (0, 1) for d in (0, 1)]
                    if min(c) >= CAVE_THRESHOLD:
                        continue  # interpolation never goes below the smallest corner
                    for lx in range(g):
                        fx = lx / g
                        for ly in range(g):
                            y = j * g + ly
                            if y < CAVE_FLOOR:
                                continue
                            fy = ly / g
                            for lz in range(g):
                                x, z = x0 + i * g + lx, z0 + k * g + lz
                                if y > cols[(x, z)]:
                                    continue
                                fz = lz / g
                                c00 = c[0] + (c[1] - c[0]) * fz
                                c01 = c[2] + (c[3] - c[2]) * fz
                                c10 = c[4] + (c[5] - c[4]) * fz
                                c11 = c[6] + (c[7] - c[6]) * fz
                                c0 = c00 + (c01 - c00) * fy
                                c1 = c10 + (c11 - c10) * fy
                                if c0 + (c1 - c0) * fx < CAVE_THRESHOLD:
                                    self._put((x, y, z), 0)

    def _tree(self, x, y, z, key, kind="oak"):
        def put(p, b):
            if self.chunk_key(p[0], p[2]) == key and p[1] < MAX_HEIGHT and self.get(*p) in (0, WATER, 51, 52):
                self._put(p, b)

        if kind == "pine":                      # tall and cone shaped
            for dy in range(6):
                put((x, y + dy, z), 38)
            for dy, r in ((2, 2), (3, 2), (4, 1), (5, 1), (6, 1), (7, 0)):
                for dx in range(-r, r + 1):
                    for dz in range(-r, r + 1):
                        if abs(dx) + abs(dz) <= r + (1 if r == 2 else 0):
                            put((x + dx, y + dy, z + dz), 40)
            return
        log, leaves = WOODS[kind]["log"], WOODS[kind]["leaves"]
        height, layers = self.TREE_SHAPES[kind]
        for dy in range(height):
            put((x, y + dy, z), log)
        for dy, r, reach in layers:         # leaf layer: height, radius, how far the corners reach
            for dx in range(-r, r + 1):
                for dz in range(-r, r + 1):
                    if abs(dx) + abs(dz) <= reach:
                        put((x + dx, y + dy, z + dz), leaves)

    # broadleaf trees: (trunk height, [(layer height, radius, max |dx|+|dz|)]); radius <= 2 so a
    # tree never reaches further than the 2-block border ensure_chunk scans for trunks
    TREE_SHAPES = {
        "oak": (4, [(2, 2, 3), (3, 2, 3), (4, 1, 1)]),
        "birch": (5, [(3, 2, 3), (4, 2, 3), (5, 1, 1)]),
        "maple": (5, [(2, 2, 2), (3, 2, 4), (4, 2, 3), (5, 1, 2), (6, 0, 0)]),
        "cherry": (4, [(2, 2, 3), (3, 2, 4), (4, 2, 2)]),
        "ashwood": (5, [(4, 2, 3), (5, 2, 2)]),
        "ebony": (7, [(3, 1, 1), (4, 2, 2), (5, 2, 3), (6, 1, 2), (7, 1, 1), (8, 0, 0)]),
    }

    def unload_chunk(self, key):
        for pos in self.chunks.pop(key, ()):
            del self.blocks[pos]
            self.lamps.discard(pos)
        self._columns.pop(key, None)

    def column(self, x, z):
        """(top solid y, water surface y) of a loaded column, or None if its chunk isn't loaded."""
        key = self.chunk_key(x, z)
        if key not in self.chunks:
            return None
        return tuple(self._column_info(key)[(x, z)])

    def solid(self, x, y, z):
        """Can something stand on / bump into this cell? (Unloaded chunks count as solid walls.)"""
        if self.chunk_key(x, z) not in self.chunks:
            return True
        return self.blocks.get((x, y, z), 0) not in NON_SOLID

    def spawn_point(self):
        return (8, self.top_y(8, 8) + 1.5, 8)

    def top_y(self, x, z):
        self.ensure_chunk(self.chunk_key(x, z))
        return max((y for (bx, y, bz) in self.chunks[self.chunk_key(x, z)] if bx == x and bz == z), default=0)

    # -- lighting
    def _column_info(self, key):
        """Per column: highest light-blocking block and highest water block (-1 if none)."""
        info = self._columns.get(key)
        if info is None:
            cx, cz = key
            info = {(x, z): [-1, -1] for x in range(cx * CHUNK_SIZE, (cx + 1) * CHUNK_SIZE)
                    for z in range(cz * CHUNK_SIZE, (cz + 1) * CHUNK_SIZE)}
            blocks = self.blocks
            for pos in self.chunks[key]:
                col = info[(pos[0], pos[2])]
                b = blocks[pos]
                if b == WATER:
                    col[1] = max(col[1], pos[1])
                elif b in TRANSPARENT:
                    continue
                elif pos[1] > col[0]:
                    col[0] = pos[1]
            self._columns[key] = info
        return info

    @staticmethod
    def _open_sky(y, water_top):
        """Light of a cell with nothing solid above it; water dims it 2 levels per block."""
        if y > water_top:
            return MAX_LIGHT
        return max(MAX_LIGHT - 2 * (water_top - y + 1), 2)

    def compute_light(self, cx, cz):
        """Sky and block light for the chunk and its 8 neighbours.

        Cells with open sky above them are lit by formula; light then spreads (BFS,
        -1 per block, -2 through water) into caves, overhangs and under trees.
        Returns a function (x, y, z) -> (sky level, block level).
        """
        columns = {}
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                columns.update(self._column_info((cx + dx, cz + dz)))
        x_lo, x_hi = (cx - 1) * CHUNK_SIZE, (cx + 2) * CHUNK_SIZE
        z_lo, z_hi = (cz - 1) * CHUNK_SIZE, (cz + 2) * CHUNK_SIZE
        blocks = self.blocks

        def spread(queue, light, sky):
            while queue:
                x, y, z, level = queue.popleft()
                for dx, dy, dz in NEIGHBOURS:
                    nx, ny, nz = x + dx, y + dy, z + dz
                    if not (x_lo <= nx < x_hi and z_lo <= nz < z_hi and 0 < ny < MAX_HEIGHT):
                        continue
                    if sky and ny > columns[(nx, nz)][0]:
                        continue                    # already fully lit by the open sky
                    b = blocks.get((nx, ny, nz), 0)
                    if b and b not in TRANSPARENT:
                        continue
                    new = level - (2 if b == WATER else 1)
                    if new > light.get((nx, ny, nz), 0):
                        light[(nx, ny, nz)] = new
                        if new > 1:
                            queue.append((nx, ny, nz, new))

        # sky light: seed from open-sky cells that sit next to a taller neighbour column
        sky_light, queue = {}, deque()
        for (x, z), (top, water_top) in columns.items():
            highest = max(columns.get((x + dx, z + dz), (top,))[0] for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            for y in range(top + 1, highest + 1):
                queue.append((x, y, z, self._open_sky(y, water_top)))
        spread(queue, sky_light, sky=True)

        block_light, queue = {}, deque()
        for (x, y, z) in self.lamps:
            if x_lo <= x < x_hi and z_lo <= z < z_hi:
                level = LIGHT_EMIT[blocks[(x, y, z)]]
                queue.append((x, y, z, level + 1))  # +1: the lamp cell itself, neighbours get `level`
        spread(queue, block_light, sky=False)

        def light_at(x, y, z):
            top, water_top = columns.get((x, z), (MAX_HEIGHT, -1))
            sky = self._open_sky(y, water_top) if y > top else sky_light.get((x, y, z), 0)
            return sky, block_light.get((x, y, z), 0)

        return light_at

    # -- meshing
    def chunk_mesh(self, cx, cz):
        """Mesh data for a chunk, by how it is drawn:
        "solid" (opaque + cut-out, collides), "translucent" (coloured glass/ice, collides),
        "water" (no collision) and "plants" (walk-through: plants, torches, ladders).
        Each is (verts, colors, uvs); only visible faces are emitted. Neighbouring chunks are
        generated first so faces on the border are culled correctly.
        """
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                self.ensure_chunk((cx + dx, cz + dz))
        out = {"solid": ([], [], []), "translucent": ([], [], []), "water": ([], [], []), "plants": ([], [], [])}
        blocks = self.blocks
        light_at = self.compute_light(cx, cz)
        for pos in self.chunks[(cx, cz)]:
            x, y, z = pos
            block_id = blocks[pos]
            d = BLOCK_DEFS.get(block_id)
            if d is None:
                continue
            if d["shape"] != CUBE:
                self._shape_mesh(out, block_id, d, x, y, z, light_at)
                continue
            water = block_id == WATER
            group = "water" if water else "translucent" if block_id in TRANSLUCENT else "solid"
            verts, colors, uvs = out[group]
            # water surface sits a little lower than a full block
            lowered = water and blocks.get((x, y + 1, z)) != WATER
            for i, ((nx, ny, nz), shade, corners, _) in enumerate(FACE_VERTS):
                neighbour = blocks.get((x + nx, y + ny, z + nz), 0)
                if water:
                    if neighbour == WATER or (neighbour and neighbour not in TRANSPARENT):
                        continue           # water shows against air and see-through blocks
                elif (neighbour and (neighbour not in TRANSPARENT or neighbour == block_id)) or (ny == -1 and y == 0):
                    continue               # hidden behind an opaque block, or glass next to the same glass
                # vertex colour carries the light for the shader: r = sky, g = block light, b = face shade
                sky, lamp = light_at(x + nx, y + ny, z + nz)
                if block_id in LIGHT_EMIT:
                    lamp = MAX_LIGHT
                col = (sky / MAX_LIGHT, lamp / MAX_LIGHT, shade, 1.0)
                for vx, vy, vz in corners:
                    if lowered and vy > 0:
                        vy = 0.4
                    verts.append((x + vx, y + vy, z + vz))
                colors.extend((col,) * 6)
                uvs.extend(_FACE_UVS[(block_id, i)])
        return out

    def shape_boxes(self, block_id, x, y, z):
        """The boxes (x0, y0, z0, x1, y1, z1 within -0.5..0.5) a non-cube block is made of."""
        d = BLOCK_DEFS[block_id]
        shape = d["shape"]
        if shape == SLAB:
            return [(-.5, -.5, -.5, .5, 0, .5)]
        if shape == CARPET:
            return [(-.5, -.5, -.5, .5, -.4375, .5)]
        if shape == STAIR:
            upper = [(-.5, 0, 0, .5, .5, .5), (0, 0, -.5, .5, .5, .5),
                     (-.5, 0, -.5, .5, .5, 0), (-.5, 0, -.5, 0, .5, .5)][d["facing"]]
            return [(-.5, -.5, -.5, .5, 0, .5), upper]
        if shape == BED:
            return [(-.5, -.5, -.5, .5, .06, .5)]
        if shape == TORCH:
            return [(-.0625, -.5, -.0625, .0625, .3, .0625)]
        if shape == LADDER:
            return [[(-.5, -.5, .42, .5, .5, .5), (.42, -.5, -.5, .5, .5, .5),
                     (-.5, -.5, -.5, .5, .5, -.42), (-.5, -.5, -.5, -.42, .5, .5)][d["facing"]]]
        if shape == DOOR:
            door = d["door"]
            if door["axis"] == 0:
                return [(-.5, -.5, -.5, -.32, .5, .5)] if door["open"] else [(-.5, -.5, -.09, .5, .5, .09)]
            return [(-.5, -.5, -.5, .5, .5, -.32)] if door["open"] else [(-.09, -.5, -.5, .09, .5, .5)]
        if shape == FENCE:
            boxes = [(-.125, -.5, -.125, .125, .5, .125)]
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = self.blocks.get((x + dx, y, z + dz), 0)
                if n == block_id or (n and n not in TRANSPARENT):
                    for y0, y1 in ((.1, .32), (-.25, -.05)):
                        if dx:
                            a, b = (.125, .5) if dx > 0 else (-.5, -.125)
                            boxes.append((a, y0, -.06, b, y1, .06))
                        else:
                            a, b = (.125, .5) if dz > 0 else (-.5, -.125)
                            boxes.append((-.06, y0, a, .06, y1, b))
            return boxes
        return [(-.5, -.5, -.5, .5, .5, .5)]

    def _shape_mesh(self, out, block_id, d, x, y, z, light_at):
        sky, lamp = light_at(x, y, z)
        if block_id in LIGHT_EMIT:
            lamp = MAX_LIGHT
        top, side, bottom = d["tiles"]
        if d["shape"] == CROSS:                       # two crossed, double-sided quads
            verts, colors, uvs = out["plants"]
            col = (sky / MAX_LIGHT, lamp / MAX_LIGHT, 0.9, 1.0)
            for (ax, az), (bx, bz) in (((-.45, -.45), (.45, .45)), ((-.45, .45), (.45, -.45))):
                quad = [(ax, -.5, az), (bx, -.5, bz), (bx, .5, bz), (ax, .5, az)]
                quad_uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
                for order in ((0, 1, 2, 2, 3, 0), (0, 3, 2, 2, 1, 0)):
                    for i in order:
                        vx, vy, vz = quad[i]
                        verts.append((x + vx, y + vy, z + vz))
                        uvs.append(tile_uv(side, *quad_uv[i]))
                    colors.extend((col,) * 6)
            return
        group = "plants" if d["shape"] in (LADDER, TORCH, CARPET) else "solid"   # plants: no collision
        verts, colors, uvs = out[group]
        blocks = self.blocks
        for box in self.shape_boxes(block_id, x, y, z):
            lo, hi = box[:3], box[3:]
            for (normal, shade, corners, _) in FACE_VERTS:
                axis = next(a for a in range(3) if normal[a])
                on_edge = (hi if normal[axis] > 0 else lo)[axis] == (0.5 if normal[axis] > 0 else -0.5)
                if on_edge:
                    n = blocks.get((x + normal[0], y + normal[1], z + normal[2]), 0)
                    if n and n not in TRANSPARENT:
                        continue                      # flush against an opaque block
                tile = top if normal[1] > 0 else bottom if normal[1] < 0 else side
                col = (sky / MAX_LIGHT, lamp / MAX_LIGHT, shade, 1.0)
                for c in corners:
                    p = [lo[a] if c[a] < 0 else hi[a] for a in range(3)]
                    verts.append((x + p[0], y + p[1], z + p[2]))
                    # project onto the face so a half-height slab shows half the texture
                    if normal[1]:
                        u, v = p[0] + .5, p[2] + .5
                    else:
                        u, v = (p[2] if normal[0] else p[0]) + .5, p[1] + .5
                    uvs.append(tile_uv(tile, u, v))
                colors.extend((col,) * 6)

    def raycast(self, origin, direction, max_distance=6.0, hit_water=False):
        """Walk the voxel grid from `origin` along `direction` (DDA). Returns
        (block position, face normal, distance) of the first block hit, or (None, None, None)."""
        ox, oy, oz = origin[0] + 0.5, origin[1] + 0.5, origin[2] + 0.5   # blocks are centred on integers
        dx, dy, dz = direction
        cell = [math.floor(ox), math.floor(oy), math.floor(oz)]
        step, t_max, t_delta = [0, 0, 0], [math.inf] * 3, [math.inf] * 3
        for a, (o, d) in enumerate(((ox, dx), (oy, dy), (oz, dz))):
            if d > 0:
                step[a], t_max[a], t_delta[a] = 1, (math.floor(o) + 1 - o) / d, 1 / d
            elif d < 0:
                step[a], t_max[a], t_delta[a] = -1, (o - math.floor(o)) / -d, -1 / d
        normal = (0, 0, 0)
        t = 0.0
        while t <= max_distance:
            b = self.blocks.get(tuple(cell), 0)
            if b and (b != WATER or hit_water):
                return tuple(cell), normal, t
            a = t_max.index(min(t_max))
            t = t_max[a]
            t_max[a] += t_delta[a]
            cell[a] += step[a]
            normal = tuple(-step[a] if i == a else 0 for i in range(3))
        return None, None, None

    # -- persistence (only the seed + player edits are stored)
    def save(self, path, player=None):
        data = {
            "player": player or {},
            "version": SAVE_VERSION,
            "seed": self.seed,
            "time_of_day": self.time_of_day,
            "containers": [[list(pos), slots] for pos, slots in self.containers.items()],
            "changes": [[x, y, z, b] for edits in self.changes.values() for (x, y, z), b in edits.items()],
        }
        Path(path).write_text(json.dumps(data))

    @classmethod
    def load(cls, path):
        data = cls.migrate(json.loads(Path(path).read_text()))
        world = cls(seed=data["seed"])
        world.time_of_day = data.get("time_of_day", world.time_of_day)
        world.player_data = data.get("player", {})
        world.containers = {tuple(pos): slots for pos, slots in data.get("containers", [])}
        for x, y, z, b in data["changes"]:
            world.changes.setdefault(cls.chunk_key(x, z), {})[(x, y, z)] = b
        return world

    # positions the game keeps in the save's player data: single points and lists of block cells
    PLAYER_POINTS = ("position", "spawn")
    PLAYER_CELL_LISTS = ("growing",)

    @classmethod
    def migrate(cls, data):
        """Bring a loaded save up to SAVE_VERSION. Saves before version 4 come from the shallow
        world (64 high, surface ~180 lower): every stored y moves up by SURFACE_OFFSET so old
        builds, chests and the player stay on the same terrain."""
        if data.get("version", 0) < 4:
            def up(p):
                return [p[0], p[1] + SURFACE_OFFSET, p[2]] + list(p[3:])
            data["changes"] = [up(e) for e in data.get("changes", [])]
            data["containers"] = [[up(pos), slots] for pos, slots in data.get("containers", [])]
            player = data.get("player") or {}
            for k in cls.PLAYER_POINTS:
                if isinstance(player.get(k), (list, tuple)) and len(player[k]) >= 3:
                    player[k] = up(player[k])
            for k in cls.PLAYER_CELL_LISTS:
                if isinstance(player.get(k), list):
                    player[k] = [up(p) for p in player[k]]
            data["player"] = player
            data["version"] = SAVE_VERSION
        return data
