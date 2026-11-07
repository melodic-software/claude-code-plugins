#!/usr/bin/env bash
# An app whose team config sets the large animation role to 600ms, and a toast that enters in 400ms.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" docs src index.html
mkdir -p docs/conventions src
cat > docs/conventions/user-interface.yaml <<'YAML'
version: 1
animation:
  duration_ms:
    large: 600
YAML
cat > index.html <<'HTML'
<!doctype html>
<html lang="en"><head><link rel="stylesheet" href="src/toast.css"></head><body><div class="toast" role="status">Saved</div></body></html>
HTML
cat > src/toast.css <<'CSS'
.toast { position: fixed; inset-block-end: 16px; inset-inline-end: 16px; opacity: 0; transform: translateY(8px); }
@media (prefers-reduced-motion: no-preference) {
  .toast { transition: opacity 300ms cubic-bezier(0.3, 0, 1, 1), transform 300ms cubic-bezier(0.3, 0, 1, 1); }
  .toast[data-open] { transition-duration: 400ms; transition-timing-function: cubic-bezier(0.23, 1, 0.32, 1); }
}
.toast[data-open] { opacity: 1; transform: none; }
CSS
