import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from world import World, FACE_VERTS, _cross, _sub, _dot, CHUNK_SIZE  # noqa: E402


def test_faces_wind_like_ursina_quad():
    for normal, _, (c0, c1, c2, *_rest) in FACE_VERTS:
        assert _dot(_cross(_sub(c1, c0), _sub(c2, c0)), normal) < 0


def test_generation_is_deterministic():
    a = World(seed=42, size_chunks=1).generate()
    b = World(seed=42, size_chunks=1).generate()
    assert a.blocks == b.blocks
    assert all(a.get(x, 0, z) == 9 for x in range(CHUNK_SIZE) for z in range(CHUNK_SIZE))


def test_hidden_faces_are_culled():
    w = World(seed=1, size_chunks=1)
    w._put((1, 1, 1), 3)
    verts, _ = w.chunk_mesh(0, 0)
    assert len(verts) == 6 * 6
    w._put((2, 1, 1), 3)
    verts, _ = w.chunk_mesh(0, 0)
    assert len(verts) == 10 * 6  # two shared faces removed


def test_edit_rebuilds_neighbour_chunk_and_bedrock_is_unbreakable():
    w = World(seed=3, size_chunks=2).generate()
    keys = w.set(CHUNK_SIZE - 1, 30, 5, 7)
    assert (0, 0) in keys and (1, 0) in keys
    assert w.set(0, 0, 0, 0) == set()
    assert w.get(0, 0, 0) == 9


def test_save_and_load_keep_edits(tmp_path):
    w = World(seed=7, size_chunks=1).generate()
    w.set(3, 40, 3, 8)
    top = w.top_y(5, 5)
    w.set(5, top, 5, 0)
    path = tmp_path / "save.json"
    w.save(path)
    loaded = World.load(path)
    assert loaded.get(3, 40, 3) == 8
    assert loaded.get(5, top, 5) == 0
    assert loaded.blocks == w.blocks
