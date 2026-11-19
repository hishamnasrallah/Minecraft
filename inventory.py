"""Items, inventory and crafting. Pure Python (no Ursina) so it can be unit-tested."""
import random

from blocks import (BLOCK_DEFS, BLOCKS, BLOCK_TILES, LEAVES, WATER, GLASS, LAMP, WOOL, STAINED_GLASS, SLABS,
                    STAIRS, SHAPE_MATERIALS)
from world import COAL_ORE

STACK_SIZE = 64
HOTBAR_SIZE = 9
INVENTORY_SIZE = 36          # 9 hotbar slots + 27 storage slots

STICK, COAL = 101, 102
RAW_MEAT, COOKED_MEAT, APPLE = 103, 104, 105
IRON_INGOT, COPPER_INGOT, TIN_INGOT, GOLD_INGOT, BRONZE_INGOT, DIAMOND = 106, 107, 108, 109, 110, 111
BUCKET, WATER_BUCKET = 112, 113
FOOD = {RAW_MEAT: 2, COOKED_MEAT: 6, APPLE: 4}      # item -> hunger points restored

MATERIAL_ITEMS = {
    STICK: ("stick", "stick"), COAL: ("coal", "coal"), IRON_INGOT: ("iron ingot", "iron_ingot"),
    COPPER_INGOT: ("copper ingot", "copper_ingot"), TIN_INGOT: ("tin ingot", "tin_ingot"),
    GOLD_INGOT: ("gold ingot", "gold_ingot"), BRONZE_INGOT: ("bronze ingot", "bronze_ingot"),
    DIAMOND: ("diamond", "diamond"),
}
FOOD_ITEMS = {RAW_MEAT: ("raw meat", "raw_meat"), COOKED_MEAT: ("cooked meat", "cooked_meat"),
              APPLE: ("apple", "apple")}
OTHER_ITEMS = {BUCKET: ("bucket", "bucket"), WATER_BUCKET: ("water bucket", "water_bucket")}

# ---------------------------------------------------------------- tools
WOOD_PICKAXE, STONE_PICKAXE, WOOD_AXE, STONE_AXE = 201, 202, 203, 204
IRON_PICKAXE, DIAMOND_PICKAXE, IRON_AXE, DIAMOND_AXE = 205, 206, 207, 208
WOOD_SHOVEL, STONE_SHOVEL, IRON_SHOVEL, DIAMOND_SHOVEL = 209, 210, 211, 212
WOOD_SWORD, STONE_SWORD, IRON_SWORD, DIAMOND_SWORD = 213, 214, 215, 216

# tier: (speed multiplier, durability, level)
TIERS = {"wooden": (2.0, 60, 1), "stone": (4.0, 130, 2), "iron": (6.0, 250, 3), "diamond": (8.0, 1500, 4)}
_TOOL_IDS = {
    "pickaxe": (WOOD_PICKAXE, STONE_PICKAXE, IRON_PICKAXE, DIAMOND_PICKAXE),
    "axe": (WOOD_AXE, STONE_AXE, IRON_AXE, DIAMOND_AXE),
    "shovel": (WOOD_SHOVEL, STONE_SHOVEL, IRON_SHOVEL, DIAMOND_SHOVEL),
    "sword": (WOOD_SWORD, STONE_SWORD, IRON_SWORD, DIAMOND_SWORD),
}
# tool id: (kind, speed multiplier, durability, name, icon tile, level)
TOOLS = {}
for _kind, _ids in _TOOL_IDS.items():
    for _id, (_tier, (_speed, _durability, _level)) in zip(_ids, TIERS.items()):
        _icon = ("wood" if _tier == "wooden" else _tier) + "_" + _kind
        TOOLS[_id] = (_kind, _speed, _durability, f"{_tier} {_kind}", _icon, _level)

ITEMS = {**BLOCKS, **{i: v[0] for d in (MATERIAL_ITEMS, FOOD_ITEMS, OTHER_ITEMS) for i, v in d.items()},
         **{t: v[3] for t, v in TOOLS.items()}}
# atlas tile used as the icon of each item
ITEM_ICONS = {**{b: tiles[1] for b, tiles in BLOCK_TILES.items()},
              **{i: v[1] for d in (MATERIAL_ITEMS, FOOD_ITEMS, OTHER_ITEMS) for i, v in d.items()},
              **{t: v[4] for t, v in TOOLS.items()}}
