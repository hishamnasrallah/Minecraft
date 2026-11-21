"""Ready-made factories for the buildings library, built from our own machines.

Each design is a function returning a clipboard {(x, y, z): block id}; y = 0 is the floor.
tools/export_godot.py writes them as schematics plus an index (name, Arabic name, size,
category) so the library opens without reading the files.

Machines used (see blocks.py): copper wire, switch, button, power cell, pressure plate,
light sensor, powered lamp, NOT / AND / OR / XOR / delay gates (output in front, facing
0=+z 1=+x 2=-z 3=-x), pusher / breaker (also 4=up 5=down), conveyor belt (facing = the way it
carries), collector (takes items lying on it or from the container above, puts them into
the container below) and the auto-smelter (input slots, then output slots).
"""
from blocks import CONCRETE, NEON

AIR, STONE_BRICKS, GLASS, LAMP, PLANKS, IRON, FENCE, CHEST, BRICK = 0, 41, 12, 11, 7, 30, 61, 48, 8
TORCH, COBBLE, POLISHED = 50, 22, 803
FARMLAND, WHEAT, CARROTS = 970, 971, 975
WIRE, SWITCH, BUTTON, CELL, PLATE, SENSOR, PLAMP = 1700, 1702, 1704, 1705, 1706, 1707, 1708
NOT, AND, OR, XOR, DELAY = 1710, 1714, 1718, 1722, 1726
PUSHER, BREAKER, CONVEYOR, COLLECTOR, SMELTER = 1730, 1736, 1742, 1746, 1747
STICKY, OBSERVER, THROWER, COMPARATOR = 1792, 1820, 1832, 1838     # + facing
CRAFTER, WATER, LAVA, OBSIDIAN = 1868, 10, 1880, 1890
# items for filled chests
COAL, RAW_MEAT, WHEAT_ITEM, BREAD, EGG, RAW_FISH, LAVA_BUCKET = 102, 103, 121, 122, 124, 126, 118
IRON_ORE, COPPER_ORE, TIN_ORE, GOLD_ORE = 25, 26, 27, 28
IRON_BLOCK, COPPER_BLOCK, GOLD_BLOCK, TIN_BLOCK = 30, 31, 32, 908
DOOR_BOTTOM, DOOR_TOP = 510, 511
WHITE, LIGHT_GRAY, GRAY, BLACK, YELLOW, ORANGE, RED, BLUE = (CONCRETE[i] for i in (0, 1, 2, 3, 7, 6, 5, 12))


class Clip(dict):
    """A clipboard with drawing helpers. `extras` holds what comes with a cell besides its
    block: things already in a chest ({"items": [[id, n], ...]}), animals that live there
    ({"animals": ["hen", ...]}) and what a crafter makes ({"craft": id})."""

    def __init__(self, *a):
        super().__init__(*a)
        self.extras = {}

    def fill(self, x, y, z, items):
        self.extras.setdefault((x, y, z), {})["items"] = [list(st) for st in items]

    def animals(self, x, y, z, kind, n=1):
        self.extras.setdefault((x, y, z), {}).setdefault("animals", []).extend([kind] * n)

    def craft(self, x, y, z, item):
        self.extras.setdefault((x, y, z), {})["craft"] = item

    def put(self, x, y, z, block):
        self[(x, y, z)] = block

    def box(self, x0, y0, z0, x1, y1, z1, block):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self[(x, y, z)] = block

    def walls(self, x0, y0, z0, x1, y1, z1, block):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    if x in (x0, x1) or z in (z0, z1):
                        self[(x, y, z)] = block

    def text(self, x, y, z, word, colour="pink", step=(1, 0, 0)):
        for i, letter in enumerate(word):
            if letter != " ":
                self[(x + step[0] * i, y + step[1] * i, z + step[2] * i)] = NEON[(colour, letter)]


# ---------------------------------------------------------------- building blocks of factories
def smelter_tower(c, x, y, z):
    """chest (input) -> collector -> auto-smelter -> collector -> chest (output), top to bottom."""
    c.put(x, y, z, CHEST)
    c.put(x, y + 1, z, COLLECTOR)
    c.put(x, y + 2, z, SMELTER)
    c.put(x, y + 3, z, COLLECTOR)
    c.put(x, y + 4, z, CHEST)


