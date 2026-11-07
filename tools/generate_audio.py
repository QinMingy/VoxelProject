"""Generate the original Moon Demo SFX bank using only the Python standard library.

Run from any directory with ``python tools/generate_audio.py``. All synthesis is
deterministic and uses no recordings, samples, external libraries, or services.
"""

from __future__ import annotations

import math
from pathlib import Path
import random
import struct
import wave

RATE = 32000
TAU = math.tau
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def buffer(seconds: float) -> list[float]:
    return [0.0] * round(seconds * RATE)


def tone(samples: list[float], start: float, duration: float, frequency: float,
         amplitude: float, decay: float = 4.0, glide: float = 0.0,
         harmonics: tuple[float, ...] = (1.0, 0.20, 0.05)) -> None:
    offset = round(start * RATE)
    length = min(round(duration * RATE), len(samples) - offset)
    for index in range(max(0, length)):
        t = index / RATE
        phase = TAU * (frequency * t + glide * t * t / (2.0 * duration))
        attack = min(1.0, t / 0.005)
        release = min(1.0, (duration - t) / 0.018)
        envelope = attack * release * math.exp(-decay * t / duration)
        value = sum(weight * math.sin(phase * (partial + 1))
                    for partial, weight in enumerate(harmonics))
        samples[offset + index] += value * amplitude * envelope


def grit(samples: list[float], rng: random.Random, start: float, duration: float,
         amplitude: float, lowpass_hz: float = 2100.0, decay: float = 5.0) -> None:
    offset = round(start * RATE)
    length = min(round(duration * RATE), len(samples) - offset)
    smooth = 0.0
    rumble = 0.0
    coefficient = 1.0 - math.exp(-TAU * lowpass_hz / RATE)
    for index in range(max(0, length)):
        t = index / RATE
        smooth += coefficient * (rng.uniform(-1.0, 1.0) - smooth)
        rumble += 0.017 * (smooth - rumble)
        envelope = min(1.0, t / 0.003) * min(1.0, (duration - t) / 0.015)
        envelope *= math.exp(-decay * t / duration)
        samples[offset + index] += (smooth - rumble) * amplitude * envelope


def write(name: str, samples: list[float], peak: float = 0.62,
          loop: bool = False) -> None:
    # Remove DC and retain at least 4 dB sample headroom before runtime mixing.
    dc = sum(samples) / max(1, len(samples))
    samples = [sample - dc for sample in samples]
    maximum = max(abs(sample) for sample in samples)
    scale = peak / max(maximum, 0.001)
    fade = round((0.003 if loop else 0.008) * RATE)
    for index in range(fade):
        gain = 0.5 - 0.5 * math.cos(math.pi * index / fade)
        samples[index] *= gain
        samples[-index - 1] *= gain
    pcm = b"".join(struct.pack("<h", round(sample * scale * 32767)) for sample in samples)
    with wave.open(str(OUTPUT / f"{name}.wav"), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm)


def drill() -> None:
    samples = buffer(1.6)
    rng = random.Random(9173)
    # Exactly 24 strikes and integral motor cycles give a stable loop cadence.
    for index in range(len(samples)):
        t = index / RATE
        samples[index] = 0.035 * math.sin(TAU * 75.0 * t)
        samples[index] += 0.012 * math.sin(TAU * 150.0 * t)
    for strike in range(24):
        at = strike / 15.0
        strength = rng.uniform(0.84, 1.0)
        tone(samples, at, 0.055, 112.0, 0.25 * strength, 7.0,
             glide=-55.0, harmonics=(1.0, 0.35, 0.11))
        grit(samples, rng, at, 0.060, 0.52 * strength, 2400.0, 6.0)
        tone(samples, at, 0.025, 1650.0, 0.035, 9.0, harmonics=(1.0,))
    write("drill_loop", samples, loop=True)


def ground_sounds() -> None:
    for variant in range(4):
        rng = random.Random(3100 + variant)
        samples = buffer(0.26)
        tone(samples, 0.0, 0.16, 78.0 + variant * 4.0, 0.32, 7.0,
             glide=-24.0, harmonics=(1.0, 0.1))
        grit(samples, rng, 0.0, 0.23, 0.75, 1500.0, 5.0)
        grit(samples, rng, 0.055, 0.17, 0.24, 3100.0, 6.0)
        write(f"footstep_{variant + 1}", samples, 0.52)
    for variant in range(3):
        rng = random.Random(4200 + variant)
        samples = buffer(0.38)
        tone(samples, 0.0, 0.22, 92.0 + variant * 13.0, 0.28, 6.0, glide=-35.0)
        grit(samples, rng, 0.0, 0.30, 0.95, 3000.0, 5.0)
        for chip in range(5):
            at = 0.022 + chip * 0.035
            grit(samples, rng, at, 0.09, 0.19, 4200.0, 7.0)
        write(f"dig_{variant + 1}", samples)
    samples = buffer(0.25)
    grit(samples, random.Random(50), 0.0, 0.21, 0.35, 1100.0, 2.0)
    tone(samples, 0.015, 0.18, 130.0, 0.22, 4.0, glide=70.0)
    write("jump", samples, 0.48)
    samples = buffer(0.38)
    tone(samples, 0.0, 0.25, 69.0, 0.5, 7.0, glide=-28.0)
    grit(samples, random.Random(51), 0.004, 0.31, 0.8, 1400.0, 5.5)
    write("land", samples)


