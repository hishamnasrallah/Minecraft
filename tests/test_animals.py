import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from world import World, CHUNK_SIZE, WATER, WATER_LEVEL  # noqa: E402
from animals import (Animal, Wildlife, MAX_ANIMALS, MAX_FISH, MAX_AMBIENT, DESPAWN_DISTANCE,  # noqa: E402
                     SPECIES, DROPS, cap_of, GROW_TIME)

FAR = (1000.0, 0.0, 1000.0)   # a player position that never scares anyone


def flat(ground=3):
    """Flat 3x3-chunk grass field with its surface block at y=ground."""
    w = World(seed=1)
    for cx in (-1, 0, 1):
        for cz in (-1, 0, 1):
            w.chunks[(cx, cz)] = set()
    for x in range(-CHUNK_SIZE, 2 * CHUNK_SIZE):
        for z in range(-CHUNK_SIZE, 2 * CHUNK_SIZE):
            for y in range(max(ground - 4, 0), ground + 1):   # (just the top layers of a high field)
                w._put((x, y, z), 9 if y == 0 else (1 if y == ground else 2))
    return w


def run(animal, world, seconds, player=FAR, dt=0.05):
    for _ in range(int(seconds / dt)):
        animal.update(dt, world, player)


def test_falls_and_lands_on_the_ground():
    w = flat()
    a = Animal("deer", 5, 10, 5, random.Random(1))
    run(a, w, 2)
    assert a.on_ground and a.y == 3.5


def test_wanders_around_but_stays_on_the_field():
    w = flat()
    a = Animal("rabbit", 8, 3.5, 8, random.Random(2))
    start = a.position
    run(a, w, 30)
    assert a.position != start
    assert a.y == 3.5 or not a.on_ground


def test_climbs_a_one_block_step_but_not_a_wall():
    w = flat()
    for z in range(-5, 20):
        for x in range(10, 15):
            w._put((x, 4, z), 2)         # platform one block up from x=10
        for y in (5, 6, 7):
            w._put((14, y, z), 3)        # 3-high wall on the platform at x=14
    a = Animal("deer", 8, 3.5, 5, random.Random(3))
    a.state, a.timer, a.target, a.yaw = "walk", 20, (20, 5), 90
    for _ in range(200):
        a.state, a.timer, a.target = "walk", 20, (20, a.z)
        a.update(0.05, w, FAR)
    assert 10 <= a.x < 14 and a.y == 4.5     # on top of the step, stopped by the wall


def test_land_animals_avoid_water():
    w = flat()
    for x in range(10, 14):
        for z in range(-16, 32):
            w._put((x, 3, z), WATER)
    rng = random.Random(4)
    for _ in range(5):
        a = Animal("rabbit", 7, 3.5, 5, rng)
        run(a, w, 40)
        assert a.x < 9.6


def test_ducks_float_on_water():
    w = flat()
    for x in range(4, 12):
        for z in range(4, 12):
            for y in (1, 2, 3):
                w._put((x, y, z), WATER)
    a = Animal("duck", 8, 5, 8, random.Random(5))
    run(a, w, 6)
    assert a.in_water and 2.5 < a.y < 4.0


def test_runs_from_a_close_player_and_when_hit():
    w = flat()
    a = Animal("rabbit", 8, 3.5, 8, random.Random(6))
    player = (10, 3.5, 8)
    run(a, w, 1, player=player)
    assert a.state == "flee" and a.x < 8
    b = Animal("deer", 8, 3.5, 8, random.Random(7))
    b.hit(12, 8)
    run(b, w, 0.5)
    assert b.state == "flee" and b.x < 8


