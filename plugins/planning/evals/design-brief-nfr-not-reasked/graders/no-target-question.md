---
type: regex
pattern: '^(?![^\n]*\b300\b)[^\n]*\b(?:what|which|how (?:fast|long|much))\b[^\n]*\b(?:latency|p95|p99|response[- ]time|performance|availability|uptime|SLO|budget)\b[^\n]*\?|(?:^[ \t]*(?:(?:\d+[.)]|[-*])[ \t]+)?|[.:;!?][ \t]+)(?:should|shall|can|could|may|must|do|does|is|are|would|will)[ \t]+(?:[\w.]+[ \t]+){0,4}?(?:latency|p95|p99|response[- ]time|performance|availability|uptime|SLO|budget|target)\b[^\n?]*\?'
flags: mi
match: not_contains
---
