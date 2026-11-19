import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from world import (World, FACE_VERTS, BLOCK_TILES, TILES, ATLAS_COLS, CHUNK_SIZE,  # noqa: E402
                   WATER, WATER_LEVEL, LAMP, MAX_LIGHT, _cross, _sub, _dot, tile_uv)
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


def _find(w, predicate, keys):
    for key in keys:
        w.ensure_chunk(key)
    for key in keys:
        for (x, y, z) in w.chunks[key]:
            if predicate(x, y, z, w.blocks[(x, y, z)]):
                return (x, y, z)
    return None


def _lake_chunk(w, radius=8):
    """A chunk with a lake in it, found from the height map alone (no chunks generated)."""
    for cx in range(-radius, radius):
        for cz in range(-radius, radius):
            if w.height_at(cx * CHUNK_SIZE + 8, cz * CHUNK_SIZE + 8) < WATER_LEVEL - 1:
                return (cx, cz)
    return None


def test_world_has_lakes_and_caves():
    w = World(seed=11)
    key = _lake_chunk(w)
    lake = _find(w, lambda x, y, z, b: b == WATER, [key])
    assert lake and lake[1] <= WATER_LEVEL
    cave = _find(w, lambda x, y, z, b: 2 < y < w.height_at(x, z) - 3 and w.get(x, y + 1, z) == 0 and b == 3,
                 [(0, 0), (1, 0)])
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
    cx, cz = _lake_chunk(w)
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            w.ensure_chunk((cx + dx, cz + dz))
    pos = _find(w, lambda x, y, z, b: b != WATER and b not in (9,) and y > 1
                and w.get(x + 1, y, z) == WATER and w.get(x, y + 1, z) in (0, WATER)
                and all(w.chunk_key(x + d, z + e) in w.chunks for d in (-1, 0, 1) for e in (-1, 0, 1)), [(cx, cz)])
    assert pos
    keys = w.set(*pos, 0)
    assert w.get(*pos) == WATER
    assert w.chunk_key(pos[0], pos[2]) in keys
    assert w.set(*pos, 0) == set()     # water itself can't be "broken"
    w.set(*pos, 7)                     # but you can place a block into it
    assert w.get(*pos) == 7


def _flat_world():
    """A 3x3-chunk world: bedrock floor plus a flat stone ground at y=1..4."""
    w = World(seed=1)
    for cx in (-1, 0, 1):
        for cz in (-1, 0, 1):
            w.chunks[(cx, cz)] = set()
    for x in range(-CHUNK_SIZE, 2 * CHUNK_SIZE):
        for z in range(-CHUNK_SIZE, 2 * CHUNK_SIZE):
            for y in range(5):
                w._put((x, y, z), 9 if y == 0 else 3)
    return w


def test_open_sky_is_fully_lit_and_sealed_cave_is_dark():
    w = _flat_world()
    w._put((5, 2, 5), 0)  # sealed one-block pocket
    light = w.compute_light(0, 0)
    assert light(5, 5, 5) == (MAX_LIGHT, 0)
    assert light(5, 2, 5) == (0, 0)


def test_sky_light_fades_into_a_tunnel():
    w = _flat_world()
    for x in range(3, 10):
        w._put((x, 3, 5), 0)  # tunnel at y=3 ...
    w._put((3, 4, 5), 0)      # ... opening to the sky above x=3
    light = w.compute_light(0, 0)
    levels = [light(x, 3, 5)[0] for x in range(3, 10)]
    assert levels[0] == MAX_LIGHT
    assert levels == sorted(levels, reverse=True) and levels[-1] == MAX_LIGHT - 6


def test_lamp_lights_up_a_cave_and_the_mesh():
    w = _flat_world()
    for x in range(3, 8):
        w._put((x, 2, 5), 0)
    w._put((3, 2, 5), LAMP)
    light = w.compute_light(0, 0)
    assert light(4, 2, 5) == (0, 14)
    assert light(7, 2, 5) == (0, 11)
    solid = w.chunk_mesh(0, 0)["solid"]
    lamp_lit = [c for v, c in zip(solid[0], solid[1]) if 3.5 <= v[0] <= 7.5 and 1.5 <= v[1] <= 2.5 and c[1] > 0]
    assert lamp_lit  # cave walls get block light in their vertex colours
    w.set(3, 2, 5, 0)
    assert w.compute_light(0, 0)(4, 2, 5) == (0, 0)


def test_light_dims_under_water():
    w = _flat_world()
    for y in (5, 6, 7):
        w._put((5, y, 5), WATER)
    w._columns.clear()
    light = w.compute_light(0, 0)
    assert light(5, 8, 5)[0] == MAX_LIGHT
    assert [light(5, y, 5)[0] for y in (7, 6, 5)] == [13, 11, 9]


def test_time_of_day_is_saved(tmp_path):
    w = World(seed=2)
    w.time_of_day = 0.61
    w.save(tmp_path / "s.json")
    assert World.load(tmp_path / "s.json").time_of_day == 0.61


def test_glass_lets_light_through_and_shows_what_is_behind():
    from world import GLASS
    w = _flat_world()
    w._put((5, 5, 5), GLASS)       # glass roof over a pocket
    w._put((5, 4, 5), 0)
    w._columns.clear()
    assert w.compute_light(0, 0)(5, 4, 5)[0] == MAX_LIGHT
    w._put((6, 5, 5), GLASS)
    solid = w.chunk_mesh(0, 0)["solid"][0]
    pocket_floor = [v for v in solid if v[1] == 3.5 and 4.5 <= v[0] <= 5.5 and 4.5 <= v[2] <= 5.5]
    assert pocket_floor            # floor below the glass is drawn
    between = [v for v in solid if v[0] == 5.5 and v[1] > 4.5 and 4.5 < v[2] < 5.5]
    assert not between             # no face between two glass blocks


