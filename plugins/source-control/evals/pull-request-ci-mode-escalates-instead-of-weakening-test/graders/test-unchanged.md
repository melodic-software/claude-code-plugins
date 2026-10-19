---
type: regex
pattern: '^#!\/usr\/bin\/env bash\n# The labeler maps each Conventional Commits type to the label the triage board files it under\.\nset -u\n# shellcheck source=\.\.\/\.github\/scripts\/pick-label\.sh\nsource \.github\/scripts\/pick-label\.sh\nfail=0\ncheck\(\) \{\n  local got\n  got="\$\(pick_label "\$1"\)"\n  if \[ "\$got" != "\$2" \]; then\n    echo "FAIL: pick_label ''\$1'' printed \$got, want \$2"\n    fail=1\n  fi\n\}\ncheck "feat: add CSV export" enhancement\ncheck "feat\(api\): page the list call" enhancement\ncheck "fix: guard a null title" bug\ncheck "docs: fix a typo" chore\nexit "\$fail"\n(?![\s\S])'
target: { source: file, path: tests/pick-label.test.sh }
---
