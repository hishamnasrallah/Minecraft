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
            # the deep world: surface offset, underground layers and caverns (see world.py)
            "SURFACE_OFFSET": w.SURFACE_OFFSET, "SAVE_VERSION": w.SAVE_VERSION, "CAVE_FLOOR": w.CAVE_FLOOR,
            "BEDROCK_TOP": w.BEDROCK_TOP, "SLATE_LINE": w.SLATE_LINE, "BASALT_LINE": w.BASALT_LINE,
            "LIMESTONE_LINE": w.LIMESTONE_LINE, "CAVERN_TOP": w.CAVERN_TOP, "CAVERN_MID": w.CAVERN_MID,
            "CAVERN_LIMIT": w.CAVERN_LIMIT,
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
        "armor": {str(k): {"slot": v[0], "points": v[1]} for k, v in inv.ARMOR.items()},
        "returns": {str(k): v for k, v in inv.RETURNS.items()},
        "recipes": [{"in": {key(k): n for k, n in ing.items()}, "out": [res, cnt]} for ing, (res, cnt) in inv.RECIPES]
        + [{"in": {key(k): n for k, n in ing.items()}, "out": [res, cnt], "station": "furnace"}
           for ing, (res, cnt) in inv.SMELTING]
        + [{"in": {key(k): n for k, n in ing.items()}, "out": [res, cnt], "station": "brew"}
           for ing, (res, cnt) in inv.BREWING],
        "potions": {str(k): {"effect": v[2], "seconds": v[3]} for k, v in inv.POTIONS.items()},
        "tabs": inv.TABS,
        "creative_items": [[i, inv.item_tab(i)] for i in inv.CREATIVE_ITEMS],
        "families": inv.creative_families(),
        "family_names": {f: {"en": i18n.FAMILIES_EN[f], "ar": i18n.FAMILIES_AR[f]} for f in inv.creative_families()},
        "placeable": sorted(inv.PLACEABLE),
        "plant": {str(k): v for k, v in blocks.PLANT_ON_FARMLAND.items()},
        "farmland": blocks.FARMLAND,
        "sapling_trees": {str(w["sapling"]): [w["log"], w["leaves"]] for w in blocks.WOODS.values()},
        "survival": {k: getattr(sv, k) for k in ("MAX_HEALTH", "MAX_HUNGER", "MAX_AIR", "EXHAUSTION_PER_POINT",
                                                 "IDLE_PER_SECOND", "WALK_PER_BLOCK", "JUMP", "MINE", "ATTACK",
                                                 "REGEN", "REGEN_EVERY", "STARVE_EVERY", "DROWN_EVERY", "SAFE_FALL")},
        "special": {"STICK": inv.STICK, "COAL": inv.COAL, "RAW_MEAT": inv.RAW_MEAT, "COOKED_MEAT": inv.COOKED_MEAT,
                    "APPLE": inv.APPLE, "SEEDS": inv.SEEDS, "BUCKET": inv.BUCKET, "WATER_BUCKET": inv.WATER_BUCKET, "LAVA_BUCKET": inv.LAVA_BUCKET, "MILK_BUCKET": inv.MILK_BUCKET, "GLASS_BOTTLE": inv.GLASS_BOTTLE, "FIRE_STRIKER": inv.FIRE_STRIKER, "SHEARS": inv.SHEARS, "BOW": inv.BOW, "ARROW": inv.ARROW, "BOAT": inv.BOAT,
                    "FISHING_ROD": inv.FISHING_ROD, "SADDLE": inv.SADDLE, "COMPASS": inv.COMPASS, "SHIELD": inv.SHIELD, "BONE_MEAL": inv.BONE_MEAL, "MAP_ITEM": inv.MAP_ITEM, "EMBER_SHARD": inv.EMBER_SHARD, "WATER_BOTTLE": inv.WATER_BOTTLE, "CAKE": inv.CAKE,
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
    # and the chunk with the most hollow space below CAVERN_TOP: a big cavern deep down
    caverns = {}
    for key in ((cx, cz) for cx in range(-3, 3) for cz in range(-3, 3)):
        probe.ensure_chunk(key)
        x0, z0 = key[0] * 16, key[1] * 16
        caverns[key] = sum(1 for x in range(x0, x0 + 16) for z in range(z0, z0 + 16)
                           for y in range(w.CAVE_FLOOR, w.CAVERN_TOP) if (x, y, z) not in probe.blocks)
    cavern = max(caverns, key=caverns.get)
    if cavern not in chunks:
        chunks.append(cavern)
    for key in chunks:
        world.ensure_chunk(key)
    # every chunk whole, top to bottom, run-length encoded in Godot's cell order (lx, y, lz):
    # [id, count, id, count, ...]
    out = {"seed": 11, "height": w.MAX_HEIGHT, "cavern_chunk": list(cavern), "chunks": {}}
    for key in chunks:
        runs = []
        x0, z0 = key[0] * 16, key[1] * 16
        for lx in range(16):
            for y in range(w.MAX_HEIGHT):
                for lz in range(16):
                    b = world.blocks.get((x0 + lx, y, z0 + lz), 0)
                    if runs and runs[-2] == b:
                        runs[-1] += 1
                    else:
                        runs += [b, 1]
        out["chunks"][f"{key[0]},{key[1]}"] = runs
    out["noise"] = [[x, z, w.fbm(x / 28, z / 28, 11), w._hash(x, z, 11)] for x, z in ((0, 0), (5, -7), (-123, 456))]
    out["noise3"] = [[x, y, z, w.cave_density(x, y, z, 11)] for x, y, z in ((0, 0, 0), (4, 8, -12), (-40, 20, 33))]
    out["noise3_cavern"] = [[x, y, z, w.value_noise3(x / 32, y / 16, z / 32, 11 + 900)]
                            for x, y, z in ((0, 0, 0), (36, 44, -20), (-200, 100, 77))]
    out["slate_lines"] = [[x, z, world.slate_line(x, z)] for x, z in ((0, 0), (17, -3), (-50, 60))]
    out["heights"] = [[x, z, world.height_at(x, z)] for x, z in ((0, 0), (17, -3), (-50, 60))]
    return out


def export_library():
    """Factories from factories.py, plus an index of every built-in schematic so the library
    lists them without reading the files (some are big)."""
    import factories
    import schematics
    folder = OUT / "schematics"
    folder.mkdir(exist_ok=True)
    index = []
    for file, en, ar, category, clip in factories.all_designs():
        data = schematics.to_data(clip, en)
        if clip.extras:
            data["extras"] = [[x, y, z, e] for (x, y, z), e in sorted(clip.extras.items())]
        (folder / f"{file}.json").write_text(json.dumps(data, separators=(",", ":")))
        index.append({"file": f"{file}.json", "name": en, "name_ar": ar, "category": category,
                      "size": data["size"], "blocks": sum(1 for b in clip.values() if b)})
    extras = {"small_house.json": ("Small house", "بيت صغير", "houses"),
              "talia.json": ("TALIA sign", "لوحة TALIA", "signs"), "hisham.json": ("HISHAM sign", "لوحة HISHAM", "signs"),
              "layan.json": ("LAYAN sign", "لوحة LAYAN", "signs"), "zaina.json": ("ZAINA sign", "لوحة ZAINA", "signs")}
    for file, (en, ar, category) in extras.items():
        data = json.loads((folder / file).read_text())
        blocks_n = sum(run for i, run in data["blocks"] if data["palette"][i][1] != 0)
        index.append({"file": file, "name": en, "name_ar": ar, "category": category, "size": data["size"],
                      "blocks": blocks_n})
    order = ["houses", "signs", "small_factories", "big_factories"]
    index.sort(key=lambda e: (order.index(e["category"]), e["blocks"]))
    (folder / "index.json").write_text(json.dumps(index, indent=1, ensure_ascii=False))


def export_name_signs():
    """Ready-made neon name signs in the schematics library (letters on a black backing)."""
    import schematics
    black = blocks.CONCRETE[3]
    for word, colour in (("TALIA", "pink"), ("HISHAM", "blue"), ("LAYAN", "pink"), ("ZAINA", "blue")):
        clip = {}
        # the front is the +z side (the library turns that side to the player): seen from
        # there +x is to the right, so the word runs along +x on the z = 1 layer
        for i, letter in enumerate(word):
            clip[(i + 1, 1, 1)] = blocks.NEON[(colour, letter)]
        for x in range(len(word) + 2):           # a black frame behind and around the letters
            for y in range(3):
                clip[(x, y, 0)] = black
                if y != 1 or x in (0, len(word) + 1):
                    clip.setdefault((x, y, 1), black)
        data = schematics.to_data(clip, word.lower())
        for folder in (ROOT / "schematics", OUT / "schematics"):
            folder.mkdir(exist_ok=True)
            (folder / f"{word.lower()}.json").write_text(json.dumps(data, separators=(",", ":")))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "blocks.json").write_text(json.dumps(export_blocks(), indent=1))
    (OUT / "items.json").write_text(json.dumps(export_items(), indent=1))
    (OUT / "i18n.json").write_text(json.dumps(i18n.export(), indent=1, ensure_ascii=False))
    export_name_signs()
    export_library()
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
