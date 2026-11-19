"""Button icons for the phone UI, drawn as white shapes on transparent PNGs.

Drawn on a 256px canvas and scaled down to 64px for smooth edges. Exported to
godot/data/ui/ by tools/export_godot.py.
"""
import math

from PIL import Image, ImageDraw

S = 256          # drawing size
OUT = 64         # final size
W = (255, 255, 255, 255)
LINE = 22


def _canvas():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _arrow(d, up=True, y0=40, y1=216, width=LINE):
    tip = y0 if up else y1
    tail = y1 if up else y0
    d.line([(128, tail), (128, tip + (10 if up else -10))], fill=W, width=width)
    head = 60 if up else -60
    d.polygon([(128, tip), (128 - 60, tip + head), (128 + 60, tip + head)], fill=W)


def jump():
    img, d = _canvas()
    for y in (70, 140):
        d.line([(60, y + 50), (128, y), (196, y + 50)], fill=W, width=LINE, joint="curve")
    d.rectangle([60, 214, 196, 226], fill=W)
    return img


def up():
    img, d = _canvas()
    _arrow(d, True)
    return img


def down():
    img, d = _canvas()
    _arrow(d, False)
    return img


def pickaxe():
    img, d = _canvas()
    d.line([(52, 226), (150, 64)], fill=W, width=26)               # handle up to the middle of the head
    d.arc([30, 40, 250, 260], start=205, end=335, fill=W, width=34)  # curved head across the top
    return img


def place():
    img, d = _canvas()
    _cube(d, 30, 70, 150)
    d.line([(196, 20), (196, 100)], fill=W, width=LINE)
    d.line([(156, 60), (236, 60)], fill=W, width=LINE)
    return img


def _cube(d, x, y, s, filled=False):
    """Isometric-ish cube outline with top-left corner (x, y) and size s."""
    o = s // 3
    front = [(x, y + o), (x + s - o, y + o), (x + s - o, y + s), (x, y + s)]
    top = [(x, y + o), (x + o, y), (x + s, y), (x + s - o, y + o)]
    side = [(x + s - o, y + o), (x + s, y), (x + s, y + s - o), (x + s - o, y + s)]
    if filled:
        for poly in (front, top, side):
            d.polygon(poly, fill=W)
        d.line(front + [front[0]], fill=(0, 0, 0, 0), width=6)
    for poly in (front, top, side):
        d.line(poly + [poly[0]], fill=W, width=14, joint="curve")


def bag():
    """Inventory: a grid of slots."""
    img, d = _canvas()
    for r in range(3):
        for c in range(3):
            x, y = 34 + c * 66, 34 + r * 66
            d.rounded_rectangle([x, y, x + 54, y + 54], radius=10, fill=W if (r, c) != (1, 1) else None,
                                outline=W, width=10)
    return img


def wing():
    img, d = _canvas()
    for i, r in enumerate((150, 115, 80)):
        d.arc([128 - r, 128 - r + 40, 128 + r, 128 + r + 40], start=200, end=330, fill=W, width=20)
    d.line([(40, 200), (216, 120)], fill=W, width=LINE)
    return img


def hammer():
    img, d = _canvas()
    d.line([(80, 210), (160, 110)], fill=W, width=24)
    d.polygon([(110, 60), (190, 40), (226, 110), (150, 130)], fill=W)
    return img


def floppy():
    img, d = _canvas()
    d.polygon([(40, 40), (180, 40), (216, 76), (216, 216), (40, 216)], outline=W, width=LINE)
    d.rectangle([80, 40, 170, 100], fill=W)
    d.rectangle([76, 140, 180, 216], outline=W, width=16)
    return img


def gear():
    img, d = _canvas()
    for i in range(8):
        a = i * math.pi / 4
        d.line([(128 + 60 * math.cos(a), 128 + 60 * math.sin(a)), (128 + 108 * math.cos(a), 128 + 108 * math.sin(a))],
               fill=W, width=34)
    d.ellipse([48, 48, 208, 208], fill=W)
    d.ellipse([98, 98, 158, 158], fill=(0, 0, 0, 0))
    return img


def cross():
    img, d = _canvas()
    d.line([(60, 60), (196, 196)], fill=W, width=28)
    d.line([(196, 60), (60, 196)], fill=W, width=28)
    return img


def half():
    img, d = _canvas()
    d.rectangle([50, 50, 206, 206], outline=W, width=LINE)
    d.rectangle([50, 128, 206, 206], fill=W)
    return img


def bolt():
    img, d = _canvas()
    d.polygon([(150, 20), (60, 140), (120, 140), (96, 236), (196, 104), (136, 104), (170, 20)], fill=W)
    return img


def trash():
    img, d = _canvas()
    d.line([(40, 60), (216, 60)], fill=W, width=LINE)
    d.rectangle([100, 30, 156, 60], outline=W, width=14)
    d.polygon([(64, 80), (192, 80), (176, 226), (80, 226)], outline=W, width=LINE)
    for x in (108, 148):
        d.line([(x, 106), (x, 200)], fill=W, width=12)
    return img


