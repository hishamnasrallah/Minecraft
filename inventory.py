"""Items, inventory and crafting. Pure Python (no Ursina) so it can be unit-tested."""
import random

from world import BLOCKS, BLOCK_TILES, WATER, GLASS, COAL_ORE, LAMP

STACK_SIZE = 64
HOTBAR_SIZE = 9
INVENTORY_SIZE = 36          # 9 hotbar slots + 27 storage slots

STICK, COAL = 101, 102
WOOD_PICKAXE, STONE_PICKAXE, WOOD_AXE, STONE_AXE = 201, 202, 203, 204

# tool id: (kind, speed multiplier, durability, name, icon tile)
TOOLS = {
    WOOD_PICKAXE: ("pickaxe", 2.0, 60, "wooden pickaxe", "wood_pickaxe"),
    STONE_PICKAXE: ("pickaxe", 4.0, 130, "stone pickaxe", "stone_pickaxe"),
    WOOD_AXE: ("axe", 2.0, 60, "wooden axe", "wood_axe"),
    STONE_AXE: ("axe", 4.0, 130, "stone axe", "stone_axe"),
}

ITEMS = {**BLOCKS, STICK: "stick", COAL: "coal", **{t: v[3] for t, v in TOOLS.items()}}
# atlas tile used as the icon of each item
ITEM_ICONS = {**{b: tiles[1] for b, tiles in BLOCK_TILES.items()}, STICK: "stick", COAL: "coal",
              **{t: v[4] for t, v in TOOLS.items()}}
PLACEABLE = set(BLOCKS) - {WATER, 9}

# ---------------------------------------------------------------- mining
HARDNESS = {1: 0.6, 2: 0.5, 3: 1.5, 4: 2.0, 5: 0.2, 6: 0.5, 7: 2.0, 8: 2.0, 11: 0.3, 12: 0.3, 13: 3.0}
TOOL_FOR = {3: "pickaxe", 8: "pickaxe", 13: "pickaxe", 4: "axe", 7: "axe"}   # which tool speeds a block up
NEEDS_TOOL = {3, 8, 13}     # these drop nothing (and are very slow) without a pickaxe


def mining(block_id, tool_item=None):
    """How breaking a block goes with what's in your hand: (seconds, drops something?, wears the tool?)."""
    hardness = HARDNESS.get(block_id, 1.0)
    tool = TOOLS.get(tool_item)
    if tool and TOOL_FOR.get(block_id) == tool[0]:
        return hardness * 1.5 / tool[1], True, True
    if block_id in NEEDS_TOOL:
        return hardness * 5, False, False
    return hardness * 1.5, True, False


def max_stack(item):
    return 1 if item in TOOLS else STACK_SIZE


def new_stack(item, amount):
    """Tools carry their remaining durability as a third value."""
    return (item, 1, TOOLS[item][2]) if item in TOOLS else (item, amount)


def drop_for(block_id, rng=random):
    """What you get for breaking a block (None = nothing)."""
    if block_id == 1:
        return 2                  # grass -> dirt
    if block_id == COAL_ORE:
        return COAL
    if block_id == 5:
        return STICK if rng.random() < 0.2 else None   # leaves sometimes drop a stick
    return block_id


# (ingredients, (result, count)) — shapeless: only the amounts matter
RECIPES = [
    ({4: 1}, (7, 4)),                          # wood -> 4 planks
    ({7: 2}, (STICK, 4)),                      # 2 planks -> 4 sticks
    ({6: 4}, (GLASS, 2)),                      # 4 sand -> 2 glass
    ({2: 2, 6: 2}, (8, 2)),                    # 2 dirt + 2 sand -> 2 brick
    ({3: 4}, (8, 1)),                          # 4 stone -> 1 brick
    ({COAL: 1, STICK: 1, GLASS: 1}, (LAMP, 2)),
    ({7: 3, STICK: 2}, (WOOD_PICKAXE, 1)),
    ({3: 3, STICK: 2}, (STONE_PICKAXE, 1)),
    ({7: 2, STICK: 2}, (WOOD_AXE, 1)),
    ({3: 2, STICK: 2}, (STONE_AXE, 1)),
]


def recipe_text(recipe):
    ingredients, (result, count) = recipe
    parts = " + ".join(f"{n} {ITEMS[i]}" for i, n in ingredients.items())
    return f"{count} {ITEMS[result]}  =  {parts}"


class Inventory:
    """Slots hold (item id, count) tuples or None. Slots 0-8 are the hotbar."""

    def __init__(self, size=INVENTORY_SIZE):
        self.slots = [None] * size

    # -- queries
    def count(self, item):
        return sum(s[1] for s in self.slots if s and s[0] == item)

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
        """Remove exactly `amount` (storage slots first). All or nothing."""
        if self.count(item) < amount:
            return False
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
