"""Wandering animals: behaviour, simple voxel physics and spawning.

Pure Python (no Ursina) so it can be unit-tested; main.py only draws them.
Positions are the centre of the animal's feet. Blocks are centred on integer
coordinates, so the block containing a point is floor(v + 0.5).
"""
import math
import random

from world import WATER, WATER_LEVEL

GRAVITY = 20.0
MAX_ANIMALS = 12
SPAWN_EVERY = 2.0            # seconds between spawn attempts
SPAWN_MIN, SPAWN_MAX = 18, 44
DESPAWN_DISTANCE = 70

SPECIES = {
    #          speed  height width  flee when the player is this close, swims, group size
    "rabbit": dict(speed=3.4, height=0.5, width=0.4, flee_range=5.0, swims=False, group=(1, 3)),
    "deer": dict(speed=2.6, height=1.4, width=0.6, flee_range=3.0, swims=False, group=(1, 3)),
    "duck": dict(speed=1.4, height=0.5, width=0.4, flee_range=2.0, swims=True, group=(2, 4)),
}


def cell(v):
    return math.floor(v + 0.5)


class Animal:
    def __init__(self, kind, x, y, z, rng=random):
        self.kind = kind
        self.spec = SPECIES[kind]
        self.x, self.y, self.z = x, y, z
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

    # -- behaviour
    def hit(self, from_x, from_z):
        """The player hit us: hop away and run."""
        dx, dz = self.x - from_x, self.z - from_z
        d = math.hypot(dx, dz) or 1.0
        self.knock = (dx / d * 6, dz / d * 6)
        if self.on_ground or self.in_water:
            self.vy = 5.0
        self.state, self.timer = "flee", 4.0

    def _think(self, dt, player):
        px, _, pz = player
        dist = math.hypot(self.x - px, self.z - pz)
        if dist < self.spec["flee_range"]:
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
        if world.chunk_key(cell(self.x), cell(self.z)) not in world.chunks:
            return
        self._think(dt, player)

        # horizontal movement
        speed = {"flee": self.spec["speed"], "walk": self.spec["speed"] * 0.45}.get(self.state, 0.0)
        if self.in_water and not self.spec["swims"]:
            speed *= 0.6
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
                step_free = not world.solid(cell(ahead_x), cell(self.y + 1.1), cell(ahead_z)) and \
                    not world.solid(cell(ahead_x), cell(self.y + self.spec["height"] + 0.9), cell(ahead_z))
                if (self.on_ground or self.in_water) and step_free:
                    self.vy = 7.0              # hop up one block
                elif self.state == "walk":
                    self.state, self.timer = "idle", self.rng.uniform(1, 3)
            elif self.state != "flee" and self._unsafe(world, ahead_x, ahead_z):
                self.state, self.timer = "idle", self.rng.uniform(1, 3)
                self.yaw += 180
            else:
                self.x += dx
                self.z += dz
                self.moving = speed > 0
                self.walk_phase += math.hypot(dx, dz) * 6

        # vertical movement: gravity, floating in water, landing
        self.in_water = world.get(cell(self.x), cell(self.y + self.spec["height"] * 0.4), cell(self.z)) == WATER
        if self.in_water:
            self.vy = min(self.vy + 25 * dt, 1.5) if self.vy < 5 else self.vy - GRAVITY * dt
            self.vy *= 0.9
        else:
            self.vy -= GRAVITY * dt
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


class Wildlife:
    """Keeps a handful of animals alive around the player."""

    def __init__(self, world, rng=None):
        self.world = world
        self.rng = rng or random.Random()
        self.animals = []
        self._spawn_timer = 0.0

    def update(self, dt, player):
        px, _, pz = player
        for a in list(self.animals):
            a.update(dt, self.world, player)
            gone = self.world.chunk_key(cell(a.x), cell(a.z)) not in self.world.chunks
            if gone or math.hypot(a.x - px, a.z - pz) > DESPAWN_DISTANCE or a.y < -10:
                self.animals.remove(a)
        self._spawn_timer -= dt
        if self._spawn_timer <= 0:
            self._spawn_timer = SPAWN_EVERY
            self.try_spawn(px, pz)

    def try_spawn(self, px, pz):
        """Pick a random spot in a ring around the player and maybe put a small group there."""
        if len(self.animals) >= MAX_ANIMALS:
            return []
        angle = self.rng.uniform(0, 2 * math.pi)
        distance = self.rng.uniform(SPAWN_MIN, SPAWN_MAX)
        x, z = cell(px + math.sin(angle) * distance), cell(pz + math.cos(angle) * distance)
        col = self.world.column(x, z)
        if col is None:
            return []
        top, water_top = col
        ground = self.world.get(x, top, z)
        if water_top > top:                       # open water: ducks only
            kind, y = "duck", water_top + 0.3
        elif ground == 1 and top > WATER_LEVEL:   # grass
            kind = self.rng.choice(["rabbit", "rabbit", "deer"])
            y = top + 0.5
        elif ground == 6:                         # beach sand
            kind, y = "duck", top + 0.5
        else:
            return []
        lo, hi = SPECIES[kind]["group"]
        spawned = []
        for _ in range(self.rng.randint(lo, hi)):
            if len(self.animals) >= MAX_ANIMALS:
                break
            a = Animal(kind, x + self.rng.uniform(-1.5, 1.5), y, z + self.rng.uniform(-1.5, 1.5), self.rng)
            if a._blocked(self.world, a.x, a.z):    # don't spawn inside a tree or a hillside
                continue
            self.animals.append(a)
            spawned.append(a)
        return spawned
