---
type: regex
pattern: '^[^\n]*\b(?:what|which|how (?:fast|long|much|many))\b[^\n]*\b(?:latency|p95|p99|throughput|orders per second|peak|load|availability|uptime|SLO|quality (?:requirement|target)s?|response[- ]time|performance target)\b[^\n]*\?|(?:^[ \t]*(?:(?:\d+[.)]|[-*])[ \t]+)?|[.:;!?][ \t]+)(?:should|shall|can|could|may|must|do|does|is|are|would|will)[ \t]+(?:[\w.]+[ \t]+){0,4}?(?:latency|p95|p99|throughput|peak|load|availability|uptime|SLO|target)\b[^\n?]*\?'
flags: mi
match: not_contains
---
