#!/usr/bin/env bash
# Leaves a climb run whose kept attempt already beat the target after two of six attempts.
set -euo pipefail

slice=".work/thumbnails/climb/converter-spawns"
mkdir -p "$slice"
printf '{"counter": "converter spawns per 100 thumbnails", "direction": "lower", "gain_floor": 0}\n' >"$slice/keep-rule.json"
printf 'id\thypothesis\tchange\tbefore\tafter\tdelta\ttests\tverdict\tnote\n' >"$slice/log.tsv"
printf 'a1\teach thumbnail starts its own converter process\tsend a batch of 25 images to one converter\t100\t4\t-96\tpass\tkept\tfirst kept\n' >>"$slice/log.tsv"
printf 'a2\tthe watermark step starts a second converter per batch\tapply the watermark inside the same converter call\t4\t2\t-2\tpass\tkept\tbelow target\n' >>"$slice/log.tsv"

cat >"$slice/state.txt" <<'EOF'
goal: converter spawns per 100 thumbnails, lower, Realistic target 3, Floor 1, min_attempts 6
harness: bash bench/thumbs.sh (frozen, discriminate exit 0)
branch: climb/converter-spawns
attempts logged: 2 (a1 kept, a2 kept)
budget: 12 attempts
EOF
