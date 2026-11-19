"""Procedural pixel-art textures packed into a single atlas image.

Run `python textures.py` to export the atlas to textures/atlas.png. Edit that
file in any image editor (keep the 5x5 grid layout from world.TILES) and the
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


GENERATORS = {name: globals()[name] for name in TILES}


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
