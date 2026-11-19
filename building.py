"""Creative bulk building: a two-corner selection, fill / replace / hollow / clear,
copy & paste with rotate and mirror, and undo. Pure Python so it can be unit-tested.
"""
from blocks import BLOCK_DEFS, DOORS, STAIRS, LADDERS

MAX_BLOCKS = 32768          # largest selection one operation may touch (32 x 32 x 32)
UNDO_STEPS = 20

_STAIR_GROUPS = {i: group for group in STAIRS.values() for i in group}


def rotate_block(block_id):
    """The same block turned 90 degrees clockwise (seen from above)."""
    d = BLOCK_DEFS.get(block_id)
    if not d or "facing" not in d and block_id not in DOORS:
        return block_id
    if block_id in _STAIR_GROUPS:
        group = _STAIR_GROUPS[block_id]
        return group[(group.index(block_id) + 1) % 4]
    if block_id in LADDERS:
        return LADDERS[(LADDERS.index(block_id) + 1) % 4]
    if block_id in DOORS:                     # doors only have an axis: turning swaps it
        return block_id + 4 if DOORS[block_id]["axis"] == 0 else block_id - 4
    return block_id


def mirror_block(block_id):
    """The same block flipped left-right along the x axis (facing +x <-> -x)."""
    if block_id in _STAIR_GROUPS:
        group = _STAIR_GROUPS[block_id]
        f = group.index(block_id)
        return group[{1: 3, 3: 1}.get(f, f)]
    if block_id in LADDERS:
        f = LADDERS.index(block_id)
        return LADDERS[{1: 3, 3: 1}.get(f, f)]
    return block_id


class Builder:
    def __init__(self):
        self.corner1 = self.corner2 = None
        self.clipboard = None             # {(dx, dy, dz): block id}, offsets from 0 upward
        self.undo_stack = []              # list of {pos: previous id}

    # -- selection
    def bounds(self):
        if self.corner1 is None or self.corner2 is None:
            return None
        lo = tuple(min(a, b) for a, b in zip(self.corner1, self.corner2))
        hi = tuple(max(a, b) for a, b in zip(self.corner1, self.corner2))
        return lo, hi

    def size(self):
        b = self.bounds()
        return tuple(h - l + 1 for l, h in zip(*b)) if b else None

    def volume(self):
        s = self.size()
        return s[0] * s[1] * s[2] if s else 0

    def cells(self):
        (x0, y0, z0), (x1, y1, z1) = self.bounds()
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    yield (x, y, z)

    def clear_selection(self):
        self.corner1 = self.corner2 = None

    # -- operations; each returns (chunk keys to rebuild, message)
    def _check(self):
        if self.bounds() is None:
            return "Select two corners first (Z and X)"
        if self.volume() > MAX_BLOCKS:
            return f"Selection too big ({self.volume()} blocks, max {MAX_BLOCKS})"
        return None

    def _apply(self, world, changes):
        keys, previous = world.bulk_set(changes)
        if previous:
            self.undo_stack.append(previous)
            del self.undo_stack[:-UNDO_STEPS]
        return keys, len(previous)

    def fill(self, world, block_id, hollow=False, replace=None):
        """Fill the selection. hollow: only the outer shell. replace: only cells holding that block."""
        problem = self._check()
        if problem:
            return set(), problem
        (x0, y0, z0), (x1, y1, z1) = self.bounds()
        changes = {}
        for pos in self.cells():
            x, y, z = pos
            if hollow and x0 < x < x1 and y0 < y < y1 and z0 < z < z1:
                continue
            if replace is not None and world.get(*pos) != replace:
                continue
            changes[pos] = block_id
        keys, n = self._apply(world, changes)
        return keys, f"Changed {n} blocks"

    def copy(self, world):
        problem = self._check()
        if problem:
            return problem
        lo = self.bounds()[0]
        self.clipboard = {(x - lo[0], y - lo[1], z - lo[2]): world.get(x, y, z) for x, y, z in self.cells()}
        solid = sum(1 for b in self.clipboard.values() if b)
        return f"Copied {self.size()[0]}x{self.size()[1]}x{self.size()[2]} ({solid} blocks)"

    def clipboard_size(self):
        if not self.clipboard:
            return None
        return tuple(max(p[a] for p in self.clipboard) + 1 for a in range(3))

    def paste(self, world, origin, include_air=False):
        """Paste with the clipboard's lowest corner at `origin`."""
        if not self.clipboard:
            return set(), "Nothing copied yet (C)"
        changes = {(origin[0] + dx, origin[1] + dy, origin[2] + dz): b
                   for (dx, dy, dz), b in self.clipboard.items() if b or include_air}
        keys, n = self._apply(world, changes)
        return keys, f"Pasted {n} blocks"

    def rotate(self):
        """Turn the clipboard 90 degrees clockwise around the vertical axis."""
        if not self.clipboard:
            return "Nothing copied yet (C)"
        size_x = self.clipboard_size()[0]
        # (x, z) -> (z, size_x - 1 - x) keeps every offset >= 0
        self.clipboard = {(dz, dy, size_x - 1 - dx): rotate_block(b) for (dx, dy, dz), b in self.clipboard.items()}
        return "Rotated the copy 90 degrees"

    def mirror(self):
        if not self.clipboard:
            return "Nothing copied yet (C)"
        size_x = self.clipboard_size()[0]
        self.clipboard = {(size_x - 1 - dx, dy, dz): mirror_block(b) for (dx, dy, dz), b in self.clipboard.items()}
        return "Mirrored the copy"

    def undo(self, world):
        if not self.undo_stack:
            return set(), "Nothing to undo"
        previous = self.undo_stack.pop()
        keys, _ = world.bulk_set(previous)
        return keys, f"Undid {len(previous)} block changes"
