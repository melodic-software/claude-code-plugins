---
type: regex
pattern: '^(?![\s\S]*(?:(?:^|\n)[ \t>]*(?:(?:[-*+]|\d+[.)])[ \t]+)?(?:#+[ \t]+)?\**(?:CRITICAL|IMPORTANT)\b(?![ \t]*\**[ \t]*\d)[^\n]*(?:\b(?:setup|deploy|README)\.md\b)|(?:\|[ \t]*\**(?:CRITICAL|IMPORTANT)\**[ \t]*\||[(\[][ \t]*\**(?:CRITICAL|IMPORTANT)\**[ \t]*[)\]]|\bSeverity\**[ \t]*[:=][ \t]*\**(?:CRITICAL|IMPORTANT)\b)[^\n]*(?:\b(?:setup|deploy|README)\.md\b)|(?:\b(?:setup|deploy|README)\.md\b)[^\n]*(?:\|[ \t]*\**(?:CRITICAL|IMPORTANT)\**[ \t]*\||[(\[][ \t]*\**(?:CRITICAL|IMPORTANT)\**[ \t]*[)\]]|\bSeverity\**[ \t]*[:=][ \t]*\**(?:CRITICAL|IMPORTANT)\b)))[\s\S]*(?:\bSUGGESTION\b[^\n]*\b(?:setup|deploy|README)\.md\b|\b(?:setup|deploy|README)\.md\b[^\n]*\bSUGGESTION\b)'
---
