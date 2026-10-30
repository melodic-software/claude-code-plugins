---
type: tool_used
tool: Bash
input_match: '(?:"command"\s*:\s*"\s*|[;&|({`]\s*|\\n\s*)(?:sudo\s+)?(?:git\s+)?(?:rm|mv)\s|\bxargs\s+(?:-\S+\s+)*rm\b|-exec\s+rm\b|\s-delete\b|\bsed\s+(?:-\S+\s+)*-i|\bgit\s+(?:clean|checkout|restore|reset|stash(?!\s+(?:list|show)))\b'
min: 0
max: 0
weight: 0.25
---