def eraser():
    img, d = _canvas()
    d.polygon([(40, 160), (140, 60), (216, 136), (116, 236)], outline=W, width=LINE)
    d.polygon([(40, 160), (90, 110), (166, 186), (116, 236)], fill=W)
    return img


def sun(rays=True, horizon=False, moon_shape=False):
    img, d = _canvas()
    if moon_shape:
        d.ellipse([50, 40, 210, 200], fill=W)
        d.ellipse([90, 20, 240, 170], fill=(0, 0, 0, 0))
        return img
    cy = 170 if horizon else 128
    d.ellipse([78, cy - 50, 178, cy + 50], fill=W)
    if rays:
        for i in range(8):
            a = i * math.pi / 4
            if horizon and math.sin(a) > 0.1:
                continue
            d.line([(128 + 70 * math.cos(a), cy + 70 * math.sin(a)), (128 + 106 * math.cos(a), cy + 106 * math.sin(a))],
                   fill=W, width=16)
    if horizon:
        d.rectangle([20, cy, 236, 256], fill=(0, 0, 0, 0))
        d.line([(20, cy), (236, cy)], fill=W, width=16)
    return img


def sunrise():
    img = sun(horizon=True)
    d = ImageDraw.Draw(img)
    _small_arrow(d, up=True)
    return img


def sunset():
    img = sun(horizon=True)
    d = ImageDraw.Draw(img)
    _small_arrow(d, up=False)
    return img


def _small_arrow(d, up):
    """A clear up / down arrow over the sun."""
    if up:
        d.polygon([(128, 4), (88, 50), (168, 50)], fill=W)
    else:
        d.polygon([(128, 56), (88, 10), (168, 10)], fill=W)


def noon():
    return sun()


def moon():
    return sun(moon_shape=True)


def pause():
    img, d = _canvas()
    d.rectangle([66, 50, 110, 206], fill=W)
    d.rectangle([146, 50, 190, 206], fill=W)
    return img


def corner(n):
    def draw():
        img, d = _canvas()
        d.line([(40, 216), (40, 40), (216, 40)], fill=W, width=LINE, joint="curve")
        d.ellipse([20, 20, 60, 60], fill=W)
        _digit(d, n, 120, 90)
        return img
    return draw


def _digit(d, n, x, y):
    """A chunky 1 or 2 without needing a font."""
    if n == 1:
        d.line([(x + 40, y), (x + 40, y + 130)], fill=W, width=24)
        d.line([(x + 10, y + 30), (x + 40, y)], fill=W, width=20)
    else:
        d.arc([x, y, x + 80, y + 70], start=180, end=40, fill=W, width=20)
        d.line([(x + 72, y + 52), (x, y + 130)], fill=W, width=20)
        d.line([(x, y + 130), (x + 84, y + 130)], fill=W, width=20)


def fill_box():
    img, d = _canvas()
    _cube(d, 34, 34, 188, filled=True)
    return img


def hollow_box():
    img, d = _canvas()
    _cube(d, 34, 34, 188)
    return img


def swap():
    img, d = _canvas()
    d.arc([40, 40, 216, 216], start=200, end=340, fill=W, width=LINE)
    d.polygon([(196, 70), (236, 110), (176, 120)], fill=W)
    d.arc([40, 40, 216, 216], start=20, end=160, fill=W, width=LINE)
    d.polygon([(60, 186), (20, 146), (80, 136)], fill=W)
    return img


def copy():
    img, d = _canvas()
    d.rounded_rectangle([30, 30, 160, 160], radius=16, outline=W, width=LINE)
    d.rounded_rectangle([96, 96, 226, 226], radius=16, fill=W)
    return img


def clipboard():
    img, d = _canvas()
    d.rounded_rectangle([50, 50, 206, 236], radius=16, outline=W, width=LINE)
    d.rounded_rectangle([90, 26, 166, 74], radius=10, fill=W)
    for y in (120, 160, 200):
        d.line([(86, y), (170, y)], fill=W, width=12)
    return img


def rotate():
    img, d = _canvas()
    d.arc([40, 40, 216, 216], start=-60, end=230, fill=W, width=LINE)
    d.polygon([(190, 40), (230, 110), (160, 100)], fill=W)
    return img


def mirror():
    img, d = _canvas()
    d.polygon([(108, 50), (108, 206), (30, 206)], fill=W)
    d.polygon([(148, 50), (148, 206), (226, 206)], outline=W, width=14)
    for y in range(20, 240, 36):
        d.line([(128, y), (128, y + 18)], fill=W, width=8)
    return img


def undo():
    img, d = _canvas()
    d.arc([60, 60, 230, 230], start=180, end=90, fill=W, width=LINE)
    d.polygon([(20, 150), (100, 150), (60, 90)], fill=W)
    return img


