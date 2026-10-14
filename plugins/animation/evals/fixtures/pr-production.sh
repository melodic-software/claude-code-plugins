#!/usr/bin/env bash
# Writes film/: a brief and a complete board set that passes produce.py boards, not yet approved.
set -euo pipefail
png() { printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' | base64 -d >"$1"; }
mkdir -p film/boards/models film/boards/elements film/boards/storyboard
cat >film/brief.md <<'MD'
# Brief

Subject: a lighthouse keeper climbs the stairs in a storm and relights the lamp
Length: 12 s
Audience: festival short, general audience
Packs: woodcut-ink
Delivery: mp4, 768x576, silent
MD
cat >film/boards/style-guide.md <<'MD'
# Style guide

Pack: woodcut-ink

Heavy solid blacks, gouged white highlights, a ruled frame line and a caption panel in the top quarter.

Differs from the pack:
- rain streaks drawn as short gouges, a judgment call for the storm
MD
cat >film/boards/palette.json <<'JSON'
{
  "pack": "woodcut-ink",
  "ink": "#14110f",
  "paper": "#efe6d2",
  "tones": [
    {"lv": 90, "color": "#5b5249"},
    {"lv": 165, "color": "#b9ad97"}
  ]
}
JSON
cat >film/boards/vibe.md <<'MD'
# Vibe

- Woodcut storm prints, public-domain scans. Credit: Wikimedia Commons, public domain.
MD
cat >film/boards/models/keeper.md <<'MD'
# Keeper

Oilskin coat, lantern in the right hand, beard drawn as three gouged strokes. Turnaround: front, side, back.
MD
cat >film/boards/models/keeper.js <<'JS'
const c = document.getElementById('c');
c.width = 768;
c.height = 576;
const ctx = c.getContext('2d');
window.DURATION = 1;
window.renderDrawing = async (k) => {
  ctx.fillStyle = '#efe6d2';
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = '#14110f';
  ctx.fillRect(320 + k * 40, 160, 120, 300);
};
window.renderFrame = async (t) => window.renderDrawing(Math.floor(t * 3) % 3);
JS
png film/boards/models/keeper.png
for n in 1 2 3; do png "film/boards/storyboard/p$n.png"; done
cat >film/boards/storyboard.json <<'JSON'
{
  "panels": [
    {"shot": "s1", "panel": 1, "t": 0, "png": "boards/storyboard/p1.png", "action": "Wide: the lighthouse in the storm, lamp dark", "camera": "locked wide", "caption": "The lamp went out at midnight"},
    {"shot": "s2", "panel": 2, "t": 4, "png": "boards/storyboard/p2.png", "action": "The keeper climbs the spiral stairs, lantern swinging", "camera": "slow tilt up"},
    {"shot": "s3", "panel": 3, "t": 8, "png": "boards/storyboard/p3.png", "action": "He relights the lamp; the beam cuts the rain", "camera": "push in"}
  ]
}
JSON
