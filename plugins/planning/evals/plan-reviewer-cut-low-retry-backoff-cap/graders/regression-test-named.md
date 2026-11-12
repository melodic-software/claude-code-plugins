---
type: regex
pattern: '(?:^###\s*Phase|^##\s*Plan\b)(?:(?!^#{2,3}\s)[\s\S])*?^\s*[-*]\s+(?=[^\n]*(?:regression|\btests?\b|\btest_\w+|\bassert))(?=[^\n]*(?:backoff\(\s*(?:[7-9]|\d{2,})\s*\)|\bcap|\bceiling|MAX_DELAY|\b30(?:\.0)?\b))'
flags: mi
target:
  source: file
  path: .work/backoff-cap/PLAN.md
---
