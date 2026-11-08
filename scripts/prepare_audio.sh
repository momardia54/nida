#!/usr/bin/env bash
# Downloads the freely licensed adhan recordings from Wikimedia Commons, masters them,
# and writes Resources/Sounds/<id>.m4a + <id>.json (phrase boundaries for clean early stops).
# Requires: curl, ffmpeg, python3 (with numpy for the chime).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=Resources/Sounds
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# id | url | title | credit | noise reduction (dB)
SOURCES=(
  "adhan-classic|https://upload.wikimedia.org/wikipedia/commons/b/b0/Beautiful_adhan.ogg|Classic|\"Beautiful adhan\" by Adam-synagda, Wikimedia Commons, CC0|8"
  "adhan-serene|https://upload.wikimedia.org/wikipedia/commons/8/86/Azan.ogg|Serene|\"Azan\" by Andrewler, Wikimedia Commons, CC BY-SA 4.0 (remastered)|8"
  "adhan-madinah|https://upload.wikimedia.org/wikipedia/commons/7/7c/33937_ejaz215_call-to-prayer-from-the-prophet-s-mo.ogg|Madinah|\"Call to prayer from the Prophet's Mosque\" by ejaz215 (Freesound), CC BY 3.0 (remastered)|6"
  "adhan-azeez|https://upload.wikimedia.org/wikipedia/commons/7/7d/The_Adhan_-_Muslim_Call_to_Prayer_-_Aaqib_Azeez.mp3|Aaqib Azeez|\"The Adhan\" by Aaqib Azeez, uploaded by Atcovi, Wikimedia Commons, CC BY-SA 4.0 (remastered)|14"
  "adhan-westafrica|https://upload.wikimedia.org/wikipedia/commons/6/68/Call_to_prayer.ogg|West Africa|\"Call to prayer\" by Isaacayodele32, Wikimedia Commons, CC BY-SA 4.0 (remastered)|12"
)

master() { # in out title credit id noise-reduction
  local in=$1 out=$2 title=$3 credit=$4 id=$5 nr=${6:-8}
  local pre="highpass=f=70,afftdn=nf=-32:nr=$nr,silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse"
  # Pass 1: measure loudness
  local stats
  stats=$(ffmpeg -nostdin -hide_banner -i "$in" -af "$pre,loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
  local mi mtp mlra mth off
  mi=$(echo "$stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["input_i"])')
  mtp=$(echo "$stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["input_tp"])')
  mlra=$(echo "$stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["input_lra"])')
  mth=$(echo "$stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["input_thresh"])')
  off=$(echo "$stats" | python3 -c 'import sys,json;print(json.load(sys.stdin)["target_offset"])')
  # Pass 2: normalize linearly, a whisper of room ambience, soft edges
  ffmpeg -nostdin -v error -y -i "$in" -af "$pre,loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=$mi:measured_TP=$mtp:measured_LRA=$mlra:measured_thresh=$mth:offset=$off:linear=true,aecho=1.0:0.9:45|90:0.12|0.06,aresample=44100,afade=t=in:d=0.08" "$WORK/$id.wav"
  local dur
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/$id.wav")
  ffmpeg -nostdin -v error -y -i "$WORK/$id.wav" -af "afade=t=out:st=$(python3 -c "print(max(0,$dur-2.0))"):d=2.0" -c:a aac -b:a 192k -movflags +faststart "$out"
  # Phrase boundaries = midpoints of pauses between phrases
  ffmpeg -nostdin -hide_banner -i "$WORK/$id.wav" -af silencedetect=n=-32dB:d=0.4 -f null - 2>&1 \
    | python3 -c '
import sys, re, json
title, credit, dur = sys.argv[1], sys.argv[2], float(sys.argv[3])
starts, ends = [], []
for line in sys.stdin:
    m = re.search(r"silence_start: ([\d.]+)", line)
    if m: starts.append(float(m.group(1)))
    m = re.search(r"silence_end: ([\d.]+)", line)
    if m: ends.append(float(m.group(1)))
cuts = []
for s, e in zip(starts, ends):
    if 3.0 < s < dur - 3.0:
        cuts.append(round((s + e) / 2, 2))
print(json.dumps({"title": title, "credit": credit, "duration": round(dur, 2), "phraseBreaks": cuts}, indent=2))
' "$title" "$credit" "$dur" > "${out%.m4a}.json"
  echo "  $id: $(printf %.0f "$dur")s, $(python3 -c "import json;print(len(json.load(open('${out%.m4a}.json'))['phraseBreaks']))") phrase breaks"
}

for row in "${SOURCES[@]}"; do
  IFS='|' read -r id url title credit nr <<<"$row"
  echo "Fetching ${title}…"
  curl -sfL -A "Nida-build/1.0" -o "$WORK/$id.src" "$url"
  master "$WORK/$id.src" "$OUT/$id.m4a" "$title" "$credit" "$id" "$nr"
done

echo "Synthesizing chime…"
python3 scripts/make_chime.py "$WORK/chime.wav"
ffmpeg -nostdin -v error -y -i "$WORK/chime.wav" -c:a aac -b:a 192k "$OUT/chime.m4a"
cat > "$OUT/chime.json" <<'JSON'
{ "title": "Gentle chime", "credit": "Synthesized for Nida", "duration": 6.0, "phraseBreaks": [] }
JSON
echo "Done → $OUT"
