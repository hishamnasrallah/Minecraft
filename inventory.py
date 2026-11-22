"""Items, inventory and crafting. Pure Python (no Ursina) so it can be unit-tested."""
import random

from blocks import (BLOCK_DEFS, BLOCKS, BLOCK_TILES, LEAVES, WATER, GLASS, LAMP, WOOL, STAINED_GLASS, SLABS,
                    STAIRS, SHAPE_MATERIALS, FAMILIES, CONCRETE, TERRACOTTA, TERRACOTTA_PLAIN, GLAZED, CARPETS,
                    WOODS, POLISHED, ROCK_BRICKS, CHISELED, WALLS, COLOR_LAMPS, LAMP_COLORS, SLATE, COBBLED_SLATE,
                    LIMESTONE, RUBY, SAPPHIRE, AMETHYST, QUARTZ, GLOW_CRYSTAL, SEEDS, WHEAT_ITEM, BREAD, CARROT,
                    PLANT_ON_FARMLAND, STAR_SHARD, SKY_KEY, STORM_CORE)
from world import COAL_ORE

STACK_SIZE = 64
HOTBAR_SIZE = 9
INVENTORY_SIZE = 36          # 9 hotbar slots + 27 storage slots

STICK, COAL = 101, 102
RAW_MEAT, COOKED_MEAT, APPLE = 103, 104, 105
IRON_INGOT, COPPER_INGOT, TIN_INGOT, GOLD_INGOT, BRONZE_INGOT, DIAMOND = 106, 107, 108, 109, 110, 111
BUCKET, WATER_BUCKET = 112, 113
LAVA_BUCKET = 118
MILK_BUCKET, CAKE = 119, 128
RETURNS = {MILK_BUCKET: BUCKET, 175: 133}                # crafting with these gives the container back
CART = 140
CHEST_CART = 141
GLASS_BOTTLE, WATER_BOTTLE = 133, 134
EMBER_SHARD, FIRE_STRIKER = 143, 129
from blocks import POTATO, BEETROOT, BEET_SEEDS, PUMPKIN_SEEDS, PUMPKIN, MELON_SEEDS, MELON_SLICE  # noqa: E402
BAKED_POTATO, PUMPKIN_PIE = 145, 150
SHEARS = 153
BOW, ARROW, BOAT, FISHING_ROD, SADDLE = 154, 155, 156, 157, 158
COMPASS, MAP_ITEM, PAPER = 168, 169, 170
BONE_MEAL, SLIMEBALL = 171, 172
SHIELD = 173
FIREWORK, HONEY_BOTTLE = 174, 175
# armour: item -> (slot, points); every point takes away 4% of the damage (at most 80%)
ARMOR = {160: ("head", 2), 161: ("chest", 6), 162: ("legs", 5), 163: ("feet", 2),
         164: ("head", 3), 165: ("chest", 8), 166: ("legs", 6), 167: ("feet", 3)}
ARMOR_NAMES = {160: ("iron helmet", "iron_helmet"), 161: ("iron chestplate", "iron_chestplate"),
               162: ("iron leggings", "iron_leggings"), 163: ("iron boots", "iron_boots"),
               164: ("diamond helmet", "diamond_helmet"), 165: ("diamond chestplate", "diamond_chestplate"),
               166: ("diamond leggings", "diamond_leggings"), 167: ("diamond boots", "diamond_boots")}
# potions: item -> (name, icon, effect, seconds); drunk from the hand, the bottle comes back
POTIONS = {135: ("swiftness potion", "potion_swift", "swift", 90), 136: ("healing potion", "potion_heal", "heal", 0),
           137: ("night vision potion", "potion_night", "night", 120), 138: ("leaping potion", "potion_leap", "leap", 90),
           139: ("fire resistance potion", "potion_fire", "fire", 120),
           142: ("water breathing potion", "potion_water", "water", 120)}
