# Sound for "The island plays itself" (s95b): the notes the island really played in the take (plugins/xylophone.jl
# logs them; movies/xylophone.jl returns them), struck the way the browsers strike them: a sine with a 3.93x partial
# (a wooden bar's overtone), 6 ms attack, 1.1 s fall. Plus a soft breeze so the gaps are not dead silence.
#   python3 -I movies/xylophone_sound.py out.wav seconds notes.json      (notes: [[t, f, g], ...])
import json, math, random, struct, sys, wave

out, secs, notes = sys.argv[1], float(sys.argv[2]), json.load(open(sys.argv[3]))
SR = 44100
buf = [0.0] * int(SR * secs)
for t, f, g in notes:
    i0 = int(t * SR); n = int(1.15 * SR)
    for k in range(n):
        if i0 + k >= len(buf):
            break
        u = k / SR
        env = min(1.0, u / 0.006) * math.exp(-u * 5.2)
        buf[i0 + k] += 0.16 * g * env * (math.sin(2 * math.pi * f * u) + 0.18 * math.exp(-u * 9) * math.sin(2 * math.pi * 3.93 * f * u))
rnd = random.Random(7); lp = 0.0; lp2 = 0.0
for k in range(len(buf)):                       # the breeze: twice low-passed noise, slowly swelling
    lp += 0.02 * (rnd.uniform(-1, 1) - lp); lp2 += 0.02 * (lp - lp2)
    buf[k] += lp2 * 0.5 * (0.6 + 0.4 * math.sin(2 * math.pi * k / SR / 5.0))
peak = max(1e-6, max(abs(v) for v in buf))
gain = 0.8 / peak
with wave.open(out, "wb") as wf:
    wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(SR)
    wf.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * gain)) * 32000)) for v in buf))
print(out, len(notes), "notes, peak", round(peak, 3))
