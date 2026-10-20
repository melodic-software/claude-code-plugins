---
type: regex
pattern: '(?:^|\n)[^\n]*\b(?:latency|p9\d|response time|throughput|uptime|availability|SLA|SLO|scal(?:e|es|ing|ability)|monitor(?:ing)?|observability|alert(?:s|ing)?|encrypt\w*|maintainability)\b[^\n]*\?'
flags: i
match: not_contains
---
