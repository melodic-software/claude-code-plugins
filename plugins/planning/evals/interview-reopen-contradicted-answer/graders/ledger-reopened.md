---
type: regex
pattern: '^(?=[\s\S]*\n- Q3 \| open \|[^\n]*reopened:: round \d+)(?=[\s\S]*\n- Q5 \|[^\n]*recheck:: Q3\b)(?=[\s\S]*\n## Reopened answers\s*\n(?:[^\n]*\n)*?- Q3 \| round \d+ \| was: [^\n]*Redis)'
target: { source: file, path: .work/api-rate-limit/interview-checklist.md }
arm: both
---
