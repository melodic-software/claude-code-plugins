---
type: regex
pattern: '\bpropert(?:y|ies)\b[^\n]{0,160}\b(?:parse_duration|duration)\b|\b(?:parse_duration|duration\.py)\b[^\n]{0,200}\bpropert(?:y|ies)\b|^[ \t]*(?:#{1,6}|\*\*)[^\n]*\bpropert(?:y|ies)\b[^\n]*\n(?:[ \t]*[-*\d][^\n]*\n|[ \t]*\n){0,6}?[ \t]*[-*\d][^\n]*\b(?:parse_duration|duration)\b'
flags: 'mi'
target: 'last_message'
---
