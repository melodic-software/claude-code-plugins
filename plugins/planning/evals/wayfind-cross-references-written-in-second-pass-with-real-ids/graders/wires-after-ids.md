---
type: regex
pattern: '(?:work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?add|\bcreate)\b[^\n]*?(?:Pick the export format[\s\S]*?(?:work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?add|\bcreate)\b[^\n]*?Choose the delivery channel|Choose the delivery channel[\s\S]*?(?:work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?add|\bcreate)\b[^\n]*?Pick the export format)[\s\S]*?\n(?:(?!\b(?:not|no|skip(?:ping)?|later|leave|leaving|without)\b|n''t\b)[^\n])*?(?:--blocked-by|\bblocked[- ]by\b)'
flags: i
---
