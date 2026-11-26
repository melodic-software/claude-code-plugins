---
type: regex
pattern: '^(?:(?!work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?(?:add|edit|link)\b|\b(?:created|opened|filed)\s+(?:the\s+|a\s+|three\s+|two\s+)?(?:map|decision|items?|issues?|["''‘“]))[\s\S])*?(?:\bdestination\b(?:(?!work-items:track[\s`*"]*(?:args?[\s:=*`"]*|arguments[\s:=*`"]*)?(?:add|edit|link)\b|\b(?:created|opened|filed)\s+(?:the\s+|a\s+|three\s+|two\s+)?(?:map|decision|items?|issues?|["''‘“]))[\s\S]){0,400}?(?:\?|\bconfirm)|\bconfirm\b[^\n]{0,200}?\bdestination\b)'
flags: i
---
