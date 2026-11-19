import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from world import World  # noqa: E402
from blocks import STAIRS, LADDERS, DOORS  # noqa: E402
from building import Builder, MAX_BLOCKS, rotate_block, mirror_block  # noqa: E402


def empty_world():
    w = World(seed=1)
    for cx in (-1, 0, 1):
        for cz in (-1, 0, 1):
            w.chunks[(cx, cz)] = set()
    return w


def test_selection_and_fill_and_undo():
    w, b = empty_world(), Builder()
    assert b.fill(w, 3)[1].startswith("Select")
    b.corner1, b.corner2 = (5, 4, 2), (2, 1, 3)        # any two opposite corners
    assert b.bounds() == ((2, 1, 2), (5, 4, 3)) and b.size() == (4, 4, 2) and b.volume() == 32
    keys, msg = b.fill(w, 3)
    assert msg == "Changed 32 blocks" and (0, 0) in keys
    assert all(w.get(*p) == 3 for p in b.cells())
    b.undo(w)
    assert not any(w.get(*p) for p in b.cells())
    assert b.undo(w)[1] == "Nothing to undo"


def test_hollow_replace_and_clear():
    w, b = empty_world(), Builder()
    b.corner1, b.corner2 = (0, 1, 0), (4, 5, 4)
    b.fill(w, 3, hollow=True)
    assert w.get(2, 3, 2) == 0 and w.get(0, 3, 2) == 3 and w.get(2, 1, 2) == 3
    b.fill(w, 41, replace=3)                           # stone -> stone bricks, air stays air
    assert w.get(0, 3, 2) == 41 and w.get(2, 3, 2) == 0
    b.fill(w, 0)
    assert not any(w.get(*p) for p in b.cells())


def test_too_big_selection_is_refused():
    w, b = empty_world(), Builder()
    b.corner1, b.corner2 = (0, 0, 0), (40, 40, 40)
    keys, msg = b.fill(w, 3)
    assert not keys and "too big" in msg and str(MAX_BLOCKS) in msg


def test_copy_paste_rotate_mirror():
    w, b = empty_world(), Builder()
    w._put((0, 1, 0), 3)
    w._put((1, 1, 0), 3)
    w._put((0, 1, 1), STAIRS[7][0])                    # a stair facing +z
    b.corner1, b.corner2 = (0, 1, 0), (1, 1, 1)
    assert "2x1x2" in b.copy(w)
    b.paste(w, (10, 1, 10))
    assert w.get(10, 1, 10) == 3 and w.get(11, 1, 10) == 3 and w.get(10, 1, 11) == STAIRS[7][0]
    assert w.get(11, 1, 11) == 0                       # air in the copy didn't overwrite anything
    b.rotate()
    b.paste(w, (20, 1, 20))
    # +z turns into +x: the stair is now on the +x side and faces +x
    assert w.get(21, 1, 21) == STAIRS[7][1]
    b.mirror()
    b.paste(w, (30, 1, 30))
    assert STAIRS[7][3] in {w.get(30, 1, z) for z in (30, 31)}


def test_paste_with_air_clears_space():
    w, b = empty_world(), Builder()
    b.corner1, b.corner2 = (0, 1, 0), (1, 1, 0)
    w._put((0, 1, 0), 3)
    b.copy(w)
    w._put((11, 1, 10), 8)
    b.paste(w, (10, 1, 10), include_air=True)
    assert w.get(10, 1, 10) == 3 and w.get(11, 1, 10) == 0


def test_rotating_blocks_four_times_is_identity():
    for block in [STAIRS[3][0], STAIRS[7][2], LADDERS[1], 510, 513, 3]:
        b = block
        for _ in range(4):
            b = rotate_block(b)
        assert b == block
        assert mirror_block(mirror_block(block)) == block
    assert rotate_block(LADDERS[0]) == LADDERS[1]
    assert DOORS[rotate_block(510)]["axis"] == 1


def test_bulk_set_skips_unloaded_and_out_of_range():
    w = empty_world()
    keys, previous = w.bulk_set({(0, 1, 0): 3, (500, 1, 500): 3, (0, 999, 0): 3, (0, 2, 0): 0})
    assert previous == {(0, 1, 0): 0} and (0, 0) in keys
