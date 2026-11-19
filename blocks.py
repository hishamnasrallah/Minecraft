"""The block registry: every block's name, textures, shape, hardness, tool, drops and
creative-menu category in one place. world.py, inventory.py and the UI read from here.

IDs are stable (they're stored in save files), so new blocks get new numbers.
"""

# block shapes
CUBE, CROSS, SLAB, STAIR, FENCE, LADDER, DOOR, BED, TORCH = (
    "cube", "cross", "slab", "stair", "fence", "ladder", "door", "bed", "torch")
CARPET = "carpet"           # a thin 1/16 layer lying on the block below

# creative menu tabs (items and tools add "tools" / "food" / "materials" in inventory.py)
NATURAL, BUILDING, COLORED, PLANTS, FUNCTIONAL = "natural", "building", "colored", "plants", "functional"

WATER, LAMP, GLASS = 10, 11, 12

BLOCK_DEFS = {}     # id -> dict
FAMILIES = {}       # variant family ("wool", "planks", "slabs", ...) -> ids in menu order


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
    if extra.get("family"):
        FAMILIES.setdefault(extra["family"], []).append(id_)
    return id_


def family(name, ids):
    """Put already registered blocks into a variant family (the UI shows one and expands the rest)."""
    for i in ids:
        BLOCK_DEFS[i]["family"] = name
        FAMILIES.setdefault(name, []).append(i)
    return list(ids)


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

# ================================================================ expanded catalogue (ids 600+)
# ---------------------------------------------------------------- colour families
CONCRETE = [block(600 + i, f"{name} concrete", f"concrete_{i}", COLORED, 1.8, "pickaxe", 1, dye=rgb,
                  family="concrete") for i, (name, rgb) in enumerate(DYES)]
TERRACOTTA_PLAIN = block(664, "terracotta", "terracotta", COLORED, 1.25, "pickaxe", 1, family="terracotta")
TERRACOTTA = [block(616 + i, f"{name} terracotta", f"terracotta_{i}", COLORED, 1.25, "pickaxe", 1, dye=rgb,
                    family="terracotta") for i, (name, rgb) in enumerate(DYES)]
GLAZED = [block(632 + i, f"{name} glazed tile", f"glazed_{i}", COLORED, 1.4, "pickaxe", 1, dye=rgb,
                family="glazed_tiles") for i, (name, rgb) in enumerate(DYES)]
CARPETS = [block(648 + i, f"{name} carpet", f"wool_{i}", COLORED, 0.1, shape=CARPET, solid=False, dye=rgb,
                 family="carpet") for i, (name, rgb) in enumerate(DYES)]

# ---------------------------------------------------------------- wood: 4 new tree species + fences/saplings
# each species: log, planks, leaves, fence, sapling at 700 + 10 * index
WOOD_SPECIES = ["maple", "cherry", "ashwood", "ebony"]
WOODS = {}          # species -> dict(log, planks, leaves, fence, sapling)
for _s, _sp in enumerate(WOOD_SPECIES):
    _b = 700 + 10 * _s
    WOODS[_sp] = dict(
        log=block(_b, f"{_sp} log", (f"{_sp}_log_top", f"{_sp}_log", f"{_sp}_log_top"), NATURAL, 2.0, "axe"),
        planks=block(_b + 1, f"{_sp} planks", f"{_sp}_planks", BUILDING, 2.0, "axe"),
        leaves=block(_b + 2, f"{_sp} leaves", f"{_sp}_leaves", NATURAL, 0.2, drop=None, leaves=True,
                     sapling=_b + 4),
        fence=block(_b + 3, f"{_sp} fence", f"{_sp}_planks", FUNCTIONAL, 2.0, "axe", shape=FENCE),
        sapling=block(_b + 4, f"{_sp} sapling", f"{_sp}_sapling", PLANTS, 0.0, shape=CROSS, solid=False),
    )
WOODS = {"oak": dict(log=4, planks=7, leaves=5, fence=61, sapling=742),
         "birch": dict(log=35, planks=36, leaves=37, fence=740, sapling=743),
         "pine": dict(log=38, planks=39, leaves=40, fence=741, sapling=744), **WOODS}
