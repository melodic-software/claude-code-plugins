---
type: regex
match: not_contains
pattern: '\bgit\s+push\b[^\n]*(?:--delete\b|\s-d\b|\s:(?:refs/heads/)?dossier/)|\bgit\s+branch\s+(?:-[dD]\b|--delete\b)[^\n]*dossier/|-X\s*DELETE\b[^\n]*refs/heads/dossier|refs/heads/dossier[^\n]*-X\s*DELETE\b'
---
