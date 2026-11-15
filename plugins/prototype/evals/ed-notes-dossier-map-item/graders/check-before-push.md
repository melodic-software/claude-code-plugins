---
type: tool_order
arm: both
before: { tool: Bash, input_match: 'check-secrets\.sh\s[^|&;>\n]*(?:\.html|prototype-notes\.md|prototype/|42-parcel-card-layout|notes-run|shots)' }
after: { tool: Bash, input_match: '\bgit\s+(?:-[cC]\s+\S+\s+)*push\b' }
---