def test_wildlife_spawns_and_despawns():
    w = World(seed=11)
    for cx in range(-4, 4):
        for cz in range(-4, 4):
            w.ensure_chunk((cx, cz))
    life = Wildlife(w, random.Random(8))
    for _ in range(300):
        life.update(0.1, (0, 20, 0))
    land = [a for a in life.animals if cap_of(a.kind) == "land"]
    assert 0 < len(land) <= MAX_ANIMALS
    assert len(life.animals) <= MAX_ANIMALS + MAX_FISH + MAX_AMBIENT
    assert not any(a.hostile for a in life.animals)          # Python spawns no night creatures
    for a in life.animals:
        if a.move != "fly":
            assert not w.solid(math.floor(a.x + 0.5), math.floor(a.y + 0.6), math.floor(a.z + 0.5))
    life.update(0.1, (DESPAWN_DISTANCE * 3, 20, 0))
    assert all(math.hypot(a.x - DESPAWN_DISTANCE * 3, a.z) <= DESPAWN_DISTANCE for a in life.animals)


def test_animals_die_after_enough_hits_and_drop_meat():
    from inventory import RAW_MEAT
    from animals import SPECIES
    w = flat()
    deer = Animal("deer", 8, 3.5, 8, random.Random(9))
    hits = 0
    drops = []
    while not deer.dead:
        drops = deer.hit(0, 8, damage=3)
        hits += 1
    assert hits == math.ceil(SPECIES["deer"]["health"] / 3)
    assert drops and drops[0][0] == RAW_MEAT and 2 <= drops[0][1] <= 3
    life = Wildlife(w, random.Random(1))
    life.animals.append(deer)
    life.update(0.1, FAR)
    assert deer not in life.animals


def pond(w, x0=4, x1=12, depth=3, ground=3):
    for x in range(x0, x1):
        for z in range(x0, x1):
            for y in range(ground - depth + 1, ground + 1):
                w._put((x, y, z), WATER)


def test_every_species_has_a_model_drops_and_valid_data():
    import animal_models
    from inventory import ITEMS
    for kind, spec in SPECIES.items():
        assert kind in animal_models.MODELS and kind in DROPS
        for key in ("speed", "height", "width", "flee_range", "swims", "group", "health"):
            assert key in spec, (kind, key)
        item, lo, hi = DROPS[kind]
        assert 0 <= lo <= hi and (item == 0 or item in ITEMS)
        for food in spec.get("food", ()):
            assert food in ITEMS
        assert len(animal_models.part_colours(kind, 0)) == len(animal_models.MODELS[kind]["parts"])


def test_models_match_the_godot_version():
    import re
    import animal_models
    src = (Path(__file__).resolve().parents[1] / "godot" / "scripts" / "animal_view.gd").read_text()
    block = src[src.index("const MODELS := {"):src.index("static var _cube_v")]
    godot = {}
    kind = None
    for line in block.splitlines():
        m = re.match(r'\t"(\w+)": \[', line)
        if m:
            kind = m.group(1)
            godot[kind] = 0
        elif kind:
            godot[kind] += line.count('["')
    assert godot == {k: len(v) for k, v in animal_models.PARTS.items()}
    gd_species = (Path(__file__).resolve().parents[1] / "godot" / "scripts" / "animals.gd").read_text()
    for kind in SPECIES:
        assert f'"{kind}": {{"speed"' in gd_species, kind


def test_woolly_drops_wool_of_its_colour():
    from blocks import WOOL
    a = Animal("woolly", 8, 3.5, 8, random.Random(3))
    a.variant = 5
    drops = []
    while not a.dead:
        drops = a.hit(0, 8, damage=3, held=0)
    assert drops and drops[0][0] == WOOL[5] and 1 <= drops[0][1] <= 2


def test_food_tempts_and_feeding_two_adults_makes_a_baby():
    from blocks import WHEAT_ITEM
    w = flat()
    life = Wildlife(w, random.Random(4))
    a = Animal("woolly", 6, 3.5, 6, life.rng)
    b = Animal("woolly", 11, 3.5, 6, life.rng)
    life.animals += [a, b]
    Wildlife.held_item = WHEAT_ITEM
    try:
        player = (8.5, 3.5, 12)
        for _ in range(20):
            life.update(0.05, player)
        assert a.state == "follow" and b.state == "follow"
        assert a.hit(8, 12, damage=1) == [] and a.health == SPECIES["woolly"]["health"] and a.love > 0
        b.hit(8, 12, damage=1)
    finally:
        Wildlife.held_item = 0
    for _ in range(200):
        life.update(0.05, FAR)
    babies = [x for x in life.animals if x.age > 0]
    assert len(babies) == 1 and babies[0].kind == "woolly" and babies[0].age <= GROW_TIME
    assert a.breed_cd > 0 and a.love == 0
    for _ in range(int(GROW_TIME / 0.5) + 2):
        life.update(0.5, FAR)
    assert babies[0].age == 0


