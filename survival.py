"""Health, hunger, breath, fall damage and death. Pure Python so it can be unit-tested."""
import math

MAX_HEALTH = 20          # shown as 10 hearts
MAX_HUNGER = 20          # shown as 10 drumsticks
MAX_AIR = 10.0           # seconds of breath under water
EXHAUSTION_PER_POINT = 4.0

# how tiring things are (4 exhaustion = 1 hunger point)
IDLE_PER_SECOND = 0.005
WALK_PER_BLOCK = 0.01
JUMP = 0.05
MINE = 0.025
ATTACK = 0.1
REGEN = 1.0              # healing 1 health costs this much

REGEN_EVERY = 4.0        # seconds per health point while well fed
STARVE_EVERY = 4.0       # seconds per lost health point at 0 hunger
DROWN_EVERY = 1.0
SAFE_FALL = 3            # blocks you can fall without getting hurt


class Survival:
    def __init__(self):
        self.respawn()

    def respawn(self):
        self.health = MAX_HEALTH
        self.hunger = MAX_HUNGER
        self.exhaustion = 0.0
        self.air = MAX_AIR
        self.dead = False
        self.cause = ""
        self.fall_top = None
        self._regen = self._starve = self._drown = 0.0

    # -- effects
    def exert(self, amount):
        self.exhaustion += amount
        while self.exhaustion >= EXHAUSTION_PER_POINT:
            self.exhaustion -= EXHAUSTION_PER_POINT
            self.hunger = max(0, self.hunger - 1)

    def damage(self, amount, cause):
        """Returns True if this actually hurt."""
        if self.dead or amount <= 0:
            return False
        self.health = max(0, self.health - amount)
        if self.health == 0:
            self.dead, self.cause = True, cause
        return True

    def eat(self, food_value):
        if self.dead or self.hunger >= MAX_HUNGER:
            return False
        self.hunger = min(MAX_HUNGER, self.hunger + food_value)
        return True

    # -- per frame
    def tick(self, dt, moved=0.0, head_under_water=False):
        """Advance hunger, healing, starving and drowning. Returns the damage taken this frame."""
        if self.dead:
            return 0
        before = self.health
        self.exert(dt * IDLE_PER_SECOND + moved * WALK_PER_BLOCK)

        if self.hunger >= 18 and self.health < MAX_HEALTH:
            self._regen += dt
            if self._regen >= REGEN_EVERY:
                self._regen = 0.0
                self.health += 1
                self.exert(REGEN)
        else:
            self._regen = 0.0
        if self.hunger == 0:
            self._starve += dt
            if self._starve >= STARVE_EVERY:
                self._starve = 0.0
                self.damage(1, "starved")
        else:
            self._starve = 0.0

        if head_under_water:
            self.air = max(0.0, self.air - dt)
            if self.air == 0:
                self._drown += dt
                if self._drown >= DROWN_EVERY:
                    self._drown = 0.0
                    self.damage(2, "drowned")
        else:
            self.air = min(MAX_AIR, self.air + dt * 4)
            self._drown = 0.0
        return max(0, before - self.health)

    def track_fall(self, y, on_ground, in_water):
        """Call every frame with the feet height. Returns fall damage taken on landing."""
        if in_water:
            self.fall_top = None              # water breaks any fall
            return 0
        if not on_ground:
            self.fall_top = y if self.fall_top is None else max(self.fall_top, y)
            return 0
        hurt = 0
        if self.fall_top is not None:
            hurt = math.floor(self.fall_top - y - SAFE_FALL)
            if hurt > 0:
                self.damage(hurt, "fell from a high place")
        self.fall_top = None
        return max(hurt, 0)

    # -- saving
    def to_data(self):
        return {"health": self.health, "hunger": self.hunger, "exhaustion": self.exhaustion}

    @classmethod
    def from_data(cls, data):
        s = cls()
        if data:
            s.health = max(1, data.get("health", MAX_HEALTH))
            s.hunger = data.get("hunger", MAX_HUNGER)
            s.exhaustion = data.get("exhaustion", 0.0)
        return s


def icons(value, maximum):
    """10 icons for a 0..20 value: 'full', 'half' or 'empty' each."""
    out = []
    for i in range(maximum // 2):
        left = value - i * 2
        out.append("full" if left >= 2 else "half" if left == 1 else "empty")
    return out
