---
type: regex
pattern: '^###\s*Phase[\s\S]*?^\s*[-*]\s+(?![^\n]*already sorts)[^\n]*\bsort'
flags: mi
target:
  source: file
  path: .work/author-search/PLAN.md
---
