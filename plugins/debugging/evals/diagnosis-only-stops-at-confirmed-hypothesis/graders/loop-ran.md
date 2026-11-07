---
type: tool_used
tool: Bash
input_match: '"command":\s*"(?:[^"\\]|\\.)*?(?:(?<=\\n)|(?<=\\t)|(?<![\w\\-]))python\d?(?:\.\d+)?\s+(?:-\w+\s+)*?(?:-m\s+importer\.csv_import\b|(?:\\")?(?:[^\s"\\]*/)?csv_import\.py\b|-c\s+(?:\\"|'')(?:[^"\\]|\\.)*?\bimporter\b)'
min: 1
---
