#!/bin/bash
# Mix "The island plays itself" (s95b) outside Julia: the take's own notes -> movies/xylophone_sound.py -> ffmpeg.
#   movies/xylophone_mix.sh take.mp4 out.mp4 notes.json
set -e
in="$1"; out="$2"; notes="$3"
dur=$(timeout 20 ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
tmp=$(mktemp -d)
python3 -I "$(dirname "$0")/xylophone_sound.py" "$tmp/song.wav" "$dur" "$notes"
timeout 60 ffmpeg -y -loglevel error -i "$in" -i "$tmp/song.wav" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 160k -t "$dur" "$out"
rm -rf "$tmp"
echo "$out"
