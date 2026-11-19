"""The ready-made factories: every design builds, uses only real blocks, and the machines
point the right way (detailed behaviour is tested in Godot: godot/tests/test_factories.gd)."""
import json

import factories
import schematics
from blocks import BLOCK_DEFS


def test_every_design_builds_with_real_blocks():
    designs = factories.all_designs()
    assert len(designs) >= 10
    for file, en, ar, category, clip in designs:
        assert category in ("small_factories", "big_factories")
        assert en and ar
        assert min(p[1] for p in clip) == 0
        assert all(b == 0 or b in BLOCK_DEFS for b in clip.values()), file


def test_designs_round_trip_as_schematics():
    for file, en, ar, category, clip in factories.all_designs():
        data = json.loads(json.dumps(schematics.to_data(clip, en)))
        back = schematics.from_data(data)
        assert {p: b for p, b in back.items() if b} == {p: b for p, b in clip.items() if b}, file


def test_big_factories_are_big_but_light():
    sizes = {file: sum(1 for b in clip.values() if b) for file, *_rest, clip in factories.all_designs()}
    assert sizes["mega_complex"] > 10000            # a whole industrial town...
    assert sizes["mega_complex"] < 40000            # ...that still pastes quickly on a phone
    assert sizes["giant_farm"] > sizes["wheat_harvester"] * 10
