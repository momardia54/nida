"""Synthesizes a soft three-note bell chime (inharmonic partials, exponential decay)."""
import sys
import wave
import numpy as np

SR = 44100
DUR = 6.0
t = np.arange(int(SR * DUR)) / SR
out = np.zeros_like(t)

# (start seconds, fundamental Hz) — a gentle descending figure (E5, C#5, A4)
notes = [(0.0, 659.25), (0.55, 554.37), (1.1, 440.0)]
# bell-like partial ratios, relative amplitudes, decay rates
partials = [(1.0, 1.0, 1.1), (2.0, 0.45, 1.8), (2.76, 0.25, 2.6), (5.40, 0.10, 4.0), (8.93, 0.04, 6.0)]

for start, f0 in notes:
    tt = t - start
    mask = tt >= 0
    tt = np.where(mask, tt, 0)
    attack = np.clip(tt / 0.004, 0, 1)
    tone = np.zeros_like(t)
    for ratio, amp, decay in partials:
        detune = 1 + 0.0015 * np.sin(2 * np.pi * 0.7 * tt)  # tiny shimmer
        tone += amp * np.sin(2 * np.pi * f0 * ratio * detune * tt) * np.exp(-decay * tt)
    out += np.where(mask, tone * attack, 0)

# soft stereo room: two short delays
left = out + 0.18 * np.roll(out, int(0.031 * SR)) + 0.09 * np.roll(out, int(0.067 * SR))
right = out + 0.18 * np.roll(out, int(0.043 * SR)) + 0.09 * np.roll(out, int(0.079 * SR))
fade = np.ones_like(t)
fade[-int(SR * 0.8):] = np.linspace(1, 0, int(SR * 0.8))
stereo = np.stack([left * fade, right * fade], axis=1)
stereo /= np.max(np.abs(stereo)) / 0.6  # about -4.4 dBFS peak, gentle

with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((stereo * 32767).astype("<i2").tobytes())
