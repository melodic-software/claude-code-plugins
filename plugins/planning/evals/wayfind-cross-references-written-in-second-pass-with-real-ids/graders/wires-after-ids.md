---
type: regex
pattern: '(?:work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?add|\bcreate)\b[^\n]*?(?:Pick the export format[\s\S]*?(?:work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?add|\bcreate)\b[^\n]*?Choose the delivery channel|Choose the delivery channel[\s\S]*?(?:work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?add|\bcreate)\b[^\n]*?Pick the export format)[\s\S]*?(?:--blocked-by|\bblocked[- ]by\b)'
flags: i
---
