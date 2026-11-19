"""Wandering creatures: behaviour, simple voxel physics, biome-aware spawning, feeding and
breeding.

Pure Python (no Ursina) so it can be unit-tested; main.py only draws them. Positions are the
centre of the animal's feet (the body centre for flyers). Blocks are centred on integer
coordinates, so the block containing a point is floor(v + 0.5).

The Godot port (godot/scripts/animals.gd) keeps the same species table; it also has the
night creatures (gloom, bramble, glob), which the Python version doesn't spawn.

Movement kinds: "walk" (land; steps up one block, goats jump two), "hop" (moves only while in
the air), "swim" (fish: stays under water), "fly" (birds, butterflies, fireflies; ambient).
"""
import math
import random

from world import WATER, WATER_LEVEL, SNOW_LINE
from inventory import RAW_MEAT, COAL, STICK, APPLE, EGG, FEATHER, RAW_FISH
from blocks import SEEDS, WHEAT_ITEM, CARROT

GRAVITY = 20.0
MAX_ANIMALS = 12             # passive land / water-surface animals
MAX_FISH = 6
MAX_AMBIENT = 6              # birds, butterflies, fireflies
MAX_HOSTILE = 6
SPAWN_EVERY = 2.0            # seconds between spawn attempts
SPAWN_MIN, SPAWN_MAX = 18, 44
DESPAWN_DISTANCE = 70
AMBIENT_DESPAWN = 40
TEMPT_RANGE = 10.0
LOVE_TIME, BREED_COOLDOWN, GROW_TIME = 30.0, 60.0, 240.0
BABY_SCALE = 0.55
WOOL = 70                    # + colour index

SPECIES = {
    #   speed, height, width, flee when the player is this close, swims, group size, health; extras:
    #   food (items that tempt / feed it), call (sound), move, cap (which limit it counts against)
    "rabbit": dict(speed=3.4, height=0.5, width=0.4, flee_range=5.0, swims=False, group=(1, 3), health=3, food=[CARROT]),
    "deer": dict(speed=2.6, height=1.4, width=0.6, flee_range=3.0, swims=False, group=(1, 3), health=8, food=[APPLE]),
    "duck": dict(speed=1.4, height=0.5, width=0.4, flee_range=2.0, swims=True, group=(2, 4), health=3, food=[SEEDS],
                 call="chirp"),
    "woolly": dict(speed=1.6, height=1.0, width=0.8, flee_range=0.0, swims=False, group=(2, 4), health=6,
                   food=[WHEAT_ITEM], call="bleat"),
    "hen": dict(speed=1.5, height=0.6, width=0.4, flee_range=1.5, swims=False, group=(2, 4), health=3, food=[SEEDS],
                call="cluck", flutter=True),
    "goat": dict(speed=2.2, height=1.1, width=0.6, flee_range=2.5, swims=False, group=(1, 3), health=7,
                 food=[WHEAT_ITEM], call="bleat", climb=2),
    "frog": dict(speed=2.2, height=0.35, width=0.4, flee_range=2.5, swims=True, group=(1, 3), health=2, move="hop",
                 hop=6.5, call="croak"),
    "turtle": dict(speed=0.7, height=0.4, width=0.7, flee_range=0.0, swims=True, group=(1, 2), health=10),
    "lizard": dict(speed=3.8, height=0.3, width=0.4, flee_range=4.0, swims=False, group=(1, 2), health=2),
    "fish": dict(speed=1.8, height=0.3, width=0.3, flee_range=4.0, swims=True, group=(3, 5), health=1, move="swim",
                 cap="fish"),
    "bird": dict(speed=4.5, height=0.3, width=0.3, flee_range=0.0, swims=False, group=(1, 3), health=1, move="fly",
                 cap="ambient", alt=(5.0, 11.0), roam=14.0, call="chirp"),
    "butterfly": dict(speed=1.3, height=0.2, width=0.2, flee_range=0.0, swims=False, group=(1, 2), health=1,
                      move="fly", cap="ambient", alt=(0.6, 2.2), roam=4.0),
    "firefly": dict(speed=0.6, height=0.1, width=0.1, flee_range=0.0, swims=False, group=(3, 5), health=1, move="fly",
                    cap="ambient", alt=(0.5, 2.5), roam=3.0),
    "gloom": dict(speed=2.4, height=1.8, width=0.6, flee_range=0.0, swims=False, group=(1, 2), health=10, hostile=True,
                  cap="hostile"),
    "bramble": dict(speed=1.25, height=0.7, width=0.9, flee_range=0.0, swims=False, group=(1, 1), health=16,
                    hostile=True, cap="hostile", damage=5, cooldown=1.8, reach=1.7, sun_proof=True),
    "glob": dict(speed=2.6, height=0.9, width=0.9, flee_range=0.0, swims=True, group=(1, 1), health=8, hostile=True,
                 cap="hostile", move="hop", hop=7.0, damage=2, reach=1.5, splits="globlet"),
    "globlet": dict(speed=3.0, height=0.45, width=0.45, flee_range=0.0, swims=True, group=(1, 1), health=3,
                    hostile=True, cap="hostile", move="hop", hop=6.0, damage=1, reach=1.1),
}
# what each animal leaves behind: (item, min, max); a woolly drops wool of its own colour
DROPS = {"rabbit": (RAW_MEAT, 1, 1), "deer": (RAW_MEAT, 2, 3), "duck": (RAW_MEAT, 1, 2), "gloom": (COAL, 0, 2),
         "woolly": (WOOL, 1, 2), "hen": (FEATHER, 1, 2), "goat": (RAW_MEAT, 1, 2), "frog": (0, 0, 0),
         "turtle": (0, 0, 0), "lizard": (0, 0, 0), "fish": (RAW_FISH, 1, 1), "bird": (FEATHER, 0, 1),
         "butterfly": (0, 0, 0), "firefly": (0, 0, 0), "bramble": (STICK, 1, 3), "glob": (0, 0, 0),
         "globlet": (SEEDS, 0, 1)}
