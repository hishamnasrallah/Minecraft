"""Procedural pixel-art textures packed into a single atlas image.

Run `python textures.py` to export the atlas to textures/atlas.png. Edit that
file in any image editor (keep the grid layout from world.TILES) and the
game will use your version instead of the generated one.
"""
import math
import random
from pathlib import Path

from PIL import Image

from world import ATLAS_COLS, TILES

TILE = 16
CUSTOM_ATLAS = Path(__file__).with_name("textures") / "atlas.png"


def _clamp(c):
    return tuple(max(0, min(255, int(v))) for v in c)


def _shade(color, factor):
    return _clamp(v * factor for v in color)


def _noise(rng, base, amount):
    img = Image.new("RGB", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            img.putpixel((x, y), _shade(base, 1 + rng.uniform(-amount, amount)))
    return img


def _speckle(img, rng, color, count):
    for _ in range(count):
        img.putpixel((rng.randrange(TILE), rng.randrange(TILE)), color)
    return img


def grass_top(rng):
    img = _noise(rng, (92, 160, 58), 0.14)
    return _speckle(img, rng, (70, 128, 44), 22)


def dirt(rng):
    img = _noise(rng, (134, 96, 62), 0.12)
    _speckle(img, rng, (100, 70, 44), 18)
    return _speckle(img, rng, (160, 120, 82), 8)


def grass_side(rng):
    img = dirt(rng)
    top = grass_top(rng)
    for x in range(TILE):
        depth = 3 + (rng.random() < 0.45) + (rng.random() < 0.2)
        for y in range(depth):
            img.putpixel((x, y), top.getpixel((x, y)))
    return img


def stone(rng):
    img = _noise(rng, (128, 128, 132), 0.08)
    for _ in range(5):
        cx, cy = rng.randrange(TILE), rng.randrange(TILE)
        for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0)):
            img.putpixel(((cx + dx) % TILE, (cy + dy) % TILE), (100, 100, 104))
    return img


def log_side(rng):
    img = Image.new("RGB", (TILE, TILE))
    for x in range(TILE):
        col_shade = 1 + rng.uniform(-0.18, 0.18)
        for y in range(TILE):
            img.putpixel((x, y), _shade((108, 78, 44), col_shade * (1 + rng.uniform(-0.05, 0.05))))
    return img


def log_top(rng):
    img = Image.new("RGB", (TILE, TILE))
    c = (TILE - 1) / 2
    for x in range(TILE):
        for y in range(TILE):
            d = max(abs(x - c), abs(y - c))
            if d > 6.5:
                color = (96, 68, 38)
            else:
                color = (184, 148, 92) if int(d) % 2 == 0 else (160, 124, 74)
            img.putpixel((x, y), _shade(color, 1 + rng.uniform(-0.05, 0.05)))
    return img


def leaves(rng):
    img = _noise(rng, (52, 120, 46), 0.2)
    _speckle(img, rng, (34, 84, 30), 40)
    return _speckle(img, rng, (80, 150, 64), 14)


def sand(rng):
    img = _noise(rng, (222, 208, 150), 0.06)
    return _speckle(img, rng, (196, 180, 124), 14)


def planks(rng):
    img = Image.new("RGB", (TILE, TILE))
    for board in range(4):
        seam = rng.randrange(TILE)
        tone = 1 + rng.uniform(-0.08, 0.08)
        for y in range(board * 4, board * 4 + 4):
            for x in range(TILE):
                color = (184, 140, 84)
                if y % 4 == 3 or x == seam:
                    color = (120, 88, 50)
                img.putpixel((x, y), _shade(color, tone * (1 + rng.uniform(-0.04, 0.04))))
    return img


def brick(rng):
    img = Image.new("RGB", (TILE, TILE))
    for y in range(TILE):
        row = y // 4
        offset = 0 if row % 2 == 0 else 4
        for x in range(TILE):
            mortar = y % 4 == 3 or (x + offset) % 8 == 7
            color = (190, 186, 176) if mortar else (162, 68, 52)
            img.putpixel((x, y), _shade(color, 1 + rng.uniform(-0.08, 0.08)))
    return img


def bedrock(rng):
    img = _noise(rng, (60, 60, 64), 0.5)
    return _speckle(img, rng, (20, 20, 22), 30)


def water(rng):
    img = _noise(rng, (46, 104, 200), 0.08)
    for _ in range(5):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for dx in range(rng.randint(2, 5)):
            img.putpixel(((x + dx) % TILE, y), (110, 160, 230))
    return img


def cake_icon(rng):
    """A round-cornered cake: sponge sides, white icing and red berries on top."""
    img = _blank()
    for x in range(2, 14):
        for y in range(6, 14):
            if y < 9:
                c = (246, 244, 238) if (x + y) % 5 else (232, 228, 220)
            else:
                c = (214, 150, 82) if y != 11 else (238, 236, 228)
            if (x in (2, 13) and y in (6, 13)):
                continue
            _px(img, x, y, c)
    for x, y in ((4, 6), (8, 6), (11, 7), (6, 7)):
        _px(img, x, y, (210, 40, 50))
    for x in range(3, 13, 3):
        _px(img, x, 9, (238, 236, 228))
    return img


def potion(colour):
    def gen(rng):
        img = _blank()
        for y in range(1, 4):
            for x in range(7, 9):
                _px(img, x, y, (150, 110, 70) if y == 1 else (200, 220, 230))
        for y in range(4, 15):
            half = 2 if y < 6 else (5 if 7 <= y <= 13 else 4)
            for x in range(8 - half, 8 + half):
                edge = x in (8 - half, 7 + half) or y in (4, 14)
                inside = colour if y >= 7 else (215, 230, 240)
                _px(img, x, y, (200, 220, 236) if edge else _shade(inside, 1 + rng.uniform(-0.08, 0.08)))
        _px(img, 6, 9, (255, 255, 255))
        return img
    return gen


def brewer_side(rng, lit=False):
    """A stand of dark wood and stone with three bottles; they bubble and glow while it works."""
    img = _dark_stone(rng)
    for i, x in enumerate((3, 7, 11)):
        for y in range(6, 12):
            for dx in range(3):
                c = ((240, 90, 200), (90, 200, 250), (250, 200, 80))[i] if lit and y > 8 else (180, 200, 210)
                img.putpixel((x + dx, y), c + (255,))
    for x in range(2, 14):
        img.putpixel((x, 13), (90, 64, 40, 255))
    return img


def ember_rock(rng):
    img = _noise(rng, (112, 40, 36), 0.14)
    return _speckle(img, rng, (150, 60, 48), 22)


def ember_bricks(rng):
    return bricks((96, 34, 34), (52, 20, 22))(rng)


def ember_ore(rng):
    img = ember_rock(rng)
    for _ in range(6):
        x, y = rng.randrange(1, TILE - 2), rng.randrange(1, TILE - 2)
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            img.putpixel((x + dx, y + dy), (255, 190, 70) if (dx + dy) % 2 else (240, 120, 40))
    return img


def ash_sand(rng):
    img = _noise(rng, (88, 76, 70), 0.12)
    return _speckle(img, rng, (60, 50, 48), 30)


def magma(rng):
    img = _noise(rng, (70, 28, 20), 0.15)
    for _ in range(9):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for dx in range(rng.randint(2, 5)):
            img.putpixel(((x + dx) % TILE, y), (255, 130, 30))
    return img


