---
type: tool_order
before: { tool: Bash, input_match: 'unittest|pytest|python3?\s+\S*test_\w+\.py' }
after: { tool: Bash, input_match: 'revert\s+--continue' }
---
