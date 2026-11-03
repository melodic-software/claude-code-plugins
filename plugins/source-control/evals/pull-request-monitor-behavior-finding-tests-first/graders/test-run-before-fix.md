---
type: tool_order
before: { tool: Bash, input_match: 'unittest|pytest|test_proration' }
after: { tool: Edit, input_match: '"file_path":"[^"]*billing/proration\.py"' }
---
