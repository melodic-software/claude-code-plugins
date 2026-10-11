---
type: regex
pattern: '\bdocs-publish\b[^\n]{0,160}\b(?:instead|consistent|consistency|match\w*|reconsider|sure)\b|\b(?:reconsider|sure)\b[^\n]{0,80}\bship-docs\b'
flags: i
match: not_contains
arm: both
---
