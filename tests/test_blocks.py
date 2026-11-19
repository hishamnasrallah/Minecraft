import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from blocks import (BLOCK_DEFS, DOORS, SLABS, STAIRS, WOOL, STAINED_GLASS, DYES, LADDERS, NON_SOLID,  # noqa: E402
                    facing_from_yaw, toggled_door)
from world import World, TILES, CHUNK_SIZE, WATER  # noqa: E402
from inventory import (Inventory, RECIPES, ITEMS, ITEM_ICONS, CREATIVE_ITEMS, TABS, TOOLS, IRON_INGOT,  # noqa: E402
                       STONE_PICKAXE, WOOD_PICKAXE, IRON_PICKAXE, STICK, creative_items, mining, item_tab)
from textures import generate_atlas, tile_image  # noqa: E402


def test_every_block_and_item_has_a_real_texture():
    atlas = generate_atlas()
    for item in ITEMS:
        tile = ITEM_ICONS[item]
        assert tile in TILES
        img = tile_image(atlas, tile)
        assert img.getpixel((8, 8))[:3] != (255, 0, 255) or img.getpixel((2, 2))[:3] != (255, 0, 255)
    for d in BLOCK_DEFS.values():
        assert all(t in TILES for t in d["tiles"])


def test_creative_menu_lists_everything_once_with_tabs_and_search():
    assert len(CREATIVE_ITEMS) == len(set(CREATIVE_ITEMS)) > 340
    assert all(item_tab(i) in TABS for i in CREATIVE_ITEMS)
    assert creative_items("all") == CREATIVE_ITEMS
    colored = creative_items("colored")
    # wool, stained glass, concrete, terracotta (+ plain), glazed tiles, carpets
    assert len(colored) == 6 * len(DYES) + 1 and set(WOOL) <= set(colored)
    stairs = creative_items("plants", "stairs")          # search ignores the tab
    assert len(stairs) == len(STAIRS) and all("stairs" in ITEMS[i] for i in stairs)
    assert creative_items("all", "RED wool") == [WOOL[5]]
    # oriented variants (door halves, ladder / stair facings) are not offered separately
    assert 511 not in CREATIVE_ITEMS and LADDERS[1] not in CREATIVE_ITEMS and STAIRS[3][2] not in CREATIVE_ITEMS


def test_every_recipe_is_valid():
    for ingredients, (result, count) in RECIPES:
        assert result in ITEMS and count > 0
        for key, n in ingredients.items():
            assert (isinstance(key, str) or key in ITEMS) and n > 0


def test_group_ingredients_accept_any_member():
    inv = Inventory()
    inv.add(36, 1)                                         # birch planks
    inv.add(39, 1)                                         # pine planks
    assert inv.count("planks") == 2
    sticks = next(r for r in RECIPES if r[1][0] == STICK)
    assert inv.craft(sticks) and inv.count("planks") == 0 and inv.count(STICK) == 4


def test_tool_tiers_gate_ores():
    assert not mining(25, WOOD_PICKAXE)[1]                 # iron ore needs a stone pickaxe or better
    assert mining(25, STONE_PICKAXE)[1]
    assert not mining(29, STONE_PICKAXE)[1]                # diamond needs iron
    assert mining(29, IRON_PICKAXE)[1]
    assert mining(29, IRON_PICKAXE)[0] < mining(25, STONE_PICKAXE)[0] * 2
    assert mining(53)[0] < 0.1                             # flowers break instantly
    assert len(TOOLS) == 16


def test_smelting_and_storage_blocks():
    inv = Inventory()
    inv.add(25, 9)
    inv.add(102, 9)
    smelt = next(r for r in RECIPES if r[1][0] == IRON_INGOT and 25 in r[0])
    for _ in range(9):
        assert inv.craft(smelt)
    block = next(r for r in RECIPES if r[0] == {IRON_INGOT: 9})
    assert inv.craft(block) and inv.count(30) == 1


def test_shapes():
    w = World(seed=1)
    for cx in (-1, 0, 1):
        for cz in (-1, 0, 1):
            w.chunks[(cx, cz)] = set()
    assert w.shape_boxes(SLABS[3], 0, 0, 0) == [(-.5, -.5, -.5, .5, 0, .5)]
    for f in range(4):
        boxes = w.shape_boxes(STAIRS[3][f], 0, 0, 0)
        assert len(boxes) == 2 and boxes[1][1] == 0         # bottom half + a raised half
    w._put((5, 5, 5), 61)
    assert len(w.shape_boxes(61, 5, 5, 5)) == 1             # lone fence: just a post
    w._put((6, 5, 5), 61)
    assert len(w.shape_boxes(61, 5, 5, 5)) == 3             # connected: post + 2 rails
    mesh = w.chunk_mesh(0, 0)
    assert mesh["solid"][0] and len(mesh["solid"][0]) == len(mesh["solid"][2])
    assert facing_from_yaw(0) == 0 and facing_from_yaw(90) == 1 and facing_from_yaw(-90) == 3


def test_doors_open_close_and_break_together():
    for door_id in DOORS:
        assert toggled_door(toggled_door(door_id)) == door_id
        assert DOORS[toggled_door(door_id)]["open"] != DOORS[door_id]["open"]
        assert DOORS[toggled_door(door_id)]["top"] == DOORS[door_id]["top"]
    w = World(seed=1)
    w.chunks[(0, 0)] = set()
    w._put((3, 1, 3), 3)
    w._put((3, 2, 3), 510)
    w._put((3, 3, 3), 511)
    w.set(3, 3, 3, 0)
    assert w.get(3, 2, 3) == 0


def test_plants_fall_when_the_ground_is_removed():
    w = World(seed=1)
    w.chunks[(0, 0)] = set()
    w._put((2, 1, 2), 6)
    for y in (2, 3, 4):
        w._put((2, y, 2), 59)                               # a stack of reeds
    w.set(2, 1, 2, 0)
    assert all(w.get(2, y, 2) == 0 for y in (2, 3, 4))
    assert 59 in NON_SOLID and not w.solid(2, 2, 2)


def test_voxel_raycast():
    w = World(seed=1)
    w.chunks[(0, 0)] = set()
    w._put((5, 2, 2), 3)
    w._put((3, 2, 2), WATER)
    pos, normal, dist = w.raycast((0, 2, 2), (1, 0, 0), 10)
    assert pos == (5, 2, 2) and normal == (-1, 0, 0) and 4 < dist < 5
    assert w.raycast((0, 2, 2), (1, 0, 0), 10, hit_water=True)[0] == (3, 2, 2)
    assert w.raycast((0, 2, 2), (1, 0, 0), 3)[0] is None
    pos, normal, _ = w.raycast((5, 6, 2), (0, -1, 0), 10)
    assert pos == (5, 2, 2) and normal == (0, 1, 0)


def test_worldgen_has_the_new_materials():
    w = World(seed=11)
    for cx in range(-5, 5):
        for cz in range(-5, 5):
            w.ensure_chunk((cx, cz))
    found = set(w.blocks.values())
    for b in (18, 19, 21, 14, 25, 26, 27, 28, 51, 53, 35):  # rocks, gravel, ores, grass, flowers, birch
        assert b in found, BLOCK_DEFS[b]["name"]


def test_chests_are_saved(tmp_path):
    w = World(seed=2)
    w.containers[(1, 2, 3)] = [[STICK, 5]] + [None] * 26
    w.save(tmp_path / "s.json")
    assert World.load(tmp_path / "s.json").containers[(1, 2, 3)][0] == [STICK, 5]
