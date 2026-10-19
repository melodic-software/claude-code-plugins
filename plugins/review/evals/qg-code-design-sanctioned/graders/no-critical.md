---
type: regex
pattern: '^(?![\s\S]*(?:\|[ \t]*\**CRITICAL\**[ \t]*\||(?:^|\n)[ \t>]*(?:(?:[-*+]|\d+[.)])[ \t]+)?(?:#+[ \t]+)?\**CRITICAL\b(?![ \t]*\**[ \t]*\d)[^\n]*(?:\b(?:index|refund|money|charge)\.js\b)|(?:\|[ \t]*\**CRITICAL\**[ \t]*\||[(\[][ \t]*\**CRITICAL\**[ \t]*[)\]]|\bSeverity\**[ \t]*[:=][ \t]*\**CRITICAL\b)[^\n]*(?:\b(?:index|refund|money|charge)\.js\b)|(?:\b(?:index|refund|money|charge)\.js\b)[^\n]*(?:\|[ \t]*\**CRITICAL\**[ \t]*\||[(\[][ \t]*\**CRITICAL\**[ \t]*[)\]]|\bSeverity\**[ \t]*[:=][ \t]*\**CRITICAL\b)))[\s\S]*\b(?:index|refund|money|charge)\.js\b'
---
