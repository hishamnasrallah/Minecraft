"""Procedural pixel-art textures packed into a single atlas image.

Run `python textures.py` to export the atlas to textures/atlas.png. Edit that
file in any image editor (keep the grid layout from world.TILES) and the
game will use your version instead of the generated one.
"""
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
            _px(img, x, 6, (60, 110, 210))
            _px(img, x, 7, (50, 96, 196))
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
    def gen(rng):
        img = _blank()
        height = 4 + stage * 3
        ripe = stage == 3
        for col in (2, 5, 8, 11, 14):
            top = TILE - height - rng.randrange(0, 2)
            for y in range(top, TILE):
                c = leaf if not (ripe and not carrot) else _mix(leaf, (214, 178, 70), 0.85)
                _px(img, col, y, _shade(c, 1 + rng.uniform(-0.12, 0.08)))
                if y % 3 == 0:
                    _px(img, col + (1 if y % 2 else -1), y, _shade(c, 0.85))
            if ripe and not carrot:              # ears of grain
                for y in range(top, top + 4):
                    _px(img, col, y, _shade((232, 196, 90), 1 + rng.uniform(-0.1, 0.1)))
                    _px(img, col + 1, y + 1, _shade((210, 170, 70), 1))
            if ripe and carrot:                  # orange tops peeking out of the soil
                _px(img, col, TILE - 1, (230, 120, 30))
                _px(img, col, TILE - 2, (240, 136, 40))
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
EXTRA_GENERATORS.update({"farmland_top": farmland_top, "seeds": seeds, "wheat": wheat, "bread": bread,
                         "carrot": carrot})
for _stage in range(4):
    EXTRA_GENERATORS[f"wheat_{_stage}"] = crop(_stage, (80, 160, 50))
    EXTRA_GENERATORS[f"carrots_{_stage}"] = crop(_stage, (60, 150, 46), carrot=True)
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
