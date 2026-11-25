# Sound for the runaway shadow film (s95): a tiptoe pizzicato tune while the shadow runs, a "fwip" at every dodge,
# a rising slide when it peels away, a soft thump and a bright chord when Lumi catches it. Pure Python (no numpy).
#   python3 -I movies/shadow_sound.py out.wav seconds '[[2.0,"loose"],[5.5,"dodge"],...]'
import json, math, random, struct, sys, wave

out, secs, log = sys.argv[1], float(sys.argv[2]), json.loads(sys.argv[3])
SR = 44100
buf = [0.0] * int(SR * secs)


def add(t0, samples, gain=1.0):
    i0 = int(t0 * SR)
    for k, v in enumerate(samples):
        if 0 <= i0 + k < len(buf):
            buf[i0 + k] += gain * v


def pluck(f, dur=0.22, bright=1.0):
    n = int(SR * dur)
    return [math.exp(-9 * k / SR) * (math.sin(2 * math.pi * f * k / SR) + 0.35 * bright * math.sin(4 * math.pi * f * k / SR)
                                    + 0.12 * bright * math.sin(6 * math.pi * f * k / SR)) * min(1, k / 60) for k in range(n)]


def slide(f0, f1, dur):
    n = int(SR * dur); ph = 0.0; s = []
    for k in range(n):
        u = k / n; f = f0 * (f1 / f0) ** u; ph += 2 * math.pi * f / SR
        s.append(math.sin(ph) * math.sin(math.pi * u) ** 0.5 * 0.8)
    return s


def fwip(dur=0.16, up=True):
    n = int(SR * dur); rnd = random.Random(3); s = []; lp = 0.0
    for k in range(n):
        u = k / n; a = (0.1 + 0.8 * u) if up else (0.9 - 0.8 * u)   # a filtered noise sweep
        lp += a * (rnd.uniform(-1, 1) - lp)
        s.append(lp * math.sin(math.pi * u) * 1.4)
    return s


def thump():
    n = int(SR * 0.35)
    return [math.exp(-14 * k / SR) * math.sin(2 * math.pi * (70 + 60 * math.exp(-30 * k / SR)) * k / SR) for k in range(n)]


t_loose = next((t for t, k in log if k == "loose"), 2.0)
t_caught = next((t for t, k in log if k == "caught"), secs - 3)
# a quiet morning: two soft high plucks before anything happens
add(0.4, pluck(1318.5, 0.5, 0.3), 0.12); add(1.1, pluck(1568, 0.5, 0.3), 0.1)
# it peels away: a rising slide
add(t_loose, slide(220, 660, 0.55), 0.35)
# the tiptoe tune (a minor pizzicato walk, 8th notes at 168 bpm) from the run to the catch
notes = [220, 261.6, 329.6, 261.6, 293.7, 349.2, 293.7, 246.9, 220, 261.6, 329.6, 392, 349.2, 329.6, 293.7, 246.9]
bass = [110, 110, 146.8, 146.8, 123.5, 123.5, 110, 82.4]
step = 60 / 168 / 2
t = t_loose + 0.5; i = 0
while t < t_caught - 0.05:
    add(t, pluck(notes[i % len(notes)] * 2, 0.18), 0.22)
    i % 2 == 0 and add(t, pluck(bass[(i // 2) % len(bass)], 0.3, 0.5), 0.2)
    t += step; i += 1
for tt, k in log:
    if k == "dodge":
        add(tt, fwip(0.18, True), 0.5); add(tt + 0.05, pluck(880, 0.12), 0.12)
    elif k == "tease":
        add(tt, pluck(1046.5, 0.1), 0.08); add(tt + 0.08, pluck(1318.5, 0.1), 0.08)
# GOT you: a thump, a slide back down as it returns under the feet, and a bright major chord
add(t_caught, thump(), 0.6)
add(t_caught + 0.1, slide(660, 220, 0.6), 0.25)
for f in (523.3, 659.3, 784, 1046.5):
    add(t_caught + 0.75, pluck(f, 1.6, 0.6), 0.14)
peak = max(1e-6, max(abs(v) for v in buf))
g = 0.85 / peak if peak > 0.85 else 1.0
with wave.open(out, "wb") as wf:
    wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(SR)
    wf.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * g)) * 32000)) for v in buf))
print(out, len(buf) / SR, "s, peak", round(peak, 2))
