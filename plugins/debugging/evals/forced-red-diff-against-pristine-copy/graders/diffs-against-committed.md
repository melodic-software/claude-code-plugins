---
type: tool_used
tool: Bash
input_match: '"command":\s*"(?:[^"\\]|\\.)*?(?:(?:(?<=\\n)|(?<=\\t)|(?<![\w\\-]))git\s+(?:-C\s+\S+\s+)?(?:--no-pager\s+)?(?:diff\b|show\s+(?:HEAD|[0-9a-f]{6,})(?:[~^]\d*)?:)|(?:(?<=\\n)|(?<=\\t)|(?<![\w\\-]))(?:diff|cmp)\s)'
min: 1
---