def deselect():
    img, d = _canvas()
    for i in range(0, 176, 44):
        d.line([(40 + i, 40), (40 + i + 22, 40)], fill=W, width=14)
        d.line([(40 + i, 216), (40 + i + 22, 216)], fill=W, width=14)
        d.line([(40, 40 + i), (40, 40 + i + 22)], fill=W, width=14)
        d.line([(216, 40 + i), (216, 40 + i + 22)], fill=W, width=14)
    d.line([(90, 90), (166, 166)], fill=W, width=18)
    d.line([(166, 90), (90, 166)], fill=W, width=18)
    return img


def book():
    img, d = _canvas()
    d.polygon([(128, 70), (30, 40), (30, 200), (128, 230)], outline=W, width=18)
    d.polygon([(128, 70), (226, 40), (226, 200), (128, 230)], fill=W)
    return img


def globe():
    img, d = _canvas()
    d.ellipse([30, 30, 226, 226], outline=W, width=18)
    d.ellipse([88, 30, 168, 226], outline=W, width=14)
    d.line([(30, 128), (226, 128)], fill=W, width=14)
    d.line([(50, 80), (206, 80)], fill=W, width=10)
    d.line([(50, 176), (206, 176)], fill=W, width=10)
    return img


def star():
    img, d = _canvas()
    pts = []
    for k in range(10):
        r = 112 if k % 2 == 0 else 46
        a = -math.pi / 2 + k * math.pi / 5
        pts.append((128 + r * math.cos(a), 136 + r * math.sin(a)))
    d.polygon(pts, fill=W)
    return img


def clock():
    img, d = _canvas()
    d.ellipse([30, 30, 226, 226], outline=W, width=20)
    d.line([(128, 128), (128, 66)], fill=W, width=20)
    d.line([(128, 128), (174, 156)], fill=W, width=20)
    return img


def sort():
    img, d = _canvas()
    for i, w in enumerate((176, 128, 80)):
        y = 60 + i * 64
        d.rounded_rectangle([40, y, 40 + w, y + 30], radius=10, fill=W)
    _small = [(196, 60), (196, 196)]
    d.line(_small, fill=W, width=16)
    d.polygon([(196, 220), (166, 176), (226, 176)], fill=W)
    return img


def grid():
    img, d = _canvas()
    for x in (40, 140):
        for y in (40, 140):
            d.rounded_rectangle([x, y, x + 76, y + 76], radius=12, fill=W)
    return img


def plus():
    img, d = _canvas()
    d.rounded_rectangle([108, 40, 148, 216], radius=12, fill=W)
    d.rounded_rectangle([40, 108, 216, 148], radius=12, fill=W)
    return img


def check():
    img, d = _canvas()
    d.line([(46, 136), (106, 196), (214, 70)], fill=W, width=30, joint="curve")
    return img


def house():
    img, d = _canvas()
    d.polygon([(128, 34), (24, 130), (232, 130)], fill=W)
    d.rectangle([56, 124, 200, 224], fill=W)
    d.rectangle([108, 160, 148, 224], fill=(0, 0, 0, 0))
    return img


def log_lines():
    img, d = _canvas()
    d.rounded_rectangle([46, 26, 210, 230], radius=16, outline=W, width=16)
    for y in (76, 116, 156, 190):
        d.line([(80, y), (176 if y != 190 else 140, y)], fill=W, width=14)
    return img


def flame():
    img, d = _canvas()
    d.polygon([(128, 28), (196, 120), (204, 176), (170, 222), (86, 222), (52, 176), (64, 120), (100, 150)], fill=W)
    d.ellipse([100, 150, 156, 214], fill=(0, 0, 0, 0))
    return img


def drop_item():
    img, d = _canvas()
    _arrow(d, False, y0=24, y1=170)
    d.rectangle([40, 200, 216, 226], fill=W)
    return img


def chat():
    img, d = _canvas()
    d.rounded_rectangle([24, 36, 232, 176], radius=40, fill=W)
    d.polygon([(70, 168), (60, 230), (130, 172)], fill=W)
    for x in (80, 128, 176):
        d.ellipse([x - 14, 92, x + 14, 120], fill=(0, 0, 0, 0))
    return img


ICONS = {
    "jump": jump, "break": pickaxe, "place": place, "items": bag, "fly": wing, "build": hammer, "up": up,
    "down": down, "save": floppy, "settings": gear, "close": cross, "half": half, "quick": bolt, "trash": trash,
    "clear_inventory": eraser, "sunrise": sunrise, "noon": noon, "sunset": sunset, "midnight": moon,
    "freeze": pause, "corner1": corner(1), "corner2": corner(2), "fill": fill_box, "hollow": hollow_box,
    "replace": swap, "clear": eraser, "copy": copy, "paste": clipboard, "rotate": rotate, "mirror": mirror,
    "undo": undo, "deselect": deselect, "library": book, "language": globe, "save_hotbar": floppy,
    "star": star, "recent": clock, "sort": sort, "all": grid, "plus": plus, "check": check, "home": house,
    "log": log_lines, "chat": chat, "furnace": flame, "drop": drop_item,
}


def render_all():
    return {name: draw().resize((OUT, OUT), Image.LANCZOS) for name, draw in ICONS.items()}