PLACEABLE = {i for i, d in BLOCK_DEFS.items() if d["creative"]} - {WATER}

# ---------------------------------------------------------------- creative menu
TABS = ["all", "natural", "building", "colored", "plants", "functional", "tools", "food", "materials"]


def item_tab(item):
    if item in BLOCK_DEFS:
        return BLOCK_DEFS[item]["tab"]
    if item in TOOLS or item in OTHER_ITEMS:
        return "tools"
    if item in FOOD_ITEMS:
        return "food"
    return "materials"


# every item the creative menu offers, in a stable order
CREATIVE_ITEMS = sorted(
    [i for i, d in BLOCK_DEFS.items() if d["creative"]] + list(MATERIAL_ITEMS) + list(FOOD_ITEMS)
    + list(OTHER_ITEMS) + list(TOOLS),
    key=lambda i: (TABS.index(item_tab(i)), i))


def creative_items(tab="all", search=""):
    """Items for a creative tab. A search text (matches names, case-insensitive) searches every tab."""
    words = search.lower().split()
    if words:
        return [i for i in CREATIVE_ITEMS if all(w in ITEMS[i].lower() for w in words)]
    return [i for i in CREATIVE_ITEMS if tab == "all" or item_tab(i) == tab]


# ---------------------------------------------------------------- mining
NEEDS_TOOL = {i for i, d in BLOCK_DEFS.items() if d["level"] > 0}   # drop nothing without the right tool tier


def mining(block_id, tool_item=None):
    """How breaking a block goes with what's in your hand: (seconds, drops something?, wears the tool?)."""
    d = BLOCK_DEFS.get(block_id)
    if d is None:
        return 1.5, True, False
    hardness = d["hardness"]
    if hardness <= 0:
        return 0.05, True, False                       # plants, torches: instant
    tool = TOOLS.get(tool_item)
    right_tool = tool is not None and d["tool"] == tool[0]
    tier_ok = d["level"] == 0 or (right_tool and tool[5] >= d["level"])
    if right_tool and tier_ok:
        return hardness * 1.5 / tool[1], True, True
    if not tier_ok:
        return hardness * 5, False, right_tool
    return hardness * 1.5, True, False


def attack_damage(item):
    """Damage dealt to animals with what's in your hand."""
    tool = TOOLS.get(item)
    if not tool:
        return 1
    base = {"sword": 4, "axe": 3, "pickaxe": 2, "shovel": 1}[tool[0]]
    return base + tool[5] - 1


def max_stack(item):
    return 1 if item in TOOLS or item == WATER_BUCKET else 16 if item == BUCKET else STACK_SIZE


def new_stack(item, amount):
    """Tools carry their remaining durability as a third value."""
    return (item, 1, TOOLS[item][2]) if item in TOOLS else (item, amount)


def drop_for(block_id, rng=random):
    """What you get for breaking a block (None = nothing)."""
    d = BLOCK_DEFS.get(block_id)
    if d is None:
        return None
    if block_id in LEAVES:            # leaves sometimes drop a stick, oak leaves sometimes an apple
        roll = rng.random()
        return STICK if roll < 0.2 else APPLE if roll < 0.28 and block_id == 5 else None
    drop = d["drop"]
    return block_id if drop == "self" else drop


# ---------------------------------------------------------------- crafting
# ingredient keys are item ids, or a group name meaning "any of these"
GROUPS = {
    "planks": [7, 36, 39],
    "rock": [22, 3, 18, 19, 21],
    "wool": list(WOOL),
}
COBBLE_ETC = "rock"


def _tool_recipes():
    out = []
    for material, ids in (("planks", 0), ("rock", 1), (IRON_INGOT, 2), (DIAMOND, 3)):
        out += [
            ({material: 3, STICK: 2}, (_TOOL_IDS["pickaxe"][ids], 1)),
            ({material: 2, STICK: 2}, (_TOOL_IDS["axe"][ids], 1)),
            ({material: 1, STICK: 2}, (_TOOL_IDS["shovel"][ids], 1)),
            ({material: 2, STICK: 1}, (_TOOL_IDS["sword"][ids], 1)),
        ]
    return out


