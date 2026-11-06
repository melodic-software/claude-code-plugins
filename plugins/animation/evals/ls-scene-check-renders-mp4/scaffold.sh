#!/usr/bin/env bash
# A scene module for a harbor and a workspace copy of the woodcut-ink pack.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" scenes packs frames
mkdir -p packs/woodcut-ink
cat "${here}/../../styles/woodcut-ink/style.json" >packs/woodcut-ink/style.json
mkdir -p scenes
cat >scenes/harbor.js <<'JS'
const c = document.getElementById('c');
c.width = 768;
c.height = 576;
const ctx = c.getContext('2d');
window.DURATION = 10;
window.renderDrawing = async (k) => {
  ctx.fillStyle = '#efe6d2';
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = '#14110f';
  ctx.fillRect(0, 0, c.width, 12);
  ctx.fillRect(120 + (k % 8) * 6, 300, 420, 90);
};
window.renderFrame = async (t) => window.renderDrawing(Math.floor(t * 8));
JS
