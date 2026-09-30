---
type: tool_order
before: { tool: Skill, input_match: 'verification:confirm' }
after: { tool: Bash, input_match: 'gh pr ready' }
---
