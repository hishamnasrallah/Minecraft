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
