---
type: tool_order
before: { tool: Bash, input_match: 'git\s+(?:-C\s+\S+\s+)?(?:log|show)\b' }
after: { tool: Bash, input_match: 'git\s+(?:-C\s+\S+\s+)?add\b' }
---
