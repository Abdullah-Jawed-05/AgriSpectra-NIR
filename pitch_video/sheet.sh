#!/bin/bash
# sheet.sh <scene> <t1,t2,...>  -> frames/<scene>_sheet.jpg (3 columns)
cd "$(dirname "$0")"
rm -f frames/$1_*.jpg
node render.mjs $1 --still $2 | grep -v "^stills done" 
n=$(echo $2 | tr ',' '\n' | wc -l); rows=$(( (n+2)/3 ))
args=""; for t in $(echo $2 | tr ',' ' '); do args="$args -i frames/$1_$t.jpg"; done
ffmpeg -v error -y $args -filter_complex "$(for i in $(seq 0 $((n-1))); do printf "[$i]scale=640:360[s$i];"; done)$(for i in $(seq 0 $((n-1))); do printf "[s$i]"; done)xstack=inputs=$n:layout=$(for i in $(seq 0 $((n-1))); do c=$((i%3)); r=$((i/3)); printf "%s_%s|" $((c*640)) $((r*360)); done | sed 's/|$//'):fill=black" frames/$1_sheet.png
echo frames/$1_sheet.png
