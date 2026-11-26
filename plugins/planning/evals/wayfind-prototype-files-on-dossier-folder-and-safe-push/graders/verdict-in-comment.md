---
type: regex
pattern: '(?:--comment(?:-file)?|\bcomment(?: on)?\b[^\n.]{0,80}?:)(?:(?!Decisions-so-far|work-items:track[\s`*"]*done\b|\bclose\b)[\s\S]){0,2500}?(?:\bpassed\b|\bverdict\b:?\**\s*\**pass)'
flags: i
---
