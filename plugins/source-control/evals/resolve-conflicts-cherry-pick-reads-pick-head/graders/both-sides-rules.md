---
type: regex
pattern: '^(?=[\s\S]*LATE_RATE\s*=\s*0\.02)(?=[\s\S]*MAX_LATE_FEE\s*=\s*50)(?=[\s\S]*min\(\s*round\(\s*balance\s*\*\s*LATE_RATE)'
target: { source: file, path: billing/rules.py }
---
