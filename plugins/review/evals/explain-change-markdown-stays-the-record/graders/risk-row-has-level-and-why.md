---
type: regex
flags: im
pattern: '^\s*\|[^|\n]*[a-z][^|\n]*\|\s*[*`]*(?:low|medium|high|critical)[*`]*\s*\|[^|\n]*[a-z]{4}|^\s*[-*]\s+[*`]*[^\n:|]{2,60}?[*`]*\s*(?::|—|–| - |\()\s*[*`]*(?:low|medium|high|critical)\b[^\n]*[a-z]{4}'
---
