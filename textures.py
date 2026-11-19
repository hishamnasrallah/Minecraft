"""Procedural pixel-art textures packed into a single atlas image.

Run `python textures.py` to export the atlas to textures/atlas.png. Edit that
file in any image editor (keep the 4x4 grid layout from world.TILES) and the
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


GENERATORS = {name: globals()[name] for name in TILES}


def generate_atlas(seed=1234):
    rows = -(-len(TILES) // ATLAS_COLS)
    atlas = Image.new("RGBA", (ATLAS_COLS * TILE, max(rows, ATLAS_COLS) * TILE), (255, 0, 255, 255))
    for index, name in enumerate(TILES):
        tile = GENERATORS[name](random.Random(seed + index))
        atlas.paste(tile, ((index % ATLAS_COLS) * TILE, (index // ATLAS_COLS) * TILE))
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