block(740, "birch fence", "birch_planks", FUNCTIONAL, 2.0, "axe", shape=FENCE)
block(741, "pine fence", "pine_planks", FUNCTIONAL, 2.0, "axe", shape=FENCE)
for _sp in ("oak", "birch", "pine"):
    block(WOODS[_sp]["sapling"], f"{_sp} sapling", f"{_sp}_sapling", PLANTS, 0.0, shape=CROSS, solid=False)
    BLOCK_DEFS[WOODS[_sp]["leaves"]]["sapling"] = WOODS[_sp]["sapling"]
for _part, _fam in (("log", "logs"), ("planks", "planks"), ("leaves", "leaves"), ("fence", "fences"),
                    ("sapling", "saplings")):
    family(_fam, [w[_part] for w in WOODS.values()])

# ---------------------------------------------------------------- stone families
SLATE, COBBLED_SLATE, LIMESTONE = 800, 801, 802
block(SLATE, "slate", "slate", NATURAL, 2.0, "pickaxe", 1, drop=COBBLED_SLATE)
block(COBBLED_SLATE, "cobbled slate", "cobbled_slate", BUILDING, 2.2, "pickaxe", 1)
block(LIMESTONE, "limestone", "limestone", NATURAL, 1.2, "pickaxe", 1)
POLISHED = {}        # source rock -> polished id
for _i, (_src, _name) in enumerate(((3, "polished stone"), (18, "polished granite"), (19, "polished basalt"),
                                    (21, "polished marble"), (20, "smooth sandstone"), (SLATE, "polished slate"),
                                    (LIMESTONE, "polished limestone"))):
    POLISHED[_src] = block(803 + _i, _name, _name.replace(" ", "_"), BUILDING, 1.6, "pickaxe", 1,
                           family="polished_stone")
ROCK_BRICKS = {}     # source rock -> bricks id
for _i, (_src, _name) in enumerate(((18, "granite bricks"), (19, "basalt bricks"), (21, "marble bricks"),
                                    (SLATE, "slate bricks"), (LIMESTONE, "limestone bricks"))):
    ROCK_BRICKS[_src] = block(810 + _i, _name, _name.replace(" ", "_"), BUILDING, 1.6, "pickaxe", 1)
block(815, "cracked stone bricks", "cracked_stone_bricks", BUILDING, 1.5, "pickaxe", 1)
block(816, "mossy stone bricks", "mossy_stone_bricks", BUILDING, 1.5, "pickaxe", 1)
CHISELED = {}
for _i, (_src, _name) in enumerate(((3, "chiseled stone"), (20, "chiseled sandstone"), (21, "chiseled marble"),
                                    (LIMESTONE, "chiseled limestone"))):
    CHISELED[_src] = block(817 + _i, _name, _name.replace(" ", "_"), BUILDING, 1.5, "pickaxe", 1,
                           family="chiseled_stone")
family("rocks", [3, 18, 19, 21, 20, SLATE, LIMESTONE])
family("cobblestone", [22, 23, COBBLED_SLATE])
family("stone_bricks", [41, 815, 816, 42, *ROCK_BRICKS.values()])
family("sand", [6, 24])

# ---------------------------------------------------------------- minerals
RUBY_ORE, SAPPHIRE_ORE, AMETHYST_ORE, QUARTZ_ORE = 900, 901, 902, 903
RUBY, SAPPHIRE, AMETHYST, QUARTZ = 114, 115, 116, 117          # gem items (registered in inventory.py)
block(RUBY_ORE, "ruby ore", "ruby_ore", NATURAL, 3.0, "pickaxe", 3, drop=RUBY)
block(SAPPHIRE_ORE, "sapphire ore", "sapphire_ore", NATURAL, 3.0, "pickaxe", 3, drop=SAPPHIRE)
block(AMETHYST_ORE, "amethyst ore", "amethyst_ore", NATURAL, 3.0, "pickaxe", 2, drop=AMETHYST)
block(QUARTZ_ORE, "quartz ore", "quartz_ore", NATURAL, 3.0, "pickaxe", 2, drop=QUARTZ)
block(904, "ruby block", "ruby_block", BUILDING, 5.0, "pickaxe", 3)
block(905, "sapphire block", "sapphire_block", BUILDING, 5.0, "pickaxe", 3)
block(906, "amethyst block", "amethyst_block", BUILDING, 4.0, "pickaxe", 2)
block(907, "quartz block", "quartz_block", BUILDING, 3.0, "pickaxe", 2)
block(908, "tin block", "tin_block", BUILDING, 5.0, "pickaxe", 1)
block(909, "coal block", "coal_block", BUILDING, 4.0, "pickaxe", 1)
GLOW_CRYSTAL = block(910, "glow crystal", "glow_crystal", FUNCTIONAL, 0.6, "pickaxe", emit=15)
family("ores", [13, 26, 27, 25, 28, 29, RUBY_ORE, SAPPHIRE_ORE, AMETHYST_ORE, QUARTZ_ORE])
family("storage_blocks", [909, 30, 31, 908, 32, 33, 34, 904, 905, 906, 907])