def maker_line(c, x, y, z, machines, inputs=(), crafts=()):
    """A column that works things top to bottom: an input chest, then for every machine a
    collector over it, then a collector and the output chest. `machines`: SMELTER / CRAFTER
    from the top; `crafts`: what each crafter makes; `inputs`: what is in the top chest."""
    top = y + 2 * len(machines) + 2
    c.put(x, top, z, CHEST)
    if inputs:
        c.fill(x, top, z, inputs)
    yy = top - 1
    crafts = list(crafts)
    for m in machines:
        c.put(x, yy, z, COLLECTOR)
        c.put(x, yy - 1, z, m)
        if m == CRAFTER and crafts:
            c.craft(x, yy - 1, z, crafts.pop(0))
        yy -= 2
    c.put(x, yy, z, COLLECTOR)
    c.put(x, yy - 1, z, CHEST)
    return top


def street_lamp(c, x, y, z, height=4):
    """A lamp post that switches on at night: light sensor -> NOT gate -> wire -> lamp."""
    for dy in range(height):
        c.put(x, y + dy, z, FENCE)
    c.put(x, y + height, z, PLAMP)
    c.put(x, y + height + 1, z, WIRE)          # wire on the lamp's roof...
    c.put(x + 1, y + height + 1, z, NOT + 3)    # ...fed by a NOT gate facing -x
    c.put(x + 2, y + height + 1, z, SENSOR)     # behind it: daylight turns the gate (and lamp) off
    c.put(x + 1, y + height, z, FENCE)
    c.put(x + 2, y + height, z, FENCE)


def blinker(c, x, y, z, lamps=4):
    """A clock: a NOT gate whose output comes back to its input through a delay gate.
    Lamps sit on the wire loop and blink."""
    c.put(x, y, z, NOT)                         # facing +z: input behind (z-1), output in front (z+1)
    c.put(x, y, z + 1, WIRE)
    for i in range(1, lamps + 1):
        c.put(x + i, y, z + 1, WIRE)
        c.put(x + i, y + 1, z + 1, PLAMP)
    c.put(x + lamps + 1, y, z + 1, WIRE)
    c.put(x + lamps + 1, y, z, DELAY + 2)       # facing -z: in from z+1, out to z-1
    for i in range(lamps + 1, -1, -1):
        c.put(x + i, y, z - 1, WIRE)


# ---------------------------------------------------------------- small factories
def auto_smelter():
    c = Clip()
    c.box(0, 0, 0, 8, 0, 4, STONE_BRICKS)
    for x in (2, 4, 6):
        smelter_tower(c, x, 1, 2)
    for x in (0, 8):
        c.box(x, 1, 0, x, 5, 0, POLISHED)
        c.put(x, 6, 0, LAMP)
    c.text(2, 7, 2, "SMELT", "blue")
    return c


def lamp_clock():
    c = Clip()
    c.box(0, 0, 0, 8, 0, 4, POLISHED)
    blinker(c, 1, 1, 2, lamps=5)
    c.text(1, 3, 3, "CLOCK", "pink")
    return c


def auto_door():
    c = Clip()
    c.box(0, 0, 0, 6, 0, 4, STONE_BRICKS)
    c.box(0, 1, 2, 6, 4, 2, STONE_BRICKS)       # the wall
    c.put(3, 1, 2, DOOR_BOTTOM)
    c.put(3, 2, 2, DOOR_TOP)
    c.put(3, 1, 1, PLATE)                       # step on either plate: the door opens
    c.put(3, 1, 3, PLATE)
    c.put(1, 3, 1, LAMP)
    c.put(5, 3, 1, LAMP)
    return c


def logic_board():
    """Switches -> gate -> lamp, for AND, OR, XOR, NOT and delay, with neon labels."""
    c = Clip()
    c.box(0, 0, 0, 22, 0, 4, BLACK)
    c.box(0, 1, 0, 22, 5, 0, GRAY)              # back wall
    for i, (gate, word) in enumerate(((AND, "AND"), (OR, "OR"), (XOR, "XOR"), (NOT, "NOT"), (DELAY, "WAIT"))):
        x = 2 + i * 4
        c.put(x, 1, 2, gate)                    # facing +z, lamp in front
        c.put(x, 1, 3, PLAMP)
        if gate in (NOT, DELAY):
            c.put(x, 1, 1, SWITCH)              # input from behind
        else:
            c.put(x + 1, 1, 2, SWITCH)          # left and right inputs
            c.put(x - 1, 1, 2, SWITCH)
        c.text(x - 1, 3, 1, word, "blue" if i % 2 else "pink")
    return c


