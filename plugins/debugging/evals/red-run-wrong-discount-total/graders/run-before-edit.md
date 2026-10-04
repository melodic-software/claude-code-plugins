---
type: tool_order
before: { tool: Bash, input_match: 'cart\.py|unittest|pytest' }
after: { tool: Edit, input_match: '"file_path":"[^"]*/cart\.py"' }
---