EGG, FEATHER, RAW_FISH, COOKED_FISH = 124, 125, 126, 127          # from animals (animals.py)
FOOD = {RAW_MEAT: 2, COOKED_MEAT: 6, APPLE: 4, BREAD: 5, CARROT: 3, RAW_FISH: 2, COOKED_FISH: 5, MILK_BUCKET: 3,
        CAKE: 12, HONEY_BOTTLE: 6, POTATO: 1, BAKED_POTATO: 5, BEETROOT: 2, MELON_SLICE: 2, PUMPKIN_PIE: 8}      # item -> hunger points restored

MATERIAL_ITEMS = {
    STICK: ("stick", "stick"), COAL: ("coal", "coal"), IRON_INGOT: ("iron ingot", "iron_ingot"),
    COPPER_INGOT: ("copper ingot", "copper_ingot"), TIN_INGOT: ("tin ingot", "tin_ingot"),
    GOLD_INGOT: ("gold ingot", "gold_ingot"), BRONZE_INGOT: ("bronze ingot", "bronze_ingot"),
    DIAMOND: ("diamond", "diamond"), RUBY: ("ruby", "ruby"), SAPPHIRE: ("sapphire", "sapphire"),
    AMETHYST: ("amethyst shard", "amethyst"), QUARTZ: ("quartz", "quartz"),
    SEEDS: ("seeds", "seeds"), WHEAT_ITEM: ("wheat", "wheat"),
    STAR_SHARD: ("star shard", "star_shard"), STORM_CORE: ("storm core", "storm_core"),
    EGG: ("egg", "egg"), FEATHER: ("feather", "feather"),
}
FOOD_ITEMS = {RAW_MEAT: ("raw meat", "raw_meat"), COOKED_MEAT: ("cooked meat", "cooked_meat"),
              APPLE: ("apple", "apple"), BREAD: ("bread", "bread"), CARROT: ("carrot", "carrot"),
              RAW_FISH: ("raw fish", "raw_fish"), COOKED_FISH: ("cooked fish", "cooked_fish"),
              MILK_BUCKET: ("milk bucket", "milk_bucket"), CAKE: ("cake", "cake"),
              POTATO: ("potato", "potato"), BAKED_POTATO: ("baked potato", "baked_potato"),
              BEETROOT: ("beetroot", "beetroot"), MELON_SLICE: ("melon slice", "melon_slice"),
              PUMPKIN_PIE: ("pumpkin pie", "pumpkin_pie"), HONEY_BOTTLE: ("honey bottle", "honey_bottle")}
OTHER_ITEMS = {BUCKET: ("bucket", "bucket"), WATER_BUCKET: ("water bucket", "water_bucket"),
               LAVA_BUCKET: ("lava bucket", "lava_bucket"),
               SKY_KEY: ("sky key", "sky_key"), CART: ("cart", "cart"),
               CHEST_CART: ("chest cart", "chest_cart"),
               EMBER_SHARD: ("ember shard", "ember_shard"), BEET_SEEDS: ("beetroot seeds", "beet_seeds"),
               PUMPKIN_SEEDS: ("pumpkin seeds", "pumpkin_seeds"), MELON_SEEDS: ("melon seeds", "melon_seeds"),
               PUMPKIN: ("pumpkin", "pumpkin"), SHEARS: ("shears", "shears"),
               BOW: ("bow", "bow"), ARROW: ("arrow", "arrow"), BOAT: ("boat", "boat"),
               FISHING_ROD: ("fishing rod", "fishing_rod"), SADDLE: ("saddle", "saddle"), **ARMOR_NAMES,
               SHIELD: ("shield", "shield"), FIREWORK: ("firework", "firework"), BONE_MEAL: ("bone meal", "bone_meal"), SLIMEBALL: ("slimeball", "slimeball"),
               COMPASS: ("compass", "compass"), MAP_ITEM: ("map", "map_item"), PAPER: ("paper", "paper"), FIRE_STRIKER: ("fire striker", "fire_striker"),
               GLASS_BOTTLE: ("glass bottle", "glass_bottle"), WATER_BOTTLE: ("water bottle", "water_bottle"),
               **{p: (v[0], v[1]) for p, v in POTIONS.items()}}