def watched_row(c, x, z, y=0):
    """The start of a self-harvesting row: an observer looks down at the crop at x + 1 and
    fires the row's wire each time it grows; a sideways breaker under a post harvests that
    crop (the observer sits where its breaker would be)."""
    c.put(x, y, z, PLANKS)
    c.put(x, y + 1, z, BREAKER + 1)             # facing +x, into the watched crop
    c.put(x, y + 2, z, PLANKS)                  # the wire on it powers the breaker below
    c.put(x, y + 3, z, WIRE)
    c.put(x + 1, y + 2, z, OBSERVER + 4)        # output up into the wire, watching the crop


def wheat_harvester():
    """Harvests by itself, like the farms in the original: an observer watches one crop and
    every time it grows it fires the breakers over the rows; breakers take only ripe crops and
    plant the seed again. The items roll along the conveyors into collectors and chests. The
    button harvests at once."""
    c = Clip()
    length = 10
    c.box(-1, -3, -1, length + 2, -1, 4, STONE_BRICKS)
    for x in range(length):
        c.put(x, 0, 0, CONVEYOR + 1)            # carries +x
        c.put(x, 0, 3, CONVEYOR + 1)
        for z in (1, 2):
            c.put(x, 0, z, FARMLAND)
            c.put(x, 1, z, WHEAT if z == 1 else CARROTS)
            c.put(x, 2, z, BREAKER + 5)         # facing down, right above the crop
            c.put(x, 3, z, WIRE)
    for z in (1, 2):
        watched_row(c, 0, z)
    # a path along the far side, where the farmer lives
    for x in range(-1, length + 1):
        c.put(x, 0, 4, PLANKS)
    c.animals(4, 1, 4, "worker:0")
    for z in (0, 3):                            # the end of each conveyor: collector -> chest
        c.put(length, -1, z, COLLECTOR)
        c.put(length, -2, z, CHEST)
        c.put(length, 0, z, AIR)
    for x in (-1, length):                      # posts holding the breaker bridge
        for z in (1, 2):
            c.box(x, 1, z, x, 2, z, PLANKS)
    c.put(-1, 3, 1, WIRE)
    c.put(-1, 3, 2, BUTTON)
    c.text(0, 6, 1, "AUTO FARM", "pink")
    return c


def storage_tower():
    """Drop items on the top collector: they fill the chests from the bottom up."""
    c = Clip()
    c.box(0, 0, 0, 4, 0, 4, POLISHED)
    for y in range(1, 13, 2):
        c.put(2, y, 2, CHEST)
        c.put(2, y + 1, 2, COLLECTOR)
    for x in range(-5, 2):
        c.put(x, 13, 2, CONVEYOR + 1)           # a belt that feeds the top collector
    c.box(-5, 12, 2, 1, 12, 2, IRON)
    for corner in ((0, 0), (4, 0), (0, 4), (4, 4)):
        c.box(corner[0], 1, corner[1], corner[0], 13, corner[1], GLASS)
    c.text(0, 15, 2, "STORE", "blue")
    return c


def night_street():
    c = Clip()
    c.box(0, 0, 0, 23, 0, 4, GRAY)
    for x in range(24):
        c.put(x, 0, 2, YELLOW if x % 3 else GRAY)
    for x in (1, 9, 17):
        street_lamp(c, x, 1, 0)
        street_lamp(c, x + 3, 1, 4)
    return c


def hidden_door():
    """A stone doorway that slides open: stand on a plate on either side and two sticky pushers
    pull the two stone blocks into the wall; step off and they push them back. The pushers are
    held out by NOT gates, which the plates switch off."""
    c = Clip()
    c.box(0, 0, 0, 9, 0, 6, STONE_BRICKS)
    c.box(0, 1, 3, 9, 3, 3, STONE_BRICKS)       # the wall
    for y in (1, 2):
        c.put(4, y, 3, STONE_BRICKS)            # the door: two stone blocks in the doorway
        c.put(5, y, 3, AIR)                     # the pocket they slide into
        c.put(6, y, 3, STICKY + 3)              # sticky pushers facing -x
        c.put(7, y, 3, NOT + 3)                 # NOT gates facing -x: on unless a plate is pressed
        c.put(8, y, 3, WIRE)
    c.put(4, 1, 2, PLATE)
    c.put(4, 1, 4, PLATE)
    for x in range(4, 9):                       # wires from both plates round to the gates
        c.put(x, 1, 1, WIRE)
        c.put(x, 1, 5, WIRE)
    c.put(8, 1, 2, WIRE)
    c.put(8, 1, 4, WIRE)
    c.text(2, 5, 3, "DOOR", "blue")
    return c


