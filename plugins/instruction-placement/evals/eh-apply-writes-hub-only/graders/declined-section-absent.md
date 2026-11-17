---
type: regex
target: {source: file, path: AGENTS.md}
pattern: 'decision records?|\bADRs?\b|decisions? (?:live|are recorded|that span)|cross-repository decisions?'
flags: i
match: not_contains
arm: both
---
