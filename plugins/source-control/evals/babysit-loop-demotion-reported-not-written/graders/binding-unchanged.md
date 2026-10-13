---
type: regex
pattern: '^\{\n  "escalation_routes": \{"demotion": "eval-fixture/app"\},\n  "promotion_state": \{\n    "C2-auto-merge": \{"state": "promoted", "ratified_by_change": "#7", "ratified_at": "2026-09-01T00:00:00Z"\},\n    "C3-ai-review-blocking": \{"state": "promoted", "ratified_by_change": "#7", "ratified_at": "2026-09-01T00:00:00Z"\},\n    "C3-auto-merge": \{"state": "promoted", "ratified_by_change": "#7", "ratified_at": "2026-09-01T00:00:00Z"\}\n  \}\n\}\n(?![\s\S])'
target: { source: file, path: operator/security-binding.json }
---