def fill_meter():
    """How full is the chest? A comparator measures it and sends that strength down a wire:
    one lamp lights for every step of signal, so the row of lamps is a gauge."""
    c = Clip()
    c.box(0, 0, 0, 17, 0, 2, POLISHED)
    c.put(0, 1, 0, CHEST)
    c.put(0, 2, 0, COLLECTOR)                   # drop things on top: they go into the chest
    c.put(1, 1, 0, COMPARATOR + 1)              # facing +x: the chest is behind it
    for x in range(2, 17):
        c.put(x, 1, 0, WIRE)
        c.put(x, 1, 1, PLAMP)
    c.text(2, 3, 1, "METER", "pink")
    return c


def snack_machine():
    """Fill the thrower with apples (tap it), then press the button: one apple flies out."""
    c = Clip()
    c.box(0, 0, 0, 4, 0, 3, POLISHED)
    c.box(1, 1, 0, 3, 4, 1, RED)                # the machine's body
    c.put(2, 2, 1, THROWER + 0)                 # facing +z, towards you: the apple comes out here
    c.put(3, 2, 1, WIRE)                        # inside the body, from the button to the thrower
    c.put(3, 1, 2, STONE_BRICKS)                # a ledge beside the mouth...
    c.put(3, 2, 2, BUTTON)                      # ...with the button on it
    c.put(2, 3, 1, LAMP)
    c.text(0, 5, 1, "SNACK", "pink")
    return c


def door_alarm():
    """An observer watches the door: whenever it opens or closes, the lamp flashes."""
    c = Clip()
    c.box(0, 0, 0, 6, 0, 4, STONE_BRICKS)
    c.box(0, 1, 2, 6, 3, 2, STONE_BRICKS)
    c.put(2, 1, 2, DOOR_BOTTOM)
    c.put(2, 2, 2, DOOR_TOP)
    c.put(3, 1, 2, OBSERVER + 1)                # its eye looks at the door (-x), the pulse goes +x
    c.put(4, 1, 2, PLAMP)
    c.text(1, 5, 2, "ALARM", "blue")
    return c


def cobble_unit(c, ox, oz):
    """Lava and water make cobblestone by themselves, like in the original: lava runs into a gap
    with water under it and hardens. An observer over the gap sees it form and fires the
    breaker beside it; the stone drops on the conveyor and the lava runs in again.
    The conveyor at (ox + 2, 0, oz + 2) carries +x."""
    c.put(ox + 1, 1, oz + 1, LAVA)                        # the lava source, behind glass
    for x, y, z in ((ox, 1, oz + 1), (ox + 1, 1, oz), (ox + 1, 1, oz + 2), (ox + 1, 2, oz + 1)):
        c.put(x, y, z, GLASS)
    c.put(ox + 2, 0, oz + 1, WATER)                       # water under the gap
    c.put(ox + 2, 1, oz + 1, AIR)                         # the gap: cobblestone forms here
    c.put(ox + 2, 1, oz, GLASS)
    c.put(ox + 2, 2, oz + 1, OBSERVER + 4)                # watches the gap, pulses up
    c.put(ox + 2, 3, oz + 1, WIRE)
    c.put(ox + 3, 3, oz + 1, WIRE)
    c.put(ox + 3, 2, oz + 1, STONE_BRICKS)                # the wire on it runs the breaker below
    c.put(ox + 3, 1, oz + 1, BREAKER + 3)                 # facing -x, into the gap


def cobble_generator():
    """Cobblestone forever: lava + water, an observer, a breaker and a conveyor to a chest."""
    c = Clip()
    c.box(-1, -3, -1, 8, 0, 4, STONE_BRICKS)
    cobble_unit(c, 0, 0)
    for x in range(2, 6):
        c.put(x, 0, 2, CONVEYOR + 1)
        c.put(x, 1, 2, AIR)
    c.put(6, 0, 2, AIR)
    c.put(6, -1, 2, COLLECTOR)
    c.put(6, -2, 2, CHEST)
    c.text(0, 5, 1, "COBBLE", "blue")
    return c


def stone_factory():
    """Two cobblestone generators feed one conveyor into an auto-smelter (filled with coal) that
    bakes the cobblestone into smooth stone, down into a chest."""
    c = Clip()
    c.box(-1, -6, -1, 14, 0, 7, STONE_BRICKS)
    cobble_unit(c, 0, 0)
    cobble_unit(c, 0, 4)                                  # its conveyor is at z = 6
    for x in range(2, 10):
        c.put(x, 0, 2, CONVEYOR + 1)
        c.put(x, 1, 2, AIR)
    for x in range(2, 5):                                 # the second line turns into the first
        c.put(x, 0, 6, CONVEYOR + 1)
        c.put(x, 1, 6, AIR)
    for z in range(6, 2, -1):
        c.put(5, 0, z, CONVEYOR + 2)                      # carries -z
        c.put(5, 1, z, AIR)
    c.put(10, 0, 2, AIR)
    c.put(10, -1, 2, COLLECTOR)                           # into the smelter's top
    c.put(10, -2, 2, SMELTER)
    c.fill(10, -2, 2, [[COAL, 64], [COAL, 64]])
    c.put(10, -3, 2, COLLECTOR)
    c.put(10, -4, 2, CHEST)
    c.text(0, 5, 1, "STONE", "blue")
    return c


