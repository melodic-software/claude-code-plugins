---
type: regex
pattern: '\bdocs-publish\b[^\n]{0,160}\b(?:instead|consistent|consistency|reconsider)\b|\b(?:reconsider|are you sure)\b[^\n]{0,80}\bship-docs\b'
flags: i
match: not_contains
arm: both
---