# (ingredients, (result, count)) — shapeless: only the amounts matter
RECIPES = [
    ({4: 1}, (7, 4)),                          # logs -> planks
    ({35: 1}, (36, 4)),
    ({38: 1}, (39, 4)),
    ({"planks": 2}, (STICK, 4)),
    ({COAL: 1, STICK: 1}, (50, 4)),            # torches
    ({6: 4}, (GLASS, 2)),
    ({COAL: 1, STICK: 1, GLASS: 1}, (LAMP, 2)),
    ({RAW_MEAT: 2, COAL: 1}, (COOKED_MEAT, 2)),   # cook over coal
    # smelting ore with coal
    ({25: 1, COAL: 1}, (IRON_INGOT, 1)),
    ({26: 1, COAL: 1}, (COPPER_INGOT, 1)),
    ({27: 1, COAL: 1}, (TIN_INGOT, 1)),
    ({28: 1, COAL: 1}, (GOLD_INGOT, 1)),
    ({COPPER_INGOT: 3, TIN_INGOT: 1}, (BRONZE_INGOT, 4)),
    ({22: 1, COAL: 1}, (3, 1)),                # cobblestone -> smooth stone
    # building blocks
    ({15: 4}, (8, 2)),                         # clay -> brick
    ({3: 4}, (41, 4)),                         # stone bricks
    ({6: 4}, (20, 1)),                         # sandstone
    ({20: 4}, (42, 4)),
    ({15: 4, COAL: 1}, (43, 4)),               # fired tiles
    ({6: 2, 15: 1}, (44, 3)),                  # plaster
    ({22: 1, 52: 1}, (23, 1)),                 # mossy cobblestone
    # functional blocks
    ({"planks": 4}, (46, 1)),                  # workbench
    ({22: 8}, (47, 1)),                        # furnace
    ({"planks": 8}, (48, 1)),                  # chest
    ({"planks": 6, STICK: 3}, (45, 1)),        # bookshelf
    ({STICK: 7}, (500, 3)),                    # ladders
    ({"planks": 6}, (510, 1)),                 # door
    ({STICK: 4, "planks": 2}, (61, 3)),        # fence
    ({"wool": 3, "planks": 3}, (62, 1)),       # bed
    ({IRON_INGOT: 3}, (BUCKET, 1)),
    # wool and dyes
    ({51: 4}, (70, 1)),                        # woven grass -> white wool
    ({70: 1, 53: 1}, (75, 1)),                 # red
    ({70: 1, 54: 1}, (77, 1)),                 # yellow
    ({70: 1, 55: 1}, (82, 1)),                 # blue
    ({GLASS: 1, 53: 1}, (405, 1)),
    ({GLASS: 1, 54: 1}, (407, 1)),
    ({GLASS: 1, 55: 1}, (412, 1)),
    # metal and gem storage blocks (and back)
    *[r for ingot, blk in ((IRON_INGOT, 30), (COPPER_INGOT, 31), (GOLD_INGOT, 32), (BRONZE_INGOT, 33),
                           (DIAMOND, 34))
      for r in (({ingot: 9}, (blk, 1)), ({blk: 1}, (ingot, 9)))],
    # slabs and stairs
    *[r for m in SHAPE_MATERIALS for r in (({m: 3}, (SLABS[m], 6)), ({m: 6}, (STAIRS[m][0], 4)))],
    *_tool_recipes(),
]


def ingredient_name(key):
    return f"any {key}" if isinstance(key, str) else ITEMS[key]


def recipe_text(recipe):
    ingredients, (result, count) = recipe
    parts = " + ".join(f"{n} {ingredient_name(i)}" for i, n in ingredients.items())
    return f"{count} {ITEMS[result]}  =  {parts}"