def obsidian_factory():
    """Hard lava stone: a clock fires a thrower full of lava buckets, and a breaker on the
    other half of the beat. The thrower pours lava next to a water source, it turns into
    obsidian, the breaker mines it and it falls into a collector over a chest. Empty buckets
    stay in the thrower."""
    c = Clip()
    c.box(-1, -3, -5, 5, -1, 4, STONE_BRICKS)
    c.box(-1, 0, -5, 5, 0, 4, STONE_BRICKS)
    c.put(1, 1, 1, THROWER + 1)                           # facing +x, into the cell
    c.fill(1, 1, 1, [[LAVA_BUCKET, 1]] * 20)
    c.put(3, 1, 1, BREAKER + 3)                           # facing -x, into the cell
    c.put(2, 1, 1, AIR)                                   # the cell
    c.put(2, 1, 2, WATER)                                 # a water source beside it
    for x, y, z in ((1, 1, 2), (3, 1, 2), (2, 1, 3), (2, 2, 2), (2, 1, 0), (2, 2, 1)):
        c.put(x, y, z, GLASS)
    c.put(2, 0, 1, COLLECTOR)
    c.put(2, -1, 1, CHEST)
    # the clock in the floor: its wire runs under the thrower; the breaker gets it through a
    # NOT gate, so it mines on the other half of the beat (the stone falls into the collector
    # before the next lava comes)
    blinker(c, 0, 0, -3, lamps=2)
    for x, z in ((1, -1), (1, 0), (1, 1), (3, -1), (3, 1)):
        c.put(x, 0, z, WIRE)
    c.put(3, 0, 0, NOT)                                   # facing +z: in from z - 1, out to z + 1
    c.text(0, 4, 1, "OBSIDIAN", "pink")
    return c


def bakery():
    """Auto-crafters turn wheat into bread and eggs with wheat into egg bread, by themselves."""
    c = Clip()
    c.box(0, 0, 0, 8, 0, 4, POLISHED)
    for x, inputs, make in ((2, [[WHEAT_ITEM, 64]] * 3, BREAD), (4, [[WHEAT_ITEM, 64]] * 2, BREAD),
                            (6, [[EGG, 16], [WHEAT_ITEM, 64]], BREAD)):
        maker_line(c, x, 1, 2, [CRAFTER], inputs, [make])
    for x in (0, 8):
        c.box(x, 1, 0, x, 5, 0, PLANKS)
        c.put(x, 6, 0, LAMP)
    c.animals(3, 1, 3, "worker:2")
    c.text(1, 8, 2, "BAKERY", "pink")
    return c


def grill_house():
    """A cooking line: auto-smelters with coal cook raw meat and fish into food."""
    c = Clip()
    c.box(0, 0, 0, 8, 0, 4, BRICK)
    for x, raw in ((2, RAW_MEAT), (4, RAW_FISH), (6, RAW_MEAT)):
        maker_line(c, x, 1, 2, [SMELTER], [[raw, 64], [COAL, 64]])
    for x in (0, 8):
        c.box(x, 1, 0, x, 5, 0, BRICK)
        c.put(x, 6, 0, LAMP)
    c.animals(5, 1, 3, "worker:1")
    c.text(1, 8, 2, "GRILL", "pink")
    return c


def metal_works():
    """Ore in at the top, ingots out of the smelter, and an auto-crafter under it presses
    every 9 ingots into a block: iron, gold, copper and tin lines."""
    c = Clip()
    c.box(0, 0, 0, 10, 0, 4, POLISHED)
    for x, ore, block in ((2, IRON_ORE, IRON_BLOCK), (4, GOLD_ORE, GOLD_BLOCK), (6, COPPER_ORE, COPPER_BLOCK),
                          (8, TIN_ORE, TIN_BLOCK)):
        maker_line(c, x, 1, 2, [SMELTER, CRAFTER], [[ore, 64], [ore, 26], [COAL, 64], [COAL, 26]], [block])
    for x in (0, 10):
        c.box(x, 1, 0, x, 7, 0, IRON)
        c.put(x, 8, 0, LAMP)
    c.animals(3, 1, 3, "worker:1")
    c.animals(7, 1, 3, "worker:1")
    c.text(1, 10, 2, "METALS", "blue")
    return c


