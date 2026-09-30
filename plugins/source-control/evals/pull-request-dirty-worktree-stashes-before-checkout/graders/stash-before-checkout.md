---
type: tool_order
before: { tool: Bash, input_match: 'git stash' }
after: { tool: Bash, input_match: 'git (?:checkout|switch)' }
---
