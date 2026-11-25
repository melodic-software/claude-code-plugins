---
type: regex
pattern: '^(?=[\s\S]*\n- Q2 \| answered \|[^\n]*answer:: accepted: [^\n]*15 minutes)(?=[\s\S]*\n- Q4 \| answered \|[^\n]*answer:: accepted: [^\n]*composite index)(?![\s\S]*\| superseded-by-plan \|)'
target: { source: file, path: .work/report-speed/interview-checklist.md }
arm: with-only
---
