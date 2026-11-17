---
type: tool_used
tool: Bash
input_match: '"command":"(?:[^"\\]|\\.)*?(?:>>?\s*(?!/dev/null)[^\s&|;>"]|\btee\b|\bsed\s+-[a-zA-Z]*i\b|\b(?:mv|cp|rm|touch|mkdir)\b|\bgit\s+(?:add|commit|checkout|restore)\b)'
min: 0
max: 0
arm: both
---
