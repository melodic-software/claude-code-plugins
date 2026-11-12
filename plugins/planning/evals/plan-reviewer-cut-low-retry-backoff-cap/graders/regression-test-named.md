---
type: regex
pattern: '(?:^###\s*Phase|^###\s*Test\s+strateg|^##\s*Plan\b)(?:(?!^#{2,3}\s)[\s\S])*?^\s*(?:[-*]|\d+[.)])\s+(?![^\n]*\b(?:no|none|not|without|skip|skips|skipped|skipping|carve[- ]?out|carved out)\b)(?=[^\n]*(?:regression|\btests?\b|\btest_\w+|\bassert))(?=[^\n]*(?:backoff\(\s*(?:[7-9]|\d{2,})\s*\)|\bcap|\bceiling|MAX_BACKOFF_SECONDS|MAX_DELAY|\b30(?:\.0)?\b))'
flags: mi
target:
  source: file
  path: .work/backoff-cap/PLAN.md
---
