import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from survival import Survival, MAX_HEALTH, MAX_HUNGER, MAX_AIR, icons  # noqa: E402


def test_hunger_drains_faster_when_walking():
    idle, walker = Survival(), Survival()
    for _ in range(600):                       # 10 minutes at 1 s steps
        idle.tick(1.0)
        walker.tick(1.0, moved=5.0)
    assert idle.hunger == MAX_HUNGER - 0       # 3 exhaustion: not even one point yet
    assert walker.hunger < MAX_HUNGER - 6


def test_full_bar_lasts_roughly_twenty_minutes_of_walking():
    s = Survival()
    minutes = 0
    while s.hunger > 0:
        for _ in range(60):
            s.tick(1.0, moved=4.0)
        minutes += 1
    assert 15 <= minutes <= 40


def test_regenerates_when_fed_and_starves_when_empty():
    s = Survival()
    s.damage(5, "test")
    for _ in range(20):
        s.tick(1.0)
    assert s.health == MAX_HEALTH            # 5 points in 20 s
    s.hunger = 0
    for _ in range(40):
        s.tick(1.0)
    assert s.health == MAX_HEALTH - 10


def test_starving_to_death():
    s = Survival()
    s.hunger = 0
    for _ in range(200):
        s.tick(1.0)
    assert s.dead and s.cause == "starved" and s.health == 0


def test_drowning_after_breath_runs_out():
    s = Survival()
    s.hunger = 10                              # no healing in the way
    for _ in range(int(MAX_AIR) - 1):
        s.tick(1.0, head_under_water=True)
    assert s.health == MAX_HEALTH and s.air == 1.0
    for _ in range(3):
        s.tick(1.0, head_under_water=True)
    assert s.health < MAX_HEALTH
    s.tick(1.0)
    assert s.air == 4.0                        # breath comes back quickly


def test_fall_damage():
    s = Survival()
    for y in (20, 21, 19, 15, 12):             # jump up a bit, then fall
        s.track_fall(y, on_ground=False, in_water=False)
    assert s.track_fall(11.5, on_ground=True, in_water=False) == 6   # fell 9.5 blocks -> 6 damage
    assert s.health == MAX_HEALTH - 6
    for y in (11.5, 12.7, 12.0):               # an ordinary jump never hurts
        s.track_fall(y, on_ground=False, in_water=False)
    assert s.track_fall(11.5, on_ground=True, in_water=False) == 0


def test_water_breaks_a_fall():
    s = Survival()
    for y in (40, 30, 20):
        s.track_fall(y, on_ground=False, in_water=False)
    s.track_fall(10, on_ground=False, in_water=True)
    assert s.track_fall(9.5, on_ground=True, in_water=False) == 0


def test_eating():
    s = Survival()
    assert not s.eat(6)                        # not hungry
    s.hunger = 10
    assert s.eat(6) and s.hunger == 16
    assert s.eat(6) and s.hunger == MAX_HUNGER


def test_respawn_and_save():
    s = Survival()
    s.damage(100, "test")
    assert s.dead and not s.damage(1, "x")
    s.respawn()
    assert not s.dead and s.health == MAX_HEALTH
    s.hunger = 7
    s.damage(3, "x")
    again = Survival.from_data(s.to_data())
    assert (again.health, again.hunger) == (17, 7)


def test_icons():
    assert icons(20, 20) == ["full"] * 10
    assert icons(7, 20) == ["full"] * 3 + ["half"] + ["empty"] * 6
    assert icons(0, 20) == ["empty"] * 10
