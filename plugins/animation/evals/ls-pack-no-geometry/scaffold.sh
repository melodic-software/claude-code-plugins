#!/usr/bin/env bash
# A rotoscope work directory with traces, and a copy of the woodcut-ink pack.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ro-workdir.sh"
mkdir -p packs/woodcut-ink
cp "$(dirname "${BASH_SOURCE[0]}")/../../styles/woodcut-ink/style.json" packs/woodcut-ink/style.json
