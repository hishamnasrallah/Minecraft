"""Sound effects, synthesised from noise and tones (no recordings needed).

    python tools/export_godot.py   ->  godot/data/sounds/*.wav

Each sound is a short mono 16-bit WAV at 22 kHz. Filters are simple one-pole low/high
passes; every sound is deterministic (fixed random seed).
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050


def _env(t, attack, decay):
    """Fast attack, exponential decay."""
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def _lowpass(samples, cutoff):
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def _highpass(samples, cutoff):
    low = _lowpass(samples, cutoff)
    return [s - l for s, l in zip(samples, low)]


def _noise(n, rng):
    return [rng.uniform(-1, 1) for _ in range(n)]


def _normalise(samples, peak=0.9):
    m = max(abs(s) for s in samples) or 1.0
    return [s / m * peak for s in samples]


def dig_stone(rng):
    n = int(RATE * 0.14)
    noise = _highpass(_noise(n, rng), 1800)
    ring = [math.sin(2 * math.pi * 1250 * i / RATE) * 0.4 for i in range(n)]
    return [(a + b) * _env(i / RATE, 0.002, 0.03) for i, (a, b) in enumerate(zip(noise, ring))]


def dig_dirt(rng):
    n = int(RATE * 0.16)
    grains = [s * (1.0 if rng.random() < 0.3 else 0.35) for s in _noise(n, rng)]
    return [s * _env(i / RATE, 0.004, 0.05) for i, s in enumerate(_lowpass(grains, 1400))]


def dig_wood(rng):
    n = int(RATE * 0.16)
    noise = _lowpass(_noise(n, rng), 900)
    body = [math.sin(2 * math.pi * (190 - 40 * i / n) * i / RATE) for i in range(n)]
    return [(0.6 * a + b) * _env(i / RATE, 0.002, 0.045) for i, (a, b) in enumerate(zip(noise, body))]


def dig_glass(rng):
    n = int(RATE * 0.3)
    partials = ((2400, 1.0), (3700, 0.6), (5200, 0.35))
    tone = [sum(a * math.sin(2 * math.pi * f * i / RATE) for f, a in partials) for i in range(n)]
    noise = _highpass(_noise(n, rng), 3000)
    return [(t + 0.5 * z * math.exp(-i / RATE / 0.01)) * _env(i / RATE, 0.001, 0.07)
            for i, (t, z) in enumerate(zip(tone, noise))]


def dig_soft(rng):
    """Leaves, plants, wool: a soft rustle."""
    n = int(RATE * 0.16)
    noise = _highpass(_lowpass(_noise(n, rng), 5000), 900)
    return [s * 0.7 * _env(i / RATE, 0.02, 0.05) for i, s in enumerate(noise)]


def place(rng):
    n = int(RATE * 0.09)
    body = [math.sin(2 * math.pi * (140 - 50 * i / n) * i / RATE) for i in range(n)]
    noise = _lowpass(_noise(n, rng), 1200)
    return [(b + 0.4 * z) * _env(i / RATE, 0.001, 0.025) for i, (b, z) in enumerate(zip(body, noise))]


def step(rng):
    n = int(RATE * 0.07)
    return [s * _env(i / RATE, 0.003, 0.018) for i, s in enumerate(_lowpass(_noise(n, rng), 900))]


def splash(rng):
    n = int(RATE * 0.45)
    noise = _lowpass(_noise(n, rng), 2500)
    bubbles = [math.sin(2 * math.pi * (500 + 300 * math.sin(i / 400)) * i / RATE) * 0.15 for i in range(n)]
    return [(z + b) * _env(i / RATE, 0.01, 0.12) for i, (z, b) in enumerate(zip(noise, bubbles))]


def hurt(rng):
    n = int(RATE * 0.22)
    phase, out = 0.0, []
    for i in range(n):
        phase += 2 * math.pi * (260 - 160 * i / n) / RATE
        out.append((math.sin(phase) + 0.3 * math.sin(phase * 2.01)) * _env(i / RATE, 0.003, 0.07))
    return out


def eat(rng):
    out = []
    for k in range(3):
        burst = _lowpass(_noise(int(RATE * 0.07), rng), 2200)
        out += [s * _env(i / RATE, 0.004, 0.02) for i, s in enumerate(burst)]
        out += [0.0] * int(RATE * 0.05)
    return out


def pop(rng):
    n = int(RATE * 0.09)
    phase, out = 0.0, []
    for i in range(n):
        phase += 2 * math.pi * (500 + 900 * i / n) / RATE
        out.append(math.sin(phase) * _env(i / RATE, 0.002, 0.03))
    return out


def click(rng):
    n = int(RATE * 0.03)
    return [math.sin(2 * math.pi * 1700 * i / RATE) * _env(i / RATE, 0.0005, 0.006) for i in range(n)]


def rain(rng):
    """Steady rain: soft band-passed hiss plus scattered drop ticks, 2 s, made to loop
    seamlessly (the extra tail is cross-faded into the start)."""
    n, fade = int(RATE * 2.0), int(RATE * 0.25)
    total = n + fade
    hiss = _highpass(_lowpass(_noise(total, rng), 2600), 350)
    low = _lowpass(_noise(total, rng), 300)
    ticks = [0.0] * total
    for _ in range(140):                                   # individual drops
        at, amp = rng.randrange(total - 400), rng.uniform(0.3, 1.0)
        for k in range(300):
            ticks[at + k] += amp * rng.uniform(-1, 1) * math.exp(-k / 45)
    ticks = _highpass(_lowpass(ticks, 4500), 900)
    out = []
    for i in range(total):
        swell = 1.0 + 0.12 * math.sin(2 * math.pi * 2 * i / n)  # whole cycles per loop
        out.append((hiss[i] + 0.6 * low[i] + 0.35 * ticks[i]) * swell)
    for i in range(fade):                                  # equal-power cross-fade
        t = i / fade
        out[i] = out[i] * math.sin(t * math.pi / 2) + out[n + i] * math.cos(t * math.pi / 2)
    return out[:n]


def _tone(n, freq_at, amp_at, harmonics=((1, 1.0),)):
    """A tone whose pitch and loudness follow freq_at(t) and amp_at(t) (t in seconds)."""
    phase, out = 0.0, []
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * freq_at(t) / RATE
        out.append(sum(a * math.sin(phase * h) for h, a in harmonics) * amp_at(t))
    return out


def cluck(rng):
    """Two short throaty clucks."""
    out = []
    for k, f0 in enumerate((620, 540)):
        n = int(RATE * 0.07)
        tone = _tone(n, lambda t, f0=f0: f0 - 1800 * t, lambda t: _env(t, 0.004, 0.022),
                     ((1, 1.0), (2, 0.5), (3, 0.25)))
        grit = _lowpass(_noise(n, rng), 2400)
        out += [s + 0.25 * g * _env(i / RATE, 0.002, 0.015) for i, (s, g) in enumerate(zip(tone, grit))]
        out += [0.0] * int(RATE * 0.06)
    return out


def bleat(rng):
    """A wavering nasal call (vibrato on a buzzy tone)."""
    n = int(RATE * 0.42)
    tone = _tone(n, lambda t: 330 + 25 * math.sin(2 * math.pi * 11 * t) - 40 * t,
                 lambda t: min(1.0, t / 0.04) * math.exp(-max(0.0, t - 0.25) / 0.06),
                 ((1, 1.0), (2, 0.6), (3, 0.45), (4, 0.3), (5, 0.2)))
    return _lowpass(tone, 2600)


def croak(rng):
    """A low creaky ribbit: a buzz chopped into pulses."""
    n = int(RATE * 0.26)
    tone = _tone(n, lambda t: 150 + 60 * t, lambda t: _env(t, 0.01, 0.12) * (0.55 + 0.45 * math.sin(2 * math.pi * 38 * t)),
                 ((1, 1.0), (2, 0.7), (3, 0.5), (5, 0.3)))
    return _lowpass(tone, 1400)


def chirp(rng):
    """A quick upward whistle, twice."""
    out = []
    for f0 in (2400, 2900):
        n = int(RATE * 0.06)
        out += _tone(n, lambda t, f0=f0: f0 + 26000 * t, lambda t: math.sin(math.pi * t / 0.06) ** 2)
        out += [0.0] * int(RATE * 0.03)
    return out


SOUNDS = {
    "dig_stone": dig_stone, "dig_dirt": dig_dirt, "dig_wood": dig_wood, "dig_glass": dig_glass,
    "dig_soft": dig_soft, "place": place, "step": step, "splash": splash, "hurt": hurt, "eat": eat,
    "pop": pop, "click": click, "rain": rain,
    "cluck": cluck, "bleat": bleat, "croak": croak, "chirp": chirp,
}
LOOPS = {"rain"}          # ambient loops (longer; the game plays them with looping on)


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def export(folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    for i, (name, make) in enumerate(SOUNDS.items()):
        write_wav(folder / f"{name}.wav", _normalise(make(random.Random(1000 + i))))
    return list(SOUNDS)
