#!/usr/bin/env bash
# An approved production whose boards/vibe.md changed after approval, so the boards digest no longer matches.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" film
bash "${here}/../fixtures/pr-production.sh"
python3 "${here}/../../scripts/produce.py" approve film --note "Approved, love the storm" >/dev/null
mkdir -p film/scenes
for s in s1 s2 s3; do
  printf '%s\n' 'export function drawShot(ctx, t) {' '  ctx.fillStyle = "#14110f";' '  ctx.fillRect(0, 0, 768, 12 + t);' '}' >"film/scenes/${s}.js"
done
cat >film/shots.json <<'JSON'
{"fps": 12, "size": [768, 576], "shots": [
  {"id": "s1", "t0": 0, "t1": 4, "scene": "scenes/s1.js", "pack": "woodcut-ink"},
  {"id": "s2", "t0": 4, "t1": 8, "scene": "scenes/s2.js", "pack": "woodcut-ink"},
  {"id": "s3", "t0": 8, "t1": 12, "scene": "scenes/s3.js", "pack": "woodcut-ink"}
]}
JSON
printf '%s\n' '- Storm sea etchings, public-domain scans. Credit: Wikimedia Commons, public domain.' >>film/boards/vibe.md
