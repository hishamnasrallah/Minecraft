import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from world import World, CHUNK_SIZE, WATER  # noqa: E402
from animals import Animal, Wildlife, MAX_ANIMALS, DESPAWN_DISTANCE  # noqa: E402

FAR = (1000.0, 0.0, 1000.0)   # a player position that never scares anyone


def flat(ground=3):
    """Flat 3x3-chunk grass field with its surface block at y=ground."""
    w = World(seed=1)
    for cx in (-1, 0, 1):
        for cz in (-1, 0, 1):
            w.chunks[(cx, cz)] = set()
    for x in range(-CHUNK_SIZE, 2 * CHUNK_SIZE):
        for z in range(-CHUNK_SIZE, 2 * CHUNK_SIZE):
            for y in range(ground + 1):
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
    assert 0 < len(life.animals) <= MAX_ANIMALS
    kinds = {a.kind for a in life.animals}
    assert kinds <= {"rabbit", "deer", "duck"}
    for a in life.animals:
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