# ---------------------------------------------------------------- misc natural and farm blocks
block(950, "hay bale", ("hay_top", "hay_side", "hay_top"), PLANTS, 0.5, family="farm_blocks")
block(951, "pumpkin", ("pumpkin_top", "pumpkin_side", "pumpkin_top"), PLANTS, 1.0, "axe", family="farm_blocks")
block(952, "melon", ("melon_top", "melon_side", "melon_top"), PLANTS, 1.0, "axe", family="farm_blocks")
block(953, "mud", "mud", NATURAL, 0.5, "shovel")
block(954, "mud bricks", "mud_bricks", BUILDING, 1.5, "pickaxe", 1)
block(955, "moss block", "moss_block", NATURAL, 0.2)
block(956, "sponge", "sponge", FUNCTIONAL, 0.6)
block(957, "packed ice", "packed_ice", NATURAL, 0.6, "pickaxe")
LAMP_COLORS = [("red", 5), ("orange", 6), ("yellow", 7), ("green", 8), ("cyan", 10), ("blue", 12),
               ("purple", 13), ("pink", 15)]
family("lamps", [LAMP])
COLOR_LAMPS = [block(960 + i, f"{name} lamp", f"lamp_{name.replace(' ', '_')}", FUNCTIONAL, 0.3, emit=14,
                     dye=DYES[d][1], family="lamps") for i, (name, d) in enumerate(LAMP_COLORS)]
FAMILIES["lamps"].append(GLOW_CRYSTAL)
BLOCK_DEFS[GLOW_CRYSTAL]["family"] = "lamps"

# ---------------------------------------------------------------- plants
NEW_FLOWERS = [block(1000 + i, name, name.replace(" ", "_"), PLANTS, 0.0, shape=CROSS, solid=False)
               for i, name in enumerate(("lavender", "marigold", "pink tulip", "orchid", "daisy", "bluebell",
                                         "dark iris", "sunflower"))]
FLOWERS = family("flowers", [53, 54, 55, 56, *NEW_FLOWERS])
LEAFY_BUSH, BERRY_BUSH, DRY_BUSH = 1010, 1011, 1012
block(LEAFY_BUSH, "leafy bush", "leafy_bush", PLANTS, 0.0, shape=CROSS, solid=False, drop=None)
block(BERRY_BUSH, "berry bush", "berry_bush", PLANTS, 0.0, shape=CROSS, solid=False)
block(DRY_BUSH, "dry bush", "dry_bush", PLANTS, 0.0, shape=CROSS, solid=False, drop=None)
family("grasses", [51, 52, LEAFY_BUSH, BERRY_BUSH, DRY_BUSH])
family("mushrooms", [57, 58])
family("wool", WOOL)
family("stained_glass", STAINED_GLASS)

# ---------------------------------------------------------------- slabs and stairs
SHAPE_MATERIALS = [3, 22, 7, 36, 39, 8, 41, 20, 21]   # stone, cobble, 3 planks, brick, stone bricks, sandstone, marble
SLABS, STAIRS = {}, {}


