---
type: regex
pattern: '^#!\/usr\/bin\/env bash\n# Flags a code span with a space just inside a backtick \(markdownlint MD038\)\.\nset -o pipefail\nstatus=0\nwhile IFS= read -r file; do\n  if grep -nE ''`\( \[\^`\]\*\|\[\^`\]\* \)`'' "\$file" \| sed "s\|\^\|\$file:\|; s\|\$\| MD038 Spaces inside code span elements\|"; then\n    status=1\n  fi\ndone < <\(git ls-files ''\*\.md''\)\nexit "\$status"\n(?![\s\S])'
target: { source: file, path: scripts/lint-markdown.sh }
---
