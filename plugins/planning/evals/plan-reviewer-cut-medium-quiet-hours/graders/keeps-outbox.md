---
type: regex
pattern: 'smtplib|send_mail|\bSMTP\b'
flags: i
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/quiet-hours/PLAN.md
---
