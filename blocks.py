"""The block registry: every block's name, textures, shape, hardness, tool, drops and
creative-menu category in one place. world.py, inventory.py and the UI read from here.

IDs are stable (they're stored in save files), so new blocks get new numbers.
"""

# block shapes
CUBE, CROSS, SLAB, STAIR, FENCE, LADDER, DOOR, BED, TORCH = (
    "cube", "cross", "slab", "stair", "fence", "ladder", "door", "bed", "torch")

# creative menu tabs (items and tools add "tools" / "food" / "materials" in inventory.py)
NATURAL, BUILDING, COLORED, PLANTS, FUNCTIONAL = "natural", "building", "colored", "plants", "functional"

WATER, LAMP, GLASS = 10, 11, 12

BLOCK_DEFS = {}     # id -> dict


def block(id_, name, tiles, tab, hardness=1.0, tool=None, level=0, drop="self", shape=CUBE,
          transparent=False, translucent=False, solid=True, emit=0, creative=True, **extra):
    """Register a block.

    tiles: one tile name, or (top, side, bottom)
    tool / level: the tool kind that speeds it up, and the tier needed for it to drop anything
                  (0 = by hand, 1 = wooden, 2 = stone, 3 = iron, 4 = diamond)
    drop: "self", None, or an item id
    transparent: light passes and neighbours' faces stay visible (glass, leaves are opaque here)
    translucent: drawn with real see-through colour (coloured glass)
    solid: you collide with it (plants, torches and ladders are walk-through)
    """
    if isinstance(tiles, str):
        tiles = (tiles, tiles, tiles)
    BLOCK_DEFS[id_] = dict(id=id_, name=name, tiles=tiles, tab=tab, hardness=hardness, tool=tool, level=level,
                           drop=drop, shape=shape, transparent=transparent or shape != CUBE or translucent,
                           translucent=translucent, solid=solid, emit=emit, creative=creative, **extra)
    return id_


# ---------------------------------------------------------------- original blocks (ids 1-13 are in old saves)
block(1, "grass", ("grass_top", "grass_side", "dirt"), NATURAL, 0.6, "shovel", drop=2)
block(2, "dirt", "dirt", NATURAL, 0.5, "shovel")
block(3, "stone", "stone", NATURAL, 1.5, "pickaxe", 1, drop=22)
block(4, "oak log", ("log_top", "log_side", "log_top"), NATURAL, 2.0, "axe")
block(5, "oak leaves", "leaves", NATURAL, 0.2, drop=None, leaves=True)
block(6, "sand", "sand", NATURAL, 0.5, "shovel")
block(7, "oak planks", "planks", BUILDING, 2.0, "axe")
block(8, "brick", "brick", BUILDING, 2.0, "pickaxe", 1)
block(9, "bedrock", "bedrock", NATURAL, -1, creative=True)
block(WATER, "water", "water", NATURAL, -1, transparent=True, solid=False, creative=False)
block(LAMP, "lamp", "lamp", FUNCTIONAL, 0.3, emit=14)
block(GLASS, "glass", "glass", BUILDING, 0.3, transparent=True)
block(13, "coal ore", "coal_ore", NATURAL, 3.0, "pickaxe", 1, drop=102)

# ---------------------------------------------------------------- natural terrain
block(14, "gravel", "gravel", NATURAL, 0.6, "shovel")
block(15, "clay", "clay", NATURAL, 0.6, "shovel")
block(16, "snow", "snow", NATURAL, 0.2, "shovel")
block(17, "ice", "ice", NATURAL, 0.5, "pickaxe", transparent=True)
block(18, "granite", "granite", NATURAL, 1.5, "pickaxe", 1)
block(19, "basalt", "basalt", NATURAL, 1.5, "pickaxe", 1)
block(20, "sandstone", "sandstone", NATURAL, 0.8, "pickaxe", 1)
block(21, "marble", "marble", NATURAL, 1.5, "pickaxe", 1)
block(22, "cobblestone", "cobblestone", BUILDING, 2.0, "pickaxe", 1)
block(23, "mossy cobblestone", "mossy_cobblestone", BUILDING, 2.0, "pickaxe", 1)
block(24, "red sand", "red_sand", NATURAL, 0.5, "shovel")
block(25, "iron ore", "iron_ore", NATURAL, 3.0, "pickaxe", 2)
block(26, "copper ore", "copper_ore", NATURAL, 3.0, "pickaxe", 1)
block(27, "tin ore", "tin_ore", NATURAL, 3.0, "pickaxe", 1)
block(28, "gold ore", "gold_ore", NATURAL, 3.0, "pickaxe", 3)
block(29, "diamond ore", "diamond_ore", NATURAL, 3.0, "pickaxe", 3, drop=111)
block(35, "birch log", ("birch_log_top", "birch_log", "birch_log_top"), NATURAL, 2.0, "axe")
block(37, "birch leaves", "birch_leaves", NATURAL, 0.2, drop=None, leaves=True)
block(38, "pine log", ("pine_log_top", "pine_log", "pine_log_top"), NATURAL, 2.0, "axe")
block(40, "pine leaves", "pine_leaves", NATURAL, 0.2, drop=None, leaves=True)

