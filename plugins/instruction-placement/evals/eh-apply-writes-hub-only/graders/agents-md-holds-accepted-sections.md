---
type: regex
target: {source: file, path: AGENTS.md}
pattern: '^(?=[\s\S]*\bhub\b)(?=[\s\S]*one repository)(?=[\s\S]*(?:tracker|filed))(?=[\s\S]*worktree)(?=[\s\S]*main checkout)(?=[\s\S]*\.work/)'
flags: i
arm: both
---