def _slab_and_stairs(material, slab_id, stair_id):
    m = BLOCK_DEFS[material]
    SLABS[material] = block(slab_id, f"{m['name']} slab", m["tiles"], BUILDING, m["hardness"], m["tool"],
                            m["level"], shape=SLAB, material=material, family="slabs")
    STAIRS[material] = []
    for f in range(4):                                   # facing: the side the high step is on
        STAIRS[material].append(block(stair_id + f, f"{m['name']} stairs", m["tiles"], BUILDING, m["hardness"],
                                      m["tool"], m["level"], shape=STAIR, material=material, facing=f,
                                      creative=f == 0, drop=stair_id, family="stairs" if f == 0 else None))


for i, material in enumerate(SHAPE_MATERIALS):
    _slab_and_stairs(material, 300 + i, 320 + i * 4)
# newer materials: slabs at 1100+, stairs at 1200+ (4 facings each)
NEW_SHAPE_MATERIALS = [WOODS[s]["planks"] for s in WOOD_SPECIES] + [
    COBBLED_SLATE, POLISHED[SLATE], 18, 19, LIMESTONE, *[POLISHED[r] for r in (3, 18, 19, 21, 20)],
    *ROCK_BRICKS.values(), 23, 954, 816]
for i, material in enumerate(NEW_SHAPE_MATERIALS):
    _slab_and_stairs(material, 1100 + i, 1200 + i * 4)
SHAPE_MATERIALS = SHAPE_MATERIALS + NEW_SHAPE_MATERIALS

# walls: stone fences (same shape as fences, joining neighbouring walls and solid blocks)
WALL_MATERIALS = [22, 23, COBBLED_SLATE, 41, 816, 8, 18, 19, 21, 20, LIMESTONE, ROCK_BRICKS[SLATE], 954]
WALLS = {}
for i, material in enumerate(WALL_MATERIALS):
    m = BLOCK_DEFS[material]
    WALLS[material] = block(1400 + i, f"{m['name']} wall", m["tiles"], BUILDING, m["hardness"], m["tool"],
                            m["level"], shape=FENCE, material=material, family="walls")


# ---------------------------------------------------------------- doors for every wood
# 1500 + 8 * n: the same layout as the oak door at 510 (axis*4 + open*2 + top)
for _n, _sp in enumerate(sp for sp in WOODS if sp != "oak"):
    _base = 1500 + 8 * _n
    for axis in (0, 1):
        for is_open in (0, 1):
            for top in (0, 1):
                i = _base + axis * 4 + is_open * 2 + top
                DOORS[i] = dict(axis=axis, open=is_open, top=top, base=_base)
                block(i, f"{_sp} door", (f"{_sp}_door_top" if top else f"{_sp}_door_bottom"), FUNCTIONAL, 2.0, "axe",
                      shape=DOOR, creative=i == _base, drop=_base if not top else None, door=DOORS[i])
    WOODS[_sp]["door"] = _base
WOODS["oak"]["door"] = 510
for _i in range(510, 518):
    DOORS[_i]["base"] = 510
family("doors", [w["door"] for w in WOODS.values()])

# ---------------------------------------------------------------- farming
# hoe a grass / dirt block into farmland, plant seeds or a carrot on it, and it grows in 4 stages
SEEDS, WHEAT_ITEM, BREAD, CARROT = 120, 121, 122, 123
FARMLAND = block(970, "farmland", ("farmland_top", "dirt", "dirt"), NATURAL, 0.5, "shovel", drop=2, creative=False)
CROPS = {}           # crop name -> [stage ids]
for _crop, _base, _seed, _ripe, _bonus in (("wheat", 971, SEEDS, WHEAT_ITEM, [SEEDS, 1, 2]),
                                          ("carrots", 975, CARROT, CARROT, [CARROT, 1, 2])):
    CROPS[_crop] = []
    for _stage in range(4):
        ripe = _stage == 3
        CROPS[_crop].append(block(_base + _stage, f"{_crop}", f"{_crop}_{_stage}", PLANTS, 0.0, shape=CROSS,
                                  solid=False, creative=False, drop=_ripe if ripe else _seed,
                                  crop=dict(stage=_stage, next=_base + _stage + 1 if not ripe else 0),
                                  **({"bonus": _bonus} if ripe else {})))
