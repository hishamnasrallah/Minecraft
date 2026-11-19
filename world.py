"""World data, infinite chunked terrain generation, meshing and save/load.

Pure Python — no Ursina import here, so this module can be unit-tested
without opening a window.
"""
import json
import math
import random
from pathlib import Path

CHUNK_SIZE = 16
MAX_HEIGHT = 64
WATER_LEVEL = 11
TREE_CHANCE = 0.012
WATER = 10
CAVE_THRESHOLD = 0.016     # bigger = more/wider caves
CAVE_GRID = 4              # cave noise is sampled every N blocks and interpolated

# id -> name
BLOCKS = {
    1: "grass",
    2: "dirt",
    3: "stone",
    4: "wood",
    5: "leaves",
    6: "sand",
    7: "planks",
    8: "brick",
    9: "bedrock",
    10: "water",
}
HOTBAR = [1, 2, 3, 4, 5, 6, 7, 8]
UNBREAKABLE = {9, WATER}
TRANSPARENT = {WATER}        # blocks you can see (and walk) through

# Texture atlas layout: ATLAS_COLS x ATLAS_COLS tiles, read left-to-right, top-to-bottom.
ATLAS_COLS = 4
TILES = [
    "grass_top", "grass_side", "dirt", "stone",
    "log_side", "log_top", "leaves", "sand",
    "planks", "brick", "bedrock", "water",
]
# id -> (top, side, bottom) tile names
BLOCK_TILES = {
    1: ("grass_top", "grass_side", "dirt"),
    2: ("dirt",) * 3,
    3: ("stone",) * 3,
    4: ("log_top", "log_side", "log_top"),
    5: ("leaves",) * 3,
    6: ("sand",) * 3,
    7: ("planks",) * 3,
    8: ("brick",) * 3,
    9: ("bedrock",) * 3,
    10: ("water",) * 3,
}

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

    def set(self, x, y, z, block_id):
        """Player edit. Returns the loaded chunk keys whose mesh must be rebuilt."""
        pos = (x, y, z)
        key = self.chunk_key(x, z)
        if not 0 <= y < MAX_HEIGHT or key not in self.chunks:
            return set()
        if block_id == 0 and self.get(*pos) in UNBREAKABLE:
            return set()
        self._edit(pos, block_id)
        touched = [pos]
        if block_id == 0:
            touched += self._flood(pos)
        # neighbours across a chunk border also need a rebuild
        return {k for (tx, _, tz) in touched
                for k in (self.chunk_key(tx + dx, tz + dz) for dx, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)))
                if k in self.chunks}

    def _edit(self, pos, block_id):
        self._put(pos, block_id)
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
        hills = fbm(x / 28, z / 28, self.seed)
        mountains = fbm(x / 90, z / 90, self.seed + 7) ** 2
        return int(3 + hills * 12 + mountains * 22)

    def has_tree(self, x, z):
        return _hash(x, z, self.seed + 777) < TREE_CHANCE and self.height_at(x, z) > WATER_LEVEL

    def ensure_chunk(self, key):
        """Generate a chunk (and re-apply the player's edits in it) if it isn't loaded."""
        if key in self.chunks:
            return False
        self.chunks[key] = set()
        cx, cz = key
        x0, z0 = cx * CHUNK_SIZE, cz * CHUNK_SIZE
        for x in range(x0, x0 + CHUNK_SIZE):
            for z in range(z0, z0 + CHUNK_SIZE):
                h = self.height_at(x, z)
                beach = h <= WATER_LEVEL + 1
                for y in range(h + 1):
                    if y == 0:
                        b = 9
                    elif y < h - 3:
                        b = 3
                    elif y < h:
                        b = 6 if beach and y >= h - 2 else 2
                    else:
                        b = 6 if beach else 1
                    self._put((x, y, z), b)
                for y in range(h + 1, WATER_LEVEL + 1):
                    self._put((x, y, z), WATER)
        self._carve_caves(key)
        # trees near the border overlap neighbouring chunks; each chunk keeps only its part
        for tx in range(x0 - 2, x0 + CHUNK_SIZE + 2):
            for tz in range(z0 - 2, z0 + CHUNK_SIZE + 2):
                if self.has_tree(tx, tz):
                    self._tree(tx, self.height_at(tx, tz) + 1, tz, key)
        for pos, b in self.changes.get(key, {}).items():
            self._put(pos, b)
        return True

    def _carve_caves(self, key):
        """Hollow out tunnels. Noise is sampled on a coarse grid and interpolated, and
        grid cells whose corners are all solid are skipped, which keeps this fast."""
        g = CAVE_GRID
        cx, cz = key
        x0, z0 = cx * CHUNK_SIZE, cz * CHUNK_SIZE
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
        if ymax < 1:
            return
        n = CHUNK_SIZE // g
        grid = {(i, j, k): cave_density(x0 + i * g, j * g, z0 + k * g, self.seed)
                for i in range(n + 1) for k in range(n + 1) for j in range(ymax // g + 2)}
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
                            if y < 1:
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

    def _tree(self, x, y, z, key):
        def put(p, b):
            if self.chunk_key(p[0], p[2]) == key and p[1] < MAX_HEIGHT and self.get(*p) in (0, WATER):
                self._put(p, b)

        for dy in range(4):
            put((x, y + dy, z), 4)
        for dy, r in ((2, 2), (3, 2), (4, 1)):
            for dx in range(-r, r + 1):
                for dz in range(-r, r + 1):
                    if abs(dx) + abs(dz) < r * 2:
                        put((x + dx, y + dy, z + dz), 5)

    def unload_chunk(self, key):
        for pos in self.chunks.pop(key, ()):
            del self.blocks[pos]

    def spawn_point(self):
        return (8, self.top_y(8, 8) + 1.5, 8)

    def top_y(self, x, z):
        self.ensure_chunk(self.chunk_key(x, z))
        return max((y for (bx, y, bz) in self.chunks[self.chunk_key(x, z)] if bx == x and bz == z), default=0)

    # -- meshing
    def chunk_mesh(self, cx, cz):
        """Mesh data for a chunk: {"solid": (verts, colors, uvs), "water": (...)}.

        Only visible faces are emitted. Neighbouring chunks are generated first so
        faces on the border are culled correctly.
        """
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                self.ensure_chunk((cx + dx, cz + dz))
        out = {"solid": ([], [], []), "water": ([], [], [])}
        blocks = self.blocks
        for pos in self.chunks[(cx, cz)]:
            x, y, z = pos
            block_id = blocks[pos]
            water = block_id == WATER
            verts, colors, uvs = out["water" if water else "solid"]
            # water surface sits a little lower than a full block
            lowered = water and blocks.get((x, y + 1, z)) != WATER
            for i, ((nx, ny, nz), shade, corners, _) in enumerate(FACE_VERTS):
                neighbour = blocks.get((x + nx, y + ny, z + nz), 0)
                if water:
                    if neighbour:          # water only shows against air
                        continue
                elif (neighbour and neighbour not in TRANSPARENT) or (ny == -1 and y == 0):
                    continue
                col = (shade, shade, shade, 1.0)
                for vx, vy, vz in corners:
                    if lowered and vy > 0:
                        vy = 0.4
                    verts.append((x + vx, y + vy, z + vz))
                colors.extend((col,) * 6)
                uvs.extend(_FACE_UVS[(block_id, i)])
        return out

    # -- persistence (only the seed + player edits are stored)
    def save(self, path):
        data = {
            "version": 2,
            "seed": self.seed,
            "changes": [[x, y, z, b] for edits in self.changes.values() for (x, y, z), b in edits.items()],
        }
        Path(path).write_text(json.dumps(data))

    @classmethod
    def load(cls, path):
        data = json.loads(Path(path).read_text())
        world = cls(seed=data["seed"])
        for x, y, z, b in data["changes"]:
            world.changes.setdefault(cls.chunk_key(x, z), {})[(x, y, z)] = b
        return world
