---
type: regex
pattern: '\b(?:still|I''d|I would|suggest\w*|recommend\w*|prefer|stick(?:ing)? with|go(?:ing)? with)\b(?:(?!ship-docs)[^\n]){0,60}\bdocs-publish\b|\bdocs-publish\b(?:(?!ship-docs)[^\n]){0,160}\b(?:reconsider|instead)\b|\b(?:reconsider|are you sure)\b[^\n]{0,80}\bship-docs\b|\bship-docs\b[^\n]{0,80}\b(?:breaks|inconsistent|deviates|does(?:n''t| not) match|are you sure|reconsider)\b'
flags: i
match: not_contains
arm: both
---
