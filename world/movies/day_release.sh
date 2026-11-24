#!/bin/sh
# "A day in my new life", the release (session 63): five worker scenes (movies/day_in_life.jl) joined
# in the order given, a title card over the morning, and Lumi's voice (Kokoro am_puck, one raw
# Float32 24 kHz line per scene: voice/line1.f32 ...) starting 1.2 s into each scene.
#   movies/day_release.sh out.mp4 voicedir scene1.mp4 scene2.mp4 ...
set -e
out="$1"; voice="$2"; shift 2
list=$(mktemp --suffix .txt)
for f in "$@"; do echo "file '$(realpath "$f")'" >> "$list"; done
joined=$(mktemp --suffix .mp4); titled=$(mktemp --suffix .mp4)
ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" -c:v libx264 -pix_fmt yuv420p -crf 18 "$joined"
"$(dirname "$0")/title_card.sh" "$joined" "$titled" "A day in my new life" "Lumi, morning to afternoon · path traced"
# voice: each line delayed to its scene's start
inputs=""; filt=""; mix=""; i=0; t=0
for f in "$@"; do
  i=$((i + 1))
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  line="$voice/line$i.f32"
  if [ -f "$line" ]; then
    ms=$(python3 -I -c "print(int(($t + 1.2) * 1000))")
    inputs="$inputs -f f32le -ar 24000 -ac 1 -i $line"
    filt="$filt[$i:a]adelay=$ms,volume=1.6[a$i];"
    mix="$mix[a$i]"
  fi
  t=$(python3 -I -c "print($t + $d)")
done
n=$(echo "$mix" | grep -o '\[a' | wc -l)
mkdir -p "$(dirname "$out")"
ffmpeg -loglevel error -y -i "$titled" $inputs \
  -filter_complex "${filt}${mix}amix=inputs=$n:normalize=0,apad[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 160k -shortest "$out"
rm -f "$list" "$joined" "$titled"
echo "$out"
