import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from inventory import (Inventory, RECIPES, STACK_SIZE, HOTBAR_SIZE, STICK, COAL, ITEMS, ITEM_ICONS,  # noqa: E402
                       drop_for, recipe_text)
from world import TILES, GLASS, LAMP, COAL_ORE  # noqa: E402


def test_add_stacks_and_overflows():
    inv = Inventory(size=3)
    assert inv.add(2, 70) == 0
    assert inv.slots[:2] == [(2, 64), (2, 6)]
    assert inv.add(3, 64) == 0
    assert inv.add(2, 100) == 100 - 58         # only the second dirt stack has room
    assert inv.count(2) == 128


def test_remove_is_all_or_nothing():
    inv = Inventory()
    inv.add(3, 5)
    assert not inv.remove(3, 6)
    assert inv.count(3) == 5
    assert inv.remove(3, 5)
    assert inv.slots[0] is None


def test_use_one_empties_the_slot():
    inv = Inventory()
    inv.add(7, 2)
    assert inv.use_one(0) == 7 and inv.use_one(0) == 7
    assert inv.use_one(0) is None


def test_click_pick_place_merge_swap():
    inv = Inventory()
    inv.slots[0] = (2, 10)
    inv.slots[1] = (2, 60)
    inv.slots[2] = (3, 1)
    cursor = inv.click(0, None)                 # pick up
    assert cursor == (2, 10) and inv.slots[0] is None
    cursor = inv.click(1, cursor)               # merge, 6 left over
    assert inv.slots[1] == (2, 64) and cursor == (2, 6)
    cursor = inv.click(2, cursor)               # swap
    assert inv.slots[2] == (2, 6) and cursor == (3, 1)
    assert inv.click(0, cursor) is None and inv.slots[0] == (3, 1)


def test_right_click_half_and_one():
    inv = Inventory()
    inv.slots[0] = (2, 5)
    cursor = inv.click(0, None, right=True)
    assert cursor == (2, 3) and inv.slots[0] == (2, 2)
    cursor = inv.click(4, cursor, right=True)
    assert cursor == (2, 2) and inv.slots[4] == (2, 1)
    assert inv.click(5, (3, 1), right=True) is None


def test_quick_move_between_hotbar_and_storage():
    inv = Inventory()
    inv.slots[0] = (2, 10)
    inv.slots[HOTBAR_SIZE + 3] = (2, 60)
    inv.quick_move(0)
    assert inv.slots[0] is None
    assert inv.slots[HOTBAR_SIZE + 3] == (2, 64) and inv.slots[HOTBAR_SIZE] == (2, 6)
    inv.quick_move(HOTBAR_SIZE)
    assert inv.slots[0] == (2, 6)


def test_crafting_chain_to_a_lamp():
    inv = Inventory()
    inv.add(4, 1)
    inv.add(6, 4)
    inv.add(COAL, 1)
    by_result = {r[1][0]: r for r in RECIPES}
    assert not inv.craft(by_result[LAMP])
    assert inv.craft(by_result[7]) and inv.count(7) == 4 and inv.count(4) == 0
    assert inv.craft(by_result[STICK]) and inv.count(STICK) == 4
    assert inv.craft(by_result[GLASS]) and inv.count(GLASS) == 2
    assert inv.craft(by_result[LAMP])
    assert inv.count(LAMP) == 2 and inv.count(COAL) == 0 and inv.count(GLASS) == 1


def test_crafting_rolls_back_when_full():
    inv = Inventory(size=1)
    inv.add(4, 1)
    wood_to_planks = next(r for r in RECIPES if r[1][0] == 7)
    assert inv.craft(wood_to_planks)            # the freed slot takes the planks
    inv = Inventory(size=1)
    inv.slots[0] = (7, 2)
    planks_to_sticks = next(r for r in RECIPES if r[1][0] == STICK)
    assert inv.craft(planks_to_sticks)
    inv = Inventory(size=1)
    inv.slots[0] = (7, STACK_SIZE)
    assert not inv.craft(planks_to_sticks)       # 62 planks stay, no room for sticks
    assert inv.slots[0] == (7, STACK_SIZE)


def test_drops():
    rng = random.Random(0)
    assert drop_for(1, rng) == 2
    assert drop_for(COAL_ORE, rng) == COAL
    assert drop_for(3, rng) == 3
    leaves = [drop_for(5, rng) for _ in range(500)]
    assert set(leaves) == {None, STICK} and 50 < leaves.count(STICK) < 150


def test_every_item_has_an_icon_and_recipes_read_well():
    for item in ITEMS:
        assert ITEM_ICONS[item] in TILES
    assert recipe_text(RECIPES[0]) == "4 planks  =  1 wood"


def test_save_round_trip():
    inv = Inventory()
    inv.add(GLASS, 3)
    inv.slots[20] = (STICK, 7)
    again = Inventory.from_data(inv.to_data())
    assert again.slots == inv.slots
    assert Inventory.from_data(None).slots == [None] * 36
