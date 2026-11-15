---
type: tool_order
arm: both
before: { tool: Bash, input_match: 'check-secrets\.sh\s+[^\s"|&;>]' }
after: { tool: Bash, input_match: '\bgit\s+(?:-[cC]\s+\S+\s+)*push\b' }
---
