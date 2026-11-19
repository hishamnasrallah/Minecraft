import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import sounds  # noqa: E402


def test_all_sounds_export_as_short_wavs(tmp_path):
    names = sounds.export(tmp_path)
    assert len(names) == len(sounds.SOUNDS) >= 12
    for name in names:
        with wave.open(str(tmp_path / f"{name}.wav")) as w:
            assert w.getnchannels() == 1 and w.getframerate() == sounds.RATE
            seconds = w.getnframes() / w.getframerate()
            if name in sounds.LOOPS:
                assert 1.0 < seconds < 3.0, name
            else:
                assert 0.02 < seconds < 0.6, name
            frames = w.readframes(w.getnframes())
            assert any(frames), f"{name} is silent"