def fire_portal(rng):
    img = Image.new("RGBA", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            v = 0.5 + 0.5 * math.sin((x - y) * 0.8 + rng.uniform(-0.6, 0.6))
            img.putpixel((x, y), (int(220 + 30 * v), int(80 + 90 * v), int(20 + 30 * v), 180))
    return img


def ember_shard(rng):
    img = _blank()
    for x, y in ((7, 3), (8, 4), (6, 5), (7, 5), (8, 5), (9, 6), (6, 7), (7, 7), (8, 7), (7, 9), (8, 9), (7, 11)):
        _px(img, x, y, (255, 150 + rng.randrange(60), 40))
    return img


def fire_striker(rng):
    img = _blank()
    for i in range(7):
        _px(img, 4 + i, 11 - i, (170, 172, 180))              # the steel
    for x, y in ((10, 4), (11, 3), (12, 4), (11, 5)):
        _px(img, x, y, (255, 180, 50))                        # the spark
    for i in range(4):
        _px(img, 3 + i, 12 + (i % 2), (60, 60, 66))
    return img


def timer_face(rng, lit=False):
    """A round clock face with one hand; the rim glows while it gives its pulse."""
    img = _dark_stone(rng)
    for x in range(TILE):
        for y in range(TILE):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d < 6.0:
                img.putpixel((x, y), (236, 230, 214, 255))
            elif d < 7.0:
                img.putpixel((x, y), (255, 80, 60, 255) if lit else (150, 60, 50, 255))
    for i in range(5):
        img.putpixel((8, 8 - i), (30, 30, 34, 255))
        img.putpixel((8 + i // 2, 8), (30, 30, 34, 255))
    return img


def counter_face(rng, lit=False):
    """Three little digit windows over a tally; the light on top shines on the Nth pulse."""
    img = _dark_stone(rng)
    for k in range(3):
        for x in range(2 + k * 4, 5 + k * 4):
            for y in range(6, 11):
                img.putpixel((x, y), (30, 60, 40, 255))
        for y in (6, 8, 10):
            img.putpixel((3 + k * 4, y), (120, 255, 140, 255))
    for x in range(6, 10):
        img.putpixel((x, 2), (255, 220, 90, 255) if lit else (90, 80, 60, 255))
    return img


def note_block(rng):
    img = boards((150, 104, 64))(rng)
    for x, y in ((9, 3), (9, 4), (9, 5), (9, 6), (9, 7), (9, 8), (10, 3), (11, 4)):
        _px(img, x, y, (30, 24, 20))
    for x in (6, 7, 8):
        for y in (8, 9, 10):
            _px(img, x, y, (30, 24, 20))
    return img


def fan_face(rng, lit=False):
    """A round grille with four blades (blurred into a ring while it spins)."""
    img = _dark_stone(rng)
    for x in range(TILE):
        for y in range(TILE):
            dx, dy = x - 7.5, y - 7.5
            d = (dx * dx + dy * dy) ** 0.5
            if d < 6.5:
                if lit:
                    c = (170, 176, 186) if int(d) % 2 else (120, 126, 136)
                else:
                    blade = abs(dx) < 1.2 or abs(dy) < 1.2
                    c = (190, 194, 204) if blade else (40, 42, 48)
                img.putpixel((x, y), c + (255,))
    img.putpixel((7, 7), (230, 200, 80, 255))
    img.putpixel((8, 8), (230, 200, 80, 255))
    return img


def iron_door(top):
    def gen(rng):
        img = _noise(rng, (196, 198, 204), 0.05).convert("RGBA")
        for i in range(TILE):
            for j in (0, TILE - 1):
                img.putpixel((j, i), (140, 142, 150, 255))
        if top:
            for x in range(3, 13):
                for y in range(3, 9):
                    img.putpixel((x, y), (0, 0, 0, 0) if (x + y) % 5 else (150, 150, 158, 255))
        else:
            for x in range(3, 13):
                img.putpixel((x, 6), (150, 152, 160, 255))
                img.putpixel((x, 11), (150, 152, 160, 255))
        return img
    return gen


def trapdoor(rng):
    img = boards((150, 110, 66))(rng).convert("RGBA")
    for x in range(TILE):
        for y in range(TILE):
            if 3 <= x <= 12 and 3 <= y <= 12 and (x in (3, 12) or y in (3, 12) or x == y or x + y == 15):
                img.putpixel((x, y), (100, 70, 40, 255))
            elif 4 <= x <= 11 and 4 <= y <= 11 and (x + y) % 4 == 0:
                img.putpixel((x, y), (0, 0, 0, 0))
    return img


def lantern(rng):
    img = _blank()
    for x in range(5, 11):
        for y in range(5, 15):
            edge = x in (5, 10) or y in (5, 14)
            _px(img, x, y, (60, 62, 70) if edge else (255, 210, 110))
    for y in range(1, 5):
        _px(img, 7, y, (70, 72, 80))
        _px(img, 8, y, (70, 72, 80))
    return img


def barrel_side(rng):
    img = boards((140, 96, 56))(rng)
    for y in (2, 13):
        for x in range(TILE):
            _px(img, x, y, (80, 80, 86))
    return img


def barrel_top(rng):
    img = rings((170, 124, 74), (120, 84, 48), (90, 64, 40))(rng)
    for x in range(5, 11):
        _px(img, x, 7, (40, 30, 24))
        _px(img, x, 8, (40, 30, 24))
    return img


def tnt_side(rng):
    img = _noise(rng, (200, 50, 40), 0.06)
    for x in range(TILE):
        for y in range(5, 11):
            img.putpixel((x, y), (232, 226, 210))
    # T N T in a 3 x 4 pixel font on the white band
    letters = {"T": ((0, 0), (1, 0), (2, 0), (1, 1), (1, 2), (1, 3)),
               "N": ((0, 0), (0, 1), (0, 2), (0, 3), (1, 1), (2, 2), (3, 0), (3, 1), (3, 2), (3, 3))}
    for x0, ch in ((2, "T"), (6, "N"), (11, "T")):
        for dx, dy in letters[ch]:
            img.putpixel((x0 + dx, 6 + dy), (30, 30, 30))
    return img


def tnt_top(rng):
    img = _noise(rng, (190, 46, 38), 0.06)
    for x, y in ((7, 7), (8, 7), (7, 8), (8, 8)):
        img.putpixel((x, y), (40, 40, 40))
    return img


def shears(rng):
    img = _blank()
    for i in range(7):
        _px(img, 4 + i, 4 + i, (200, 202, 210))
        _px(img, 11 - i, 4 + i, (200, 202, 210))
    for x, y in ((3, 12), (4, 12), (3, 13), (11, 12), (12, 12), (12, 13)):
        _px(img, x, y, (170, 40, 40))
    return img


def bow_icon(rng):
    img = _blank()
    for i in range(12):
        x = 3 + i
        y = 13 - i
        bend = int(2.2 * math.sin(math.pi * i / 11))
        _px(img, x - bend, y - bend, (130, 90, 50))
    for i in range(12):
        _px(img, 3 + i, 13 - i, (230, 230, 230))           # the string
    return img


def arrow_icon(rng):
    img = _blank()
    for i in range(10):
        _px(img, 3 + i, 12 - i, (150, 110, 70))
    for x, y in ((12, 3), (13, 2), (13, 3), (12, 2), (14, 1)):
        _px(img, x, y, (200, 200, 206))
    for x, y in ((2, 13), (3, 14), (2, 12), (4, 14), (1, 13)):
        _px(img, x, y, (240, 240, 240))
    return img


def boat_icon(rng):
    img = _blank()
    for x in range(1, 15):
        for y in range(8, 13):
            if y == 12 and x in (1, 14):
                continue
            edge = y == 8 or x in (1, 14)
            _px(img, x, y, (110, 76, 44) if edge else _shade((160, 116, 70), 1 + rng.uniform(-0.08, 0.08)))
    return img


def rod_icon(rng):
    img = _blank()
    for i in range(12):
        _px(img, 2 + i, 13 - i, (120, 84, 50))
    for y in range(3, 12):
        _px(img, 14, y, (220, 220, 220))
    _px(img, 14, 12, (200, 40, 40))
    return img


def saddle_icon(rng):
    img = _blank()
    for x in range(3, 13):
        for y in range(5, 10):
            _px(img, x, y, (140, 80, 40) if y > 5 else (110, 60, 30))
    for y in range(9, 14):
        _px(img, 4, y, (90, 60, 40))
        _px(img, 11, y, (90, 60, 40))
    return img


def armour_icon(piece, colour):
    shapes = {"helmet": [(x, y) for x in range(3, 13) for y in range(3, 9) if not (5 <= x <= 10 and y >= 6)],
              "chestplate": [(x, y) for x in range(2, 14) for y in range(2, 14) if not (6 <= x <= 9 and y <= 4)
                             and not ((x <= 3 or x >= 12) and y >= 7)],
              "leggings": [(x, y) for x in range(3, 13) for y in range(2, 15) if not (7 <= x <= 8 and y >= 6)],
              "boots": [(x, y) for x in list(range(2, 7)) + list(range(9, 14)) for y in range(8, 14)
                        if not (y <= 10 and x in (2, 13))]}

    def gen(rng):
        img = _blank()
        for x, y in shapes[piece]:
            _px(img, x, y, _shade(colour, 1 + rng.uniform(-0.1, 0.1)))
        return img
    return gen


def compass_icon(rng):
    img = _blank()
    for x in range(TILE):
        for y in range(TILE):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d < 6.5:
                _px(img, x, y, (120, 122, 130) if d > 5.3 else (236, 232, 220))
    for i in range(4):
        _px(img, 8, 4 + i, (210, 40, 40))
        _px(img, 7, 8 + i, (60, 60, 70))
    return img


def map_icon(rng):
    img = _blank()
    for x in range(2, 14):
        for y in range(2, 14):
            edge = x in (2, 13) or y in (2, 13)
            land = ((x * 3 + y * 5) % 7) < 3
            _px(img, x, y, (170, 140, 90) if edge else ((110, 170, 80) if land else (90, 140, 210)))
    _px(img, 8, 7, (210, 40, 40))
    return img


def paper_icon(rng):
    img = _blank()
    for x in range(3, 13):
        for y in range(2, 14):
            _px(img, x, y, (240, 238, 228) if (y % 3) else (200, 200, 196))
    return img


def enchant_top(rng):
    img = _noise(rng, (150, 30, 40), 0.08)
    for x in range(4, 12):
        for y in range(4, 12):
            img.putpixel((x, y), (236, 230, 214) if (x + y) % 5 else (90, 70, 160))
    return img


def enchant_side(rng):
    img = _noise(rng, (26, 18, 40), 0.25)
    for x in range(TILE):
        for y in range(0, 4):
            img.putpixel((x, y), (150, 30, 40))
    for x in (3, 8, 12):
        img.putpixel((x, 8), (110, 220, 230))
    return img


def composter_side(rng):
    img = boards((150, 104, 60))(rng)
    for y in (3, 12):
        for x in range(TILE):
            _px(img, x, y, (100, 70, 40))
    return img


def composter_top(rng, full=False):
    img = _blank()
    for x in range(TILE):
        for y in range(TILE):
            edge = x < 2 or y < 2 or x > 13 or y > 13
            if edge:
                _px(img, x, y, (130, 90, 52))
            else:
                _px(img, x, y, _shade((230, 226, 200) if full else (90, 70, 40), 1 + rng.uniform(-0.15, 0.1)))
    return img


def campfire_side(rng):
    img = _blank()
    for x in range(TILE):
        for y in range(10, 14):
            _px(img, x, y, (110, 80, 50) if (x // 4) % 2 else (90, 64, 40))
    for x in range(3, 13):
        for y in range(2, 10):
            if abs(x - 8) < (10 - y) * 0.7:
                _px(img, x, y, (255, 200 - (10 - y) * 12, 40))
    return img


def bone_meal(rng):
    img = _blank()
    for _ in range(14):
        x, y = rng.randrange(4, 12), rng.randrange(5, 13)
        _px(img, x, y, (240, 238, 228))
    return img


def slime_block(rng):
    img = Image.new("RGBA", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            edge = x in (0, 15) or y in (0, 15)
            inner = 4 <= x <= 11 and 4 <= y <= 11
            c = (80, 190, 70) if edge or inner else (120, 220, 100)
            img.putpixel((x, y), c + (200,))
    return img


def painting(n):
    """Four little pictures of our own: a sunset over the sea, a mountain, a flower, a night sky."""
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                frame = x in (0, 15) or y in (0, 15)
                if frame:
                    c = (120, 84, 48)
                elif n == 0:
                    c = (250, 150 - y * 6, 80) if y < 9 else (40, 90, 170)
                    if (x - 8) ** 2 + (y - 9) ** 2 < 9 and y < 9:
                        c = (255, 220, 90)
                elif n == 1:
                    c = (130, 190, 240) if y < 16 - min(x, 15 - x) * 1.6 else (90, 110, 120)
                    if y < 6 - abs(x - 8) * 0.0 and y > 16 - min(x, 15 - x) * 1.6:
                        c = (240, 240, 245)
                elif n == 2:
                    c = (230, 220, 190)
                    if (x - 8) ** 2 + (y - 6) ** 2 < 8:
                        c = (220, 60, 90)
                    if x == 8 and y > 8:
                        c = (60, 140, 60)
                else:
                    c = (20, 24, 60)
                    if rng.random() < 0.06:
                        c = (255, 255, 220)
                    if (x - 11) ** 2 + (y - 4) ** 2 < 5:
                        c = (240, 236, 200)
                img.putpixel((x, y), c)
        return img
    return gen


def item_frame(rng):
    img = boards((150, 110, 66))(rng)
    for x in range(3, 13):
        for y in range(3, 13):
            img.putpixel((x, y), (122, 86, 52))
    return img


def flower_pot(rng):
    img = _blank()
    for x in range(4, 12):
        for y in range(6, 15):
            _px(img, x, y, (170, 90, 60) if y > 6 else (130, 70, 46))
    return img


def shield_icon(rng):
    img = _blank()
    for x in range(3, 13):
        for y in range(2, 14):
            if y > 10 and abs(x - 7.5) > 13 - y:
                continue
            edge = x in (3, 12) or y == 2
            _px(img, x, y, (150, 152, 160) if edge else (140, 100, 60))
    for y in range(3, 13):
        _px(img, 7, y, (150, 152, 160))
        _px(img, 8, y, (150, 152, 160))
    return img


def beehive_side(rng):
    img = boards((200, 160, 90))(rng)
    for x in range(5, 11):
        for y in range(8, 12):
            img.putpixel((x, y), (60, 40, 20))
    return img


def scaffolding(rng):
    img = _blank()
    for i in range(TILE):
        for j in (0, 1, 14, 15):
            _px(img, i, j, (200, 170, 100))
            _px(img, j, i, (200, 170, 100))
        _px(img, i, i, (180, 150, 86))
    return img


def firework(rng):
    img = _blank()
    for y in range(4, 14):
        for x in range(6, 10):
            _px(img, x, y, (200, 40, 40) if y % 3 else (240, 240, 240))
    for x, y in ((7, 3), (8, 2), (7, 14), (8, 15)):
        _px(img, x, y, (230, 200, 90))
    return img


def lava(rng):
    img = _noise(rng, (222, 92, 18), 0.08)
    for _ in range(7):                       # bright molten streaks
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for dx in range(rng.randint(2, 6)):
            img.putpixel(((x + dx) % TILE, (y + dx // 3) % TILE), (255, 196, 60))
    for _ in range(10):                      # dark cooling crust
        img.putpixel((rng.randrange(TILE), rng.randrange(TILE)), (150, 40, 10))
    return img


def obsidian(rng):
    img = _noise(rng, (26, 18, 40), 0.25)
    for _ in range(8):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for dx in range(rng.randint(1, 3)):
            img.putpixel(((x + dx) % TILE, y), (70, 48, 110))
    return img


def lamp(rng):
    img = Image.new("RGB", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            edge = min(x, y, TILE - 1 - x, TILE - 1 - y)
            if edge == 0:
                color = (96, 72, 40)
            elif (x in (5, 10) or y in (5, 10)):
                color = (150, 110, 52)
            else:
                color = (255, 222, 130)
            img.putpixel((x, y), _shade(color, 1 + rng.uniform(-0.06, 0.06)))
    return img


def glass(rng):
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))   # transparent centre
    for x in range(TILE):
        for y in range(TILE):
            if min(x, y, TILE - 1 - x, TILE - 1 - y) == 0:
                img.putpixel((x, y), _clamp((205 + rng.uniform(-15, 15),) * 2 + (225, 255)))
    for i in range(3):                                      # a couple of glints
        img.putpixel((3 + i, 5 - i), (235, 245, 255, 255))
        img.putpixel((9 + i, 12 - i), (235, 245, 255, 255))
    return img


def coal_ore(rng):
    img = stone(rng)
    for _ in range(5):
        cx, cy = rng.randrange(2, TILE - 3), rng.randrange(2, TILE - 3)
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1), (2, 1)):
            img.putpixel((cx + dx, cy + dy), _shade((30, 30, 32), 1 + rng.uniform(-0.2, 0.2)))
    return img


def stick(rng):
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    for i in range(3, 13):
        img.putpixel((i, TILE - 1 - i), _shade((120, 86, 48), 1 + rng.uniform(-0.1, 0.1)) + (255,))
        img.putpixel((i + 1, TILE - 1 - i), _shade((90, 62, 34), 1) + (255,))
    return img


def coal(rng):
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    c = (TILE - 1) / 2
    for x in range(TILE):
        for y in range(TILE):
            if (x - c) ** 2 + (y - c) ** 2 * 1.3 < 26 + rng.uniform(-4, 4):
                img.putpixel((x, y), _shade((58, 58, 64), 1 + rng.uniform(-0.3, 0.4)) + (255,))
    return img


WOOD_HEAD, STONE_HEAD = (184, 140, 84), (140, 140, 146)


def _handle(img, rng):
    for i in range(2, 12):                      # diagonal handle, bottom-left to the middle
        img.putpixel((i, TILE - 1 - i), _shade((120, 86, 48), 1 + rng.uniform(-0.1, 0.1)) + (255,))
        img.putpixel((i + 1, TILE - 1 - i), (80, 56, 30, 255))


def _pickaxe(rng, head):
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    _handle(img, rng)
    for i in range(10):                          # curved head across the top-right
        x, y = 5 + i, 2 + abs(i - 5) // 2
        for dy in (0, 1):
            img.putpixel((x, y + dy), _shade(head, 1 + rng.uniform(-0.1, 0.1) - 0.25 * dy) + (255,))
    return img


def _axe(rng, head):
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    _handle(img, rng)
    for x in range(8, 14):                       # blade next to the top of the handle
        for y in range(1, 7):
            if (x - 8) + (6 - y) < 9:
                img.putpixel((x, y), _shade(head, 1 + rng.uniform(-0.1, 0.1) - (0.25 if x == 13 else 0)) + (255,))
    return img


def wood_pickaxe(rng):
    return _pickaxe(rng, WOOD_HEAD)


def stone_pickaxe(rng):
    return _pickaxe(rng, STONE_HEAD)


def wood_axe(rng):
    return _axe(rng, WOOD_HEAD)


def stone_axe(rng):
    return _axe(rng, STONE_HEAD)


def raw_meat(rng):
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    for x in range(TILE):
        for y in range(TILE):
            d = ((x - 8) / 6.0) ** 2 + ((y - 7) / 4.5) ** 2
            if d < 1:
                base = (226, 214, 200) if d > 0.75 else (196, 70, 70)   # fat rim, red middle
                img.putpixel((x, y), _shade(base, 1 + rng.uniform(-0.1, 0.1)) + (255,))
    for x in range(3, 6):                        # bone sticking out
        img.putpixel((x, 12 + (x - 3) // 2), (236, 230, 216, 255))
    return img


def cooked_meat(rng):
    img = raw_meat(rng)
    for x in range(TILE):
        for y in range(TILE):
            r, g, b, a = img.getpixel((x, y))
            if a and r > g + 60:                 # browned instead of red
                img.putpixel((x, y), _shade((150, 88, 48), 1 + rng.uniform(-0.12, 0.12)) + (255,))
    return img


def apple(rng):
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    for x in range(TILE):
        for y in range(TILE):
            if (x - 7.5) ** 2 + (y - 9) ** 2 < 30:
                shine = 1.35 if (x - 5) ** 2 + (y - 7) ** 2 < 3 else 1
                img.putpixel((x, y), _shade((200, 36, 40), shine * (1 + rng.uniform(-0.08, 0.08))) + (255,))
    for y in range(1, 4):
        img.putpixel((8, y), (96, 66, 36, 255))
    for x in (9, 10, 11):
        img.putpixel((x, 2), (70, 150, 60, 255))
    return img


def hud_icons(size=9):
    """Icons for the health / hunger bars: heart_*, food_*, bubble (full, half, empty variants)."""
    def shape(inside, color, half=False, empty=False):
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        for x in range(size):
            for y in range(size):
                if inside(x, y):
                    outline = any(not inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                    if outline:
                        c = (20, 20, 20, 255)
                    elif empty or (half and x >= size // 2):
                        c = (40, 40, 44, 200)
                    else:
                        c = color + (255,)
                    img.putpixel((x, y), c)
        return img

    def heart(x, y):
        if not (0 <= x < size and 0 <= y < size):
            return False
        top = y <= 2 and (x in range(1, 4) or x in range(5, 8)) or (y == 0 and False)
        body = 2 <= y and abs(x - 4) <= 4 - max(0, y - 3) and y < 8
        return top or body

    def food(x, y):
        if not (0 <= x < size and 0 <= y < size):
            return False
        meat = (x - 5) ** 2 + (y - 3.5) ** 2 < 10
        bone = x + y in (8, 9) and x < 4
        return meat or bone

    def bubble(x, y):
        return 0 <= x < size and 0 <= y < size and (x - 4) ** 2 + (y - 4) ** 2 < 17

    icons = {}
    for state in ("full", "half", "empty"):
        icons[f"heart_{state}"] = shape(heart, (220, 40, 44), state == "half", state == "empty")
        icons[f"food_{state}"] = shape(food, (178, 104, 56), state == "half", state == "empty")
    icons["bubble"] = shape(bubble, (120, 180, 240))
    return icons


def crack_stages(stages=6, seed=99):
    """Transparent overlays with more and more cracks, shown while a block is being mined."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    result = []
    for _ in range(stages):
        for _ in range(3):                       # each stage adds a few random-walk cracks
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            for _ in range(7):
                img.putpixel((x, y), (20, 20, 20, 200))
                x = max(0, min(TILE - 1, x + rng.choice((-1, 0, 1))))
                y = max(0, min(TILE - 1, y + rng.choice((-1, 0, 1))))
        result.append(img.copy())
    return result




# ================================================================ expanded block set
def _rgba(c, a=255):
    return tuple(c[:3]) + (a,)


def _blank():
    return Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))


def _px(img, x, y, color, a=255):
    if 0 <= x < TILE and 0 <= y < TILE:
        img.putpixel((x, y), _rgba(_clamp(color), a))


def noise_tile(base, amount=0.1, specks=(), seed_count=12):
    def gen(rng):
        img = _noise(rng, base, amount)
        for color, count in specks:
            _speckle(img, rng, color, count)
        return img
    return gen


def blotchy(base, other, cells=6, amount=0.08):
    """Large irregular patches of a second colour (granite, marble veins...)."""
    def gen(rng):
        img = _noise(rng, base, amount)
        for _ in range(cells):
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            for _ in range(rng.randint(4, 10)):
                img.putpixel((x % TILE, y % TILE), _shade(other, 1 + rng.uniform(-0.1, 0.1)))
                x += rng.choice((-1, 0, 1))
                y += rng.choice((-1, 0, 1))
        return img
    return gen


def layered(base, bands=4, amount=0.05):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for y in range(TILE):
            band = 1 + (0.08 if (y // (TILE // bands)) % 2 else -0.04) - (0.12 if y % (TILE // bands) == 0 else 0)
            for x in range(TILE):
                img.putpixel((x, y), _shade(base, band * (1 + rng.uniform(-amount, amount))))
        return img
    return gen


def cobble(base, moss=None):
    """Rounded stones with dark gaps between them."""
    def gen(rng):
        centers = [(rng.uniform(0, TILE), rng.uniform(0, TILE), rng.uniform(0.85, 1.15)) for _ in range(9)]
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                d = sorted(min((x - cx + dx) ** 2 + (y - cy + dy) ** 2 for dx in (-TILE, 0, TILE) for dy in (-TILE, 0, TILE))
                           for cx, cy, _ in centers)
                nearest = min(centers, key=lambda c: min((x - c[0] + dx) ** 2 + (y - c[1] + dy) ** 2
                                                         for dx in (-TILE, 0, TILE) for dy in (-TILE, 0, TILE)))
                edge = d[1] ** 0.5 - d[0] ** 0.5 < 1.1
                color = _shade(base, 0.55 if edge else nearest[2] * (1 + rng.uniform(-0.06, 0.06)))
                if moss and not edge and rng.random() < 0.35 * (1 - y / TILE + 0.3):
                    color = _shade(moss, 1 + rng.uniform(-0.15, 0.1))
                img.putpixel((x, y), color)
        return img
    return gen


def ore(specks, base=(128, 128, 132)):
    def gen(rng):
        img = stone(rng)
        for _ in range(5):
            cx, cy = rng.randrange(1, TILE - 2), rng.randrange(1, TILE - 2)
            color = rng.choice(specks)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1), (-1, 0)):
                img.putpixel((cx + dx, cy + dy), _shade(color, 1 + rng.uniform(-0.15, 0.15)))
        return img
    return gen


def metal_block(base):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                edge = min(x, y, TILE - 1 - x, TILE - 1 - y)
                f = 1.25 if edge == 0 and (x == 0 or y == 0) else 0.7 if edge == 0 else 1.0
                f *= 1.1 if (x + y) % 7 == 0 else 1
                img.putpixel((x, y), _shade(base, f * (1 + rng.uniform(-0.03, 0.03))))
        return img
    return gen


def ingot(base):
    def gen(rng):
        img = _blank()
        for y in range(6, 12):
            inset = (11 - y) // 2
            for x in range(2 + inset, 14 - inset):
                f = 1.3 if y == 6 else 0.75 if y == 11 or x in (2 + inset, 13 - inset) else 1.0
                _px(img, x, y, _shade(base, f))
        return img
    return gen


def gem(rng):
    img = _blank()
    for y in range(3, 14):
        half = 6 - abs(y - 6) if y <= 6 else max(0, 6 - (y - 6))
        for x in range(8 - half, 8 + half):
            f = 1.35 if x < 8 and y < 7 else 0.8 if x >= 8 and y > 6 else 1.0
            _px(img, x, y, _shade((90, 220, 225), f))
    return img


def bark(base, stripes=None):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            col = 1 + rng.uniform(-0.15, 0.15)
            for y in range(TILE):
                img.putpixel((x, y), _shade(base, col * (1 + rng.uniform(-0.05, 0.05))))
        if stripes:
            for _ in range(7):
                x, y = rng.randrange(TILE - 3), rng.randrange(TILE)
                for dx in range(rng.randint(2, 4)):
                    img.putpixel((x + dx, y), stripes)
        return img
    return gen


def rings(light, dark, bark_color):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        c = (TILE - 1) / 2
        for x in range(TILE):
            for y in range(TILE):
                d = max(abs(x - c), abs(y - c))
                color = bark_color if d > 6.5 else (light if int(d) % 2 == 0 else dark)
                img.putpixel((x, y), _shade(color, 1 + rng.uniform(-0.05, 0.05)))
        return img
    return gen


def boards(base):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for board in range(4):
            seam = rng.randrange(TILE)
            tone = 1 + rng.uniform(-0.08, 0.08)
            for y in range(board * 4, board * 4 + 4):
                for x in range(TILE):
                    f = 0.66 if (y % 4 == 3 or x == seam) else 1.0
                    img.putpixel((x, y), _shade(base, f * tone * (1 + rng.uniform(-0.04, 0.04))))
        return img
    return gen


def foliage(base, dark_amount=40):
    def gen(rng):
        img = _noise(rng, base, 0.2)
        _speckle(img, rng, _shade(base, 0.65), dark_amount)
        return _speckle(img, rng, _shade(base, 1.25), 14)
    return gen


def bricks(base, mortar, rows=4, length=8):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        h = TILE // rows
        for y in range(TILE):
            offset = 0 if (y // h) % 2 == 0 else length // 2
            for x in range(TILE):
                m = y % h == h - 1 or (x + offset) % length == length - 1
                img.putpixel((x, y), _shade(mortar if m else base, 1 + rng.uniform(-0.07, 0.07)))
        return img
    return gen


def tiles(rng):
    img = Image.new("RGB", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            grout = x % 8 == 7 or y % 8 == 7
            corner = (x % 8 in (1, 2) and y % 8 in (1, 2))
            color = (150, 140, 130) if grout else (64, 110, 170) if corner else (226, 216, 196)
            img.putpixel((x, y), _shade(color, 1 + rng.uniform(-0.04, 0.04)))
    return img


def bookshelf(rng):
    img = boards((184, 140, 84))(rng)
    for shelf in (1, 9):
        x = 1
        while x < TILE - 1:
            w = rng.choice((1, 2))
            color = rng.choice([(150, 40, 40), (40, 70, 140), (60, 120, 60), (170, 130, 50), (90, 50, 110)])
            for dx in range(w):
                for y in range(shelf, shelf + 6):
                    _px(img, x + dx, y, _shade(color, 1 + rng.uniform(-0.1, 0.1)))
            x += w + (1 if rng.random() < 0.2 else 0)
    return img


def workbench_top(rng):
    img = boards((184, 140, 84))(rng)
    for i in range(TILE):
        _px(img, i, 0, (90, 62, 34))
        _px(img, 0, i, (90, 62, 34))
        _px(img, i, TILE - 1, (90, 62, 34))
        _px(img, TILE - 1, i, (90, 62, 34))
    for i in range(3, 13):                          # a square and a ruler drawn on top
        _px(img, i, 4, (70, 50, 30))
        _px(img, 4, i, (70, 50, 30))
    return img


def workbench_side(rng):
    img = boards((160, 118, 68))(rng)
    for i in range(3, 13):                          # a saw hanging on the side
        _px(img, i, 6, (170, 170, 176))
        _px(img, i, 7, (140, 140, 146))
        if i % 2:
            _px(img, i, 8, (140, 140, 146))
    for y in range(5, 9):
        _px(img, 2, y, (100, 66, 34))
    return img


def furnace_top(rng):
    return cobble((128, 128, 132))(rng)


def furnace_front(rng):
    img = furnace_top(rng)
    for x in range(4, 12):
        for y in range(8, 14):
            glow = y >= 12
            _px(img, x, y, (230, 120 + rng.randrange(60), 30) if glow else (24, 22, 22))
    for x in range(3, 13):
        _px(img, x, 7, (70, 70, 74))
    return img


def chest_top(rng):
    img = boards((170, 120, 64))(rng)
    for i in range(TILE):
        for j in (0, TILE - 1):
            _px(img, i, j, (90, 60, 30))
            _px(img, j, i, (90, 60, 30))
    return img


def chest_front(rng):
    img = chest_top(rng)
    for x in range(TILE):
        _px(img, x, 6, (90, 60, 30))
    for x in range(7, 9):
        for y in range(5, 9):
            _px(img, x, y, (200, 200, 210))
    return img


def torch(rng):
    img = _blank()
    for y in range(6, 16):
        _px(img, 7, y, (110, 78, 42))
        _px(img, 8, y, (86, 60, 32))
    for x, y, c in ((7, 5, (255, 220, 90)), (8, 5, (255, 200, 60)), (7, 4, (255, 240, 150)), (8, 4, (255, 170, 40)),
                    (7, 3, (255, 150, 30)), (8, 3, (255, 230, 120))):
        _px(img, x, y, c)
    return img


def ladder(rng):
    img = _blank()
    for y in range(TILE):
        for x in (2, 3, 12, 13):
            _px(img, x, y, _shade((120, 86, 48), 1 + rng.uniform(-0.1, 0.1)))
    for y in (2, 6, 10, 14):
        for x in range(4, 12):
            _px(img, x, y, _shade((140, 100, 56), 1 + rng.uniform(-0.1, 0.1)))
    return img


def _door(rng, window):
    img = boards((150, 108, 60))(rng)
    for i in range(TILE):
        for j in (0, 1, TILE - 2, TILE - 1):
            _px(img, j, i, (96, 66, 34))
    if window:
        for x in range(4, 12):
            for y in range(4, 11):
                img.putpixel((x, y), (0, 0, 0, 0))
    else:
        _px(img, 12, 2, (210, 200, 120))
        _px(img, 12, 3, (210, 200, 120))
    return img


def door_top(rng):
    return _door(rng, True)


def door_bottom(rng):
    return _door(rng, False)


def bed_top(rng):
    img = _noise(rng, (176, 46, 40), 0.06)
    for x in range(TILE):
        for y in range(0, 5):
            img.putpixel((x, y), _shade((236, 232, 224), 1 + rng.uniform(-0.04, 0.04)))
    return img


def bed_side(rng):
    img = boards((150, 108, 60))(rng)
    for x in range(TILE):
        for y in range(0, 9):
            img.putpixel((x, y), _shade((176, 46, 40), 1 + rng.uniform(-0.06, 0.06)))
    return img


def _plant(rng, stems, top=None):
    img = _blank()
    for x0, height, lean in stems:
        x = x0
        for y in range(TILE - 1, TILE - 1 - height, -1):
            _px(img, int(x), y, _shade((70, 140, 50), 1 + rng.uniform(-0.15, 0.15)))
            x += lean
    if top:
        top(img)
    return img


def tall_grass(rng):
    return _plant(rng, [(rng.randrange(2, 14), rng.randrange(6, 14), rng.uniform(-0.25, 0.25)) for _ in range(9)])


def fern(rng):
    img = _blank()
    for side in (-1, 1):
        for y in range(4, 16):
            for i in range(1, (16 - y) // 2 + 3):
                _px(img, 8 + side * i + (y - 4) // 6 * side, y - i // 2, _shade((50, 120, 50), 1 + rng.uniform(-0.15, 0.1)))
    for y in range(3, 16):
        _px(img, 8, y, (40, 100, 40))
    return img


def flower(petal, center=(240, 210, 60)):
    def gen(rng):
        def head(img):
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, 1), (1, -1), (-1, 1)):
                _px(img, 8 + dx, 6 + dy, _shade(petal, 1 + rng.uniform(-0.1, 0.1)))
            _px(img, 8, 6, center)
        img = _plant(rng, [(8, 9, 0)], head)
        _px(img, 7, 11, (70, 140, 50))
        _px(img, 9, 12, (70, 140, 50))
        return img
    return gen


def mushroom(cap, spots=None):
    def gen(rng):
        img = _blank()
        for y in range(9, 15):
            for x in (7, 8):
                _px(img, x, y, (226, 220, 206))
        for y in range(5, 9):
            for x in range(4 + (8 - y) // 2 * 0, 12):
                if abs(x - 7.5) <= 4 - (8 - y) // 2:
                    _px(img, x, y, _shade(cap, 1 + rng.uniform(-0.08, 0.08)))
        if spots:
            for x, y in ((6, 6), (9, 7), (8, 5)):
                _px(img, x, y, spots)
        return img
    return gen


def reeds(rng):
    return _plant(rng, [(x, rng.randrange(12, 16), 0) for x in (3, 6, 10, 13)])


def cactus(rng):
    img = Image.new("RGB", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            f = 0.75 if x in (1, 14) else 1.1 if x % 5 == 2 else 1.0
            img.putpixel((x, y), _shade((70, 140, 60), f * (1 + rng.uniform(-0.05, 0.05))))
    for _ in range(8):
        img.putpixel((rng.randrange(TILE), rng.randrange(TILE)), (220, 220, 180))
    return img


def cactus_top(rng):
    img = cactus(rng)
    for x in range(2, 14):
        for y in range(2, 14):
            img.putpixel((x, y), _shade((96, 166, 80), 1 + rng.uniform(-0.05, 0.05)))
    return img


def wool(rgb):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                weave = 1.08 if (x + y) % 4 < 2 else 0.94
                img.putpixel((x, y), _shade(rgb, weave * (1 + rng.uniform(-0.05, 0.05))))
        return img
    return gen


def stained_glass(rgb):
    def gen(rng):
        img = Image.new("RGBA", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                frame = min(x, y, TILE - 1 - x, TILE - 1 - y) == 0
                img.putpixel((x, y), _rgba(_shade(rgb, 0.8 if frame else 1.05), 235 if frame else 120))
        return img
    return gen


def ice(rng):
    img = Image.new("RGBA", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            img.putpixel((x, y), _rgba(_shade((150, 190, 240), 1 + rng.uniform(-0.05, 0.05)), 190))
    for _ in range(4):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for i in range(5):
            img.putpixel(((x + i) % TILE, (y + i // 2) % TILE), (235, 245, 255, 230))
    return img


def _shovel(rng, head):
    img = _blank()
    _handle(img, rng)
    for x in range(10, 15):
        for y in range(1, 6):
            if abs((x - 12) + (y - 3)) <= 2 and abs((x - 12) - (y - 3)) <= 3:
                _px(img, x, y, _shade(head, 1 + rng.uniform(-0.1, 0.1)))
    return img


def _sword(rng, head):
    img = _blank()
    for i in range(1, 11):                          # blade along the diagonal
        _px(img, 4 + i, 11 - i, _shade(head, 1.15))
        _px(img, 5 + i, 11 - i, _shade(head, 0.85))
    for i in range(-2, 3):                          # cross guard
        _px(img, 5 + i, 10 + i, (90, 62, 34))
    for i in range(3):                              # grip
        _px(img, 3 - i, 12 + i, (110, 78, 42))
    return img


def bucket(rng, water_fill=False):
    img = _blank()
    for y in range(5, 14):
        half = 5 - (y - 5) // 4
        for x in range(8 - half, 8 + half):
            edge = x in (8 - half, 7 + half) or y == 13
            _px(img, x, y, (120, 120, 126) if edge else (170, 170, 178))
    if water_fill:
        for x in range(4, 12):
            fills = {"lava": ((250, 150, 40), (220, 90, 20)), "milk": ((248, 248, 244), (226, 226, 220))}
            top, low = fills.get(water_fill, ((60, 110, 210), (50, 96, 196)))
            _px(img, x, 6, top)
            _px(img, x, 7, low)
    return img


METALS = {"wood": (184, 140, 84), "stone": (140, 140, 146), "iron": (214, 214, 220), "diamond": (90, 220, 225)}

EXTRA_GENERATORS = {
    "gravel": noise_tile((128, 120, 112), 0.12, (((90, 84, 80), 30), ((170, 162, 150), 20))),
    "clay": noise_tile((158, 164, 178), 0.04, (((140, 146, 160), 12),)),
    "snow": noise_tile((240, 244, 250), 0.03),
    "ice": ice,
    "granite": blotchy((168, 112, 96), (120, 80, 70), 10),
    "basalt": noise_tile((62, 62, 68), 0.1, (((40, 40, 46), 25),)),
    "sandstone": layered((214, 196, 140)),
    "marble": blotchy((232, 230, 226), (170, 170, 176), 5, 0.03),
    "cobblestone": cobble((128, 128, 132)),
    "mossy_cobblestone": cobble((124, 128, 124), moss=(80, 120, 60)),
    "red_sand": noise_tile((196, 112, 58), 0.07, (((170, 92, 46), 14),)),
    "iron_ore": ore([(216, 175, 140), (190, 150, 120)]),
    "copper_ore": ore([(206, 112, 60), (80, 160, 120)]),
    "tin_ore": ore([(200, 200, 212), (170, 172, 184)]),
    "gold_ore": ore([(246, 206, 60), (220, 170, 40)]),
    "diamond_ore": ore([(110, 232, 232), (80, 200, 210)]),
    "iron_block": metal_block((206, 206, 210)),
    "copper_block": metal_block((196, 110, 70)),
    "gold_block": metal_block((240, 200, 60)),
    "bronze_block": metal_block((176, 130, 70)),
    "diamond_block": metal_block((96, 220, 220)),
    "birch_log": bark((222, 220, 210), stripes=(40, 40, 40)),
    "birch_log_top": rings((226, 210, 170), (204, 186, 146), (222, 220, 210)),
    "birch_planks": boards((214, 196, 140)),
    "birch_leaves": foliage((110, 160, 80)),
    "pine_log": bark((80, 56, 34)),
    "pine_log_top": rings((170, 130, 80), (140, 104, 62), (70, 48, 30)),
    "pine_planks": boards((128, 92, 54)),
    "pine_leaves": foliage((44, 92, 66)),
    "stone_bricks": bricks((128, 128, 132), (96, 96, 100), rows=2, length=16),
    "sandstone_bricks": bricks((214, 196, 140), (176, 160, 110), rows=4, length=8),
    "tiles": tiles,
    "plaster": noise_tile((228, 222, 210), 0.03),
    "bookshelf": bookshelf, "workbench_top": workbench_top, "workbench_side": workbench_side,
    "furnace_top": furnace_top, "furnace_front": furnace_front,
    "chest_top": chest_top, "chest_front": chest_front,
    "torch": torch, "ladder": ladder, "door_top": door_top, "door_bottom": door_bottom,
    "bed_top": bed_top, "bed_side": bed_side,
    "tall_grass": tall_grass, "fern": fern,
    "red_flower": flower((210, 40, 40)), "yellow_flower": flower((245, 215, 50), (200, 140, 30)),
    "blue_flower": flower((70, 100, 220)), "white_flower": flower((240, 240, 240)),
    "red_mushroom": mushroom((200, 40, 36), (240, 240, 240)), "brown_mushroom": mushroom((140, 100, 70)),
    "reeds": reeds, "cactus": cactus, "cactus_top": cactus_top,
    "iron_ingot": ingot((214, 214, 220)), "copper_ingot": ingot((206, 116, 66)), "tin_ingot": ingot((196, 198, 210)),
    "gold_ingot": ingot((246, 206, 60)), "bronze_ingot": ingot((184, 136, 72)), "diamond": gem,
    "bucket": bucket, "water_bucket": lambda rng: bucket(rng, True),
    "lava_bucket": lambda rng: bucket(rng, "lava"), "milk_bucket": lambda rng: bucket(rng, "milk"),
    "cake": cake_icon,
}
for _i, (_name, _rgb) in enumerate(__import__("blocks").DYES):
    EXTRA_GENERATORS[f"wool_{_i}"] = wool(_rgb)
    EXTRA_GENERATORS[f"glass_{_i}"] = stained_glass(_rgb)
for _metal, _head in METALS.items():
    EXTRA_GENERATORS[f"{_metal}_shovel"] = (lambda h: lambda rng: _shovel(rng, h))(_head)
    EXTRA_GENERATORS[f"{_metal}_sword"] = (lambda h: lambda rng: _sword(rng, h))(_head)
    EXTRA_GENERATORS.setdefault(f"{_metal}_pickaxe", (lambda h: lambda rng: _pickaxe(rng, h))(_head))
    EXTRA_GENERATORS.setdefault(f"{_metal}_axe", (lambda h: lambda rng: _axe(rng, h))(_head))



# ================================================================ second expansion (colour families, woods, stones...)
def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def concrete(rgb):
    """Smooth, flat colour with the faintest grain."""
    def gen(rng):
        img = _noise(rng, rgb, 0.025)
        for _ in range(6):
            _px(img, rng.randrange(TILE), rng.randrange(TILE), _shade(rgb, 0.9))
        return img
    return gen


def terracotta(rgb):
    """Fired clay: the colour pulled towards earthy brown, with a soft mottled grain."""
    base = _mix(rgb, (150, 96, 70), 0.35)

    def gen(rng):
        img = _noise(rng, base, 0.05)
        for _ in range(10):
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            for dx in range(rng.randint(2, 4)):
                _px(img, (x + dx) % TILE, y, _shade(base, 0.9))
        return img
    return gen


def glazed(rgb, index):
    """A shiny patterned tile: dark rim, a diamond motif in a light tint and an accent dot.
    The motif turns with the colour index so neighbouring colours don't look alike."""
    light = _mix(rgb, (255, 255, 255), 0.45)
    dark = _shade(rgb, 0.55)
    accent = _mix(rgb, (255, 220, 120) if sum(rgb) < 380 else (40, 40, 60), 0.6)

    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                u, v = (x, y) if index % 2 == 0 else (y, TILE - 1 - x)
                rim = min(u, v, TILE - 1 - u, TILE - 1 - v) == 0
                d = abs(u - 7.5) + abs(v - 7.5)
                if rim:
                    c = dark
                elif d < 2.5:
                    c = accent
                elif 4.5 < d < 6.5:
                    c = light
                elif (u + v) % 6 == 0 and d > 7:
                    c = light
                else:
                    c = rgb
                img.putpixel((x, y), _shade(c, 1.1 if (x < 3 and y < 3) else 1 + rng.uniform(-0.03, 0.03)))
        return img
    return gen


def sapling(leaf, stem=(100, 70, 40)):
    def gen(rng):
        img = _blank()
        for y in range(8, TILE):
            _px(img, 8, y, stem)
        for cx, cy, r in ((8, 6, 3.2), (5, 9, 2.2), (11, 9, 2.2)):
            for x in range(TILE):
                for y in range(TILE):
                    if (x - cx) ** 2 + (y - cy) ** 2 < r * r:
                        _px(img, x, y, _shade(leaf, 1 + rng.uniform(-0.18, 0.15)))
        return img
    return gen


def stone_variant(base, dark=None):
    """A stone in a different colour (stone(), recoloured)."""
    def gen(rng):
        img = _noise(rng, base, 0.08)
        for _ in range(5):
            cx, cy = rng.randrange(TILE), rng.randrange(TILE)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0)):
                img.putpixel(((cx + dx) % TILE, (cy + dy) % TILE), dark or _shade(base, 0.8))
        return img
    return gen


def slate(rng):
    img = Image.new("RGB", (TILE, TILE))
    for y in range(TILE):
        band = 1 + 0.07 * ((y * 7) % 3 - 1)
        for x in range(TILE):
            seam = (y + (x // 5)) % 5 == 0 and rng.random() < 0.7
            img.putpixel((x, y), _shade((72, 76, 88), (0.78 if seam else band) * (1 + rng.uniform(-0.05, 0.05))))
    return img


def limestone(rng):
    img = _noise(rng, (212, 202, 168), 0.05)
    for _ in range(3):                                # little shell fossils
        cx, cy = rng.randrange(2, TILE - 2), rng.randrange(2, TILE - 2)
        for dx, dy in ((0, 0), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)):
            _px(img, cx + dx, cy + dy, (182, 170, 136))
    return _speckle(img, rng, (226, 218, 190), 10)


def polished(base):
    """Ground smooth: a bevelled frame (light top-left, dark bottom-right) around a calm face."""
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                if x == 0 or y == 0:
                    f = 1.22
                elif x == TILE - 1 or y == TILE - 1:
                    f = 0.7
                elif x in (1, TILE - 2) or y in (1, TILE - 2):
                    f = 0.92
                else:
                    f = 1.03
                img.putpixel((x, y), _shade(base, f * (1 + rng.uniform(-0.03, 0.03))))
        return img
    return gen


def chiseled(base):
    """A carved block: frame, an inner square and a carved cross in the middle."""
    def gen(rng):
        img = polished(base)(rng)
        for i in range(3, 13):
            for j in (3, 12):
                _px(img, i, j, _shade(base, 0.68))
                _px(img, j, i, _shade(base, 0.68))
        for i in range(5, 11):
            _px(img, i, 7, _shade(base, 0.75))
            _px(img, 7, i, _shade(base, 0.75))
            _px(img, i, 8, _shade(base, 1.18))
            _px(img, 8, i, _shade(base, 1.18))
        return img
    return gen


def cracked_bricks(rng):
    img = bricks((128, 128, 132), (96, 96, 100), rows=2, length=16)(rng)
    for _ in range(3):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for _ in range(8):
            _px(img, x, y, (58, 58, 62))
            x = max(0, min(TILE - 1, x + rng.choice((-1, 0, 1))))
            y = max(0, min(TILE - 1, y + 1))
    return img


def mossy_bricks(rng):
    img = bricks((124, 128, 124), (92, 96, 92), rows=2, length=16)(rng)
    for x in range(TILE):
        for y in range(TILE):
            if rng.random() < 0.38 * (1.2 - y / TILE):
                _px(img, x, y, _shade((78, 124, 58), 1 + rng.uniform(-0.15, 0.12)))
    return img


def gem_item(color):
    def gen(rng):
        img = _blank()
        for y in range(3, 14):
            half = 6 - abs(y - 6) if y <= 6 else max(0, 6 - (y - 6))
            for x in range(8 - half, 8 + half):
                f = 1.4 if x < 8 and y < 7 else 0.75 if x >= 8 and y > 6 else 1.0
                _px(img, x, y, _shade(color, f))
        return img
    return gen


def shard(color):
    def gen(rng):
        img = _blank()
        for i in range(10):
            for w in range(-1, 2):
                _px(img, 4 + i // 2 + w, 13 - i, _shade(color, 1.3 if w < 0 else 0.8 if w > 0 else 1.0))
                _px(img, 9 + i // 3 + w, 13 - i // 1 if i < 7 else 7, _shade(color, 1.15 if w < 0 else 0.85))
        return img
    return gen


def gem_block(color):
    """Cut-gem block: diagonal facets in light and dark tones of the gem colour."""
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                u, v = x % 8, y % 8
                f = 1.3 if u + v < 4 else 0.72 if u + v > 11 else 1.12 if u > v else 0.92
                if min(x, y, TILE - 1 - x, TILE - 1 - y) == 0:
                    f = 0.62
                img.putpixel((x, y), _shade(color, f * (1 + rng.uniform(-0.03, 0.03))))
        return img
    return gen


def quartz_block(rng):
    img = _noise(rng, (236, 230, 222), 0.025)
    for x in range(TILE):
        _px(img, x, 0, (250, 248, 244))
        _px(img, x, TILE - 1, (196, 190, 182))
    for y in range(TILE):
        _px(img, 0, y, (250, 248, 244))
        _px(img, TILE - 1, y, (196, 190, 182))
    return img


def glow_crystal(rng):
    img = _noise(rng, (60, 50, 90), 0.1)
    for cx, cy, color in ((4, 5, (255, 236, 140)), (11, 4, (170, 250, 255)), (8, 11, (255, 210, 120)),
                          (13, 12, (220, 255, 200)), (3, 12, (255, 250, 210))):
        for dy in range(-3, 3):
            w = 1 if dy < -1 else 2
            for dx in range(-w + 1, w):
                _px(img, cx + dx, cy + dy, _shade(color, 1.0 - 0.06 * dy))
    return img


def hay_side(rng):
    img = Image.new("RGB", (TILE, TILE))
    for x in range(TILE):
        tone = 1 + rng.uniform(-0.12, 0.12)
        for y in range(TILE):
            band = y in (3, 4, 11, 12)
            img.putpixel((x, y), _shade((150, 100, 40) if band else (214, 180, 70), tone * (1 + rng.uniform(-0.05, 0.05))))
    return img


def hay_top(rng):
    img = _noise(rng, (206, 172, 64), 0.12)
    for _ in range(30):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for d in range(3):
            _px(img, x + d, y + (d if rng.random() < 0.5 else 0), (236, 206, 100))
    return img


def ribbed(base, rib, rib_every=4, stripe=None):
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                c = rib if x % rib_every == 0 else base
                if stripe and (x // 2) % 3 == 0:
                    c = stripe
                img.putpixel((x, y), _shade(c, 1 + rng.uniform(-0.06, 0.06)))
        return img
    return gen


def fruit_top(base, stem=(90, 120, 40)):
    def gen(rng):
        img = _noise(rng, base, 0.06)
        for x in range(TILE):
            for y in range(TILE):
                d = max(abs(x - 7.5), abs(y - 7.5))
                if d > 6.5:
                    _px(img, x, y, _shade(base, 0.82))
        for x in range(6, 10):
            for y in range(6, 10):
                _px(img, x, y, _shade(stem, 1 + rng.uniform(-0.1, 0.1)))
        return img
    return gen


def sponge(rng):
    img = _noise(rng, (214, 196, 72), 0.06)
    for _ in range(18):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        _px(img, x, y, (150, 128, 30))
        _px(img, x + 1, y, (170, 148, 40))
    return img


def color_lamp(rgb):
    glow = _mix(rgb, (255, 255, 230), 0.4)
    frame = _shade(rgb, 0.4)

    def gen(rng):
        img = Image.new("RGB", (TILE, TILE))
        for x in range(TILE):
            for y in range(TILE):
                edge = min(x, y, TILE - 1 - x, TILE - 1 - y)
                if edge == 0:
                    c = frame
                elif x in (5, 10) or y in (5, 10):
                    c = _shade(rgb, 0.75)
                else:
                    c = glow
                img.putpixel((x, y), _shade(c, 1 + rng.uniform(-0.05, 0.05)))
        return img
    return gen


def tulip(petal):
    def gen(rng):
        def head(img):
            for y in range(3, 8):
                for x in range(6, 11):
                    if not (y == 3 and x in (7, 9)) and not (y == 7 and x in (6, 10)):
                        _px(img, x, y, _shade(petal, 1.15 if x == 7 else 1 + rng.uniform(-0.08, 0.05)))
        img = _plant(rng, [(8, 9, 0)], head)
        for x, y in ((6, 12), (7, 11), (10, 12), (9, 11)):
            _px(img, x, y, (70, 140, 50))
        return img
    return gen


def lavender(rng):
    img = _plant(rng, [(5, 10, 0.1), (8, 13, 0), (11, 10, -0.1)])
    for x0, top in ((5, 6), (8, 3), (11, 6)):
        for y in range(top, top + 5):
            _px(img, x0 + (y % 2), y, _shade((150, 110, 220), 1 + rng.uniform(-0.15, 0.1)))
    return img


def bell_flower(petal):
    def gen(rng):
        img = _plant(rng, [(7, 12, 0.08)])
        for cx, cy in ((5, 7), (9, 5), (11, 9)):
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1), (-1, 1), (2, 1)):
                _px(img, cx + dx, cy + dy, _shade(petal, 1 + rng.uniform(-0.1, 0.1)))
            _px(img, cx, cy - 1, (70, 140, 50))
        return img
    return gen


def sunflower(rng):
    img = _plant(rng, [(8, 12, 0)])
    for x in range(TILE):
        for y in range(TILE):
            d = (x - 8) ** 2 + (y - 5) ** 2
            if d < 5:
                _px(img, x, y, (110, 70, 30))
            elif d < 15:
                _px(img, x, y, _shade((250, 204, 40), 1 + rng.uniform(-0.1, 0.08)))
    for x, y in ((6, 12), (10, 11)):
        _px(img, x, y, (70, 140, 50))
        _px(img, x + 1, y, (70, 140, 50))
    return img


def bush(leaf, berries=None, dry=False):
    def gen(rng):
        img = _blank()
        if dry:
            for _ in range(6):
                x, y = 8.0, 15.0
                dx = rng.uniform(-0.8, 0.8)
                for _ in range(rng.randint(6, 11)):
                    _px(img, int(x), int(y), _shade(leaf, 1 + rng.uniform(-0.2, 0.2)))
                    x += dx
                    y -= 1
            return img
        for x in range(TILE):
            for y in range(4, TILE):
                if (x - 7.5) ** 2 / 56 + (y - 10.5) ** 2 / 36 < 1 and rng.random() < 0.88:
                    _px(img, x, y, _shade(leaf, 1 + rng.uniform(-0.25, 0.2)))
        if berries:
            for _ in range(7):
                _px(img, rng.randrange(3, 13), rng.randrange(7, 15), berries)
        return img
    return gen


WOOD_COLORS = {          # species: (bark, bark stripes, ring light, ring dark, planks, leaves, sapling leaves)
    "maple": ((112, 74, 58), (86, 54, 40), (204, 150, 104), (178, 122, 84), (182, 104, 66), (206, 74, 34), (210, 90, 40)),
    "cherry": ((84, 46, 52), (140, 96, 96), (234, 176, 164), (212, 148, 140), (222, 158, 148), (242, 160, 196), (240, 150, 190)),
    "ashwood": ((138, 128, 114), (100, 92, 82), (222, 150, 92), (196, 124, 72), (206, 120, 62), (150, 162, 54), (140, 160, 60)),
    "ebony": ((44, 36, 34), (64, 54, 50), (90, 64, 50), (64, 44, 36), (62, 44, 38), (78, 92, 34), (70, 96, 40)),
}
for _sp, (_bark, _stripe, _rl, _rd, _pl, _lv, _sap) in WOOD_COLORS.items():
    EXTRA_GENERATORS[f"{_sp}_log"] = bark(_bark, stripes=_stripe)
    EXTRA_GENERATORS[f"{_sp}_log_top"] = rings(_rl, _rd, _bark)
    EXTRA_GENERATORS[f"{_sp}_planks"] = boards(_pl)
    EXTRA_GENERATORS[f"{_sp}_leaves"] = foliage(_lv)
    EXTRA_GENERATORS[f"{_sp}_sapling"] = sapling(_sap)
EXTRA_GENERATORS.update({
    "oak_sapling": sapling((60, 130, 50)), "birch_sapling": sapling((120, 170, 80), (220, 218, 208)),
    "pine_sapling": sapling((44, 96, 66)),
    "terracotta": terracotta((168, 100, 72)),
    "slate": slate, "cobbled_slate": cobble((74, 78, 90)), "limestone": limestone,
    "polished_stone": polished((140, 140, 144)), "polished_granite": polished((176, 112, 94)),
    "polished_basalt": polished((66, 66, 74)), "polished_marble": polished((236, 234, 230)),
    "smooth_sandstone": polished((218, 200, 146)), "polished_slate": polished((78, 82, 96)),
    "polished_limestone": polished((216, 206, 172)),
    "granite_bricks": bricks((170, 108, 92), (120, 80, 70), rows=4, length=8),
    "basalt_bricks": bricks((64, 64, 72), (36, 36, 42), rows=4, length=8),
    "marble_bricks": bricks((234, 232, 228), (176, 176, 182), rows=2, length=8),
    "slate_bricks": bricks((76, 80, 94), (48, 50, 60), rows=4, length=4),
    "limestone_bricks": bricks((214, 204, 170), (170, 160, 128), rows=2, length=16),
    "cracked_stone_bricks": cracked_bricks, "mossy_stone_bricks": mossy_bricks,
    "chiseled_stone": chiseled((132, 132, 136)), "chiseled_sandstone": chiseled((214, 196, 140)),
    "chiseled_marble": chiseled((232, 230, 226)), "chiseled_limestone": chiseled((212, 202, 168)),
    "ruby_ore": ore([(220, 30, 60), (180, 20, 44)]), "sapphire_ore": ore([(40, 80, 220), (70, 120, 240)]),
    "amethyst_ore": ore([(160, 90, 220), (200, 140, 240)]), "quartz_ore": ore([(244, 240, 232), (220, 214, 206)]),
    "ruby_block": gem_block((200, 30, 56)), "sapphire_block": gem_block((44, 84, 210)),
    "amethyst_block": gem_block((150, 92, 210)), "quartz_block": quartz_block,
    "tin_block": metal_block((190, 194, 206)), "coal_block": metal_block((44, 44, 50)),
    "ruby": gem_item((220, 36, 64)), "sapphire": gem_item((50, 90, 225)), "amethyst": shard((170, 110, 230)),
    "quartz": shard((240, 236, 228)),
    "glow_crystal": glow_crystal,
    "hay_side": hay_side, "hay_top": hay_top,
    "pumpkin_side": ribbed((224, 130, 30), (180, 96, 20)), "pumpkin_top": fruit_top((216, 124, 30)),
    "melon_side": ribbed((96, 160, 50), (60, 110, 34), 5, (150, 196, 70)),
    "melon_top": fruit_top((110, 168, 56), (120, 110, 50)),
    "mud": noise_tile((70, 56, 48), 0.1, (((52, 42, 36), 24), ((90, 74, 62), 10))),
    "mud_bricks": bricks((150, 116, 84), (104, 84, 64), rows=4, length=8),
    "moss_block": foliage((86, 128, 52), 30), "sponge": sponge,
    "packed_ice": noise_tile((150, 184, 236), 0.05, (((190, 214, 250), 20), ((128, 164, 220), 12))),
    "lavender": lavender, "marigold": flower((240, 140, 30), (180, 80, 20)), "pink_tulip": tulip((240, 140, 180)),
    "orchid": flower((200, 80, 200), (250, 230, 250)), "daisy": flower((250, 250, 250), (250, 200, 40)),
    "bluebell": bell_flower((100, 140, 240)), "dark_iris": tulip((70, 40, 110)), "sunflower": sunflower,
    "leafy_bush": bush((60, 130, 50)), "berry_bush": bush((50, 116, 50), (200, 30, 50)),
    "dry_bush": bush((130, 96, 60), dry=True),
})
for _i, (_name, _rgb) in enumerate(__import__("blocks").DYES):
    EXTRA_GENERATORS[f"concrete_{_i}"] = concrete(_rgb)
    EXTRA_GENERATORS[f"terracotta_{_i}"] = terracotta(_rgb)
    EXTRA_GENERATORS[f"glazed_{_i}"] = glazed(_rgb, _i)
for _name, _dye in __import__("blocks").LAMP_COLORS:
    EXTRA_GENERATORS[f"lamp_{_name.replace(' ', '_')}"] = color_lamp(__import__("blocks").DYES[_dye][1])

# ================================================================ farming, hoes, doors of every wood
def _hoe(rng, head):
    img = _blank()
    _handle(img, rng)
    for x in range(8, 14):                       # a flat blade bent down at the top of the handle
        _px(img, x, 2, _shade(head, 1.1 + rng.uniform(-0.08, 0.08)))
        _px(img, x, 3, _shade(head, 0.85))
    _px(img, 13, 4, _shade(head, 0.8))
    return img


def farmland_top(rng):
    img = _noise(rng, (92, 62, 40), 0.08)
    for y in range(TILE):
        if y % 4 in (0, 1):                      # ploughed furrows
            for x in range(TILE):
                img.putpixel((x, y), _shade((66, 44, 28), 1 + rng.uniform(-0.08, 0.08)))
    return img


def crop(stage, leaf, fruit=None, carrot=False):
    """A crop at a growth stage. Ripe: grain ears, or `fruit` (a colour) showing: low at the
    soil (carrot=True: roots and tubers) or as round fruit among the leaves."""
    def gen(rng):
        img = _blank()
        height = 4 + stage * 3
        ripe = stage == 3
        grain = fruit is None and not carrot
        for col in (2, 5, 8, 11, 14):
            top = TILE - height - rng.randrange(0, 2)
            for y in range(top, TILE):
                c = leaf if not (ripe and grain) else _mix(leaf, (214, 178, 70), 0.85)
                _px(img, col, y, _shade(c, 1 + rng.uniform(-0.12, 0.08)))
                if y % 3 == 0:
                    _px(img, col + (1 if y % 2 else -1), y, _shade(c, 0.85))
            if ripe and grain:                   # ears of grain
                for y in range(top, top + 4):
                    _px(img, col, y, _shade((232, 196, 90), 1 + rng.uniform(-0.1, 0.1)))
                    _px(img, col + 1, y + 1, _shade((210, 170, 70), 1))
            if ripe and carrot:                  # tops peeking out of the soil
                tone = fruit or (230, 120, 30)
                _px(img, col, TILE - 1, tone)
                _px(img, col, TILE - 2, _shade(tone, 1.08))
        if ripe and fruit is not None and not carrot:   # round fruit among the leaves
            for cx, cy in ((4, 11), (11, 12)):
                for dx in range(-2, 3):
                    for dy in range(-2, 3):
                        if dx * dx + dy * dy <= 5:
                            _px(img, cx + dx, cy + dy, _shade(fruit, 1 + rng.uniform(-0.1, 0.05) - 0.05 * dy))
        return img
    return gen


def seeds(rng):
    img = _blank()
    for _ in range(9):
        x, y = rng.randrange(3, 13), rng.randrange(4, 13)
        _px(img, x, y, _shade((120, 150, 60), 1 + rng.uniform(-0.15, 0.15)))
        _px(img, x + 1, y, _shade((90, 120, 40), 1))
    return img


def wheat(rng):
    img = _blank()
    for i, col in enumerate((5, 8, 11)):
        for y in range(6, 15):
            _px(img, col + (y - 10) // 4 * (i - 1), y, (190, 160, 70))
        for y in range(1, 7):
            _px(img, col, y, _shade((236, 200, 96), 1 + rng.uniform(-0.1, 0.1)))
            _px(img, col + (1 if y % 2 else -1), y, _shade((214, 178, 76), 1))
    return img


def bread(rng):
    img = _blank()
    for x in range(TILE):
        for y in range(TILE):
            d = ((x - 8) / 7.0) ** 2 + ((y - 9) / 4.0) ** 2
            if d < 1:
                c = (200, 140, 70) if y > 8 else (170, 106, 44)
                _px(img, x, y, _shade(c, 1 + rng.uniform(-0.08, 0.08)))
    for x in (4, 7, 10):                         # scored crust
        _px(img, x, 7, (230, 190, 120))
        _px(img, x + 1, 6, (230, 190, 120))
    return img


def carrot(rng):
    img = _blank()
    for i in range(10):
        w = max(1, 3 - i // 4)
        for k in range(w):
            _px(img, 3 + i + k, 12 - i + k, _shade((236, 120, 30), 1 + rng.uniform(-0.1, 0.1)))
    for x, y in ((12, 3), (13, 2), (14, 3), (12, 1), (11, 2)):
        _px(img, x, y, (70, 150, 50))
    return img


def wood_door(planks, frame):
    def gen_door(top):
        def gen(rng):
            img = boards(planks)(rng)
            for i in range(TILE):
                for j in (0, 1, TILE - 2, TILE - 1):
                    _px(img, j, i, frame)
            if top:
                for x in range(4, 12):
                    for y in range(4, 11):
                        img.putpixel((x, y), (0, 0, 0, 0))
            else:
                _px(img, 12, 2, (210, 200, 120))
                _px(img, 12, 3, (210, 200, 120))
            return img
        return gen
    return gen_door


for _metal, _head in METALS.items():
    EXTRA_GENERATORS[f"{_metal}_hoe"] = (lambda h: lambda rng: _hoe(rng, h))(_head)
def _round_item(colour, spots=None, flat=False):
    def gen(rng):
        img = _blank()
        for x in range(TILE):
            for y in range(TILE):
                dx, dy = (x - 7.5) / (6.5 if not flat else 6.5), (y - 8.5) / (5.5 if not flat else 3.5)
                if dx * dx + dy * dy <= 1:
                    _px(img, x, y, _shade(colour, 1.1 - 0.25 * (dy + 1) / 2 + rng.uniform(-0.05, 0.05)))
        for _ in range(spots or 0):
            _px(img, rng.randrange(5, 11), rng.randrange(5, 12), _shade(colour, 0.7))
        return img
    return gen


def _seed_item(colour):
    def gen(rng):
        img = _blank()
        for _ in range(7):
            x, y = rng.randrange(3, 12), rng.randrange(4, 13)
            _px(img, x, y, colour)
            _px(img, x + 1, y, _shade(colour, 0.8))
        return img
    return gen


def pumpkin_pie(rng):
    img = _blank()
    for x in range(2, 14):
        for y in range(7, 13):
            c = (200, 140, 70) if y in (7, 12) or x in (2, 13) else (226, 132, 40)
            _px(img, x, y, _shade(c, 1 + rng.uniform(-0.06, 0.06)))
    return img


def melon_slice(rng):
    img = _blank()
    for x in range(2, 14):
        for y in range(6, 13):
            if (x - 8) ** 2 / 36 + (y - 12) ** 2 / 36 <= 1:
                rim = (x - 8) ** 2 / 36 + (y - 12) ** 2 / 36 > 0.7
                _px(img, x, y, (70, 150, 50) if rim else (230, 70, 70))
    for x, y in ((6, 10), (9, 9), (11, 11)):
        _px(img, x, y, (30, 20, 20))
    return img


EXTRA_GENERATORS.update({"farmland_top": farmland_top, "seeds": seeds, "wheat": wheat, "bread": bread,
                         "carrot": carrot, "potato": _round_item((196, 160, 96), 4),
                         "baked_potato": _round_item((214, 160, 70), 3), "beetroot": _round_item((150, 30, 56)),
                         "pumpkin": _round_item((230, 130, 30), 0, True), "pumpkin_pie": pumpkin_pie,
                         "melon_slice": melon_slice, "beet_seeds": _seed_item((140, 60, 60)),
                         "pumpkin_seeds": _seed_item((230, 220, 170)), "melon_seeds": _seed_item((40, 34, 30))})
for _stage in range(4):
    EXTRA_GENERATORS[f"wheat_{_stage}"] = crop(_stage, (80, 160, 50))
    EXTRA_GENERATORS[f"carrots_{_stage}"] = crop(_stage, (60, 150, 46), carrot=True)
    EXTRA_GENERATORS[f"potatoes_{_stage}"] = crop(_stage, (70, 140, 60), (200, 170, 100), carrot=True)
    EXTRA_GENERATORS[f"beetroots_{_stage}"] = crop(_stage, (60, 130, 50), (150, 30, 50), carrot=True)
    EXTRA_GENERATORS[f"pumpkins_{_stage}"] = crop(_stage, (70, 140, 50), (230, 130, 30))
    EXTRA_GENERATORS[f"melons_{_stage}"] = crop(_stage, (60, 140, 50), (90, 170, 60))
for _sp, _cols in WOOD_COLORS.items():
    _wd = wood_door(_cols[4], _shade(_cols[4], 0.65))
    EXTRA_GENERATORS[f"{_sp}_door_top"] = _wd(True)
    EXTRA_GENERATORS[f"{_sp}_door_bottom"] = _wd(False)
_wd = wood_door((196, 186, 150), (150, 140, 110))          # birch
EXTRA_GENERATORS["birch_door_top"], EXTRA_GENERATORS["birch_door_bottom"] = _wd(True), _wd(False)
_wd = wood_door((120, 84, 50), (78, 54, 30))               # pine
EXTRA_GENERATORS["pine_door_top"], EXTRA_GENERATORS["pine_door_bottom"] = _wd(True), _wd(False)


# ================================================================ neon letters
FONT_5X7 = {   # rows top to bottom, 5 columns each
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}


def neon_letter(letter, rgb):
    """A dark tile with a glowing tube letter: 5x7 font at 2 px per dot, with a soft halo."""
    def gen(rng):
        img = Image.new("RGB", (TILE, TILE), (16, 14, 22))
        dots = [(c, r) for r, row in enumerate(FONT_5X7[letter]) for c, ch in enumerate(row) if ch == "1"]
        lit = set()
        for c, r in dots:
            for dx in (0, 1):
                for dy in (0, 1):
                    lit.add((3 + c * 2 + dx, 1 + r * 2 + dy))
        halo = _mix((16, 14, 22), rgb, 0.35)
        for x, y in lit:
            for hx in (-1, 0, 1):
                for hy in (-1, 0, 1):
                    if (x + hx, y + hy) not in lit and 0 <= x + hx < TILE and 0 <= y + hy < TILE:
                        img.putpixel((x + hx, y + hy), halo)
        for x, y in lit:
            core = _mix(rgb, (255, 255, 255), 0.45) if (x + y) % 2 == 0 else rgb
            img.putpixel((x, y), core)
        for i in range(TILE):                     # thin frame
            for x, y in ((i, 0), (i, TILE - 1), (0, i), (TILE - 1, i)):
                img.putpixel((x, y), (40, 36, 50))
        return img
    return gen


for (_cname, _letter), _id in __import__("blocks").NEON.items():
    EXTRA_GENERATORS[f"neon_{_cname}_{_letter}"] = neon_letter(_letter, dict(__import__("blocks").NEON_COLORS)[_cname])


# ================================================================ animal items
def egg(rng):
    img = _blank()
    for x in range(TILE):
        for y in range(TILE):
            d = ((x - 7.5) / 4.6) ** 2 + ((y - 8.5) / (6.2 if y < 9 else 5.4)) ** 2
            if d < 1:
                shine = 1.12 if (x - 6) ** 2 + (y - 6) ** 2 < 4 else (0.84 if d > 0.7 and x > 8 else 1.0)
                _px(img, x, y, _shade((236, 222, 196), shine * (1 + rng.uniform(-0.03, 0.03))))
    for _ in range(4):                            # a few freckles
        _px(img, rng.randrange(5, 11), rng.randrange(6, 13), (196, 170, 132))
    return img


def feather(rng):
    img = _blank()
    for i in range(12):                           # the quill runs from bottom left to top right
        x, y = 3 + i, 13 - i
        _px(img, x, y, (226, 220, 206))
        if i > 1:
            w = 3 if 3 < i < 10 else 2
            for k in range(1, w + 1):
                _px(img, x - k, y - k, _shade((246, 244, 238), 1 - 0.04 * k + rng.uniform(-0.04, 0.04)))
                _px(img, x + k, y + k, _shade((214, 210, 200), 1 - 0.04 * k + rng.uniform(-0.04, 0.04)))
    _px(img, 2, 14, (150, 130, 100))
    return img


def raw_fish(rng):
    img = _blank()
    for x in range(1, 12):
        half = 4 - abs(x - 6) * 0.55
        for y in range(TILE):
            if abs(y - 8) < half:
                c = (150, 170, 186) if y < 8 else (214, 222, 228)
                _px(img, x, y, _shade(c, 1 + rng.uniform(-0.06, 0.06)))
    for x in range(11, 15):                        # tail
        for y in range(8 - (x - 10), 9 + (x - 10)):
            _px(img, x, y, (120, 140, 158))
    _px(img, 3, 7, (20, 20, 24))                   # eye
    for x in (5, 7, 9):
        _px(img, x, 6, (122, 146, 164))
    return img


def cooked_fish(rng):
    img = raw_fish(rng)
    for x in range(TILE):
        for y in range(TILE):
            r, g, b, a = img.getpixel((x, y))
            if a and (r, g, b) != (20, 20, 24):
                img.putpixel((x, y), _shade((196, 132, 66) if y < 8 else (226, 176, 104),
                                            (r + g + b) / 3 / 170 + rng.uniform(-0.05, 0.05)) + (255,))
    for x in (4, 7, 10):                           # grill marks
        _px(img, x, 8, (110, 64, 30))
        _px(img, x + 1, 7, (110, 64, 30))
    return img


# ================================================================ machines and logic
METAL = (118, 122, 132)
COPPER = (206, 116, 66)


def _plate(base=METAL, rivets=True):
    def gen(rng):
        img = _noise(rng, base, 0.05).convert("RGBA")
        for i in range(TILE):
            for x, y in ((i, 0), (i, TILE - 1), (0, i), (TILE - 1, i)):
                img.putpixel((x, y), _shade(base, 0.6) + (255,))
        if rivets:
            for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
                img.putpixel((x, y), _shade(base, 1.35) + (255,))
        return img
    return gen


def _arrow_on(img, color, rotate=0):
    """A chunky arrow pointing up (towards -y of the tile), then rotated by 90 * rotate degrees."""
    a = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    for y in range(3, 8):
        for x in range(8 - (y - 3) - 1, 8 + (y - 3) + 1):
            a.putpixel((x, y), color + (255,))
    for y in range(8, 13):
        for x in (7, 8):
            a.putpixel((x, y), color + (255,))
    a = a.rotate(-90 * rotate)
    img.alpha_composite(a)
    return img


def wire(on, strength=3):
    """Glittering red dust: dark when no power runs through it, brighter the stronger the signal."""
    def gen(rng):
        img = _blank()
        base = {1: (160, 22, 16), 2: (205, 30, 22), 3: (255, 40, 28)}[strength] if on else (104, 14, 12)
        for x in range(TILE):
            for y in range(TILE):
                k = 1 + rng.uniform(-0.25, 0.2)
                _px(img, x, y, _shade(base, k))
        sparks = (6 + 6 * strength) if on else 6
        for _ in range(sparks):
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            _px(img, x, y, (255, 170, 150) if on else (140, 30, 26))
        return img
    return gen


def switch(on):
    def gen(rng):
        img = _plate((110, 110, 116))(rng)
        for y in range(3, 13):
            for x in range(5, 11):
                img.putpixel((x, y), (40, 40, 44, 255))
        lever_y = range(3, 8) if on else range(8, 13)
        for y in lever_y:
            for x in (7, 8):
                img.putpixel((x, y), (120, 86, 48, 255))
        knob = (60, 220, 90) if on else (220, 60, 50)
        for x in (6, 7, 8, 9):
            img.putpixel((x, 3 if on else 12), knob + (255,))
        return img
    return gen


def button_top(rng):
    img = _plate((126, 126, 130))(rng)
    for x in range(5, 11):
        for y in range(5, 11):
            img.putpixel((x, y), _shade((200, 60, 50), 1.1 if (x + y) % 4 else 0.9) + (255,))
    return img


def power_cell(rng):
    """A block of packed red power crystal: always gives power, glowing seams."""
    img = _blank()
    for x in range(TILE):
        for y in range(TILE):
            seam = x in (0, 15) or y in (0, 15) or (x + 2 * y) % 7 == 0
            c = (230, 60, 40) if seam else (150, 24, 20)
            _px(img, x, y, _shade(c, 1 + rng.uniform(-0.15, 0.15)))
    for _ in range(10):
        _px(img, rng.randrange(1, 15), rng.randrange(1, 15), (255, 150, 120))
    return img


def power_cell_top(rng):
    return power_cell(rng)


def pressure_plate(rng):
    img = _noise(rng, (150, 150, 154), 0.06).convert("RGBA")
    for i in range(2, 14):
        for x, y in ((i, 2), (i, 13), (2, i), (13, i)):
            img.putpixel((x, y), (100, 100, 108, 255))
    return img


def light_sensor(rng):
    """Blue glass panes in a wooden frame, catching the daylight."""
    img = _blank()
    for x in range(TILE):
        for y in range(TILE):
            if x in (0, 15) or y in (0, 15) or x in (7, 8) or y in (7, 8):
                _px(img, x, y, _shade((150, 110, 66), 1 + rng.uniform(-0.1, 0.1)))
            else:
                shine = 1.25 if (x + y) % 9 == 0 else 1.0
                _px(img, x, y, _shade((70, 110, 170), shine + rng.uniform(-0.08, 0.08)))
    return img


def powered_lamp(on):
    """A lamp of glowing cells in a dark frame: dim amber when off, bright warm light when on."""
    def gen(rng):
        img = _blank()
        frame = (70, 44, 30) if not on else (120, 74, 40)
        for x in range(TILE):
            for y in range(TILE):
                if x in (0, 15) or y in (0, 15) or x in (5, 10) or y in (5, 10):
                    _px(img, x, y, _shade(frame, 1 + rng.uniform(-0.1, 0.1)))
                else:
                    c = (255, 222, 130) if on else (130, 88, 50)
                    _px(img, x, y, _shade(c, 1 + rng.uniform(-0.12, 0.12)))
        return img
    return gen


GATE_SYMBOLS = {   # 5x5 symbols drawn at 1 px
    "not": ["01110", "10001", "10001", "10001", "01110"],
    "and": ["10001", "10001", "10001", "01010", "00100"],
    "or": ["00100", "01010", "10001", "10001", "10001"],
    "xor": ["10001", "01010", "00100", "01010", "10001"],
    "delay": ["11111", "00100", "00100", "00100", "11111"],
    "comparator": ["11000", "00110", "00001", "00110", "11111"],
}
GATE_COLORS = {"not": (230, 80, 80), "and": (90, 200, 255), "or": (120, 230, 120), "xor": (240, 200, 60),
               "delay": (210, 140, 255), "comparator": (255, 150, 60)}


def smooth_stone(rng):
    """Light smooth stone with a thin darker rim: the chip gates sit on."""
    img = _noise(rng, (164, 164, 168), 0.04).convert("RGBA")
    for i in range(TILE):
        for x, y in ((i, 0), (i, 15), (0, i), (15, i)):
            img.putpixel((x, y), (126, 126, 130, 255))
    return img


def gate(kind, facing):
    def gen(rng):
        img = smooth_stone(rng)
        _arrow_on(img, (150, 40, 34), {0: 2, 1: 1, 2: 0, 3: 3}[facing])
        for r, row in enumerate(GATE_SYMBOLS[kind]):
            for c, ch in enumerate(row):
                if ch == "1":
                    img.putpixel((1 + c, 1 + r), GATE_COLORS[kind] + (255,))
        return img
    return gen


def machine_face(base, mark, facing=None, vertical=None):
    """A machine face with a mark: an arrow for the facing, or the working face."""
    def gen(rng):
        img = _plate(base)(rng)
        if mark == "arrow":
            _arrow_on(img, (240, 220, 120), {0: 2, 1: 1, 2: 0, 3: 3}[facing])
        elif mark == "up":
            _arrow_on(img, (240, 220, 120), 0 if vertical == "up" else 2)
        elif mark == "push":
            for x in range(2, 14):
                for y in range(2, 14):
                    img.putpixel((x, y), _shade((170, 130, 80), 1 + rng.uniform(-0.1, 0.1)) + (255,))
        elif mark == "teeth":
            for x in range(2, 14):
                for y in range(2, 14):
                    if (x + y) % 4 < 2:
                        img.putpixel((x, y), (210, 210, 220, 255))
        return img
    return gen


def conveyor(facing):
    def gen(rng):
        img = _noise(rng, (46, 46, 52), 0.05).convert("RGBA")
        for y in range(0, TILE, 4):
            for x in range(TILE):
                img.putpixel((x, y), (70, 70, 78, 255))
        _arrow_on(img, (240, 200, 60), {0: 2, 1: 1, 2: 0, 3: 3}[facing])
        return img
    return gen


def collector_top(rng):
    img = _plate((96, 100, 110))(rng)
    for x in range(3, 13):
        for y in range(3, 13):
            img.putpixel((x, y), (30, 30, 34, 255))
    return img


def _dark_stone(rng):
    img = _noise(rng, (92, 92, 96), 0.12).convert("RGBA")
    for i in range(TILE):
        for x, y in ((i, 0), (i, 15), (0, i), (15, i)):
            img.putpixel((x, y), (64, 64, 68, 255))
    return img


def smelter_front(rng, lit=False):
    """A stone furnace face with a fire window: dark and cold, or glowing while it works."""
    img = _dark_stone(rng)
    for x in range(4, 12):
        for y in range(8, 14):
            if lit:
                c = (250, 130, 30) if y > 10 else (255, 200, 70)
            else:
                c = (30, 28, 30) if y > 11 else (48, 44, 46)
            img.putpixel((x, y), _shade(c, 1 + rng.uniform(-0.2, 0.2)) + (255,))
    for x in range(4, 12):
        img.putpixel((x, 7), (40, 40, 44, 255))
    return img


def crafter_top(rng, lit=False):
    """A 3 x 3 crafting grid set in a stone frame; the slots glow while it works."""
    img = _dark_stone(rng)
    for gx in range(3):
        for gy in range(3):
            for x in range(2 + gx * 4, 5 + gx * 4):
                for y in range(2 + gy * 4, 5 + gy * 4):
                    c = (240, 190, 90) if lit and (gx + gy) % 2 == 0 else (150, 106, 62)
                    img.putpixel((x, y), _shade(c, 1 + rng.uniform(-0.1, 0.1)) + (255,))
    return img


def crafter_side(rng, lit=False):
    """Wooden boards with a small hatch: a lamp in it shines while it works."""
    img = Image.new("RGBA", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            c = (150, 108, 64) if (y // 4) % 2 else (136, 96, 56)
            if y % 4 == 0:
                c = (96, 66, 38)
            img.putpixel((x, y), _shade(c, 1 + rng.uniform(-0.08, 0.08)) + (255,))
    for x in range(5, 11):
        for y in range(5, 11):
            edge = x in (5, 10) or y in (5, 10)
            c = (70, 70, 76) if edge else ((255, 214, 110) if lit else (40, 36, 34))
            img.putpixel((x, y), c + (255,))
    return img


def _track(links, boost=None):
    """Rails on wooden sleepers. links: the two sides they lead to ((dx, dz), ...); a turn bends
    round the corner between them. boost: None, False (off) or True (on, glowing)."""
    def gen(rng):
        img = _blank()
        rail = (196, 198, 206)
        wood = (120, 84, 50)
        (ax, az), (bx, bz) = links
        straight = ax == -bx and az == -bz
        for x in range(TILE):
            for y in range(TILE):
                if straight:
                    along, across = (x, y) if ax != 0 else (y, x)   # x-links: rails run left-right
                    if along % 4 in (1, 2) and 1 <= across <= 14:   # sleepers lie across the rails
                        _px(img, x, y, _shade(wood, 1 + rng.uniform(-0.1, 0.1)))
                    if across in (3, 4, 11, 12):
                        _px(img, x, y, _shade(rail, 1 + rng.uniform(-0.05, 0.05)))
                else:
                    cx = 15.5 if (ax == 1 or bx == 1) else -0.5     # the corner the turn wraps round
                    cy = 15.5 if (az == 1 or bz == 1) else -0.5
                    d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                    import math
                    ang = math.degrees(math.atan2(abs(y - cy), abs(x - cx)))
                    if 2.5 < d < 13.5 and int(ang) % 18 < 7:     # sleepers along the radius
                        _px(img, x, y, _shade(wood, 1 + rng.uniform(-0.1, 0.1)))
                    if 3.5 <= d <= 5.0 or 11.0 <= d <= 12.5:
                        _px(img, x, y, _shade(rail, 1 + rng.uniform(-0.05, 0.05)))
        if boost is not None:                     # a gold strip down the middle, bright when on
            glow = (255, 214, 60) if boost else (150, 120, 50)
            for i in range(TILE):
                for d in (7, 8):
                    if (ax != 0 and i % 3 != 2) or (ax == 0 and i % 3 != 2):
                        _px(img, i if ax != 0 else d, d if ax != 0 else i, glow)
        return img
    return gen


def cart_icon(rng):
    """A little wooden cart on two wheels, for the item."""
    img = _blank()
    for x in range(2, 14):
        for y in range(5, 11):
            edge = x in (2, 13) or y in (5, 10)
            _px(img, x, y, (96, 66, 40) if edge else _shade((150, 108, 66), 1 + rng.uniform(-0.1, 0.1)))
    for x in range(2, 14):
        _px(img, x, 7, (170, 172, 180))                 # a metal band
    for wx in (4, 11):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                _px(img, wx + dx, 12 + dy, (60, 60, 66) if dx or dy else (150, 150, 156))
    return img


def chest_cart_icon(rng):
    """The cart with a chest sitting in it."""
    img = cart_icon(rng)
    for x in range(4, 12):
        for y in range(1, 7):
            edge = x in (4, 11) or y in (1, 6)
            _px(img, x, y, (92, 60, 30) if edge else (176, 122, 60))
    _px(img, 7, 4, (200, 200, 210))
    _px(img, 8, 4, (200, 200, 210))
    return img


def sticky_face(rng):
    """Green glue, shiny in spots."""
    img = _noise(rng, (96, 170, 72), 0.1).convert("RGBA")
    for _ in range(14):
        img.putpixel((rng.randrange(TILE), rng.randrange(TILE)), (170, 230, 140, 255))
    return img


def observer_body(rng):
    """Grey stone with a darker band round the middle."""
    img = _noise(rng, (120, 120, 124), 0.08).convert("RGBA")
    for x in range(TILE):
        for y in (6, 9):
            img.putpixel((x, y), (82, 82, 86, 255))
    return img


def observer_face(rng):
    """The watching face: two dark eye slits on grey stone."""
    img = _noise(rng, (110, 110, 114), 0.08).convert("RGBA")
    for x in list(range(2, 7)) + list(range(9, 14)):
        for y in range(6, 10):
            img.putpixel((x, y), (28, 28, 32, 255) if y in (7, 8) else (60, 60, 66, 255))
    for x in (4, 11):
        img.putpixel((x, 7), (200, 200, 210, 255))
    return img


def observer_out(on):
    def gen(rng):
        img = _noise(rng, (100, 100, 104), 0.08).convert("RGBA")
        for x in range(6, 10):
            for y in range(6, 10):
                img.putpixel((x, y), (255, 60, 40, 255) if on else (70, 20, 18, 255))
        return img
    return gen


def thrower_face(rng):
    """Stone with a dark square mouth the items come out of."""
    img = _noise(rng, (124, 124, 128), 0.08).convert("RGBA")
    for x in range(4, 12):
        for y in range(4, 12):
            edge = x in (4, 11) or y in (4, 11)
            img.putpixel((x, y), (70, 70, 74, 255) if edge else (22, 22, 24, 255))
    return img


EXTRA_GENERATORS.update({
    "thrower_body": lambda rng: _noise(rng, (124, 124, 128), 0.1).convert("RGBA"), "thrower_face": thrower_face,
    "observer_body": observer_body, "observer_face": observer_face,
    "observer_out_off": observer_out(False), "observer_out_on": observer_out(True),
    "sticky_face": sticky_face,
    "track_x": _track(((1, 0), (-1, 0))), "track_z": _track(((0, 1), (0, -1))),
    "track_c0": _track(((1, 0), (0, 1))), "track_c1": _track(((-1, 0), (0, 1))),
    "track_c2": _track(((-1, 0), (0, -1))), "track_c3": _track(((1, 0), (0, -1))),
    "boost_x_off": _track(((1, 0), (-1, 0)), False), "boost_z_off": _track(((0, 1), (0, -1)), False),
    "boost_x_on": _track(((1, 0), (-1, 0)), True), "boost_z_on": _track(((0, 1), (0, -1)), True),
    "cart": cart_icon, "chest_cart": chest_cart_icon,
    "ember_rock": ember_rock, "ember_bricks": ember_bricks, "ember_ore": ember_ore, "ash_sand": ash_sand,
    "magma": magma, "fire_portal": fire_portal, "ember_shard": ember_shard, "fire_striker": fire_striker,
    "iron_door_top": iron_door(True), "iron_door_bottom": iron_door(False), "trapdoor": trapdoor,
    "lantern": lantern, "barrel_side": barrel_side, "barrel_top": barrel_top, "tnt_side": tnt_side,
    "tnt_top": tnt_top, "tnt_bottom": tnt_top, "tnt_lit": noise_tile((250, 240, 230), 0.05), "shears": shears,
    "composter_side": composter_side, "composter_top": composter_top,
    "composter_top_full": lambda rng: composter_top(rng, True), "campfire_top": noise_tile((90, 60, 36), 0.2),
    "campfire_side": campfire_side, "anvil_top": noise_tile((70, 70, 76), 0.08),
    "anvil_side": noise_tile((56, 56, 62), 0.1), "slime_block": slime_block, "bone_meal": bone_meal,
    "slimeball": _round_item((110, 210, 90)),
    **{f"painting_{n}": painting(n) for n in range(4)}, "item_frame": item_frame, "flower_pot": flower_pot,
    "shield": shield_icon, "beehive_side": beehive_side, "beehive_top": noise_tile((220, 180, 100), 0.1),
    "scaffolding": scaffolding, "firework": firework, "honey_bottle": potion((240, 170, 30)),
    "compass": compass_icon, "map_item": map_icon, "paper": paper_icon, "enchant_top": enchant_top,
    "enchant_side": enchant_side,
    "bow": bow_icon, "arrow": arrow_icon, "boat": boat_icon, "fishing_rod": rod_icon, "saddle": saddle_icon,
    **{f"{m}_{p}": armour_icon(p, c) for m, c in (("iron", (214, 214, 220)), ("diamond", (90, 220, 225)))
       for p in ("helmet", "chestplate", "leggings", "boots")},
    "timer_face": timer_face, "timer_face_on": lambda rng: timer_face(rng, True),
    "counter_face": counter_face, "counter_face_on": lambda rng: counter_face(rng, True),
    "note_block": note_block, "fan_face": fan_face, "fan_face_on": lambda rng: fan_face(rng, True),
    "glass_bottle": potion((215, 230, 240)), "water_bottle": potion((60, 110, 210)),
    "potion_swift": potion((120, 200, 250)), "potion_heal": potion((240, 60, 80)),
    "potion_night": potion((40, 50, 160)), "potion_leap": potion((120, 230, 90)),
    "potion_fire": potion((240, 150, 40)), "potion_water": potion((40, 160, 170)),
    "brewer_top": _dark_stone, "brewer_side": brewer_side, "brewer_side_on": lambda rng: brewer_side(rng, True),
})
EXTRA_GENERATORS.update({
    "wire_off": wire(False), "wire_on": wire(True), "wire_dim": wire(True, 1), "wire_mid": wire(True, 2), "switch_off": switch(False), "switch_on": switch(True),
    "switch_side": _plate((110, 110, 116)), "button_top": button_top, "button_side": _plate((126, 126, 130)),
    "power_cell": power_cell, "power_cell_top": power_cell_top, "pressure_plate": pressure_plate,
    "light_sensor": light_sensor, "machine_side": _plate(), "machine_bottom": _plate((80, 82, 90), rivets=False),
    "powered_lamp_off": powered_lamp(False), "powered_lamp_on": powered_lamp(True),
    "gate_side": smooth_stone, "collector_top": collector_top, "collector_side": _plate((96, 100, 110)),
    "smelter_top": _dark_stone, "smelter_front": smelter_front,
    "smelter_front_on": lambda rng: smelter_front(rng, True),
    "crafter_top": crafter_top, "crafter_top_on": lambda rng: crafter_top(rng, True),
    "crafter_side": crafter_side, "crafter_side_on": lambda rng: crafter_side(rng, True),
})
for _kind in GATE_SYMBOLS:
    for _f in range(4):
        EXTRA_GENERATORS[f"gate_{_kind}_{_f}"] = gate(_kind, _f)
for _f in range(4):
    EXTRA_GENERATORS[f"conveyor_{_f}"] = conveyor(_f)
for _m, _base, _work in (("pusher", (150, 112, 70), "push"), ("breaker", (110, 110, 120), "teeth")):
    for _f in range(6):
        if _f < 4:
            EXTRA_GENERATORS[f"{_m}_top_{_f}"] = machine_face(_base, "arrow", _f)
            EXTRA_GENERATORS[f"{_m}_side_{_f}"] = machine_face(_base, None)
            EXTRA_GENERATORS[f"{_m}_bottom_{_f}"] = machine_face(_base, None)
        else:
            up = _f == 4
            EXTRA_GENERATORS[f"{_m}_top_{_f}"] = machine_face(_base, _work if up else None)
            EXTRA_GENERATORS[f"{_m}_side_{_f}"] = machine_face(_base, "up", vertical="up" if up else "down")
            EXTRA_GENERATORS[f"{_m}_bottom_{_f}"] = machine_face(_base, None if up else _work)


# ================================================================ the sky realm
def _sparkle(img, rng, colors, count):
    for _ in range(count):
        x, y = rng.randrange(1, TILE - 1), rng.randrange(1, TILE - 1)
        c = rng.choice(colors)
        img.putpixel((x, y), c + (255,) if img.mode == "RGBA" else c)


def sky_stone(rng):
    img = _noise(rng, (176, 168, 206), 0.07)
    _speckle(img, rng, (150, 140, 186), 18)
    return img


def sky_soil(rng):
    return _noise(rng, (126, 108, 150), 0.1)


def sky_grass_top(rng):
    img = _noise(rng, (86, 206, 196), 0.1)
    _speckle(img, rng, (140, 236, 220), 14)
    return img


def sky_grass_side(rng):
    img = sky_soil(rng)
    for x in range(TILE):
        for y in range(0, 3 + (x * 7 % 3)):
            img.putpixel((x, y), _shade((86, 206, 196), 1 + rng.uniform(-0.08, 0.08)))
    return img


def cloud(rng):
    img = _noise(rng, (240, 242, 250), 0.03)
    _speckle(img, rng, (224, 228, 242), 20)
    return img


def star_ore(rng):
    img = sky_stone(rng)
    for _ in range(5):
        cx, cy = rng.randrange(3, 13), rng.randrange(3, 13)
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            img.putpixel((cx + dx, cy + dy), (255, 236, 140) if (dx, dy) == (0, 0) else (240, 200, 90))
    return img


def star_block(rng):
    img = _noise(rng, (60, 50, 110), 0.08)
    for _ in range(14):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        img.putpixel((x, y), (255, 240, 160))
    return img


def portal(rng):
    img = Image.new("RGBA", (TILE, TILE))
    for x in range(TILE):
        for y in range(TILE):
            v = 0.5 + 0.5 * math.sin((x + y) * 0.7 + rng.uniform(-0.6, 0.6))
            img.putpixel((x, y), (int(120 + 80 * v), int(50 + 40 * v), int(200 + 50 * v), 170))
    return img


def storm_crystal(rng):
    img = _noise(rng, (60, 110, 200), 0.06).convert("RGBA")
    for i in range(TILE):
        for x in (i, TILE - 1 - i):
            img.putpixel((x, i), (200, 240, 255, 255))
    return img


def pillar_stone(rng):
    img = _noise(rng, (40, 34, 56), 0.08)
    for y in range(0, TILE, 5):
        for x in range(TILE):
            img.putpixel((x, y), (28, 24, 40))
    return img


def storm_heart(rng):
    img = _noise(rng, (30, 40, 80), 0.06).convert("RGBA")
    for x in range(TILE):
        for y in range(TILE):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d < 6:
                img.putpixel((x, y), _shade((120, 220, 255), 1.3 - d / 7) + (255,))
    return img


def star_shard(rng):
    img = _blank()
    pts = [(8, 1), (10, 6), (15, 7), (11, 10), (12, 15), (8, 12), (4, 15), (5, 10), (1, 7), (6, 6)]
    from PIL import ImageDraw
    ImageDraw.Draw(img).polygon(pts, fill=(255, 226, 120, 255), outline=(200, 150, 40, 255))
    return img


def sky_key(rng):
    img = _blank()
    for x in range(3, 9):
        for y in range(3, 9):
            if 4 <= ((x - 5.5) ** 2 + (y - 5.5) ** 2) <= 9:
                _px(img, x, y, (170, 110, 230))
    for i in range(7):
        _px(img, 8 + i, 8 + i, (220, 200, 120))
    _px(img, 12, 14, (220, 200, 120))
    _px(img, 14, 12, (220, 200, 120))
    _px(img, 5, 5, (255, 240, 160))
    return img


def storm_core(rng):
    img = _blank()
    for x in range(TILE):
        for y in range(TILE):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d < 6.5:
                _px(img, x, y, _shade((90, 180, 255), 1.4 - d / 6))
    for x, y in ((7, 3), (8, 5), (7, 7), (8, 9), (7, 11)):
        _px(img, x, y, (255, 255, 200))
    return img


EXTRA_GENERATORS.update({
    "sky_stone": sky_stone, "sky_soil": sky_soil, "sky_grass_top": sky_grass_top, "sky_grass_side": sky_grass_side,
    "cloud": cloud, "star_ore": star_ore, "star_block": star_block, "portal": portal, "storm_crystal": storm_crystal,
    "pillar_stone": pillar_stone, "storm_heart": storm_heart, "star_shard": star_shard, "sky_key": sky_key,
    "storm_core": storm_core,
})


GENERATORS = {name: EXTRA_GENERATORS.get(name) or globals()[name] for name in TILES}


def generate_atlas(seed=1234):
    rows = -(-len(TILES) // ATLAS_COLS)
    atlas = Image.new("RGBA", (ATLAS_COLS * TILE, max(rows, ATLAS_COLS) * TILE), (255, 0, 255, 255))
    for index, name in enumerate(TILES):
        tile = GENERATORS[name](random.Random(seed + index))
        atlas.paste(tile.convert("RGBA"), ((index % ATLAS_COLS) * TILE, (index // ATLAS_COLS) * TILE))
    return atlas


def load_atlas():
    """Use textures/atlas.png if the player made one, otherwise generate the default."""
    if CUSTOM_ATLAS.exists():
        return Image.open(CUSTOM_ATLAS).convert("RGBA")
    return generate_atlas()


def tile_image(atlas, name):
    size = atlas.width // ATLAS_COLS
    index = TILES.index(name)
    x, y = (index % ATLAS_COLS) * size, (index // ATLAS_COLS) * size
    return atlas.crop((x, y, x + size, y + size))


if __name__ == "__main__":
    CUSTOM_ATLAS.parent.mkdir(exist_ok=True)
    generate_atlas().save(CUSTOM_ATLAS)
    print(f"Wrote {CUSTOM_ATLAS}")
