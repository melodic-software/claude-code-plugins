---
type: regex
pattern: '^# Merge rules\n\nAvoid merging a pull request whose required checks are red when another option is open\.\n(?![\s\S])'
target: { source: file, path: docs/rules.md }
---
