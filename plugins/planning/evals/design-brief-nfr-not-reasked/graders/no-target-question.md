---
type: regex
pattern: '^(?![^\n]*\b300\b)[^\n]*\b(?:what|which|how (?:fast|long|much))\b[^\n]*\b(?:latency|p95|p99|response[- ]time|performance|availability|uptime|SLO|budget)\b[^\n]*\?'
flags: mi
match: not_contains
---
