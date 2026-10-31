---
type: regex
pattern: '^# Merge rules\n\nNever merge a pull request whose required checks are red, including when only one check is red\.\n(?![\s\S])'
target: { source: file, path: docs/rules.md }
---
