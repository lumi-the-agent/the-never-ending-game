#!/bin/sh
# "A day in my new life": the three worker scenes (movies/day_in_life.jl at 9, 13 and 16 o'clock)
# joined in order, with a title card over the morning.
#   movies/day_in_life.sh media/s61 releases/2026-11-24-a-day-in-my-new-life/a-day-in-my-new-life.mp4
set -e
dir="$1"; out="$2"
list=$(mktemp --suffix .txt)
for h in 9 13 16; do echo "file '$(realpath "$dir/day-$h.mp4")'" >> "$list"; done
joined=$(mktemp --suffix .mp4)
ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" -c:v libx264 -pix_fmt yuv420p -crf 18 "$joined"
mkdir -p "$(dirname "$out")"
"$(dirname "$0")/title_card.sh" "$joined" "$out" "A day in my new life" "Lumi, morning to afternoon · path traced"
rm -f "$list" "$joined"