PLANT_ON_FARMLAND = {SEEDS: CROPS["wheat"][0], CARROT: CROPS["carrots"][0]}   # item -> crop stage 0


# ---------------------------------------------------------------- neon letters
# glowing letter blocks A-Z in two colours, for signs and names
NEON_COLORS = [("pink", (255, 70, 190)), ("blue", (60, 210, 255))]
NEON = {}            # (colour, letter) -> id
for _c, (_cname, _rgb) in enumerate(NEON_COLORS):
    for _i, _letter in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
        NEON[(_cname, _letter)] = block(1600 + _c * 32 + _i, f"{_cname} neon {_letter}", f"neon_{_cname}_{_letter}",
                                        COLORED, 0.4, emit=11, neon=_rgb, letter=_letter,
                                        family=f"neon_{_cname}")


# ---------------------------------------------------------------- machines and logic (power)
# Power runs through copper wire (0-15, fading by 1 per wire). Sources: switch, push button,
# power cell, pressure plate, light sensor. Logic gates take inputs from their sides / back and
# power the block in front. Users: powered lamp, doors, pusher, breaker. Plus conveyor belts,
# collectors (pull items from above / items lying on top, push into the container below) and
# the auto-smelter. The "logic" entry says what each block is; `facing` 0-3 = +z, +x, -z, -x,
# 4 = up, 5 = down.
MACHINES = "machines"
LOGIC = {}           # kind -> base id (variants follow)


def _logic(id_, name, tiles, kind, shape=CUBE, creative=True, drop="self", **extra):
    logic = dict(kind=kind, **{k: extra.pop(k) for k in ("facing", "on") if k in extra})
    block(id_, name, tiles, MACHINES, extra.pop("hardness", 1.0), extra.pop("tool", "pickaxe"), 0, drop=drop,
          shape=shape, creative=creative, logic=logic, **extra)
    LOGIC.setdefault(kind, id_)
    return id_


_logic(1700, "copper wire", "wire_off", "wire", shape=CARPET, solid=False, hardness=0.0, tool=None, on=False)
_logic(1701, "copper wire", "wire_on", "wire", shape=CARPET, solid=False, hardness=0.0, tool=None, on=True,
       creative=False, drop=1700, emit=3)
_logic(1702, "switch", ("switch_off", "switch_side", "switch_side"), "switch", on=False, hardness=0.6)
_logic(1703, "switch", ("switch_on", "switch_side", "switch_side"), "switch", on=True, creative=False, drop=1702,
       hardness=0.6)
_logic(1704, "push button", ("button_top", "button_side", "button_side"), "button", hardness=0.6)
_logic(1705, "power cell", ("power_cell_top", "power_cell", "power_cell_top"), "cell", hardness=1.5, emit=6)
_logic(1706, "pressure plate", "pressure_plate", "plate", shape=CARPET, solid=False, hardness=0.5)
_logic(1707, "light sensor", ("light_sensor", "machine_side", "machine_side"), "sensor", hardness=0.8)
_logic(1708, "powered lamp", "powered_lamp_off", "lamp", on=False, hardness=0.4)
_logic(1709, "powered lamp", "powered_lamp_on", "lamp", on=True, creative=False, drop=1708, emit=15, hardness=0.4)
GATES = ["not", "and", "or", "xor", "delay"]
for _g, _gate in enumerate(GATES):
    for _f in range(4):
        _logic(1710 + _g * 4 + _f, f"{_gate} gate", (f"gate_{_gate}_{_f}", "gate_side", "gate_side"), _gate,
               facing=_f, creative=_f == 0, drop=1710 + _g * 4, hardness=0.6)
for _f in range(6):
    for _base, _m in ((1730, "pusher"), (1736, "breaker")):
        _logic(_base + _f, _m, (f"{_m}_top_{_f}", f"{_m}_side_{_f}", f"{_m}_bottom_{_f}"), _m, facing=_f,
               creative=_f == 0, drop=_base, hardness=1.5)
for _f in range(4):
    _logic(1742 + _f, "conveyor belt", (f"conveyor_{_f}", "machine_side", "machine_bottom"), "conveyor", shape=SLAB,
           facing=_f, creative=_f == 0, drop=1742, hardness=0.8)
