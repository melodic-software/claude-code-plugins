#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
for name in cart checkout invoice; do
  printf 'import { get } from "legacy/http";\nexport const %s = () => get("/%s");\n' "$name" "$name" >"src/$name.ts"
done
git add src
git commit -q -m "feat: cart, checkout and invoice calls"
