#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat > src/header.css <<'CSS'
.page-header {
  padding: 16px 24px;
}
CSS
