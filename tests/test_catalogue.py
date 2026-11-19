"""The expanded block catalogue: colour families, woods, stones, minerals, plants and families."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import blocks as b  # noqa: E402
import i18n  # noqa: E402
import inventory as inv  # noqa: E402
from world import World, TILES, ATLAS_COLS  # noqa: E402
from textures import generate_atlas, tile_image  # noqa: E402

# a few ids from before the expansion: saves store ids, so these must never change
OLD_IDS = {1: "grass", 3: "stone", 7: "oak planks", 13: "coal ore", 29: "diamond ore", 61: "oak fence",
           70: "white wool", 85: "pink wool", 300: "stone slab", 320: "stone stairs", 400: "white glass",
           500: "ladder", 510: "door"}


def test_old_ids_are_unchanged():
    for i, name in OLD_IDS.items():
        assert b.BLOCKS[i] == name


def test_catalogue_is_much_bigger_and_fits_the_atlas():
    creative_blocks = [i for i, d in b.BLOCK_DEFS.items() if d["creative"]]
    assert len(creative_blocks) >= 300
    assert len(TILES) <= ATLAS_COLS * ATLAS_COLS
    assert generate_atlas().size == (ATLAS_COLS * 16, ATLAS_COLS * 16)


def test_new_textures_are_distinct():
    atlas = generate_atlas()
    names = [t for t in TILES if t.startswith(("concrete_", "terracotta_", "glazed_"))] + [
        f"{s}_{part}" for s in b.WOOD_SPECIES for part in ("log", "planks", "leaves")]
    pixels = {n: tile_image(atlas, n).tobytes() for n in names}
    assert len(set(pixels.values())) == len(names)
    for n, px in pixels.items():
        assert bytes((255, 0, 255, 255)) not in px, n


def test_families_list_creative_variants_in_order():
    families = inv.creative_families()
    creative = set(inv.CREATIVE_ITEMS)
    for f in ("wool", "concrete", "terracotta", "glazed_tiles", "carpet", "stained_glass", "planks", "logs",
              "leaves", "slabs", "stairs", "fences", "walls", "flowers", "ores", "stone_bricks", "polished_stone",
              "lamps", "gems", "pickaxes"):
        assert len(families[f]) >= 2, f
        assert set(families[f]) <= creative
    assert families["wool"] == b.WOOL
    assert families["planks"][0] == 7                                  # oak first
    assert len(families["stairs"]) == len(b.STAIRS) and len(families["slabs"]) == len(b.SLABS)
    assert set(families) <= set(i18n.FAMILIES)
    seen = [i for ids in families.values() for i in ids]
    assert len(seen) == len(set(seen))                                 # an item is in one family at most


def test_arabic_names_for_new_blocks():
    assert i18n.arabic_name(b.CONCRETE[0]) == "خرسانة بيضاء"
    assert i18n.arabic_name(b.TERRACOTTA[5]) == "فخار أحمر"
    assert i18n.arabic_name(b.WOODS["maple"]["planks"]) == "ألواح قيقب"
    assert i18n.arabic_name(b.SLABS[b.WOODS["ebony"]["planks"]]) == "بلاطة ألواح أبنوس"
    assert i18n.arabic_name(b.WALLS[22]).startswith("سور ")
    assert len({i18n.arabic_name(i) for i in b.FAMILIES["flowers"]}) == len(b.FAMILIES["flowers"])


def test_carpet_shape():
    w = World(seed=1)
    w.chunks[(0, 0)] = set()
    carpet = b.CARPETS[4]
    assert w.shape_boxes(carpet, 0, 0, 0) == [(-.5, -.5, -.5, .5, -.4375, .5)]
    assert carpet in b.NON_SOLID and carpet in b.PLANTS_NEED_SOIL
    w._put((2, 1, 2), 3)
    w._put((2, 2, 2), carpet)
    w.set(2, 1, 2, 0)
    assert w.get(2, 2, 2) == 0                                         # falls with its floor


def test_recipes_for_new_blocks():
    results = {r[1][0] for r in inv.RECIPES}
    for i in (*b.CONCRETE, *b.TERRACOTTA, *b.GLAZED, *b.CARPETS, *b.COLOR_LAMPS, *b.WALLS.values(),
              *b.POLISHED.values(), *b.ROCK_BRICKS.values(), *b.CHISELED.values(), *b.SLABS.values(),
              *(s[0] for s in b.STAIRS.values()), *(w["planks"] for w in b.WOODS.values()),
              *(w["fence"] for w in b.WOODS.values()), 904, 905, 906, 907, 908, 909, b.GLOW_CRYSTAL):
        assert i in results, b.BLOCKS[i]
    plank = next(r for r in inv.RECIPES if r[0] == {b.WOODS["cherry"]["log"]: 1})
    assert plank[1] == (b.WOODS["cherry"]["planks"], 4)


def test_new_blocks_generate_in_the_world():
    w = World(seed=11)
    for cx in range(-6, 6):
        for cz in range(-6, 6):
            w.ensure_chunk((cx, cz))
    found = set(w.blocks.values())
    for species in b.WOOD_SPECIES:
        assert b.WOODS[species]["log"] in found and b.WOODS[species]["leaves"] in found, species
    for i in (b.SLATE, b.LIMESTONE, b.RUBY_ORE, b.SAPPHIRE_ORE, b.AMETHYST_ORE, b.QUARTZ_ORE,
              b.LEAFY_BUSH, b.BERRY_BUSH, 951, 952, *b.FAMILIES["flowers"]):
        assert i in found, b.BLOCKS[i]
    # ores stay in their depth bands and slate deep down, far below the surface layer
    from world import World as W, SLATE_LINE
    deepest = {ore: max_y for ore, _, max_y in W.ORES}
    assert deepest[b.RUBY_ORE] < SLATE_LINE and deepest[b.SAPPHIRE_ORE] < SLATE_LINE
    for (x, y, z), block_id in w.blocks.items():
        if block_id in deepest:
            assert y <= deepest[block_id]
        elif block_id == b.SLATE:
            assert y < SLATE_LINE + 6


def test_carpets_are_drawn_without_collision():
    w = World(seed=1)
    for cx in (-1, 0, 1):
        for cz in (-1, 0, 1):
            w.chunks[(cx, cz)] = set()
    w._put((3, 1, 3), 3)
    w._put((3, 2, 3), b.CARPETS[0])
    mesh = w.chunk_mesh(0, 0)
    assert len(mesh["plants"][0]) == 5 * 6          # top + 4 thin sides (the bottom rests on stone)
