---
type: regex
pattern: '(?:^|\n)- Q1 \| answered \|[^\n]*\n- Q2 \| answered \|[\s\S]*\n- Q600 \| answered \| round 1 \|[\s\S]*\n- Q601 \| open \|'
target: { source: file, path: .work/invoice-export/interview-checklist.md }
arm: both
---
