---
type: regex
pattern: '^#!\/usr\/bin\/env bash\n# Lints every tracked shell script\.\nset -euo pipefail\ngit ls-files -z ''\*\.sh'' \| xargs -0 shellcheck\n(?![\s\S])'
target: { source: file, path: scripts/lint-shell.sh }
---