# ---------------------------------------------------------------- building blocks
block(30, "iron block", "iron_block", BUILDING, 5.0, "pickaxe", 2)
block(31, "copper block", "copper_block", BUILDING, 5.0, "pickaxe", 1)
block(32, "gold block", "gold_block", BUILDING, 3.0, "pickaxe", 3)
block(33, "bronze block", "bronze_block", BUILDING, 5.0, "pickaxe", 2)
block(34, "diamond block", "diamond_block", BUILDING, 5.0, "pickaxe", 3)
block(36, "birch planks", "birch_planks", BUILDING, 2.0, "axe")
block(39, "pine planks", "pine_planks", BUILDING, 2.0, "axe")
block(41, "stone bricks", "stone_bricks", BUILDING, 1.5, "pickaxe", 1)
block(42, "sandstone bricks", "sandstone_bricks", BUILDING, 0.8, "pickaxe", 1)
block(43, "tiles", "tiles", BUILDING, 1.5, "pickaxe", 1)
block(44, "plaster", "plaster", BUILDING, 1.0, "pickaxe")

# ---------------------------------------------------------------- functional
block(45, "bookshelf", ("planks", "bookshelf", "planks"), FUNCTIONAL, 1.5, "axe")
block(46, "workbench", ("workbench_top", "workbench_side", "planks"), FUNCTIONAL, 2.5, "axe")
block(47, "furnace", ("furnace_top", "furnace_front", "furnace_top"), FUNCTIONAL, 3.5, "pickaxe", 1)
block(48, "chest", ("chest_top", "chest_front", "chest_top"), FUNCTIONAL, 2.5, "axe", container=True)
block(50, "torch", "torch", FUNCTIONAL, 0.0, shape=TORCH, solid=False, emit=13)
block(61, "oak fence", "planks", FUNCTIONAL, 2.0, "axe", shape=FENCE)
block(62, "bed", ("bed_top", "bed_side", "planks"), FUNCTIONAL, 0.2, shape=BED)

# ladders face one of 4 directions: 500 + facing (0 = +z, 1 = +x, 2 = -z, 3 = -x: the wall it hangs on)
LADDERS = [block(500 + f, "ladder", "ladder", FUNCTIONAL, 0.4, "axe", shape=LADDER, solid=False,
                 facing=f, creative=f == 0, drop=500, climbable=True) for f in range(4)]

# doors: 510 + axis*4 + open*2 + top  (axis 0 = panel across x, 1 = across z)
DOORS = {}
for axis in (0, 1):
    for is_open in (0, 1):
        for top in (0, 1):
            i = 510 + axis * 4 + is_open * 2 + top
            DOORS[i] = dict(axis=axis, open=is_open, top=top)
            block(i, "door", ("door_top" if top else "door_bottom"), FUNCTIONAL, 2.0, "axe", shape=DOOR,
                  creative=i == 510, drop=510 if not top else None, door=DOORS[i])