# ---------------------------------------------------------------- tools
WOOD_PICKAXE, STONE_PICKAXE, WOOD_AXE, STONE_AXE = 201, 202, 203, 204
IRON_PICKAXE, DIAMOND_PICKAXE, IRON_AXE, DIAMOND_AXE = 205, 206, 207, 208
WOOD_SHOVEL, STONE_SHOVEL, IRON_SHOVEL, DIAMOND_SHOVEL = 209, 210, 211, 212
WOOD_SWORD, STONE_SWORD, IRON_SWORD, DIAMOND_SWORD = 213, 214, 215, 216
WOOD_HOE, STONE_HOE, IRON_HOE, DIAMOND_HOE = 217, 218, 219, 220

# tier: (speed multiplier, durability, level)
TIERS = {"wooden": (2.0, 60, 1), "stone": (4.0, 130, 2), "iron": (6.0, 250, 3), "diamond": (8.0, 1500, 4)}
_TOOL_IDS = {
    "pickaxe": (WOOD_PICKAXE, STONE_PICKAXE, IRON_PICKAXE, DIAMOND_PICKAXE),
    "axe": (WOOD_AXE, STONE_AXE, IRON_AXE, DIAMOND_AXE),
    "shovel": (WOOD_SHOVEL, STONE_SHOVEL, IRON_SHOVEL, DIAMOND_SHOVEL),
    "sword": (WOOD_SWORD, STONE_SWORD, IRON_SWORD, DIAMOND_SWORD),
    "hoe": (WOOD_HOE, STONE_HOE, IRON_HOE, DIAMOND_HOE),
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

# variant families for the creative menu: one item stands for the family and expands to the rest
ITEM_FAMILIES = {
    "ingots": [IRON_INGOT, COPPER_INGOT, TIN_INGOT, GOLD_INGOT, BRONZE_INGOT],
    "gems": [DIAMOND, RUBY, SAPPHIRE, AMETHYST, QUARTZ],
    **{kind + "s": list(ids) for kind, ids in _TOOL_IDS.items()},
}
# ---------------------------------------------------------------- creative menu
TABS = ["all", "natural", "building", "colored", "plants", "functional", "machines", "tools", "food", "materials"]


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


def creative_families():
    """Variant family -> its creative item ids, in menu order (the first one represents the family)."""
    creative = set(CREATIVE_ITEMS)
    families = {f: [i for i in ids if i in creative] for f, ids in {**FAMILIES, **ITEM_FAMILIES}.items()}
    return {f: ids for f, ids in families.items() if ids}


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
    return 1 if item in TOOLS or item in (WATER_BUCKET, LAVA_BUCKET, MILK_BUCKET, FIRE_STRIKER, SHEARS, BOW, SHIELD,
                                         BOAT, FISHING_ROD, SADDLE, COMPASS, MAP_ITEM, *ARMOR) else 16 if item == BUCKET else STACK_SIZE


def new_stack(item, amount):
    """Tools carry their remaining durability as a third value."""
    return (item, 1, TOOLS[item][2]) if item in TOOLS else (item, amount)


def drop_for(block_id, rng=random):
    """What you get for breaking a block (None = nothing)."""
    d = BLOCK_DEFS.get(block_id)
    if d is None:
        return None
    if block_id in (51, 52):          # tall grass and ferns sometimes hide seeds
        return SEEDS if rng.random() < 0.15 else None
    if block_id in LEAVES:            # leaves sometimes drop a stick or a sapling, oak leaves an apple
        roll = rng.random()
        if roll >= 0.94:
            return d.get("sapling")
        return STICK if roll < 0.2 else APPLE if roll < 0.28 and block_id == 5 else None
    drop = d["drop"]
    return block_id if drop == "self" else drop


# ---------------------------------------------------------------- crafting
# ingredient keys are item ids, or a group name meaning "any of these"
GROUPS = {
    "planks": [w["planks"] for w in WOODS.values()],
    "rock": [22, 3, 18, 19, 21, COBBLED_SLATE, SLATE, LIMESTONE],
    "wool": list(WOOL),
    "logs": [w["log"] for w in WOODS.values()],
    "flowers": list(FAMILIES["flowers"]),
}
GROUPS["fuel"] = [COAL, 909] + GROUPS["planks"] + GROUPS["logs"]   # burns in a furnace
COBBLE_ETC = "rock"


def _tool_recipes():
    out = []
    for material, ids in (("planks", 0), ("rock", 1), (IRON_INGOT, 2), (DIAMOND, 3)):
        out += [
            ({material: 3, STICK: 2}, (_TOOL_IDS["pickaxe"][ids], 1)),
            ({material: 2, STICK: 2}, (_TOOL_IDS["axe"][ids], 1)),
            ({material: 1, STICK: 2}, (_TOOL_IDS["shovel"][ids], 1)),
            ({material: 2, STICK: 1}, (_TOOL_IDS["sword"][ids], 1)),
            ({material: 2, STICK: 3}, (_TOOL_IDS["hoe"][ids], 1)),
        ]
    return out


# (ingredients, (result, count)) — shapeless: only the amounts matter
def _expanded_recipes():
    """Recipes for the expanded catalogue (colour families, woods, stone variants, gems...)."""
    out = []
    for i, wool in enumerate(WOOL):
        out += [({6: 4, 14: 4, wool: 1}, (CONCRETE[i], 8)),           # sand + gravel, coloured with wool
                ({TERRACOTTA_PLAIN: 8, wool: 1}, (TERRACOTTA[i], 8)),
                ({TERRACOTTA[i]: 1, COAL: 1}, (GLAZED[i], 1)),          # fire it again for a glaze
                ({wool: 2}, (CARPETS[i], 3))]
    out.append(({15: 1, COAL: 1}, (TERRACOTTA_PLAIN, 1)))
    for species, w in WOODS.items():
        if species not in ("oak", "birch", "pine"):
            out.append(({w["log"]: 1}, (w["planks"], 4)))
        if species != "oak":
            out.append(({STICK: 4, w["planks"]: 2}, (w["fence"], 3)))
    for src, polished in POLISHED.items():
        out.append(({src: 4}, (polished, 4)))
    for src, brick in ROCK_BRICKS.items():
        out.append(({POLISHED[src]: 4}, (brick, 4)))
    for src, chiseled in CHISELED.items():
        out.append(({SLABS[src] if src in SLABS else src: 2}, (chiseled, 1)))
    out += [
        ({COBBLED_SLATE: 1, COAL: 1}, (SLATE, 1)),
        ({41: 1, COAL: 1}, (815, 1)),                  # cracked stone bricks
        ({41: 1, 52: 1}, (816, 1)),                    # mossy stone bricks
        ({2: 3, 15: 1}, (953, 4)),                     # mud: dirt mixed with clay
        ({953: 4, 51: 1}, (954, 4)),                   # mud bricks
        ({51: 9}, (950, 1)),                           # hay bale from tall grass
        ({52: 4, 2: 1}, (955, 2)),                     # moss block
        ({"wool": 1, 54: 1}, (956, 1)),                # sponge
        ({17: 9}, (957, 1)),                           # packed ice
        ({AMETHYST: 2, QUARTZ: 2, LAMP: 1}, (GLOW_CRYSTAL, 2)),
        ({QUARTZ: 4}, (907, 1)),
        ({AMETHYST: 4}, (906, 1)),
        ({TIN_INGOT: 9}, (908, 1)), ({908: 1}, (TIN_INGOT, 9)),
        ({COAL: 9}, (909, 1)), ({909: 1}, (COAL, 9)),
        ({RUBY: 9}, (904, 1)), ({904: 1}, (RUBY, 9)),
        ({SAPPHIRE: 9}, (905, 1)), ({905: 1}, (SAPPHIRE, 9)),
        ({1001: 1, 70: 1}, (76, 1)),                   # marigold -> orange wool
        ({1000: 1, 70: 1}, (83, 1)),                   # lavender -> purple wool
        ({1002: 1, 70: 1}, (85, 1)),                   # pink tulip -> pink wool
        ({1003: 1, 70: 1}, (84, 1)),                   # orchid -> magenta wool
        ({1005: 1, 70: 1}, (81, 1)),                   # bluebell -> light blue wool
        ({1006: 1, 70: 1}, (73, 1)),                   # dark iris -> black wool
        ({1007: 1, 70: 1}, (77, 1)),                   # sunflower -> yellow wool
        ({52: 1, 70: 1}, (79, 1)),                     # fern -> green wool
        ({1011: 1, 70: 1}, (75, 1)),                   # berries -> red wool
    ]
    for lamp, (color, dye) in zip(COLOR_LAMPS, LAMP_COLORS):
        out.append(({LAMP: 1, STAINED_GLASS[dye]: 1}, (lamp, 1)))
    for material, wall in WALLS.items():
        out.append(({material: 6}, (wall, 6)))
    for ore, gem in ((900, RUBY), (901, SAPPHIRE), (902, AMETHYST), (903, QUARTZ)):
        out.append(({ore: 1, COAL: 1}, (gem, 1)))      # smelting an ore block you picked up in creative
    return out


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
    *[({w["planks"]: 6}, (w["door"], 2)) for w in WOODS.values()],      # a door of each wood
    # machines and logic
    ({COPPER_INGOT: 1}, (1700, 8)), ({STICK: 1, "rock": 1}, (1702, 1)), ({"rock": 1}, (1704, 1)),
    ({COPPER_INGOT: 2, COAL: 2, IRON_INGOT: 1}, (1705, 1)), ({"planks": 2, COPPER_INGOT: 1}, (1706, 1)),
    ({GLASS: 1, QUARTZ: 1, COPPER_INGOT: 1}, (1707, 1)), ({LAMP: 1, COPPER_INGOT: 1}, (1708, 1)),
    ({"rock": 1, COPPER_INGOT: 1}, (1710, 1)), ({"rock": 1, COPPER_INGOT: 2}, (1714, 1)),
    ({"rock": 1, COPPER_INGOT: 1, QUARTZ: 1}, (1718, 1)), ({"rock": 1, COPPER_INGOT: 2, QUARTZ: 1}, (1722, 1)),
    ({"rock": 1, COPPER_INGOT: 1, STICK: 1}, (1726, 1)),
    ({"planks": 3, "rock": 4, IRON_INGOT: 1, COPPER_INGOT: 1}, (1730, 1)),
    ({"rock": 6, IRON_INGOT: 2, COPPER_INGOT: 1}, (1736, 1)),
    ({IRON_INGOT: 1, "planks": 3, COPPER_INGOT: 1}, (1742, 4)), ({IRON_INGOT: 5, 48: 1}, (1746, 1)),
    ({47: 1, COPPER_INGOT: 4, IRON_INGOT: 2}, (1747, 1)),
    ({"rock": 6, COPPER_INGOT: 2, QUARTZ: 1}, (1820, 1)),  # observer
    ({"rock": 7, COPPER_INGOT: 1}, (1832, 1)),            # thrower
    ({STICK: 1, COPPER_INGOT: 1}, (1846, 2)),              # power torch
    ({"rock": 3, COPPER_INGOT: 3, QUARTZ: 1}, (1838, 1)),  # comparator
    ({1730: 1, WHEAT_ITEM: 3}, (1792, 1)),                # sticky pusher: a pusher with a gluey face
    ({IRON_INGOT: 1, STICK: 2}, (1750, 8)),               # track
    ({IRON_INGOT: 1, GOLD_INGOT: 1, COPPER_INGOT: 1, STICK: 1}, (1756, 4)),   # boost track
    ({IRON_INGOT: 5}, (CART, 1)),
    ({CART: 1, 48: 1}, (CHEST_CART, 1)),
    ({GLASS: 3}, (GLASS_BOTTLE, 3)),
    ({IRON_INGOT: 6}, (1924, 1)),                          # iron door
    ({"planks": 6}, (1932, 2)),                            # trapdoors
    ({"planks": 2, STICK: 4}, (1940, 1)),                  # fence gate
    ({GLASS: 6}, (1948, 16)),                              # glass panes
    ({IRON_INGOT: 1, 50: 1}, (1949, 1)),                   # lantern: a torch in iron
    ({"planks": 6, "logs": 1}, (1950, 1)),                 # barrel
    ({6: 4, COAL: 5}, (1951, 1)),                          # TNT: sand and coal powder
    ({IRON_INGOT: 2}, (SHEARS, 1)),
    ({STICK: 3, "wool": 1}, (BOW, 1)),
    ({STICK: 1, FEATHER: 1, 22: 1}, (ARROW, 4)),
    ({"planks": 5}, (BOAT, 1)),
    ({"planks": 6, STICK: 1}, (1953, 3)),                # signs
    ({"planks": 7}, (1962, 1)),                            # composter
    ({"planks": 6, IRON_INGOT: 1}, (SHIELD, 1)),
    ({"planks": 6, "flowers": 3}, (1991, 1)),              # beehive
    ({59: 6, "wool": 1}, (1992, 6)),                        # scaffolding: reeds tied with wool
    ({PAPER: 1, COAL: 1, "wool": 1}, (FIREWORK, 3)),
    ({STICK: 8, "wool": 1}, (1970, 1)), ({STICK: 8, "flowers": 1}, (1974, 1)),   # paintings
    ({STICK: 8, 121: 1}, (1978, 1)), ({STICK: 8, 123: 1}, (1982, 1)),
    ({STICK: 8, 48: 1}, (1986, 1)),                        # item frame
    ({8: 3}, (1990, 1)),                                   # flower pot from bricks
    ({STICK: 3, COAL: 1, "logs": 3}, (1963, 1)),           # campfire
    ({IRON_INGOT: 31}, (1964, 1)),                         # anvil: a lot of iron
    ({SLIMEBALL: 9}, (1965, 1)), ({1965: 1}, (SLIMEBALL, 9)),
    ({59: 3}, (PAPER, 3)),                               # paper from reeds
    ({IRON_INGOT: 4, COPPER_INGOT: 1}, (COMPASS, 1)),
    ({PAPER: 8, COMPASS: 1}, (MAP_ITEM, 1)),
    ({DIAMOND: 2, 1890: 4, 45: 1}, (1961, 1)),           # enchanting table: diamonds, obsidian, a bookshelf
    ({STICK: 3, "wool": 1, IRON_INGOT: 1}, (FISHING_ROD, 1)),
    ({"wool": 3, IRON_INGOT: 1}, (SADDLE, 1)),
    ({IRON_INGOT: 5}, (160, 1)), ({IRON_INGOT: 8}, (161, 1)), ({IRON_INGOT: 7}, (162, 1)), ({IRON_INGOT: 4}, (163, 1)),
    ({DIAMOND: 5}, (164, 1)), ({DIAMOND: 8}, (165, 1)), ({DIAMOND: 7}, (166, 1)), ({DIAMOND: 4}, (167, 1)),
    ({"rock": 4, COPPER_INGOT: 2, 1726: 1}, (1906, 1)),     # timer: a delay gate in a box
    ({"rock": 4, COPPER_INGOT: 2, 1700: 2}, (1908, 1)),     # counter
    ({"planks": 8, COPPER_INGOT: 1}, (1910, 1)),           # note block
    ({"rock": 4, IRON_INGOT: 2, COPPER_INGOT: 1}, (1911, 1)),   # fan
    ({PUMPKIN: 1, EGG: 1, 59: 1}, (PUMPKIN_PIE, 1)),     # pumpkin, egg and reeds for sweetness
    ({PUMPKIN: 1}, (PUMPKIN_SEEDS, 4)), ({MELON_SLICE: 1}, (MELON_SEEDS, 1)),
    ({IRON_INGOT: 1, COAL: 1}, (FIRE_STRIKER, 1)),       # lights an obsidian frame: the way to the fire realm
    ({EMBER_SHARD: 4}, (910, 1)),                        # ember shards make a glow crystal
    ({1900: 4}, (1901, 4)),                              # ember bricks
    ({1868: 1, GLASS_BOTTLE: 1}, (1884, 1)),            # a brewing stand: from an auto-crafter
    ({COBBLED_SLATE: 3, IRON_INGOT: 1, GLASS_BOTTLE: 1}, (1884, 1)),     # a cart with a chest: carries things along the track
    ({116: 4, 910: 1, DIAMOND: 1}, (SKY_KEY, 1)),            # amethyst x4, glow crystal, diamond
    ({STAR_SHARD: 9}, (1804, 1)), ({1804: 1}, (STAR_SHARD, 9)),
    ({STAR_SHARD: 4, STORM_CORE: 1}, (1808, 1)),
    ({WHEAT_ITEM: 3}, (BREAD, 1)), ({WHEAT_ITEM: 9}, (950, 1)), ({950: 1}, (WHEAT_ITEM, 9)),
    ({EGG: 1, WHEAT_ITEM: 2}, (BREAD, 2)),     # egg bread
    ({MILK_BUCKET: 1, WHEAT_ITEM: 3, EGG: 1}, (CAKE, 1)),   # the bucket comes back (RETURNS)
    ({RAW_FISH: 2, COAL: 1}, (COOKED_FISH, 2)),
    ({FEATHER: 4}, (70, 1)),                   # feathers stuffed into white wool
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
    *_expanded_recipes(),
]


