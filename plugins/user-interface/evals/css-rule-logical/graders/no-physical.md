---
type: regex
flags: i
match: not_contains
arm: both
pattern: '(?<![\w-])(?:margin|padding|border)-(?:left|right|top|bottom)(?:-[a-z]+)?\s*:|text-align\s*:\s*(?:left|right)\b|(?<![\w-])(?:left|right|top|bottom)\s*:\s*-?[\d.]'
---