def crystal_sounds() -> None:
    samples = buffer(0.83)
    for at, note in [(0.0, 659.25), (0.06, 987.77), (0.14, 1318.51)]:
        tone(samples, at, 0.60, note, 0.17, 5.0, harmonics=(1.0, 0.13, 0.025))
    grit(samples, random.Random(61), 0.0, 0.19, 0.17, 2800.0, 6.0)
    write("crystal_exposed", samples, 0.56)
    samples = buffer(1.04)
    grit(samples, random.Random(62), 0.0, 0.45, 0.50, 1600.0, 4.0)
    tone(samples, 0.0, 0.32, 82.0, 0.25, 5.0, glide=-25.0)
    for at, note in [(0.06, 523.25), (0.13, 783.99), (0.20, 1046.50)]:
        tone(samples, at, 0.75, note, 0.22, 4.5, harmonics=(1.0, 0.16, 0.04))
    write("crystal_loose", samples)
    samples = buffer(0.66)
    for at, note in [(0.0, 392.0), (0.07, 587.33), (0.14, 783.99)]:
        tone(samples, at, 0.42, note, 0.24, 5.0, harmonics=(1.0, 0.10))
    tone(samples, 0.03, 0.10, 125.0, 0.20, 6.0)
    write("crystal_pickup", samples)
    samples = buffer(0.45)
    tone(samples, 0.0, 0.25, 103.0, 0.30, 6.0, glide=-45.0)
    grit(samples, random.Random(63), 0.005, 0.34, 0.6, 1700.0, 5.0)
    tone(samples, 0.035, 0.31, 740.0, 0.13, 5.0, harmonics=(1.0, 0.10))
    write("crystal_drop", samples)


def oxygen_sounds() -> None:
    for variant in range(3):
        samples = buffer(0.20)
        frequency = [783.99, 880.0, 987.77][variant]
        tone(samples, 0.0, 0.18, frequency, 0.22, 4.0, glide=frequency * 0.2,
             harmonics=(1.0, 0.08))
        tone(samples, 0.025, 0.14, frequency * 1.5, 0.04, 5.5, harmonics=(1.0,))
        write(f"oxygen_pickup_{variant + 1}", samples, 0.43)
    for name, notes, spacing in [
        ("oxygen_low", [620.0, 760.0], 0.23),
        ("oxygen_critical", [760.0, 620.0, 760.0], 0.18),
        ("boundary_warning", [360.0, 310.0], 0.19),
    ]:
        samples = buffer(spacing * (len(notes) - 1) + 0.24)
        for index, note in enumerate(notes):
            tone(samples, index * spacing, 0.18, note, 0.30, 1.0,
                 harmonics=(1.0, 0.10))
        write(name, samples, 0.48)


def airlock_sounds() -> None:
    samples = buffer(1.45)
    grit(samples, random.Random(70), 0.0, 1.26, 0.26, 900.0, 1.5)
    tone(samples, 0.0, 1.10, 68.0, 0.24, 1.7, glide=42.0)
    for at, note in [(0.15, 440.0), (0.38, 660.0)]:
        tone(samples, at, 0.40, note, 0.12, 4.0, harmonics=(1.0, 0.08))
    write("deploy", samples)
    samples = buffer(1.65)
    grit(samples, random.Random(71), 0.0, 1.3, 0.13, 750.0, 2.0)
    for at, note in [(0.0, 392.0), (0.17, 523.25), (0.34, 783.99)]:
        tone(samples, at, 0.95, note, 0.22, 3.6, harmonics=(1.0, 0.11, 0.025))
    tone(samples, 0.2, 0.25, 100.0, 0.13, 5.0)
    write("safe_extract", samples)
    samples = buffer(1.50)
    for at, note in [(0.0, 392.0), (0.18, 293.66), (0.36, 196.0)]:
        tone(samples, at, 0.45, note, 0.20, 3.5, harmonics=(1.0, 0.16))
    grit(samples, random.Random(72), 0.45, 0.95, 0.22, 950.0, 2.5)
    tone(samples, 0.63, 0.45, 82.0, 0.23, 5.0, glide=-14.0)
    write("rescue", samples, 0.58)


def interface_sounds() -> None:
    samples = buffer(0.36)
    tone(samples, 0.0, 0.32, 880.0, 0.22, 5.0, glide=-120.0, harmonics=(1.0, 0.04))
    write("radar_ping", samples, 0.40)
    for name, frequency, glide in [("ui_click", 520.0, -170.0),
                                   ("rotate", 700.0, 100.0)]:
        samples = buffer(0.09)
        tone(samples, 0.0, 0.075, frequency, 0.23, 6.0, glide=glide,
             harmonics=(1.0, 0.14))
        grit(samples, random.Random(81), 0.0, 0.035, 0.10, 2400.0, 7.0)
        write(name, samples, 0.44)
    for name, notes in [("menu_open", [360.0, 540.0]),
                        ("menu_close", [540.0, 360.0])]:
        samples = buffer(0.23)
        for index, note in enumerate(notes):
            tone(samples, index * 0.055, 0.15, note, 0.25, 4.5, harmonics=(1.0, 0.10))
        write(name, samples, 0.43)
    samples = buffer(0.31)
    for note in [196.0, 233.08]:
        tone(samples, 0.0, 0.27, note, 0.21, 2.5, harmonics=(1.0, 0.12))
    write("error", samples, 0.47)
    samples = buffer(0.64)
    for index, note in enumerate([523.25, 659.25, 1046.50]):
        tone(samples, index * 0.085, 0.41, note, 0.23, 4.5, harmonics=(1.0, 0.10))
    write("purchase", samples, 0.55)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    drill()
    ground_sounds()
    crystal_sounds()
    oxygen_sounds()
    airlock_sounds()
    interface_sounds()
    files = list(OUTPUT.glob("*.wav"))
    print(f"Generated {len(files)} original mono PCM SFX at {RATE} Hz in {OUTPUT}")


if __name__ == "__main__":
    main()