WOOL_COLOURS = [0, 0, 0, 0, 1, 1, 2, 3, 4, 4, 6, 7, 10, 12, 13, 14]
VARIANTS = {"rabbit": 2, "fish": 3, "butterfly": 4, "bird": 3}


def cell(v):
    return math.floor(v + 0.5)


def cap_of(kind):
    return SPECIES[kind].get("cap", "land")


class Animal:
    def __init__(self, kind, x, y, z, rng=random):
        self.kind = kind
        self.spec = SPECIES[kind]
        self.move = self.spec.get("move", "walk")
        self.x, self.y, self.z = x, y, z
        self.home = (x, y, z)
        self.target3 = (x, y, z)
        self.vel = (0.0, 0.0, 0.0)            # flyers and swimmers
        self.vy = 0.0
        self.yaw = rng.uniform(0, 360)        # degrees, 0 = +z, 90 = +x (same as Ursina's rotation_y)
        self.rng = rng
        self.state, self.timer = "idle", rng.uniform(0.5, 3)
        self.target = None
        self.on_ground = False
        self.in_water = False
        self.knock = (0.0, 0.0)               # horizontal push after being hit
        self.walk_phase = 0.0                 # drives the leg animation
        self.moving = False
        self.health = self.spec["health"]
        self.dead = False
        self.killed = False                   # died from the player's hits (not despawned)
        self.hurt_time = 0.0                  # >0 right after being hit (drawn red)
        self.hostile = self.spec.get("hostile", False)
        self.ambient = cap_of(kind) == "ambient"
        self.variant = rng.choice(WOOL_COLOURS) if kind == "woolly" else rng.randrange(VARIANTS.get(kind, 1))
        self.age = 0.0                        # >0: a baby
        self.love = 0.0                       # >0: fed, looking for a mate
        self.breed_cd = 0.0
        self.tame = False
        self.fed = False
        self.egg_timer = rng.uniform(60, 150) if kind == "hen" else 0.0
        self.hop_cd = 0.0
        self.dry_time = 0.0
        self.player_dist = 0.0

    # -- helpers
    @property
    def position(self):
        return (self.x, self.y, self.z)

    def _blocked(self, world, x, z):
        """Would the body hit something at (x, z)?"""
        h = self.spec["height"]
        for y in (self.y + 0.1, self.y + h - 0.1):
            if world.solid(cell(x), cell(y), cell(z)):
                return True
        return False

    def _unsafe(self, world, x, z):
        """Land animals avoid walking into water or off ledges higher than 2 blocks."""
        if self.spec["swims"]:
            return False
        cx, cz = cell(x), cell(z)
        feet = cell(self.y - 0.4)
        for drop in range(3):
            b = world.get(cx, feet - drop, cz)
            if b == WATER:
                return True
            if b:
                return False
        return True

    def wants_food(self, item):
        return bool(item) and not self.hostile and item in self.spec.get("food", ())

    # -- behaviour
    def hit(self, from_x, from_z, damage=1, held=None):
        """The player hit us: lose health, hop away and run. Returns the drops if it died.
        Holding this animal's food feeds it instead (an adult gets ready to breed)."""
        held = Wildlife.held_item if held is None else held
        if self.wants_food(held):
            if self.age > 0:
                self.age = max(0.0, self.age - 60)
                self.fed = True
            elif self.love <= 0 and self.breed_cd <= 0:
                self.love = LOVE_TIME
                self.fed = True
            self.tame = True
            return []
        self.health -= damage
        self.hurt_time = 0.25
        if self.health <= 0:
            self.dead = True
            self.killed = True
            item, lo, hi = DROPS[self.kind]
            n = self.rng.randint(lo, hi)
            if not item or n <= 0 or self.age > 0:
                return []
            return [(item + self.variant if self.kind == "woolly" else item, n)]
        dx, dz = self.x - from_x, self.z - from_z
        d = math.hypot(dx, dz) or 1.0
        self.knock = (dx / d * 6, dz / d * 6)
        if self.on_ground or self.in_water:
            self.vy = 5.0
        if not self.hostile:
            self.state, self.timer, self.love = "flee", 4.0, 0.0
        return []

    def _think(self, dt, player):
        px, _, pz = player
        dist = math.hypot(self.x - px, self.z - pz)
        self.player_dist = dist
        if self.state != "flee" and self.wants_food(Wildlife.held_item) and dist < TEMPT_RANGE:
            self.state = "follow"
            self.yaw = math.degrees(math.atan2(px - self.x, pz - self.z))
            return
        if self.state == "follow":
            self.state, self.timer = "idle", 1.0
        if dist < self.spec["flee_range"] and not self.tame:
            self.state, self.timer = "flee", max(self.timer, 2.0)
        self.timer -= dt
        if self.state == "flee":
            self.yaw = math.degrees(math.atan2(self.x - px, self.z - pz))
            if self.timer <= 0:
                self.state, self.timer = "idle", self.rng.uniform(1, 3)
        elif self.state == "walk":
            tx, tz = self.target
            if math.hypot(tx - self.x, tz - self.z) < 0.5 or self.timer <= 0:
                self.state, self.timer = "idle", self.rng.uniform(2, 6)
            else:
                want = math.degrees(math.atan2(tx - self.x, tz - self.z))
                turn = (want - self.yaw + 180) % 360 - 180
                self.yaw += max(-240 * dt, min(240 * dt, turn))
        elif self.timer <= 0:                  # idle -> pick somewhere to wander to
            angle = self.rng.uniform(0, 2 * math.pi)
            distance = self.rng.uniform(3, 8)
            self.target = (self.x + math.sin(angle) * distance, self.z + math.cos(angle) * distance)
            self.state, self.timer = "walk", 8.0

    def update(self, dt, world, player):
        dt = min(dt, 0.1)                      # keep the physics stable during lag spikes
        self.hurt_time = max(0.0, self.hurt_time - dt)
        if world.chunk_key(cell(self.x), cell(self.z)) not in world.chunks:
            return
        if self.move == "fly":
            return self._fly(dt, world)
        if self.move == "swim":
            self.in_water = world.get(cell(self.x), cell(self.y + 0.15), cell(self.z)) == WATER
            if self.in_water:
                return self._swim(dt, world, player)
            self.dry_time += dt                # a fish on land flops about and soon dies
            if self.dry_time > 12:
                self.dead = True
            if self.on_ground:
                self.vy = 4.0
            return self._fall(dt, world)
        self._think(dt, player)

        # horizontal movement
        speed = {"flee": self.spec["speed"], "walk": self.spec["speed"] * 0.45}.get(self.state, 0.0)
        if self.state == "follow":
            speed = self.spec["speed"] * 0.6 if self.player_dist > 1.8 else 0.0
        if self.in_water and not self.spec["swims"]:
            speed *= 0.6
        if self.move == "hop":                 # only moves while in the air
            self.hop_cd -= dt
            if self.on_ground:
                if speed > 0 and self.hop_cd <= 0:
                    self.vy = self.spec["hop"]
                    self.hop_cd = self.rng.uniform(0.8, 2.0)
                    self.on_ground = False
                else:
                    speed = 0.0
            else:
                speed *= 1.3
        rad = math.radians(self.yaw)
        dx = math.sin(rad) * speed * dt + self.knock[0] * dt
        dz = math.cos(rad) * speed * dt + self.knock[1] * dt
        self.knock = (self.knock[0] * 0.85, self.knock[1] * 0.85)
        self.moving = False
        if dx or dz:
            reach = self.spec["width"] / 2
            length = math.hypot(dx, dz) or 1.0
            ahead_x = self.x + dx + dx / length * reach
            ahead_z = self.z + dz + dz / length * reach
            if self._blocked(world, ahead_x, ahead_z):
                ax, az = cell(ahead_x), cell(ahead_z)
                head = cell(self.y + self.spec["height"] + 0.9)
                step_free = not world.solid(ax, cell(self.y + 1.1), az) and not world.solid(ax, head, az)
                leap_free = (self.spec.get("climb", 1) >= 2 and not step_free
                             and not world.solid(ax, cell(self.y + 2.1), az) and not world.solid(ax, head + 1, az))
                if (self.on_ground or self.in_water) and step_free:
                    self.vy = 7.0              # hop up one block
                elif self.on_ground and leap_free:
                    self.vy = 9.4              # goats spring up two blocks
                elif self.state == "walk":
                    self.state, self.timer = "idle", self.rng.uniform(1, 3)
            elif self.state not in ("flee", "follow") and self._unsafe(world, ahead_x, ahead_z):
                self.state, self.timer = "idle", self.rng.uniform(1, 3)
                self.yaw += 180
            else:
                self.x += dx
                self.z += dz
                self.moving = speed > 0
                self.walk_phase += math.hypot(dx, dz) * 6
        self._fall(dt, world)

    def _fall(self, dt, world):
        """Vertical movement: gravity, floating in water, landing."""
        self.in_water = world.get(cell(self.x), cell(self.y + self.spec["height"] * 0.4), cell(self.z)) == WATER
        if self.in_water and self.move != "swim":
            self.vy = min(self.vy + 25 * dt, 1.5) if self.vy < 5 else self.vy - GRAVITY * dt
            self.vy *= 0.9
        else:
            self.vy -= GRAVITY * dt
            if self.spec.get("flutter") and self.vy < -2.5:
                self.vy = -2.5                 # hens glide down
        new_y = self.y + self.vy * dt
        self.on_ground = False
        if self.vy <= 0:
            below = cell(new_y - 0.01)
            if world.solid(cell(self.x), below, cell(self.z)):
                new_y = below + 0.5
                self.vy = 0.0
                self.on_ground = True
        elif world.solid(cell(self.x), cell(new_y + self.spec["height"]), cell(self.z)):
            new_y, self.vy = self.y, 0.0   # bumped its head
        self.y = new_y

    def _steer(self, dt, speed, rate):
        tx, ty, tz = self.target3
        dx, dy, dz = tx - self.x, ty - self.y, tz - self.z
        d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d > 0.01:
            k = min(1.0, dt * rate)
            want = (dx / d * speed, dy / d * speed, dz / d * speed)
            self.vel = tuple(v + (w - v) * k for v, w in zip(self.vel, want))
        return (self.x + self.vel[0] * dt, self.y + self.vel[1] * dt, self.z + self.vel[2] * dt)

    def _swim(self, dt, world, player):
        """Fish glide to random points inside the water and dart away from the player."""
        self.timer -= dt
        ax, az = self.x - player[0], self.z - player[2]
        self.player_dist = math.hypot(ax, az)
        scared = self.player_dist < self.spec["flee_range"]
        close = math.dist(self.position, self.target3) < 0.5
        if self.timer <= 0 or close or (scared and self.state != "flee"):
            if scared:
                d = self.player_dist or 1.0
                t = (self.x + ax / d * 4, self.y, self.z + az / d * 4)
                self.state = "flee"
            else:
                a = self.rng.uniform(0, 2 * math.pi)
                t = (self.x + math.sin(a) * 4, self.y + self.rng.uniform(-1, 1), self.z + math.cos(a) * 4)
                self.state = "walk"
            if world.get(cell(t[0]), cell(t[1]), cell(t[2])) == WATER and \
                    world.get(cell(t[0]), cell(t[1] + 0.5), cell(t[2])) == WATER:
                self.target3 = t
            self.timer = self.rng.uniform(2, 5)
        n = self._steer(dt, self.spec["speed"] * (2 if self.state == "flee" else 1), 3)
        if world.get(cell(n[0]), cell(n[1] + 0.15), cell(n[2])) == WATER:
            self.x, self.y, self.z = n
        else:
            self.vel = tuple(-v * 0.5 for v in self.vel)
            self.timer = 0
        if self.vel[0] or self.vel[2]:
            self.yaw = math.degrees(math.atan2(self.vel[0], self.vel[2]))
        self.moving = True
        self.walk_phase += dt * (14 if self.state == "flee" else 7)
        self.vy = 0.0

    def _fly(self, dt, world):
        """Flyers: no gravity, wander between points around their home at their own height."""
        self.timer -= dt
        if self.timer <= 0 or math.dist(self.position, self.target3) < 0.6:
            roam = self.spec["roam"]
            x = self.home[0] + self.rng.uniform(-roam, roam)
            z = self.home[2] + self.rng.uniform(-roam, roam)
            col = world.column(cell(x), cell(z))
            ground = max(col) if col else self.y - 2
            lo, hi = self.spec["alt"]
            self.target3 = (x, ground + self.rng.uniform(lo, hi), z)
            self.timer = self.rng.uniform(3, 8)
        n = self._steer(dt, self.spec["speed"], 1.5 if self.kind == "bird" else 3)
        if world.solid(cell(n[0]), cell(n[1]), cell(n[2])):
            self.vel = (self.vel[0], abs(self.spec["speed"]), self.vel[2])
            self.timer = 0
            n = (self.x, self.y + self.spec["speed"] * dt, self.z)
            if world.solid(cell(n[0]), cell(n[1]), cell(n[2])):
                n = self.position
        self.x, self.y, self.z = n
        if abs(self.vel[0]) + abs(self.vel[2]) > 0.01:
            self.yaw = math.degrees(math.atan2(self.vel[0], self.vel[2]))
        self.moving = True
        self.walk_phase += dt * (22 if self.kind == "butterfly" else 12)


