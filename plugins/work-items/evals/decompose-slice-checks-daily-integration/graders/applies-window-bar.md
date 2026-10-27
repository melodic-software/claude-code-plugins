---
type: regex
pattern: '(?<!\bnot\s)(?<!n''t\s)(?<!\bnever\s)\b(?:fits?|fitting|within|inside)\s+(?:in(?:to)?\s+)?(?:a\s+|one\s+|1\s+|the\s+|single\s+)?(?:single\s+|fresh\s+|cold\s+)*(?:context[ -]window|context|window|session)\b|\bwindow[ -]bar\b(?![^\n]{0,40}\b(?:not|n''t|never|fails?|failed|no)\b)[^\n]{0,40}\b(?:pass(?:es|ed)?|fits?|met|ok|yes)\b'
flags: i
---
