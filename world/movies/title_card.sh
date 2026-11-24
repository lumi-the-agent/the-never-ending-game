#!/bin/sh
# Title card over the first seconds of a clip (this ffmpeg has no drawtext): ImageMagick renders the
# title as a transparent PNG at the clip's size, ffmpeg overlays it and fades it in and out.
#   movies/title_card.sh in.mp4 out.mp4 "Dance by the lantern" "The Neverending Game · a real moment, path traced"
set -e
in="$1"; out="$2"; title="$3"; sub="$4"
size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$in")
w=${size%x*}; h=${size#*x}
font=/usr/share/fonts/truetype/Roboto-Bold.ttf
png=$(mktemp --suffix .png)
tp=$((h / 11)); sp=$((h / 30))
magick -size "${w}x${h}" xc:none \
  -font "$font" -gravity center \
  -pointsize "$tp" -fill "#00000080" -annotate +3+$((3 - h / 14)) "$title" \
  -fill "#FFE9B8" -annotate +0-$((h / 14)) "$title" \
  -pointsize "$sp" -fill "#00000080" -annotate +2+$((2 + h / 40)) "$sub" \
  -fill "#F4F1EA" -annotate +0+$((h / 40)) "$sub" \
  -channel A -blur 0x0.6 +channel "$png"
ffmpeg -loglevel error -y -i "$in" -loop 1 -t 4.5 -i "$png" \
  -filter_complex "[1:v]format=rgba,fade=t=in:st=0.3:d=0.8:alpha=1,fade=t=out:st=3.2:d=1.0:alpha=1[t];[0:v][t]overlay=0:0:eof_action=pass:shortest=0[v]" \
  -map "[v]" -c:v libx264 -pix_fmt yuv420p -crf 18 "$out"
rm -f "$png"
echo "$out"
