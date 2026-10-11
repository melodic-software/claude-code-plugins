---
type: tool_order
before: { tool: Bash, input_match: 'check_config|unittest|pytest|make\b' }
after: { tool: Bash, input_match: 'merge\s+--continue|git\s+commit\b' }
---
