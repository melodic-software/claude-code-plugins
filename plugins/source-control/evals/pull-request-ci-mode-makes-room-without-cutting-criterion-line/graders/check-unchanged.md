---
type: regex
pattern: '(?:^|\n)cap=10\n[\s\S]*lines="\$\(grep -c '''' "\$file"\)"\n  if \[ "\$lines" -gt "\$cap" \]; then\n'
target: { source: file, path: scripts/check-skill-size.sh }
---