class Wildlife:
    """Keeps a handful of creatures alive around the player."""
    held_item = 0                  # what the player holds (food tempts and feeds animals)

    def __init__(self, world, rng=None):
        self.world = world
        self.rng = rng or random.Random()
        self.animals = []
        self.laid = []             # [(item, count), position] eggs laid (the game may pick these up)
        self._spawn_timer = 0.0
        self._spawn_turn = 0

    def update(self, dt, player, daylight=1.0):
        px, _, pz = player
        lovers, born = [], []
        for a in list(self.animals):
            a.update(dt, self.world, player)
            d = math.hypot(a.x - px, a.z - pz)
            if a.ambient:
                night_kind = a.kind == "firefly"
                if (night_kind and daylight > 0.45) or (not night_kind and daylight < 0.3):
                    if d > 16 or night_kind:
                        a.dead = True
                if d > AMBIENT_DESPAWN:
                    a.dead = True
            elif not a.hostile:
                self._tick_passive(a, dt, d, daylight, lovers)
            gone = self.world.chunk_key(cell(a.x), cell(a.z)) not in self.world.chunks
            if a.dead or gone or (d > DESPAWN_DISTANCE and not a.tame) or a.y < -10:
                self.animals.remove(a)
        if lovers:
            born = self._breed(lovers)
        self.animals.extend(born)
        self._spawn_timer -= dt
        if self._spawn_timer <= 0:
            self._spawn_timer = SPAWN_EVERY
            self._spawn_turn += 1
            self.try_spawn(px, pz)
            if self._spawn_turn % 2 == 0:
                self.try_spawn_ambient(px, pz, daylight)

    def _tick_passive(self, a, dt, d, daylight, lovers):
        a.age = max(0.0, a.age - dt)
        a.breed_cd = max(0.0, a.breed_cd - dt)
        a.fed = False
        if a.love > 0:
            a.love -= dt
            lovers.append(a)
        if a.kind == "hen" and a.age <= 0:
            a.egg_timer -= dt
            if a.egg_timer <= 0:
                a.egg_timer = self.rng.uniform(90, 180)
                if d < 40:
                    self.laid.append(((EGG, 1), (a.x, a.y + 0.3, a.z)))
                    del self.laid[:-16]
        if daylight < 0.25 and a.state == "walk" and a.kind in ("woolly", "hen", "goat", "deer"):
            a.state, a.timer = "idle", 5.0     # settle down for the night

    def _breed(self, lovers):
        """Pairs of fed adults walk to each other; when they meet a baby appears."""
        born = []
        for a in lovers:
            if a.love <= 0 or a.state == "flee":
                continue
            mates = [b for b in lovers if b is not a and b.kind == a.kind and b.love > 0]
            if not mates:
                continue
            b = min(mates, key=lambda m: math.dist(a.position, m.position))
            dist = math.dist(a.position, b.position)
            if dist > 8:
                continue
            if dist < 1.7:
                baby = Animal(a.kind, (a.x + b.x) / 2, (a.y + b.y) / 2 + 0.3, (a.z + b.z) / 2, self.rng)
                baby.age, baby.tame = GROW_TIME, True
                baby.variant = self.rng.choice((a.variant, b.variant))
                born.append(baby)
                for p in (a, b):
                    p.love, p.breed_cd, p.state, p.timer = 0.0, BREED_COOLDOWN, "idle", 2.0
            else:
                a.state, a.target, a.timer = "walk", (b.x, b.z), 2.0
        return born

    def _counts(self):
        counts = {"land": 0, "fish": 0, "ambient": 0, "hostile": 0}
        for a in self.animals:
            counts[cap_of(a.kind)] += 1
        return counts

    def pick_kind(self, x, z):
        """What lives at (x, z): (kind, y, variant or None), or None (biome from ground and height)."""
        col = self.world.column(x, z)
        if col is None:
            return None
        top, water_top = col
        ground = self.world.get(x, top, z)
        rng = self.rng
        if water_top > top:                       # open water: fish below, ducks on top
            if water_top - top >= 2 and rng.random() < 0.65:
                return "fish", top + 1 + rng.random() * (water_top - top - 1.5), None
            return "duck", water_top + 0.3, None
        y = top + 0.5
        if ground == 6:                           # sand: beach or desert
            if top <= WATER_LEVEL + 1:
                return ("turtle" if rng.random() < 0.4 else "duck"), y, None
            return "lizard", y, None
        if ground == 16 or top >= SNOW_LINE - 2:  # snowy heights: goats and white rabbits
            return ("goat", y, None) if rng.random() < 0.6 else ("rabbit", y, 1)
        if ground == 3 and top > WATER_LEVEL + 8:
            return "goat", y, None
        if ground != 1 or top <= WATER_LEVEL:
            return None
        wet, trees = False, 0
        for ox, oz in ((4, 0), (-4, 0), (0, 4), (0, -4), (3, 3), (-3, -3)):
            c = self.world.column(x + ox, z + oz)
            if c is not None and c[1] > c[0]:
                wet = True
            if self.world.has_tree(x + ox, z + oz) or self.world.has_tree(x + ox + 1, z + oz):
                trees += 1
        if wet and rng.random() < 0.5:
            return "frog", y, None
        if trees >= 2:                            # forest
            return rng.choice(["deer", "deer", "rabbit", "hen"]), y, None
        return rng.choice(["woolly", "woolly", "woolly", "hen", "hen", "rabbit", "deer"]), y, None   # meadow

    def try_spawn(self, px, pz):
        """Pick a random spot in a ring around the player and maybe put a small group there."""
        counts = self._counts()
        if counts["land"] >= MAX_ANIMALS and counts["fish"] >= MAX_FISH:
            return []
        angle = self.rng.uniform(0, 2 * math.pi)
        distance = self.rng.uniform(SPAWN_MIN, SPAWN_MAX)
        x, z = cell(px + math.sin(angle) * distance), cell(pz + math.cos(angle) * distance)
        pick = self.pick_kind(x, z)
        if pick is None:
            return []
        kind, y, variant = pick
        cap = cap_of(kind)
        limit = MAX_FISH if cap == "fish" else MAX_ANIMALS
        lo, hi = SPECIES[kind]["group"]
        spawned = []
        colour = None
        for _ in range(self.rng.randint(lo, hi)):
            if counts[cap] >= limit:
                break
            a = Animal(kind, x + self.rng.uniform(-1.5, 1.5), y, z + self.rng.uniform(-1.5, 1.5), self.rng)
            if variant is not None:
                a.variant = variant
            if kind == "fish":                      # a school shares a colour
                colour = a.variant if colour is None else colour
                a.variant = colour
                if self.world.get(cell(a.x), cell(a.y + 0.15), cell(a.z)) != WATER:
                    continue
            elif a._blocked(self.world, a.x, a.z):  # don't spawn inside a tree or a hillside
                continue
            self.animals.append(a)
            spawned.append(a)
            counts[cap] += 1
        return spawned

    def try_spawn_ambient(self, px, pz, daylight):
        """Birds and butterflies by day, fireflies at night, near the player."""
        counts = self._counts()
        if counts["ambient"] >= MAX_AMBIENT or 0.45 < daylight < 0.55:
            return []
        angle = self.rng.uniform(0, 2 * math.pi)
        distance = self.rng.uniform(8, 26)
        x, z = cell(px + math.sin(angle) * distance), cell(pz + math.cos(angle) * distance)
        col = self.world.column(x, z)
        if col is None or col[1] > col[0]:
            return []
        ground = self.world.get(x, col[0], z)
        if daylight < 0.3:
            kind = "firefly" if ground == 1 else None
        elif ground == 1 and self.rng.random() < 0.55:
            kind = "butterfly"
        else:
            kind = "bird" if ground != 16 else None
        if kind is None:
            return []
        lo, hi = SPECIES[kind]["group"]
        alt_lo, alt_hi = SPECIES[kind]["alt"]
        colour = self.rng.randrange(VARIANTS.get(kind, 1))
        spawned = []
        for _ in range(self.rng.randint(lo, hi)):
            if counts["ambient"] >= MAX_AMBIENT:
                break
            p = (x + self.rng.uniform(-2, 2), col[0] + self.rng.uniform(alt_lo, alt_hi), z + self.rng.uniform(-2, 2))
            if self.world.solid(cell(p[0]), cell(p[1]), cell(p[2])):
                continue
            a = Animal(kind, *p, rng=self.rng)
            a.home = (x, p[1], z)
            if kind == "bird":
                a.variant = colour
            self.animals.append(a)
            spawned.append(a)
            counts["ambient"] += 1
        return spawned
