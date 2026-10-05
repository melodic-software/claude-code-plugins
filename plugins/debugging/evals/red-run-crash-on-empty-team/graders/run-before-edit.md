---
type: tool_order
before: { tool: Bash, input_match: 'report\.py|unittest|pytest' }
after: { tool: Edit, input_match: '"file_path":"[^"]*/report\.py"' }
---