# the furnace: one piece of fuel (coal, a coal block, planks or a log) per item
SMELTING = [
    ({25: 1, "fuel": 1}, (IRON_INGOT, 1)), ({26: 1, "fuel": 1}, (COPPER_INGOT, 1)),
    ({27: 1, "fuel": 1}, (TIN_INGOT, 1)), ({28: 1, "fuel": 1}, (GOLD_INGOT, 1)),
    ({6: 1, "fuel": 1}, (GLASS, 1)), ({22: 1, "fuel": 1}, (3, 1)), ({RAW_MEAT: 1, "fuel": 1}, (COOKED_MEAT, 1)),
    ({15: 1, "fuel": 1}, (664, 1)), ({COBBLED_SLATE: 1, "fuel": 1}, (SLATE, 1)),
    ({"logs": 1, "fuel": 1}, (COAL, 1)), ({24: 1, "fuel": 1}, (GLASS, 1)),
    ({RAW_FISH: 1, "fuel": 1}, (COOKED_FISH, 1)), ({POTATO: 1, "fuel": 1}, (BAKED_POTATO, 1)),
]


# the brewing stand: a water bottle and one ingredient
BREWING = [
    ({WATER_BOTTLE: 1, 59: 1}, (135, 1)),                # reeds: swiftness
    ({WATER_BOTTLE: 1, APPLE: 1}, (136, 1)),             # apple: healing
    ({WATER_BOTTLE: 1, CARROT: 1}, (137, 1)),            # carrot: night vision
    ({WATER_BOTTLE: 1, FEATHER: 1}, (138, 1)),           # feather: leaping
    ({WATER_BOTTLE: 1, 1890: 1}, (139, 1)),              # obsidian: fire resistance
    ({WATER_BOTTLE: 1, EMBER_SHARD: 1}, (139, 2)),       # ember shard: fire resistance, twice
    ({WATER_BOTTLE: 1, RAW_FISH: 1}, (142, 1)),          # fish: water breathing
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
        for i, n in recipe[0].items():
            if i in RETURNS and self.add(RETURNS[i], n):
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
