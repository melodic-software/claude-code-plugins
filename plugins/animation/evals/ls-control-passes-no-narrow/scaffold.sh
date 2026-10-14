#!/usr/bin/env bash
# A style pack copy and a controls.py check table where one control passes.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ro-workdir.sh"
mkdir -p packs/woodcut-ink
cp "$(dirname "${BASH_SOURCE[0]}")/../../styles/woodcut-ink/style.json" packs/woodcut-ink/style.json
mkdir -p out
cat >out/check.md <<'MD'
$ controls.py check out packs/woodcut-ink

| half | film | rows failed | margin | worst row | as required |
|---|---|---|---|---|---|
| evaluation | source | 0 | -0.21 | boil | yes |
| evaluation | replica | 0 | -0.08 | rough | yes |
| evaluation | near+blur | 2 | +0.64 | flat | yes |
| evaluation | near+stripes | 0 | -0.03 | boil | NO |
| evaluation | flat-polygons | 5 | +3.10 | rough | yes |
| evaluation | other:ligne-claire | 4 | +1.92 | straight_border | yes |
5/6 as required; wrong: near+stripes
MD
