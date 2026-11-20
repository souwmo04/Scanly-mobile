"""Synthesises the background music and sound effects for the promo.

Everything is generated from scratch (no samples), so there are no licence
questions. Reads public/vo/timeline.json for scene boundaries and writes
public/music.wav. Music is ducked while the voice speaks.
"""

import json
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parent.parent
TIMELINE = json.loads((ROOT / "public" / "vo" / "timeline.json").read_text(encoding="utf-8"))
SR = 48000
FPS = 30
TOTAL = TIMELINE[-1]["startFrame"] + TIMELINE[-1]["durationFrames"]
N = int(TOTAL / FPS * SR) + SR // 2
rng = np.random.default_rng(7)

scene = {s["id"]: s for s in TIMELINE}


def t_of(sid: str) -> float:
    return scene[sid]["startFrame"] / FPS


REVEAL = t_of("reveal")
TURN = t_of("turn")
CTA = t_of("cta")
BPM = 100
BEAT = 60 / BPM

left = np.zeros(N)
right = np.zeros(N)


def add(sig: np.ndarray, start: float, gain: float = 1.0, pan: float = 0.0) -> None:
    i = int(start * SR)
    if i >= N:
        return
    sig = sig[: N - i]
    left[i : i + len(sig)] += sig * gain * (1 - max(pan, 0))
    right[i : i + len(sig)] += sig * gain * (1 + min(pan, 0))


def lp(sig, freq, order=2):
    return sosfilt(butter(order, freq, "low", fs=SR, output="sos"), sig)


def hp(sig, freq, order=2):
    return sosfilt(butter(order, freq, "high", fs=SR, output="sos"), sig)


def bp(sig, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), sig)


def env(n, attack, release):
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def saw(freq, dur, detune=0.0):
    t = np.arange(int(dur * SR)) / SR
    out = np.zeros_like(t)
    for d in (-detune, 0, detune):
        f = freq * (1 + d)
        out += 2 * ((t * f + rng.random()) % 1) - 1
    return out / 3


def note(name: str) -> float:
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440 * 2 ** ((names[pitch] + (octave - 4) * 12) / 12)


# --- Dark intro pad (hook + problem + turn) -------------------------------
dark = ["A2", "E3", "C4", "B3"]
dur = REVEAL
pad = sum(saw(note(n), dur, 0.004) for n in dark) / len(dark)
pad = lp(pad, 900)
t = np.arange(len(pad)) / SR
pad *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.25 * t)  # slow swell
add(pad * env(len(pad), 1.5, 0.3), 0, 0.22)
sub = np.sin(2 * np.pi * note("A1") * t) * env(len(t), 2.0, 0.3)
add(sub, 0, 0.18)

# Heartbeat thumps during the problem scene.
def kick(f0=120, f1=42, length=0.35):
    n = int(length * SR)
    tt = np.arange(n) / SR
    freq = f1 + (f0 - f1) * np.exp(-tt * 28)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-tt * 9)


p0, p1 = t_of("problem"), TURN
x = p0
while x < p1 - 0.2:
    add(kick(90, 38, 0.4), x, 0.55)
    add(kick(90, 38, 0.4), x + 0.22, 0.35)
    x += 1.1

# Riser into the reveal.
rise_len = REVEAL - TURN
n = int(rise_len * SR)
tt = np.arange(n) / SR
noise = rng.standard_normal(n)
riser = np.zeros(n)
chunks = 40
for k in range(chunks):
    a, b = k * n // chunks, (k + 1) * n // chunks
    centre = 300 * (12000 / 300) ** (k / chunks)
    riser[a:b] = bp(noise, centre * 0.7, min(centre * 1.3, 20000))[a:b]
riser *= (tt / rise_len) ** 2.2
tone_f = 110 * (880 / 110) ** (tt / rise_len)
riser += 0.35 * np.sin(2 * np.pi * np.cumsum(tone_f) / SR) * (tt / rise_len) ** 2
add(riser, TURN, 0.5)

