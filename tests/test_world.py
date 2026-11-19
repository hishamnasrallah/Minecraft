import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from world import (World, FACE_VERTS, BLOCK_TILES, TILES, ATLAS_COLS, CHUNK_SIZE,  # noqa: E402
                   WATER, WATER_LEVEL, _cross, _sub, _dot, tile_uv)
from textures import generate_atlas, tile_image  # noqa: E402


def test_faces_wind_like_ursina_quad():
    for normal, _, corners, _ in FACE_VERTS:
        c0, c1, c2 = corners[:3]
        assert _dot(_cross(_sub(c1, c0), _sub(c2, c0)), normal) < 0


def test_side_face_uvs_are_upright():
    for normal, _, corners, uvs in FACE_VERTS:
        if normal[1] == 0:
            for (_, y, _), (_, v) in zip(corners, uvs):
                assert v == y + 0.5


def test_tile_uvs_stay_inside_their_tile():
    for index, tile in enumerate(TILES):
        col, row = index % ATLAS_COLS, index // ATLAS_COLS
        for u, v in ((0, 0), (1, 1)):
            au, av = tile_uv(tile, u, v)
            assert col / ATLAS_COLS < au < (col + 1) / ATLAS_COLS
            # v is flipped: row 0 is at the top of the image, i.e. v near 1
            assert 1 - (row + 1) / ATLAS_COLS < av < 1 - row / ATLAS_COLS


def test_generation_is_deterministic_and_infinite():
    a, b = World(seed=42), World(seed=42)
    for key in [(0, 0), (-3, 7), (100, -250)]:
        a.ensure_chunk(key)
        b.ensure_chunk(key)
        assert a.chunks[key] == b.chunks[key]
        assert a.chunks[key]  # far away chunks have terrain too
    x0, z0 = 100 * CHUNK_SIZE, -250 * CHUNK_SIZE
    assert a.get(x0, 0, z0) == 9


def test_chunk_order_does_not_change_terrain():
    keys = [(0, 0), (1, 0), (0, 1), (1, 1), (-1, -1)]
    a, b = World(seed=5), World(seed=5)
    for k in keys:
        a.ensure_chunk(k)
    for k in reversed(keys):
        b.ensure_chunk(k)
    assert a.blocks == b.blocks


def test_hidden_faces_are_culled():
    w = World(seed=1)
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            w.chunks[(dx, dz)] = set()  # empty, already "generated"
    w._put((1, 1, 1), 3)
    verts, colors, uvs = w.chunk_mesh(0, 0)["solid"]
    assert len(verts) == len(colors) == len(uvs) == 6 * 6
    w._put((2, 1, 1), 3)
    assert len(w.chunk_mesh(0, 0)["solid"][0]) == 10 * 6  # two shared faces removed


def test_water_is_see_through_and_has_its_own_mesh():
    w = World(seed=1)
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            w.chunks[(dx, dz)] = set()
    w._put((1, 1, 1), 3)
    w._put((2, 1, 1), WATER)
    w._put((3, 1, 1), WATER)
    mesh = w.chunk_mesh(0, 0)
    assert len(mesh["solid"][0]) == 6 * 6           # stone face behind the water is still drawn
    assert len(mesh["water"][0]) == 10 * 6 - 6      # water hides water and the stone, not air
    top = [v for v in mesh["water"][0] if v[1] > 1]
    assert top and all(abs(v[1] - 1.4) < 1e-9 for v in top)  # lowered surface


def test_edits_survive_unload_and_bedrock_is_unbreakable():
    w = World(seed=3)
    w.chunk_mesh(0, 0)
    keys = w.set(CHUNK_SIZE - 1, 50, 5, 7)
    assert (0, 0) in keys and (1, 0) in keys
    assert w.set(0, 0, 0, 0) == set()
    assert w.get(0, 0, 0) == 9
    w.unload_chunk((0, 0))
    assert w.get(CHUNK_SIZE - 1, 50, 5) == 0
    w.ensure_chunk((0, 0))
    assert w.get(CHUNK_SIZE - 1, 50, 5) == 7


def test_save_and_load_keep_edits(tmp_path):
    w = World(seed=7)
    top = w.top_y(5, 5)
    w.set(3, 50, 3, 8)
    w.set(5, top, 5, 0)
    path = tmp_path / "save.json"
    w.save(path)
    loaded = World.load(path)
    loaded.ensure_chunk((0, 0))
    assert loaded.get(3, 50, 3) == 8
    assert loaded.get(5, top, 5) == 0
    assert loaded.chunks[(0, 0)] == w.chunks[(0, 0)]


def test_atlas_has_every_tile():
    atlas = generate_atlas()
    assert atlas.width == ATLAS_COLS * 16
    for tiles in BLOCK_TILES.values():
        for name in tiles:
            img = tile_image(atlas, name)
            assert img.size == (16, 16)
            assert img.getpixel((5, 5))[:3] != (255, 0, 255)  # not the empty-slot filler


def _find(w, predicate, radius=6):
    for cx in range(-radius, radius):
        for cz in range(-radius, radius):
            w.ensure_chunk((cx, cz))
    for (x, y, z), b in list(w.blocks.items()):
        if predicate(x, y, z, b):
            return (x, y, z)
    return None


def test_world_has_lakes_and_caves():
    w = World(seed=11)
    lake = _find(w, lambda x, y, z, b: b == WATER)
    assert lake and lake[1] <= WATER_LEVEL
    cave = _find(w, lambda x, y, z, b: 2 < y < w.height_at(x, z) - 3 and w.get(x, y + 1, z) == 0 and b == 3)
    assert cave, "expected an air pocket under the surface"


def test_chunk_order_does_not_change_caves():
    keys = [(2, 2), (3, 2), (2, 3)]
    a, b = World(seed=9), World(seed=9)
    for k in keys:
        a.ensure_chunk(k)
    for k in reversed(keys):
        b.ensure_chunk(k)
    assert a.blocks == b.blocks


def test_breaking_next_to_water_floods_the_gap():
    w = World(seed=11)
    pos = _find(w, lambda x, y, z, b: b != WATER and b not in (9,) and y > 1
                and w.get(x + 1, y, z) == WATER and w.get(x, y + 1, z) in (0, WATER)
                and all(w.chunk_key(x + d, z + e) in w.chunks for d in (-1, 0, 1) for e in (-1, 0, 1)))
    assert pos
    keys = w.set(*pos, 0)
    assert w.get(*pos) == WATER
    assert w.chunk_key(pos[0], pos[2]) in keys
    assert w.set(*pos, 0) == set()     # water itself can't be "broken"
    w.set(*pos, 7)                     # but you can place a block into it
    assert w.get(*pos) == 7