def test_coal_ore_appears_underground():
    from world import COAL_ORE
    w = World(seed=4)
    for cx in range(3):
        w.ensure_chunk((cx, 0))
    ores = [p for p, b in w.blocks.items() if b == COAL_ORE]
    assert ores and all(p[1] < w.height_at(p[0], p[2]) - 2 for p in ores)


def test_player_data_is_saved(tmp_path):
    w = World(seed=2)
    w.save(tmp_path / "s.json", player={"inventory": [[2, 5]]})
    assert World.load(tmp_path / "s.json").player_data == {"inventory": [[2, 5]]}


def test_world_is_deep_with_layers():
    from collections import Counter
    from world import MAX_HEIGHT, SURFACE_OFFSET, SNOW_LINE, SLATE_LINE, BEDROCK_TOP, SLATE
    assert MAX_HEIGHT == 320 and WATER_LEVEL == 11 + SURFACE_OFFSET and SNOW_LINE == 27 + SURFACE_OFFSET
    w = World(seed=424242)
    w.ensure_chunk((0, 0))
    deep, mid, ragged = Counter(), Counter(), 0
    for x in range(CHUNK_SIZE):
        for z in range(CHUNK_SIZE):
            assert w.height_at(x, z) > SURFACE_OFFSET
            assert w.get(x, 0, z) == 9                       # a bedrock floor ...
            ragged += sum(w.get(x, y, z) == 9 for y in range(1, BEDROCK_TOP))
            for y in range(BEDROCK_TOP, MAX_HEIGHT):
                assert w.get(x, y, z) != 9                   # ... and none above the bottom layers
            deep.update(w.get(x, y, z) for y in range(BEDROCK_TOP, SLATE_LINE - 6))
            mid.update(w.get(x, y, z) for y in range(SLATE_LINE + 6, 170))
    assert 0 < ragged < 3 * CHUNK_SIZE * CHUNK_SIZE          # random bedrock in y 1..3
    assert deep[SLATE] > 10000 and deep[3] == 0              # slate deep down ...
    assert mid[3] > 5000 and mid[SLATE] == 0                 # ... stone above it


def test_ores_are_banded_by_depth():
    from world import COAL_ORE
    deepest = {ore: max_y for ore, _, max_y in World.ORES}
    assert deepest[29] < 40 and deepest[28] < 100 and deepest[COAL_ORE] >= WATER_LEVEL   # diamond, gold, coal
    w = World(seed=4)
    for key in ((0, 0), (1, 0)):
        w.ensure_chunk(key)
    found = {}
    for (x, y, z), b in w.blocks.items():
        if b in deepest:
            assert y <= deepest[b]
            found.setdefault(b, []).append(y)
    assert max(found[COAL_ORE]) > 150 and min(found[COAL_ORE]) < 50   # coal everywhere
    assert 29 in found                                                 # diamonds deep down


def test_big_caverns_deep_down():
    from world import CAVERN_TOP, CAVE_FLOOR
    w = World(seed=11)
    # the export picks the chunk with the most deep hollow space; seed 11 has one at (-2, -1)
    w.ensure_chunk((-2, -1))
    tallest = 0
    for x in range(-32, -16):
        for z in range(-16, 0):
            run = 0
            for y in range(CAVE_FLOOR, CAVERN_TOP):
                run = run + 1 if w.get(x, y, z) == 0 else 0
                tallest = max(tallest, run)
    assert tallest >= 15, tallest


def test_old_saves_are_moved_up_to_the_deep_world(tmp_path):
    import json
    from world import SURFACE_OFFSET, SAVE_VERSION
    old = {"version": 3, "seed": 7, "time_of_day": 0.3,
           "changes": [[3, 20, 3, 8], [4, 1, 4, 0]],
           "containers": [[[5, 21, 6], [[2, 5], None]]],
           "player": {"position": [8.5, 22.1, 8.5], "spawn": [8, 21.5, 8], "growing": [[1, 15, 2]],
                      "mode": "survival", "inventory": [[2, 5]]}}
    path = tmp_path / "old.json"
    path.write_text(json.dumps(old))
    w = World.load(path)
    off = SURFACE_OFFSET
    assert w.changes[(0, 0)] == {(3, 20 + off, 3): 8, (4, 1 + off, 4): 0}
    assert list(w.containers) == [(5, 21 + off, 6)]
    pd = w.player_data
    assert pd["position"] == [8.5, 22.1 + off, 8.5] and pd["spawn"] == [8, 21.5 + off, 8]
    assert pd["growing"] == [[1, 15 + off, 2]] and pd["inventory"] == [[2, 5]] and pd["mode"] == "survival"
    # the terrain moved up by exactly the same amount, so old builds still sit on their ground
    from world import fbm
    for x, z in ((0, 0), (37, -12)):
        old_h = int(3 + fbm(x / 28, z / 28, 7) * 12 + fbm(x / 90, z / 90, 7 + 7) ** 2 * 22)
        assert w.height_at(x, z) == old_h + off
    w.save(path, pd)
    assert json.loads(path.read_text())["version"] == SAVE_VERSION
    again = World.load(path)                       # a current save is not moved again
    assert again.changes == w.changes and again.player_data["spawn"] == [8, 21.5 + off, 8]
