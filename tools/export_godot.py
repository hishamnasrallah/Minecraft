"""Export the game data from the Python version for the Godot version.

    python tools/export_godot.py

Writes godot/data/: blocks.json (block registry + world constants), items.json
(items, tools, recipes, creative tabs), atlas.png and hud icons, and test fixtures
so the Godot tests can check that both versions generate exactly the same world.
The Python files stay the single source of truth for blocks, items and recipes.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import blocks  # noqa: E402
import world as w  # noqa: E402
import inventory as inv  # noqa: E402
import survival as sv  # noqa: E402
import i18n  # noqa: E402
import ui_icons  # noqa: E402
import sounds  # noqa: E402
from textures import generate_atlas, hud_icons, crack_stages  # noqa: E402

OUT = ROOT / "godot" / "data"
TREE_KINDS = ["oak", "birch", "pine", "maple", "cherry", "ashwood", "ebony"]   # index = Godot's tree kind


def export_blocks():
    tile_index = {t: i for i, t in enumerate(w.TILES)}
    defs = {}
    for i, d in blocks.BLOCK_DEFS.items():
        entry = {k: v for k, v in d.items() if k not in ("tiles", "id")}
        entry["tiles"] = [tile_index[t] for t in d["tiles"]]
        if entry.get("drop") == "self":
            entry["drop"] = i
        defs[str(i)] = entry
    return {
        "constants": {
            "CHUNK_SIZE": w.CHUNK_SIZE, "MAX_HEIGHT": w.MAX_HEIGHT, "WATER_LEVEL": w.WATER_LEVEL,
            "TREE_CHANCE": w.TREE_CHANCE, "MAX_LIGHT": w.MAX_LIGHT, "CAVE_THRESHOLD": w.CAVE_THRESHOLD,
            "CAVE_GRID": w.CAVE_GRID, "SNOW_LINE": w.SNOW_LINE, "ATLAS_COLS": w.ATLAS_COLS,
            "ORES": [list(o) for o in w.World.ORES],
            # tree species in kind-index order (Godot stores the index), and their shapes
            "TREE_KINDS": TREE_KINDS,
            "TREES": {k: [blocks.WOODS[k]["log"], blocks.WOODS[k]["leaves"], *w.World.TREE_SHAPES.get(k, (0, []))]
                      for k in TREE_KINDS},
            "FLOWERS": list(blocks.FLOWERS),
            "GEN_IDS": {"SLATE": blocks.SLATE, "LIMESTONE": blocks.LIMESTONE, "DRY_BUSH": blocks.DRY_BUSH,
                        "LEAFY_BUSH": blocks.LEAFY_BUSH, "BERRY_BUSH": blocks.BERRY_BUSH, "PUMPKIN": 951,
                        "MELON": 952},
        },
        "tiles": w.TILES,
        "plants_need_soil": sorted(blocks.PLANTS_NEED_SOIL),
        "dyes": [[name, list(rgb)] for name, rgb in blocks.DYES],
        "blocks": defs,
    }


def export_items():
    def key(k):
        return k if isinstance(k, str) else str(k)
    return {
        "items": {str(i): name for i, name in inv.ITEMS.items()},
        "icons": {str(i): w.TILES.index(t) for i, t in inv.ITEM_ICONS.items()},
        "tools": {str(i): {"kind": t[0], "speed": t[1], "durability": t[2], "name": t[3], "level": t[5]}
                  for i, t in inv.TOOLS.items()},
        "food": {str(i): v for i, v in inv.FOOD.items()},
        "groups": inv.GROUPS,
        "recipes": [{"in": {key(k): n for k, n in ing.items()}, "out": [res, cnt]} for ing, (res, cnt) in inv.RECIPES]
        + [{"in": {key(k): n for k, n in ing.items()}, "out": [res, cnt], "station": "furnace"}
           for ing, (res, cnt) in inv.SMELTING],
        "tabs": inv.TABS,
        "creative_items": [[i, inv.item_tab(i)] for i in inv.CREATIVE_ITEMS],
        "families": inv.creative_families(),
        "family_names": {f: {"en": i18n.FAMILIES_EN[f], "ar": i18n.FAMILIES_AR[f]} for f in inv.creative_families()},
        "placeable": sorted(inv.PLACEABLE),
        "survival": {k: getattr(sv, k) for k in ("MAX_HEALTH", "MAX_HUNGER", "MAX_AIR", "EXHAUSTION_PER_POINT",
                                                 "IDLE_PER_SECOND", "WALK_PER_BLOCK", "JUMP", "MINE", "ATTACK",
                                                 "REGEN", "REGEN_EVERY", "STARVE_EVERY", "DROWN_EVERY", "SAFE_FALL")},
        "special": {"STICK": inv.STICK, "COAL": inv.COAL, "RAW_MEAT": inv.RAW_MEAT, "COOKED_MEAT": inv.COOKED_MEAT,
                    "APPLE": inv.APPLE, "BUCKET": inv.BUCKET, "WATER_BUCKET": inv.WATER_BUCKET,
                    "STACK_SIZE": inv.STACK_SIZE, "HOTBAR_SIZE": inv.HOTBAR_SIZE, "INVENTORY_SIZE": inv.INVENTORY_SIZE},
    }


def export_fixtures():
    """Reference results from the Python version for the Godot parity tests."""
    world = w.World(seed=11)
    chunks = [(0, 0), (-1, 2), (3, -2)]
    # plus one chunk for each tree species, so the new trees, flowers and bushes are compared too
    wanted = set(TREE_KINDS) - {"pine"}
    for cx in range(-8, 8):
        for cz in range(-8, 8):
            kinds = {world.tree_kind(x, z) for x in range(cx * 16, cx * 16 + 16) for z in range(cz * 16, cz * 16 + 16)
                     if world.has_tree(x, z)}
            if kinds & wanted:
                wanted -= kinds
                chunks.append((cx, cz))
    # and chunks with limestone and desert bushes
    probe = w.World(seed=11)
    for block_id in (blocks.LIMESTONE, blocks.DRY_BUSH):
        for key in ((cx, cz) for cx in range(-6, 6) for cz in range(-6, 6)):
            probe.ensure_chunk(key)
            if any(probe.blocks[p] == block_id for p in probe.chunks[key]):
                if key not in chunks:
                    chunks.append(key)
                break
    for key in chunks:
        world.ensure_chunk(key)
    out = {"seed": 11, "chunks": {}}
    for key in chunks:
        cells = sorted([x, y, z, world.blocks[(x, y, z)]] for (x, y, z) in world.chunks[key])
        out["chunks"][f"{key[0]},{key[1]}"] = cells
    out["noise"] = [[x, z, w.fbm(x / 28, z / 28, 11), w._hash(x, z, 11)] for x, z in ((0, 0), (5, -7), (-123, 456))]
    out["noise3"] = [[x, y, z, w.cave_density(x, y, z, 11)] for x, y, z in ((0, 0, 0), (4, 8, -12), (-40, 20, 33))]
    out["heights"] = [[x, z, world.height_at(x, z)] for x, z in ((0, 0), (17, -3), (-50, 60))]
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "blocks.json").write_text(json.dumps(export_blocks(), indent=1))
    (OUT / "items.json").write_text(json.dumps(export_items(), indent=1))
    (OUT / "i18n.json").write_text(json.dumps(i18n.export(), indent=1, ensure_ascii=False))
    atlas = generate_atlas()
    atlas.save(OUT / "atlas.png")
    import item_icons  # noqa: E402
    sheet, mapping = item_icons.render(atlas, {t: i for i, t in enumerate(w.TILES)}, 16, w.ATLAS_COLS)
    sheet.save(OUT / "icons3d.png")
    items = json.loads((OUT / "items.json").read_text())
    items["icons3d"] = {"size": item_icons.SIZE, "cols": item_icons.COLS, "map": {str(k): v for k, v in mapping.items()}}
    (OUT / "items.json").write_text(json.dumps(items, indent=1))
    icons = OUT / "icons"
    icons.mkdir(exist_ok=True)
    for name, image in hud_icons().items():
        image.save(icons / f"{name}.png")
    for i, image in enumerate(crack_stages()):
        image.save(icons / f"crack_{i}.png")
    ui = OUT / "ui"
    ui.mkdir(exist_ok=True)
    for name, image in ui_icons.render_all().items():
        image.save(ui / f"{name}.png")
    sounds.export(OUT / "sounds")
    fixtures = ROOT / "godot" / "tests" / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    (fixtures / "worldgen.json").write_text(json.dumps(export_fixtures()))
    print(f"Exported to {OUT}")


if __name__ == "__main__":
    main()