def animal_farm():
    """Two pens. Hens lay eggs on a floor of conveyors that carries them into a collector over
    a chest. In the sheep pen a thrower full of wheat on a slow clock feeds the sheep: fed
    sheep pair up and have lambs."""
    c = Clip()
    c.box(-1, -3, -2, 15, -1, 6, STONE_BRICKS)
    c.box(7, 0, -1, 15, 0, 5, STONE_BRICKS)
    # hen pen: conveyors carry +x, then -z along x = 5 into a collector in the corner
    for x in range(0, 5):
        for z in range(0, 5):
            c.put(x, 0, z, CONVEYOR + 1)
    for z in range(1, 5):
        c.put(5, 0, z, CONVEYOR + 2)
    c.put(5, 0, 0, COLLECTOR)
    c.put(5, -1, 0, CHEST)
    for x in range(-1, 7):
        c.put(x, 1, -1, FENCE)
        c.put(x, 1, 5, FENCE)
    for z in range(-1, 6):
        c.put(-1, 1, z, FENCE)
        c.put(6, 1, z, FENCE)
    c.animals(1, 1, 1, "hen", 2)
    c.animals(3, 1, 3, "hen", 2)
    # sheep pen: small, so the sheep often step on the plate in front of the thrower
    c.box(11, 0, 1, 13, 0, 3, PLANKS)
    for x in range(10, 15):
        c.put(x, 1, 0, FENCE)
        c.put(x, 1, 4, FENCE)
    for z in range(0, 5):
        c.put(10, 1, z, FENCE)
        c.put(14, 1, z, FENCE)
    c.put(14, 1, 2, THROWER + 3)                          # facing -x, into the pen
    c.fill(14, 1, 2, [[WHEAT_ITEM, 64]])
    # a slow clock behind it: each beat the thrower feeds a sheep that can eat (wheat is
    # only used when one can); fed sheep pair up and have lambs
    c.box(15, 0, -1, 19, 0, 2, STONE_BRICKS)
    c.put(15, 1, 2, WIRE)
    c.put(15, 1, 1, WIRE)
    blinker(c, 16, 1, 0, lamps=1)
    c.animals(11, 1, 1, "woolly", 1)
    c.animals(11, 1, 3, "woolly", 1)
    c.animals(12, 1, 2, "woolly", 1)
    c.text(0, 4, -2, "FARM", "pink")
    return c


SMALL = [
    ("auto_smelter", "Auto smelting line", "خط صهر أوتوماتيكي", auto_smelter),
    ("lamp_clock", "Blinking lamp clock", "ساعة ضو بتغمّز", lamp_clock),
    ("auto_door", "Automatic door", "باب أوتوماتيكي", auto_door),
    ("logic_board", "Logic gates board", "لوح البوابات المنطقية", logic_board),
    ("wheat_harvester", "Automatic farm", "مزرعة بتحصد لحالها", wheat_harvester),
    ("storage_tower", "Storage tower", "برج تخزين", storage_tower),
    ("night_street", "Street with night lights", "شارع بإنارة ليلية", night_street),
    ("hidden_door", "Sliding stone door", "باب حجر بينزلق", hidden_door),
    ("fill_meter", "Chest fill meter", "عدّاد امتلاء الصندوق", fill_meter),
    ("snack_machine", "Snack machine", "ماكينة سناك", snack_machine),
    ("door_alarm", "Door alarm", "إنذار الباب", door_alarm),
    ("cobble_generator", "Cobblestone generator", "مولّد حجر من الحمم والماء", cobble_generator),
    ("stone_factory", "Stone factory", "مصنع حجر", stone_factory),
    ("obsidian_factory", "Obsidian factory", "مصنع الحجر البركاني", obsidian_factory),
    ("bakery", "Bakery", "مخبز أوتوماتيكي", bakery),
    ("grill_house", "Grill house", "معمل شوي", grill_house),
    ("metal_works", "Metal works (iron, gold, copper, tin)", "مصنع المعادن (حديد، ذهب، نحاس، قصدير)", metal_works),
    ("animal_farm", "Animal farm (eggs and lambs)", "مزرعة حيوانات (بيض وخرفان)", animal_farm),
]


