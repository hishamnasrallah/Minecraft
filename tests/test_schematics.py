import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import schematics  # noqa: E402
from blocks import STAIRS, BLOCKS  # noqa: E402


def sample():
    clip = {(x, y, z): 0 for x in range(3) for y in range(2) for z in range(4)}
    for x in range(3):
        for z in range(4):
            clip[(x, 0, z)] = 41
    clip[(1, 1, 2)] = STAIRS[7][1]
    clip[(0, 1, 0)] = 510
    return clip


def test_round_trip(tmp_path):
    clip = sample()
    path = schematics.save(clip, "My House 1", tmp_path)
    assert path.name == "My_House_1.json"
    assert schematics.load(path) == clip
    assert schematics.list_saved(tmp_path) == [(path, "My House 1", (3, 2, 4))]


def test_runs_keep_files_small(tmp_path):
    clip = {(x, y, z): 3 for x in range(16) for y in range(16) for z in range(16)}
    data = schematics.to_data(clip, "cube")
    assert data["blocks"] == [[0, 4096]] and len(data["palette"]) == 1


def test_matches_blocks_by_name_when_ids_change():
    data = schematics.to_data(sample(), "x")
    for entry in data["palette"]:
        if entry[0] == "stone bricks":
            entry[1] = 9999                           # pretend the id changed
        if entry[0] == "brick":
            entry[1] = 1
    assert schematics.from_data(data) == sample()
    data["palette"].append(["some removed block", 777])
    data["blocks"][0][0] = len(data["palette"]) - 1  # unknown blocks turn into air
    assert schematics.from_data(data)[(0, 0, 0)] == 0


def test_bad_files_are_rejected_or_skipped(tmp_path):
    with pytest.raises(ValueError):
        schematics.from_data({"format": "something else"})
    data = schematics.to_data(sample(), "x")
    data["blocks"] = data["blocks"][:-1]
    with pytest.raises(ValueError):
        schematics.from_data(data)
    (tmp_path / "broken.json").write_text("{not json")
    (tmp_path / "other.json").write_text(json.dumps({"hello": 1}))
    schematics.save(sample(), "ok", tmp_path)
    assert [name for _, name, _ in schematics.list_saved(tmp_path)] == ["ok"]


def test_names_are_made_safe(tmp_path):
    assert schematics.clean_name("  ../../evil name!! ") == "evil_name"
    assert schematics.clean_name("بيت صغير") == "بيت_صغير"
    with pytest.raises(ValueError):
        schematics.save(sample(), "///", tmp_path)
    with pytest.raises(ValueError):
        schematics.save({}, "empty", tmp_path)
    path = schematics.save(sample(), "gone", tmp_path)
    schematics.delete(path)
    assert not path.exists()


def test_bundled_examples_load():
    found = schematics.list_saved()
    assert found
    for path, _, size in found:
        clip = schematics.load(path)
        assert len(clip) == size[0] * size[1] * size[2]
        assert all(b == 0 or b in BLOCKS for b in clip.values())