class Inventory:
    """Slots hold (item id, count) tuples or None. Slots 0-8 are the hotbar."""

    def __init__(self, size=INVENTORY_SIZE):
        self.slots = [None] * size

    # -- queries
    def count(self, item):
        """How many of an item (or of a group like "planks") you have."""
        members = GROUPS.get(item, (item,)) if isinstance(item, str) else (item,)
        return sum(s[1] for s in self.slots if s and s[0] in members)

    def item_at(self, index):
        return self.slots[index][0] if self.slots[index] else None

    # -- adding / removing
    def add(self, item, amount=1):
        """Add items, topping up existing stacks first. Returns how many did not fit."""
        limit = max_stack(item)
        for i, s in enumerate(self.slots):
            if amount and s and s[0] == item and s[1] < limit:
                moved = min(amount, limit - s[1])
                self.slots[i] = (item, s[1] + moved)
                amount -= moved
        for i, s in enumerate(self.slots):
            if amount and s is None:
                moved = min(amount, limit)
                self.slots[i] = new_stack(item, moved)
                amount -= moved
        return amount

    def remove(self, item, amount=1):
        """Remove exactly `amount` (storage slots first). All or nothing. Works with groups too."""
        if self.count(item) < amount:
            return False
        if isinstance(item, str):
            for member in GROUPS[item]:
                take = min(amount, self.count(member))
                if take:
                    self.remove(member, take)
                    amount -= take
            return True
        for i in reversed(range(len(self.slots))):
            s = self.slots[i]
            if amount and s and s[0] == item:
                taken = min(amount, s[1])
                self.slots[i] = (item, s[1] - taken) if s[1] > taken else None
                amount -= taken
        return True

    def use_one(self, index):
        """Take one item from a slot (e.g. to place a block). Returns the item id or None."""
        s = self.slots[index]
        if not s:
            return None
        self.slots[index] = (s[0], s[1] - 1) if s[1] > 1 else None
        return s[0]

    def wear(self, index):
        """Use up one point of a tool's durability. Returns True if the tool broke."""
        s = self.slots[index]
        if not s or s[0] not in TOOLS:
            return False
        if s[2] <= 1:
            self.slots[index] = None
            return True
        self.slots[index] = (s[0], 1, s[2] - 1)
        return False

    # -- mouse interaction in the inventory screen
    def click(self, index, cursor, right=False):
        """Click a slot while holding `cursor` (a stack or None). Returns the new cursor."""
        slot = self.slots[index]
        if not right:
            if cursor is None:
                self.slots[index] = None
                return slot
            if slot is None:
                self.slots[index] = cursor
                return None
            if slot[0] == cursor[0] and max_stack(slot[0]) > 1:
                moved = min(cursor[1], STACK_SIZE - slot[1])
                self.slots[index] = (slot[0], slot[1] + moved)
                rest = cursor[1] - moved
                return (cursor[0], rest) if rest else None
            self.slots[index] = cursor           # different items: swap
            return slot
        # right click: take half, or put down one
        if cursor is None:
            if slot is None:
                return None
            half = (slot[1] + 1) // 2
            if half == slot[1]:                  # a single item (or tool): take it as it is
                self.slots[index] = None
                return slot
            self.slots[index] = (slot[0], slot[1] - half)
            return (slot[0], half)
        if slot is None and cursor[1] == 1:
            self.slots[index] = cursor
            return None
        if slot is None or (slot[0] == cursor[0] and slot[1] < max_stack(slot[0])):
            self.slots[index] = (cursor[0], (slot[1] if slot else 0) + 1)
            return (cursor[0], cursor[1] - 1) if cursor[1] > 1 else None
        return cursor

    def quick_move(self, index):
        """Shift-click: move a stack between the hotbar and the storage area."""
        s = self.slots[index]
        if not s:
            return
        target = range(HOTBAR_SIZE, len(self.slots)) if index < HOTBAR_SIZE else range(HOTBAR_SIZE)
        item, amount = s[0], s[1]
        self.slots[index] = None
        for i in target:                         # top up matching stacks, then empty slots
            t = self.slots[i]
            if amount and t and t[0] == item and t[1] < max_stack(item):
                moved = min(amount, STACK_SIZE - t[1])
                self.slots[i] = (item, t[1] + moved)
                amount -= moved
        for i in target:
            if amount and self.slots[i] is None:
                self.slots[i] = s if amount == s[1] else (item, amount)   # keeps a tool's durability
                amount = 0
        if amount:
            self.slots[index] = s if amount == s[1] else (item, amount)

    # -- crafting
    def can_craft(self, recipe):
        return all(self.count(i) >= n for i, n in recipe[0].items())

    def craft(self, recipe):
        """Craft once. Nothing changes if ingredients are missing or the result doesn't fit."""
        if not self.can_craft(recipe):
            return False
        before = list(self.slots)
        for i, n in recipe[0].items():
            self.remove(i, n)
        result, count = recipe[1]
        if self.add(result, count):
            self.slots = before
            return False
        return True

    # -- saving
    def to_data(self):
        return [list(s) if s else None for s in self.slots]

    @classmethod
    def from_data(cls, data):
        inv = cls(len(data) if data else INVENTORY_SIZE)
        if data:
            inv.slots = [tuple(s) if s else None for s in data]
        return inv
