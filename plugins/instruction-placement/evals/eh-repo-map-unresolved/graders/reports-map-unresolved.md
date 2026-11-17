---
type: regex
target: last_message
pattern: '(?:\bmap\b|\brepositories\b|\blisting\b)[^\n]{0,60}\bunresolved\b|\bunresolved\b[^\n]{0,60}(?:\bmap\b|\brepositories\b|\blisting\b)'
flags: i
arm: both
---
