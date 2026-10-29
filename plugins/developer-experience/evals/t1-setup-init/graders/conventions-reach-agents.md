---
type: regex
target: { source: file, path: AGENTS.md }
pattern: '(?<![\w./-])(?!(?:README|AGENTS|CLAUDE)\.md\b)[\w./-]+\.md\b|(?:[^\S\n]*\S[^\n]*\n(?:[^\S\n]*\n)*){10}'
---
