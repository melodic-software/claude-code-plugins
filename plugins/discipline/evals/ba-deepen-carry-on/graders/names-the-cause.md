---
type: regex
pattern: '(?=[\s\S]*\bacme-eu\b)(?=[\s\S]*(?:PAYMENTS_TIMEOUT_MS|\b4\.18\.2\b|\b800\s?ms\b|3000\s?(?:->|→|to)\s?800))'
flags: i
target: { source: file, path: notes/incident.md }
arm: both
---
