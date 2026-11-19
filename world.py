"""World data, terrain generation, chunk meshing and save/load.

Pure Python — no Ursina import here, so this module can be unit-tested
without opening a window.
"""
import json
import math
import random
from pathlib import Path

CHUNK_SIZE = 16
WATER_LEVEL = 6

# id: (name, (r, g, b))
BLOCKS = {
    1: ("grass", (0.37, 0.70, 0.25)),
    2: ("dirt", (0.55, 0.38, 0.22)),
    3: ("stone", (0.52, 0.52, 0.55)),
    4: ("wood", (0.45, 0.30, 0.15)),
    5: ("leaves", (0.18, 0.52, 0.18)),
    6: ("sand", (0.90, 0.84, 0.55)),
    7: ("planks", (0.76, 0.58, 0.34)),
    8: ("brick", (0.70, 0.27, 0.22)),
    9: ("bedrock", (0.15, 0.15, 0.17)),
}
HOTBAR = [1, 2, 3, 4, 5, 6, 7, 8]
UNBREAKABLE = {9}

# (normal, brightness) — simple fake lighting so cube edges are visible.
FACES = [
    ((0, 1, 0), 1.00),
    ((0, -1, 0), 0.50),
    ((1, 0, 0), 0.80),
    ((-1, 0, 0), 0.80),
    ((0, 0, 1), 0.65),
    ((0, 0, -1), 0.65),
]


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _face_corners(normal):
    """Four corners of a unit-cube face, ordered so the face is front-facing in Ursina.

    Ursina's built-in Quad (normal -Z, visible from the default camera) has
    cross(v1 - v0, v2 - v0) pointing opposite to its normal, so we match that.
    """
    u, v = [axis for axis in range(3) if normal[axis] == 0]
    corners = []
    for du, dv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        c = [normal[0] * 0.5, normal[1] * 0.5, normal[2] * 0.5]
        c[u] = du * 0.5
        c[v] = dv * 0.5
        corners.append(tuple(c))
    if _dot(_cross(_sub(corners[1], corners[0]), _sub(corners[2], corners[0])), normal) > 0:
        corners.reverse()
    c0, c1, c2, c3 = corners
    return (c0, c1, c2, c2, c3, c0)  # two triangles


FACE_VERTS = [(normal, shade, _face_corners(normal)) for normal, shade in FACES]


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
    def __init__(self, seed=None, size_chunks=5):
        self.seed = random.randint(0, 999_999) if seed is None else seed
        self.size_chunks = size_chunks
        self.size = size_chunks * CHUNK_SIZE
        self.blocks = {}          # (x, y, z) -> block id
        self.chunks = {}          # (cx, cz) -> set of (x, y, z)
        self.changes = {}         # player edits: (x, y, z) -> id (0 = removed)

    # -- basic access
    @staticmethod
    def chunk_key(x, z):
        return (x // CHUNK_SIZE, z // CHUNK_SIZE)

    def in_bounds(self, x, y, z):
        return 0 <= x < self.size and 0 <= z < self.size and 0 <= y < 64

    def get(self, x, y, z):
        return self.blocks.get((x, y, z), 0)

    def _put(self, pos, block_id):
        key = self.chunk_key(pos[0], pos[2])
        if block_id:
            self.blocks[pos] = block_id
            self.chunks.setdefault(key, set()).add(pos)
        elif pos in self.blocks:
            del self.blocks[pos]
            self.chunks[key].discard(pos)

    def set(self, x, y, z, block_id):
        """Player edit. Returns the chunk keys whose mesh must be rebuilt."""
        pos = (x, y, z)
        if not self.in_bounds(*pos):
            return set()
        if block_id == 0 and self.get(*pos) in UNBREAKABLE:
            return set()
        self._put(pos, block_id)
        self.changes[pos] = block_id
        # neighbours across a chunk border also need a rebuild
        return {self.chunk_key(x + dx, z + dz) for dx, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= x + dx < self.size and 0 <= z + dz < self.size}

    # -- generation
    def height_at(self, x, z):
        return int(4 + fbm(x / 28, z / 28, self.seed) * 14)

    def generate(self):
        rng = random.Random(self.seed)
        for x in range(self.size):
            for z in range(self.size):
                h = self.height_at(x, z)
                for y in range(h + 1):
                    if y == 0:
                        b = 9
                    elif y < h - 3:
                        b = 3
                    elif y < h:
                        b = 2
                    else:
                        b = 6 if h <= WATER_LEVEL else 1
                    self._put((x, y, z), b)
        for _ in range(self.size * self.size // 120):
            x, z = rng.randrange(2, self.size - 2), rng.randrange(2, self.size - 2)
            h = self.height_at(x, z)
            if h > WATER_LEVEL:
                self._tree(x, h + 1, z)
        return self

    def _tree(self, x, y, z):
        for dy in range(4):
            self._put((x, y + dy, z), 4)
        for dy, r in ((2, 2), (3, 2), (4, 1)):
            for dx in range(-r, r + 1):
                for dz in range(-r, r + 1):
                    p = (x + dx, y + dy, z + dz)
                    if self.in_bounds(*p) and not self.get(*p) and abs(dx) + abs(dz) < r * 2:
                        self._put(p, 5)

    def spawn_point(self):
        c = self.size // 2
        return (c, self.top_y(c, c) + 1.5, c)

    def top_y(self, x, z):
        return max((y for (bx, y, bz) in self.chunks.get(self.chunk_key(x, z), ()) if bx == x and bz == z), default=0)

    # -- meshing
    def chunk_mesh(self, cx, cz):
        """Vertices + colors for all visible faces in a chunk (hidden faces culled)."""
        verts, colors = [], []
        for (x, y, z) in self.chunks.get((cx, cz), ()):
            r, g, b = BLOCKS[self.blocks[(x, y, z)]][1]
            for (nx, ny, nz), shade, corners in FACE_VERTS:
                if (x + nx, y + ny, z + nz) in self.blocks or (ny == -1 and y == 0):
                    continue
                col = (r * shade, g * shade, b * shade, 1.0)
                for vx, vy, vz in corners:
                    verts.append((x + vx, y + vy, z + vz))
                    colors.append(col)
        return verts, colors

    # -- persistence (only the seed + player edits are stored)
    def save(self, path):
        data = {
            "seed": self.seed,
            "size_chunks": self.size_chunks,
            "changes": [[x, y, z, b] for (x, y, z), b in self.changes.items()],
        }
        Path(path).write_text(json.dumps(data))

    @classmethod
    def load(cls, path):
        data = json.loads(Path(path).read_text())
        world = cls(seed=data["seed"], size_chunks=data["size_chunks"]).generate()
        for x, y, z, b in data["changes"]:
            world._put((x, y, z), b)
            world.changes[(x, y, z)] = b
        return world
