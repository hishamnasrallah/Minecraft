"""Little 3D pictures of blocks for the hotbar, the items screen and dropped items.

Each cube-like block is drawn from the block atlas as an isometric cube (top, left and right
faces, shaded). Plants, torches, ladders, doors, fences and items keep their flat tile.

    python tools/export_godot.py   ->  godot/data/icons3d.png + "icons3d" in items.json
"""
from PIL import Image

from blocks import BLOCK_DEFS

SIZE = 48
COLS = 32
SHAPES = {"cube": 1.0, "slab": 0.5, "stair": 1.0, "carpet": 0.12}
SHADE = {"top": 1.0, "left": 0.82, "right": 0.62}


def _face(out, tile, origin, u_vec, v_vec, shade, v0=0.0, v_span=1.0):
    """Paint `tile` onto the parallelogram origin + u*u_vec + v*v_vec (u, v in 0..1)."""
    ox, oy = origin
    ux, uy = u_vec
    vx, vy = v_vec
    det = ux * vy - uy * vx
    ts = tile.size[0]
    px = tile.load()
    dst = out.load()
    xs = [ox, ox + ux, ox + vx, ox + ux + vx]
    ys = [oy, oy + uy, oy + vy, oy + uy + vy]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        for x in range(int(min(xs)), int(max(xs)) + 1):
            dx, dy = x + 0.5 - ox, y + 0.5 - oy
            u = (dx * vy - dy * vx) / det
            v = (ux * dy - uy * dx) / det
            if 0 <= u < 1 and 0 <= v < 1 and 0 <= x < SIZE and 0 <= y < SIZE:
                r, g, b, a = px[min(ts - 1, int(u * ts)), min(ts - 1, int((v0 + v * v_span) * ts))]
                if a > 20:
                    dst[x, y] = (int(r * shade), int(g * shade), int(b * shade), a)


def block_icon(tiles, height=1.0):
    """tiles: (top, side) images. An isometric cube `height` tall (1 = full block)."""
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    top, side = tiles
    m = 2                                  # margin
    half = (SIZE - 2 * m) / 2              # 22 for 48 px
    q = half / 2                           # the rhombus is half as tall as wide
    side_h = (SIZE - 2 * m - 2 * q) * height
    drop = (SIZE - 2 * m - 2 * q) * (1 - height)
    top_left = (m, m + q + drop)
    centre = (m + half, m + 2 * q + drop)
    _face(out, top, top_left, (half, -q), (half, q), SHADE["top"])
    _face(out, side, top_left, (half, q), (0, side_h), SHADE["left"], 1 - height, height)
    _face(out, side, centre, (half, -q), (0, side_h), SHADE["right"], 1 - height, height)
    return out


def render(atlas, tile_index, tile_px, atlas_cols):
    """-> (icon atlas image, {block id: icon index})"""
    def tile(name):
        i = tile_index[name]
        x, y = (i % atlas_cols) * tile_px, (i // atlas_cols) * tile_px
        return atlas.crop((x, y, x + tile_px, y + tile_px)).convert("RGBA")

    chosen = [(i, d) for i, d in sorted(BLOCK_DEFS.items()) if d["creative"] and d["shape"] in SHAPES]
    rows = -(-len(chosen) // COLS)
    sheet = Image.new("RGBA", (COLS * SIZE, rows * SIZE), (0, 0, 0, 0))
    mapping = {}
    for n, (i, d) in enumerate(chosen):
        top_name, side_name = d["tiles"][0], d["tiles"][1]
        icon = block_icon((tile(top_name), tile(side_name)), SHAPES[d["shape"]])
        sheet.paste(icon, ((n % COLS) * SIZE, (n // COLS) * SIZE))
        mapping[i] = n
    return sheet, mapping
