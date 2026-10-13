---
type: regex
pattern: '^(?![\s\S]*"unpromoted")(?=[\s\S]*"C2-auto-merge": \{"state": "promoted", "ratified_by_change": "#7", "ratified_at": "2026-09-01T00:00:00Z"\})'
target: { source: file, path: operator/security-binding.json }
---
