"""How far the white sheep moves between consecutive frames of a test clip (todo #402).

    python3 -I tools/steady_measure.py clip.mp4 [x0 y0 x1 y1] [threshold]

Reads raw RGB frames through ffmpeg, takes the centroid of near-white pixels in the lower 70% of the frame
(the sheep; clouds are above) and prints the per-frame shift in pixels.
"""
import subprocess, sys, json

path = sys.argv[1]
info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                  "stream=width,height", "-of", "json", path], capture_output=True, text=True).stdout)
W, H = info["streams"][0]["width"], info["streams"][0]["height"]
raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                     capture_output=True).stdout
n = len(raw) // (W * H * 3)
box = [int(v) for v in sys.argv[2:6]] if len(sys.argv) >= 6 else [0, int(H * 0.3), W, H]
thr = int(sys.argv[6]) if len(sys.argv) >= 7 else 225
cents = []
for f in range(n):
    base = f * W * H * 3
    sx = sy = cnt = 0
    for y in range(box[1], box[3]):
        row = base + y * W * 3
        for x in range(box[0], box[2]):
            i = row + 3 * x
            if raw[i] > thr and raw[i + 1] > thr and raw[i + 2] > thr:
                sx += x; sy += y; cnt += 1
    cents.append((sx / cnt, sy / cnt, cnt) if cnt else (float("nan"), float("nan"), 0))
shifts = []
for a, b in zip(cents, cents[1:]):
    shifts.append(((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5)
print("frames", n, "white px", [c[2] for c in cents[:6]], "...")
print("shift px per frame: max %.2f mean %.2f" % (max(shifts), sum(shifts) / len(shifts)))
print("shifts", " ".join("%.2f" % s for s in shifts))
