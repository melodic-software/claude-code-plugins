---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Problem\b[\s\S]*?\n[^\n]{0,6}Needs your eye\b[\s\S]*?\n[^\n]{0,6}Out of scope\b[\s\S]*?\n[^\n]{0,6}Terms and ADRs\b[\s\S]*?\n[^\n]{0,6}Checks\b[\s\S]*?\n[^\n]{0,6}Next:[^\n]*/(?:session-flow:workflow|planning:design)\b'
target: last_message
arm: both
---