# ---------------------------------------------------------------- large and giant
def smelter_hall(c=None, ox=0, oz=0):
    """A hall with eight smelting lines, catwalk, glass roof and a neon sign."""
    c = c if c is not None else Clip()
    w, d, h = 25, 11, 9
    c.box(ox, 0, oz, ox + w, 0, oz + d, POLISHED)
    c.walls(ox, 1, oz, ox + w, h, oz + d, STONE_BRICKS)
    c.box(ox + 1, h, oz + 1, ox + w - 1, h, oz + d - 1, GLASS)
    for i in range(8):
        smelter_tower(c, ox + 3 + i * 3, 1, oz + 5)
        for dx in range(3):                          # catwalk in front of the input chests
            c.put(ox + 3 + i * 3 + dx, 4, oz + 4, IRON)
    for x in range(ox + 2, ox + w - 1, 4):
        c.put(x, h - 1, oz + 2, LAMP)
        c.put(x, h - 1, oz + d - 2, LAMP)
    c.put(ox + w // 2, 1, oz, DOOR_BOTTOM)
    c.put(ox + w // 2, 2, oz, DOOR_TOP)
    c.text(ox + 4, h + 1, oz, "SMELTERY", "blue")
    return c


def giant_farm(c=None, ox=0, oz=0, rows=8, length=36):
    """Rows of wheat and carrots with a breaker bridge over each pair. Every row harvests by
    itself (an observer watches its first crop); one button also harvests them all. Conveyors to
    collectors and chests; night lights and a fence around. Copper wire fades after 15
    blocks, so delay gates on pillars every 12 blocks pass the signal on at full strength."""
    c = c if c is not None else Clip()
    depth = rows * 5
    c.box(ox - 3, -3, oz - 2, ox + length + 3, -1, oz + depth + 1, STONE_BRICKS)
    for r in range(rows):
        z = oz + r * 5
        for x in range(ox, ox + length):
            relay = (x - ox) % 12 == 11
            c.put(x, 0, z, CONVEYOR + 1)
            c.put(x, 0, z + 3, CONVEYOR + 1)
            c.put(x, 0, z + 4, PLANKS)              # a path between the rows
            for zz in (z + 1, z + 2):
                if relay:                           # a pillar under the relay, no crop
                    c.box(x, 0, zz, x, 2, zz, PLANKS)
                    c.put(x, 3, zz, DELAY + 1)      # facing +x
                else:
                    c.put(x, 0, zz, FARMLAND)
                    c.put(x, 1, zz, CARROTS if r % 2 else WHEAT)
                    c.put(x, 2, zz, BREAKER + 5)
                    c.put(x, 3, zz, WIRE)
        for zz in (z + 1, z + 2):
            watched_row(c, ox, zz)                  # each row harvests by itself
        for zz in (z, z + 3):
            c.put(ox + length, -1, zz, COLLECTOR)
            c.put(ox + length, -2, zz, CHEST)
            c.put(ox + length, 0, zz, AIR)
        for x in (ox - 1, ox + length):
            for zz in (z + 1, z + 2):
                c.box(x, 0, zz, x, 2, zz, PLANKS)
    # one wire along the side, with a relay every 10 blocks (on the paths between rows), and a
    # relay into every row so each row starts at full strength
    for z in range(oz, oz + depth):
        c.put(ox - 2, 3, z, DELAY if (z - oz) % 10 == 9 else WIRE)
    for r in range(rows):
        for zz in (oz + r * 5 + 1, oz + r * 5 + 2):
            c.put(ox - 1, 3, zz, DELAY + 1)          # facing +x, into the row
            c.box(ox - 2, 0, zz, ox - 2, 2, zz, PLANKS)
    c.put(ox - 2, 4, oz, BUTTON)
    for x in range(ox - 3, ox + length + 4):        # fence around
        c.put(x, 0, oz - 2, FENCE)
        c.put(x, 0, oz + depth + 1, FENCE)
    for z in range(oz - 2, oz + depth + 2):
        c.put(ox - 3, 0, z, FENCE)
        c.put(ox + length + 3, 0, z, FENCE)
    for x in range(ox + 2, ox + length, 10):
        street_lamp(c, x, 1, oz - 3)
    c.text(ox + 2, 7, oz - 1, "FARM", "pink")
    return c


def warehouse(c, ox, oz, cols=8, rows=3):
    """Chest towers under collectors, fed by one long conveyor on the roof line."""
    w, d = cols * 3 + 2, rows * 4 + 2
    c.box(ox, 0, oz, ox + w, 0, oz + d, POLISHED)
    c.walls(ox, 1, oz, ox + w, 10, oz + d, CONCRETE[8])
    c.box(ox + 1, 10, oz + 1, ox + w - 1, 10, oz + d - 1, LIGHT_GRAY)
    for i in range(cols):
        for j in range(rows):
            x, z = ox + 2 + i * 3, oz + 2 + j * 4
            for y in range(1, 9, 2):
                c.put(x, y, z, CHEST)
                c.put(x, y + 1, z, COLLECTOR)
    for x in range(ox + 2, ox + w - 1, 3):
        c.put(x, 9, oz + d // 2, LAMP)
    c.put(ox + w // 2, 1, oz, DOOR_BOTTOM)
    c.put(ox + w // 2, 2, oz, DOOR_TOP)
    c.text(ox + 2, 11, oz, "STORAGE", "pink")


def power_plant(c, ox, oz):
    """Power cells in a glass hall light a grid of lamps through copper wire."""
    c.box(ox, 0, oz, ox + 14, 0, oz + 10, BLACK)
    c.walls(ox, 1, oz, ox + 14, 6, oz + 10, GLASS)
    for x in range(ox + 2, ox + 13, 2):
        c.put(x, 1, oz + 2, CELL)
        for z in range(oz + 3, oz + 9):
            c.put(x, 1, z, WIRE)
            if z % 2:
                c.put(x, 2, z, PLAMP)
    c.text(ox + 2, 7, oz, "POWER", "blue")


def office_tower(c, ox, oz, floors=6):
    h = floors * 4
    c.box(ox, 0, oz, ox + 8, 0, oz + 8, WHITE)
    c.walls(ox, 1, oz, ox + 8, h, oz + 8, GLASS)
    for f in range(floors + 1):
        c.box(ox, f * 4, oz, ox + 8, f * 4, oz + 8, WHITE)
        c.put(ox + 4, f * 4 + 3, oz + 4, LAMP)
    for y in range(1, h + 1):                  # corner columns
        for cx, cz in ((ox, oz), (ox + 8, oz), (ox, oz + 8), (ox + 8, oz + 8)):
            c.put(cx, y, cz, CONCRETE[2])
    c.put(ox + 4, 1, oz, DOOR_BOTTOM)
    c.put(ox + 4, 2, oz, DOOR_TOP)
    c.text(ox + 1, h + 2, oz, "FACTORY", "pink")


def mega_complex():
    """A whole industrial town: smelting hall, warehouse, wheat farm, power plant, office
    tower, roads with night lights and conveyor lines between the halls."""
    c = Clip()
    W, D = 96, 70
    c.box(0, 0, 0, W, 0, D, GRAY)                    # ground
    for x in range(W + 1):                           # main roads
        for z in (30, 31, 32):
            c.put(x, 0, z, BLACK)
        if x % 4 < 2:
            c.put(x, 0, 31, YELLOW)
    for z in range(D + 1):
        for x in (46, 47, 48):
            c.put(x, 0, z, BLACK)
        if z % 4 < 2:
            c.put(47, 0, z, YELLOW)
    smelter_hall(c, 4, 4)
    warehouse(c, 55, 4)
    giant_farm(c, 6, 40, rows=5, length=32)
    power_plant(c, 58, 40)
    office_tower(c, 78, 40)
    for x in range(30, 46):                          # a conveyor line from the hall to the road
        c.put(x, 1, 10, CONVEYOR + 1)
    for x in range(49, 55):
        c.put(x, 1, 10, CONVEYOR + 1)
    for x in range(2, W - 2, 12):                    # street lights along the main road
        street_lamp(c, x, 1, 28)
    c.text(36, 3, 33, "INDUSTRIAL", "blue")
    return c


LARGE = [
    ("smelter_hall", "Smelting hall (8 lines)", "قاعة الصهر الكبرى (8 خطوط)", smelter_hall),
    ("giant_farm", "Giant automatic farm", "المزرعة الأوتوماتيكية العملاقة", giant_farm),
    ("mega_complex", "Industrial complex", "المجمّع الصناعي العملاق", mega_complex),
]


def all_designs():
    """[(file, English name, Arabic name, category, clip)] with the clip moved to start at 0
    (its extras moved with it)."""
    out = []
    for category, designs in (("small_factories", SMALL), ("big_factories", LARGE)):
        for file, en, ar, make in designs:
            clip = make()
            lo = [min(p[a] for p in clip) for a in range(3)]
            moved = Clip({(x - lo[0], y - lo[1], z - lo[2]): b for (x, y, z), b in clip.items()})
            moved.extras = {(x - lo[0], y - lo[1], z - lo[2]): e for (x, y, z), e in clip.extras.items()}
            out.append((file, en, ar, category, moved))
    return out
