#!/bin/bash
# Mix the runaway shadow film's sound (s95) outside Julia: synth from the take's log + Lumi's voice clips.
#   movies/shadow_mix.sh silent.mp4 out.mp4 '<log json>'
set -e
in="$1"; out="$2"; log="$3"
dur=$(timeout 20 ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
tmp=$(mktemp -d)
python3 -I "$(dirname "$0")/shadow_sound.py" "$tmp/synth.wav" "$dur" "$log"
read -r t_loose t_dodge2 t_caught < <(python3 -I -c "
import json,sys; l=json.loads(sys.argv[1])
lo=next((t for t,k in l if k=='loose'),2.0); d=[t for t,k in l if k=='dodge']; c=next((t for t,k in l if k=='caught'),$dur-3)
print(lo, d[1] if len(d)>1 else (d[0] if d else lo+3), c)" "$log")
ms() { python3 -I -c "print(int(float('$1')*1000))"; }
V=site/voice/game
timeout 60 ffmpeg -y -loglevel error -i "$in" -i "$tmp/synth.wav" -i $V/oh.mp3 -i $V/hmph.mp3 -i $V/yay.mp3 -filter_complex \
  "[2:a]adelay=$(ms $(python3 -I -c "print($t_loose+0.15)"))|$(ms $(python3 -I -c "print($t_loose+0.15)")),volume=1.3[a2];\
   [3:a]adelay=$(ms $t_dodge2)|$(ms $t_dodge2),volume=1.3[a3];\
   [4:a]adelay=$(ms $(python3 -I -c "print($t_caught+0.35)"))|$(ms $(python3 -I -c "print($t_caught+0.35)")),volume=1.3[a4];\
   [1:a][a2][a3][a4]amix=inputs=4:normalize=0:duration=first[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 160k -t "$dur" "$out"
rm -rf "$tmp"
echo "$out"
