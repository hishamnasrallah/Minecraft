"""Saving copied structures (the building clipboard) as shareable schematic files.

A schematic is a small JSON file in the schematics/ folder:

    {
      "format": "blockworld-schematic", "version": 1,
      "name": "small house", "size": [x, y, z],
      "palette": [["air", 0], ["stone bricks", 41], ...],     # [block name, block id]
      "blocks": [[palette index, run length], ...]            # x, then y, then z order
    }

Repeated blocks are stored as runs to keep files small. Blocks are matched by name
first (so files survive id changes) and by id as a fallback. Pure Python, unit-tested.
"""
import json
import re
from pathlib import Path

from blocks import BLOCK_DEFS, BLOCKS

FOLDER = Path(__file__).with_name("schematics")
FORMAT = "blockworld-schematic"
_BY_NAME = {}
for _id, _name in BLOCKS.items():
    _BY_NAME.setdefault(_name, _id)          # oriented variants share a name: keep the first id


def clean_name(name):
    """Turn a typed name into a safe file name (letters/digits in any script, - and _)."""
    name = re.sub(r"[^\w\- ]", "", name.strip())[:40].strip()
    return re.sub(r"\s+", "_", name)


def to_data(clipboard, name):
    size = [max(p[a] for p in clipboard) + 1 for a in range(3)]
    palette, index, runs = [], {}, []
    for x in range(size[0]):
        for y in range(size[1]):
            for z in range(size[2]):
                b = clipboard.get((x, y, z), 0)
                if b not in index:
                    index[b] = len(palette)
                    palette.append([BLOCKS.get(b, "air"), b])
                i = index[b]
                if runs and runs[-1][0] == i:
                    runs[-1][1] += 1
                else:
                    runs.append([i, 1])
    return {"format": FORMAT, "version": 1, "name": name, "size": size, "palette": palette, "blocks": runs}


def from_data(data):
    """Back to a clipboard dict. Unknown blocks become air. Raises ValueError on a bad file."""
    if data.get("format") != FORMAT:
        raise ValueError("not a BlockWorld schematic")
    sx, sy, sz = data["size"]
    ids = []
    for name, block_id in data["palette"]:
        if block_id and BLOCKS.get(block_id) == name:
            ids.append(block_id)             # exact id still means the same block
        else:
            ids.append(_BY_NAME.get(name, 0) if name != "air" else 0)
    cells = [ids[i] for i, run in data["blocks"] for _ in range(run)]
    if len(cells) != sx * sy * sz:
        raise ValueError("schematic is damaged (wrong number of blocks)")
    clipboard, n = {}, 0
    for x in range(sx):
        for y in range(sy):
            for z in range(sz):
                clipboard[(x, y, z)] = cells[n] if cells[n] in BLOCK_DEFS else 0
                n += 1
    return clipboard


def save(clipboard, name, folder=FOLDER):
    file_name = clean_name(name)
    if not file_name:
        raise ValueError("give the schematic a name")
    if not clipboard:
        raise ValueError("nothing copied yet (C)")
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{file_name}.json"
    path.write_text(json.dumps(to_data(clipboard, name.strip()), separators=(",", ":")), encoding="utf-8")
    return path


def load(path):
    return from_data(json.loads(Path(path).read_text(encoding="utf-8")))


def list_saved(folder=FOLDER):
    """[(path, display name, size)] of the schematics in the folder, by name. Broken files are skipped."""
    found = []
    for path in sorted(folder.glob("*.json")) if folder.exists() else []:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if data.get("format") == FORMAT:
                found.append((path, data.get("name") or path.stem, tuple(data["size"])))
        except (ValueError, KeyError, OSError):
            continue
    return found


def delete(path):
    Path(path).unlink(missing_ok=True)