_logic(1746, "collector", ("collector_top", "collector_side", "machine_bottom"), "collector", container=True,
       hardness=1.5)
_logic(1747, "auto-smelter", ("smelter_top", "smelter_front", "machine_bottom"), "smelter", container=True,
       hardness=2.0)
for _kind, _ids in (("gates", [1710 + g * 4 for g in range(len(GATES))]), ("power_sources", [1702, 1704, 1705, 1706, 1707])):
    family(_kind, _ids)


# ---------------------------------------------------------------- the sky realm (second world)
# Floating islands reached through a portal: a frame of amethyst blocks opened with a sky key.
SKY_STONE, SKY_GRASS, CLOUD, STAR_ORE, STAR_BLOCK, PORTAL = 1800, 1801, 1802, 1803, 1804, 1805
STORM_CRYSTAL, PILLAR_STONE, STORM_HEART, SKY_DIRT = 1806, 1807, 1808, 1809
STAR_SHARD, SKY_KEY, STORM_CORE = 130, 131, 132              # items (registered in inventory.py)
PORTAL_FRAME = 906                                            # amethyst block
block(SKY_STONE, "sky stone", "sky_stone", NATURAL, 1.5, "pickaxe", 1)
block(SKY_DIRT, "sky soil", "sky_soil", NATURAL, 0.5, "shovel")
block(SKY_GRASS, "sky grass", ("sky_grass_top", "sky_grass_side", "sky_soil"), NATURAL, 0.6, "shovel", drop=SKY_DIRT)
block(CLOUD, "cloud", "cloud", NATURAL, 0.3)
block(STAR_ORE, "star ore", "star_ore", NATURAL, 4.0, "pickaxe", 3, drop=STAR_SHARD)
block(STAR_BLOCK, "star block", "star_block", BUILDING, 5.0, "pickaxe", 3, emit=10)
block(PORTAL, "portal", "portal", FUNCTIONAL, -1, translucent=True, solid=False, emit=11, creative=False, drop=None)
block(STORM_CRYSTAL, "storm crystal", "storm_crystal", FUNCTIONAL, 1.0, "pickaxe", emit=15, drop=None)
block(PILLAR_STONE, "pillar stone", "pillar_stone", BUILDING, 12.0, "pickaxe", 3)
block(STORM_HEART, "storm heart", "storm_heart", FUNCTIONAL, 3.0, "pickaxe", emit=13)


# ---------------------------------------------------------------- derived lookups
BLOCKS = {i: d["name"] for i, d in BLOCK_DEFS.items()}
BLOCK_TILES = {i: d["tiles"] for i, d in BLOCK_DEFS.items()}
TRANSPARENT = {i for i, d in BLOCK_DEFS.items() if d["transparent"]}
TRANSLUCENT = {i for i, d in BLOCK_DEFS.items() if d["translucent"]}
NON_SOLID = {0} | {i for i, d in BLOCK_DEFS.items() if not d["solid"]}
LIGHT_EMIT = {i: d["emit"] for i, d in BLOCK_DEFS.items() if d["emit"]}
UNBREAKABLE = {i for i, d in BLOCK_DEFS.items() if d["hardness"] < 0}
LEAVES = {i for i, d in BLOCK_DEFS.items() if d.get("leaves")}
PLANTS_NEED_SOIL = {i for i, d in BLOCK_DEFS.items() if d["shape"] in (CROSS, CARPET)}   # fall without ground
SHAPED = {i for i, d in BLOCK_DEFS.items() if d["shape"] != CUBE}


def facing_from_yaw(yaw):
    """Player yaw in degrees (0 = +z, 90 = +x) -> facing index 0..3 (0 = +z, 1 = +x, 2 = -z, 3 = -x)."""
    return int(((yaw % 360) + 45) // 90) % 4


FACING_VECTORS = [(0, 1), (1, 0), (0, -1), (-1, 0)]   # (dx, dz) for facing 0..3


def toggled_door(block_id):
    """The same door half, opened if it was closed and closed if it was open."""
    return block_id - 2 if DOORS[block_id]["open"] else block_id + 2