# ---------------------------------------------------------------- plants
block(51, "tall grass", "tall_grass", PLANTS, 0.0, shape=CROSS, solid=False, drop=None)
block(52, "fern", "fern", PLANTS, 0.0, shape=CROSS, solid=False, drop=None)
block(53, "red flower", "red_flower", PLANTS, 0.0, shape=CROSS, solid=False)
block(54, "yellow flower", "yellow_flower", PLANTS, 0.0, shape=CROSS, solid=False)
block(55, "blue flower", "blue_flower", PLANTS, 0.0, shape=CROSS, solid=False)
block(56, "white flower", "white_flower", PLANTS, 0.0, shape=CROSS, solid=False)
block(57, "red mushroom", "red_mushroom", PLANTS, 0.0, shape=CROSS, solid=False)
block(58, "brown mushroom", "brown_mushroom", PLANTS, 0.0, shape=CROSS, solid=False)
block(59, "reeds", "reeds", PLANTS, 0.0, shape=CROSS, solid=False)
block(60, "cactus", ("cactus_top", "cactus", "cactus_top"), PLANTS, 0.4)

# ---------------------------------------------------------------- colours (wool + stained glass)
DYES = [
    ("white", (232, 232, 232)), ("light gray", (160, 160, 158)), ("gray", (90, 92, 96)), ("black", (28, 28, 32)),
    ("brown", (112, 74, 44)), ("red", (176, 46, 40)), ("orange", (230, 124, 34)), ("yellow", (236, 200, 52)),
    ("lime", (120, 196, 40)), ("green", (72, 104, 30)), ("cyan", (34, 136, 150)), ("light blue", (96, 164, 222)),
    ("blue", (52, 64, 168)), ("purple", (122, 50, 174)), ("magenta", (186, 70, 180)), ("pink", (230, 140, 170)),
]
WOOL = [block(70 + i, f"{name} wool", f"wool_{i}", COLORED, 0.8, dye=rgb) for i, (name, rgb) in enumerate(DYES)]
STAINED_GLASS = [block(400 + i, f"{name} glass", f"glass_{i}", COLORED, 0.3, translucent=True, dye=rgb)
                 for i, (name, rgb) in enumerate(DYES)]

# ---------------------------------------------------------------- slabs and stairs
SHAPE_MATERIALS = [3, 22, 7, 36, 39, 8, 41, 20, 21]   # stone, cobble, 3 planks, brick, stone bricks, sandstone, marble
SLABS, STAIRS = {}, {}
for i, material in enumerate(SHAPE_MATERIALS):
    m = BLOCK_DEFS[material]
    SLABS[material] = block(300 + i, f"{m['name']} slab", m["tiles"], BUILDING, m["hardness"], m["tool"],
                            m["level"], shape=SLAB, material=material)
    STAIRS[material] = []
    for f in range(4):                                   # facing: the side the high step is on
        STAIRS[material].append(block(320 + i * 4 + f, f"{m['name']} stairs", m["tiles"], BUILDING, m["hardness"],
                                      m["tool"], m["level"], shape=STAIR, material=material, facing=f,
                                      creative=f == 0, drop=320 + i * 4))


# ---------------------------------------------------------------- derived lookups
BLOCKS = {i: d["name"] for i, d in BLOCK_DEFS.items()}
BLOCK_TILES = {i: d["tiles"] for i, d in BLOCK_DEFS.items()}
TRANSPARENT = {i for i, d in BLOCK_DEFS.items() if d["transparent"]}
TRANSLUCENT = {i for i, d in BLOCK_DEFS.items() if d["translucent"]}
NON_SOLID = {0} | {i for i, d in BLOCK_DEFS.items() if not d["solid"]}
LIGHT_EMIT = {i: d["emit"] for i, d in BLOCK_DEFS.items() if d["emit"]}
UNBREAKABLE = {i for i, d in BLOCK_DEFS.items() if d["hardness"] < 0}
LEAVES = {i for i, d in BLOCK_DEFS.items() if d.get("leaves")}
PLANTS_NEED_SOIL = {51, 52, 53, 54, 55, 56, 57, 58, 59}
SHAPED = {i for i, d in BLOCK_DEFS.items() if d["shape"] != CUBE}


def facing_from_yaw(yaw):
    """Player yaw in degrees (0 = +z, 90 = +x) -> facing index 0..3 (0 = +z, 1 = +x, 2 = -z, 3 = -x)."""
    return int(((yaw % 360) + 45) // 90) % 4


FACING_VECTORS = [(0, 1), (1, 0), (0, -1), (-1, 0)]   # (dx, dz) for facing 0..3


def toggled_door(block_id):
    """The same door half, opened if it was closed and closed if it was open."""
    return block_id - 2 if DOORS[block_id]["open"] else block_id + 2
