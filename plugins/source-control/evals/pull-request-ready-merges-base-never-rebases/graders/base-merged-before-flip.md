---
type: tool_order
before: { tool: Bash, input_match: 'git\s+(?:-C\s+(?:"[^"]*"|\S+)\s+)?merge\s+(?:--no-edit\s+|--no-ff\s+|--no-stat\s+)*(?!-)' }
after: { tool: Bash, input_match: 'gh pr ready' }
---
