#!/usr/bin/env python3
"""Generate candidate notification chime sounds for Jools.

Each chime is a short (≤2s), gentle tonal sound synthesized from
sine waves with ADSR envelope shaping. Output is 16-bit 44.1kHz
mono WAV at -12dB (to avoid raw-sine harshness).

Run: python3 scripts/generate_chimes.py
Output: Jools/Resources/Sounds/jools-chime-{name}.wav
Then convert: for f in Jools/Resources/Sounds/*.wav; do
    afconvert "$f" "${f%.wav}.caf" -d LEI16 -f caff
done
"""

import math
import struct
import wave
import os

SAMPLE_RATE = 44100
GAIN_DB = -12  # attenuate from raw sine
GAIN = 10 ** (GAIN_DB / 20)  # ≈ 0.25
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                          "Jools", "Resources", "Sounds")


def sine(freq: float, t: float) -> float:
    """Pure sine wave at frequency freq, at time t."""
    return math.sin(2 * math.pi * freq * t)


def adsr(t: float, attack: float, decay: float, sustain_level: float,
         sustain_dur: float, release: float) -> float:
    """ADSR envelope. Returns amplitude [0, 1] at time t."""
    if t < attack:
        return t / attack
    t -= attack
    if t < decay:
        return 1.0 - (1.0 - sustain_level) * (t / decay)
    t -= decay
    if t < sustain_dur:
        return sustain_level
    t -= sustain_dur
    if t < release:
        return sustain_level * (1.0 - t / release)
    return 0.0


def write_wav(filename: str, samples: list[float], sample_rate: int = SAMPLE_RATE):
    """Write mono 16-bit WAV file."""
    path = os.path.join(OUTPUT_DIR, filename)
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        for s in samples:
            clamped = max(-1.0, min(1.0, s))
            wf.writeframes(struct.pack("<h", int(clamped * 32767)))
    print(f"  wrote {path} ({len(samples) / sample_rate:.2f}s)")


def generate_gentle():
    """Two-tone ascending chime (C5→E5), soft attack, reverb tail."""
    duration = 1.5
    n = int(SAMPLE_RATE * duration)
    samples = []
    c5 = 523.25
    e5 = 659.25

    for i in range(n):
        t = i / SAMPLE_RATE
        # First tone: C5 with soft attack
        env1 = adsr(t, attack=0.02, decay=0.15, sustain_level=0.3,
                     sustain_dur=0.1, release=0.8)
        tone1 = sine(c5, t) * env1

        # Second tone: E5, delayed by 0.15s
        t2 = t - 0.15
        if t2 > 0:
            env2 = adsr(t2, attack=0.02, decay=0.12, sustain_level=0.35,
                        sustain_dur=0.1, release=0.9)
            tone2 = sine(e5, t2) * env2
        else:
            tone2 = 0.0

        # Light harmonic shimmer (octave above, quiet)
        shimmer = sine(c5 * 2, t) * env1 * 0.15
        shimmer2 = sine(e5 * 2, t - 0.15) * (env2 if t > 0.15 else 0) * 0.12

        samples.append((tone1 + tone2 + shimmer + shimmer2) * GAIN)

    write_wav("jools-chime-gentle.wav", samples)


def generate_warm():
    """Marimba-like single note (G4) with warm harmonics, fast decay."""
    duration = 1.2
    n = int(SAMPLE_RATE * duration)
    samples = []
    g4 = 392.0

    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, attack=0.003, decay=0.08, sustain_level=0.2,
                   sustain_dur=0.05, release=0.9)

        # Fundamental
        s = sine(g4, t) * 1.0
        # 2nd harmonic (warm character)
        s += sine(g4 * 2, t) * 0.5
        # 3rd harmonic (marimba body)
        s += sine(g4 * 3, t) * 0.2
        # 4th (subtle brightness)
        s += sine(g4 * 4, t) * 0.08

        # Percussive transient: brief noise burst
        if t < 0.005:
            import random
            s += random.uniform(-0.3, 0.3) * (1.0 - t / 0.005)

        samples.append(s * env * GAIN * 0.7)

    write_wav("jools-chime-warm.wav", samples)


def generate_minimal():
    """Clean sine pluck (A4), very short. A UI confirmation sound."""
    duration = 0.8
    n = int(SAMPLE_RATE * duration)
    samples = []
    a4 = 440.0

    for i in range(n):
        t = i / SAMPLE_RATE
        env = adsr(t, attack=0.001, decay=0.06, sustain_level=0.15,
                   sustain_dur=0.02, release=0.6)

        s = sine(a4, t) * 1.0
        # Very subtle 2nd harmonic
        s += sine(a4 * 2, t) * 0.15

        samples.append(s * env * GAIN)

    write_wav("jools-chime-minimal.wav", samples)


def generate_duo():
    """Two-note descending motif (E5→C5), playful doorbell feel."""
    duration = 1.3
    n = int(SAMPLE_RATE * duration)
    samples = []
    e5 = 659.25
    c5 = 523.25

    for i in range(n):
        t = i / SAMPLE_RATE
        # First note: E5
        env1 = adsr(t, attack=0.005, decay=0.1, sustain_level=0.25,
                     sustain_dur=0.08, release=0.5)
        tone1 = sine(e5, t) * env1
        tone1 += sine(e5 * 2, t) * env1 * 0.2

        # Second note: C5, delayed by 0.2s
        t2 = t - 0.2
        if t2 > 0:
            env2 = adsr(t2, attack=0.005, decay=0.1, sustain_level=0.3,
                        sustain_dur=0.1, release=0.7)
            tone2 = sine(c5, t2) * env2
            tone2 += sine(c5 * 2, t2) * env2 * 0.18
        else:
            tone2 = 0.0

        samples.append((tone1 + tone2) * GAIN)

    write_wav("jools-chime-duo.wav", samples)


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print("Generating Jools notification chimes...")
    generate_gentle()
    generate_warm()
    generate_minimal()
    generate_duo()
    print("\nDone. Converting to .caf...")

    import subprocess
    for name in ["gentle", "warm", "minimal", "duo"]:
        wav = os.path.join(OUTPUT_DIR, f"jools-chime-{name}.wav")
        caf = os.path.join(OUTPUT_DIR, f"jools-chime-{name}.caf")
        subprocess.run([
            "afconvert", wav, caf,
            "-d", "LEI16", "-f", "caff"
        ], check=True)
        print(f"  converted → {caf}")

    print("\nAll chimes ready.")