def test_hens_lay_eggs():
    from inventory import EGG
    w = flat()
    life = Wildlife(w, random.Random(5))
    hen = Animal("hen", 8, 3.5, 8, life.rng)
    hen.egg_timer = 0.5
    life.animals.append(hen)
    for _ in range(20):
        life.update(0.05, (8, 3.5, 20))
    assert life.laid and life.laid[0][0] == (EGG, 1)


def test_fish_stay_under_water():
    w = flat()
    pond(w)
    fish = Animal("fish", 8, 1.5, 8, random.Random(6))
    run(fish, w, 20)
    assert w.get(math.floor(fish.x + 0.5), math.floor(fish.y + 0.65), math.floor(fish.z + 0.5)) == WATER
    assert 4 <= fish.x < 12 and fish.moving


def test_fish_on_land_dies():
    w = flat()
    fish = Animal("fish", 8, 3.5, 8, random.Random(7))
    run(fish, w, 14)
    assert fish.dead


def test_flyers_hover_above_the_ground():
    w = flat()
    for kind in ("bird", "butterfly", "firefly"):
        f = Animal(kind, 8, 6, 8, random.Random(8))
        run(f, w, 10)
        lo, hi = SPECIES[kind]["alt"]
        assert f.y > 3.5 and not w.solid(math.floor(f.x + 0.5), math.floor(f.y + 0.5), math.floor(f.z + 0.5)), kind


def test_goats_jump_up_two_blocks():
    w = flat()
    for z in range(-5, 20):
        for x in range(10, 15):
            w._put((x, 4, z), 2)
            w._put((x, 5, z), 2)              # a two-block ledge from x=10
    goat = Animal("goat", 8, 3.5, 5, random.Random(9))
    deer = Animal("deer", 8, 3.5, 5, random.Random(9))
    for a in (goat, deer):
        for _ in range(200):
            a.state, a.timer, a.target = "walk", 20, (14, a.z)
            a.update(0.05, w, FAR)
    assert goat.y == 5.5 and goat.x >= 10
    assert deer.y == 3.5 and deer.x < 10


def test_biomes_pick_fitting_creatures():
    g = WATER_LEVEL + 3
    w = flat(ground=g)                    # a meadow above the sea
    life = Wildlife(w, random.Random(10))
    seen = {life.pick_kind(5, 5)[0] for _ in range(60)}
    assert seen <= {"woolly", "hen", "rabbit", "deer"} and "woolly" in seen
    w = flat(ground=g)
    for x in range(-16, 32):
        for z in range(-16, 32):
            w._put((x, g, z), 6)             # desert sand
    life = Wildlife(w, random.Random(10))
    assert {life.pick_kind(5, 5)[0] for _ in range(10)} == {"lizard"}
    w = flat(ground=g)                   # (fresh world: column tops are cached)
    pond(w, depth=3, ground=g)
    life = Wildlife(w, random.Random(10))
    kinds = {life.pick_kind(8, 8)[0] for _ in range(40)}
    assert kinds <= {"fish", "duck"} and "fish" in kinds


def test_ambient_creatures_by_day_and_night():
    w = flat()
    life = Wildlife(w, random.Random(11))
    day = []
    for _ in range(80):
        day += life.try_spawn_ambient(8, 8, 1.0)
    assert day and {a.kind for a in day} <= {"bird", "butterfly"}
    assert len([a for a in life.animals if a.ambient]) <= MAX_AMBIENT
    life.update(0.1, (8, 3.5, 8), daylight=0.1)
    assert all(math.hypot(a.x - 8, a.z - 8) <= 16 for a in life.animals if a.ambient)
    life.animals.clear()
    night = []
    for _ in range(80):
        night += life.try_spawn_ambient(8, 8, 0.1)
    assert night and {a.kind for a in night} == {"firefly"}