# --- Impact at the reveal -------------------------------------------------
def impact(length=3.0):
    n = int(length * SR)
    tt = np.arange(n) / SR
    boom = kick(160, 32, length) * 1.4
    crash = hp(rng.standard_normal(n), 3000) * np.exp(-tt * 2.2) * 0.5
    return boom + crash


add(impact(), REVEAL, 0.9)
add(impact(2.5), CTA, 0.7)

# --- Bright section: chords + beat from the reveal ------------------------
progression = [["C3", "G3", "E4", "C5"], ["G2", "D3", "B3", "G4"], ["A2", "E3", "C4", "A4"], ["F2", "C3", "A3", "F4"]]
bar = 4 * BEAT
x, i = REVEAL, 0
end = TOTAL / FPS
while x < end:
    chord = progression[i % 4]
    length = min(bar, end - x) + 0.4
    sig = sum(saw(note(nm), length, 0.006) for nm in chord) / 4
    sig = lp(sig, 2400)
    sig *= env(len(sig), 0.05, 0.4)
    add(sig, x, 0.16, pan=-0.2)
    add(sig, x, 0.16, pan=0.2)
    # Plucked arpeggio on eighth notes.
    for s in range(8):
        nm = chord[[1, 2, 3, 2, 1, 2, 3, 2][s]]
        f = note(nm) * 2
        pl = int(0.25 * SR)
        tp = np.arange(pl) / SR
        pluck = np.sin(2 * np.pi * f * tp) * np.exp(-tp * 14)
        add(pluck, x + s * BEAT / 2, 0.10, pan=0.4 if s % 2 else -0.4)
    x += bar
    i += 1

beat_end = end - 1.5
x = REVEAL + bar / 2  # let the impact breathe first
k = 0
while x < beat_end:
    add(kick(), x, 0.7)
    hat_n = int(0.06 * SR)
    hat = hp(rng.standard_normal(hat_n), 7000) * np.exp(-np.arange(hat_n) / SR * 60)
    add(hat, x + BEAT / 2, 0.18, pan=0.3)
    if k % 2 == 1:
        sn_n = int(0.2 * SR)
        snare = bp(rng.standard_normal(sn_n), 900, 6000) * np.exp(-np.arange(sn_n) / SR * 18)
        add(snare, x, 0.28)
    x += BEAT
    k += 1

# --- Whooshes at every other scene change ---------------------------------
def whoosh(length=0.6):
    n = int(length * SR)
    tt = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    chunks = 12
    for c in range(chunks):
        a, b = c * n // chunks, (c + 1) * n // chunks
        centre = 400 + 5000 * np.sin(np.pi * c / chunks)
        out[a:b] = bp(noise, centre * 0.6, centre * 1.4)[a:b]
    return out * np.sin(np.pi * tt / length) ** 2


for s in TIMELINE[1:]:
    if s["id"] in ("reveal", "turn", "cta"):
        continue
    add(whoosh(), s["startFrame"] / FPS - 0.3, 0.35)

# --- Duck under the voice, fade out, normalise ----------------------------
duck = np.ones(N)
for s in TIMELINE:
    a = s["startFrame"] / FPS + s["voiceDelayFrames"] / FPS
    b = a + s["seconds"]
    ia, ib = int(a * SR), int(b * SR)
    duck[ia:ib] = 0.55
duck = lp(duck, 4)  # smooth the gain changes
fade = np.ones(N)
fs = int(end * SR) - int(2.0 * SR)
fade[fs:] = np.linspace(1, 0, N - fs) ** 1.5
mix = np.stack([left, right], axis=1) * (duck * fade)[:, None]
mix /= np.max(np.abs(mix)) + 1e-9
mix *= 0.89
wavfile.write(ROOT / "public" / "music.wav", SR, (mix * 32767).astype(np.int16))
print(f"music.wav {N / SR:.2f}s")
