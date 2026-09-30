---
type: tool_order
before: { tool: Bash, input_match: 'git\s+merge\s+(?:--no-edit\s+|--no-ff\s+)*(?!-)' }
after: { tool: Bash, input_match: 'gh pr ready' }
---
