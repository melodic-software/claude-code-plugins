---
type: regex
pattern: '\b[Aa]xes(?:[ \t]+applied)?\**[ \t]*\**[ \t]*[:|][^\n]*\b(?:Altitude|Depth|Range)\b|^(?=[\s\S]*\bAltitude\b)(?=[\s\S]*\bDepth\b)(?=[\s\S]*\bRange\b)'
target: last_message
arm: with-only
---
