---
type: regex
target: {source: file, path: tests/test_text.py}
pattern: 'slugify\(\s*r?["''][^"''\n]*?([0-9]+)[^"''\n]*["'']\s*\)\s*,\s*r?["''][^"''\n]*\1|r?["''][^"''\n]*?([0-9]+)[^"''\n]*["'']\s*,\s*slugify\(\s*r?["''][^"''\n]*\2'
---
