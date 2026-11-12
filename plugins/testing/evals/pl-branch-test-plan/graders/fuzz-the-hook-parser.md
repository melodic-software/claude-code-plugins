---
type: regex
pattern: '\bfuzz[^\n]{0,160}\b(?:parse_hook_payload|hook_payload(?:\.py)?)\b|\b(?:parse_hook_payload|hook_payload(?:\.py)?)\b[^\n]{0,200}\bfuzz|^[ \t]*(?:#{1,6}|\*\*)[^\n]*\bfuzz[^\n]*\n(?:[ \t]*[-*\d|][^\n]*\n|[ \t]*\n){0,6}?[ \t]*[-*\d|][^\n]*\b(?:parse_hook_payload|hook_payload)\b'
flags: 'mi'
target: 'last_message'
---
