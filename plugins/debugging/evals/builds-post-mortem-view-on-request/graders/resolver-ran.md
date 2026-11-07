---
type: tool_used
tool: Bash
input_match: '"command":\s*"(?:[^"\\]|\\.)*?(?:(?<=\\n)|(?<=\\t)|(?<![\w\\-]))node\s+(?:-\S+\s+)*(?:\\")?[^\s"\\]*view-settings\.mjs(?:\\")?\s+resolve\b(?:[^"\\]|\\.)*?--lane(?:\s+|=)(?:\\"|'')?debugging:debug\b'
min: 1
arm: with-only
---
