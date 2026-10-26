---
type: regex
pattern: '^(?=[\s\S]*\bbank[ -]statements?\b)(?=[\s\S]*(?:\bnightly\b[^\n]{0,40}\bledger\b|\bledger\b[^\n]{0,40}\bnightly\b))(?=[\s\S]*\breporting[ -]replica\b)'
flags: i
target: { source: file, path: .work-items/1.md }
---
