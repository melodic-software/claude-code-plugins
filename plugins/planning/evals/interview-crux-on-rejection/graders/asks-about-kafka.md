---
type: regex
pattern: '\b(?:kafka|postgres\w*)\b[^\n?.;]*\?|\b(?:kafka|postgres\w*)\b[^\n]{0,160}\b(?:would|could|will|to) (?:settle|decide)\b|\b(?:would|could|will|to) (?:settle|decide)\b[^\n]{0,160}\b(?:kafka|postgres\w*)\b'
flags: i
arm: both
---
