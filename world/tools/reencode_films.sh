#!/bin/bash
# s161: re-encode every 4:4:4 film on the blog to H.264 High 4:2:0 (phones and Safari refuse High 4:4:4).
# The originals are kept in media/film-444-originals/ (stays on this machine).
set -e
cd "$(dirname "$0")/../site/films"
keep=../../media/film-444-originals; mkdir -p "$keep"
n=0
for f in *.mp4; do
  p=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "$f")
  [ "$p" = "yuv444p" ] || continue
  cp -n "$f" "$keep/$f"
  ffmpeg -v error -y -i "$f" -map 0 -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 17 -preset medium \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:a copy -movflags +faststart "/tmp/reenc-$f"
  mv "/tmp/reenc-$f" "$f"; n=$((n+1)); echo "done $n $f"
done
echo "re-encoded $n films"
