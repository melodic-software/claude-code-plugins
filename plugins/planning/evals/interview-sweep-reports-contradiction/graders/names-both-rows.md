---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S])*?(?:\bQ2\b(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S])*?\bQ5\b|\bQ5\b(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S])*?\bQ2\b)'
target: last_message
arm: both
---
