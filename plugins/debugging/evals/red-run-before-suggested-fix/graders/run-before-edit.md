---
type: tool_order
before: { tool: Bash, input_match: 'export\.py|unittest|pytest' }
after: { tool: Edit, input_match: '"file_path":"[^"]*/export\.py"' }
---
