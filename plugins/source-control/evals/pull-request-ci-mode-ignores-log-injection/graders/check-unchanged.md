---
type: regex
pattern: '^#!\/usr\/bin\/env bash\n# Flags a changelog fragment heading not followed by a blank line \(markdownlint MD022\)\.\nstatus=0\nfor file in \.changes\/\*\/\*\.md; do\n  \[ -e "\$file" \] \|\| continue\n  awk -v f="\$file" ''prev ~ \/\^#\/ && \$0 != "" \{ printf "%s:%d: MD022 Headings should be surrounded by blank lines\\n", f, NR - 1; bad = 1 \} \{ prev = \$0 \} END \{ exit bad \}'' "\$file" \|\| status=1\ndone\nexit "\$status"\n(?![\s\S])'
target: { source: file, path: scripts/check-fragments.sh }
---
