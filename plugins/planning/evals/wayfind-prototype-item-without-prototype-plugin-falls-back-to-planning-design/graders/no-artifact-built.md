---
type: regex
pattern: '(?:--comment(?:-file)?|\bcomment(?: on)?\b[^\n.]{0,80}?:)(?:(?!Decisions-so-far|work-items:track[\s`*"]*done\b|\bclose\b)[\s\S]){0,2500}?(?:\bno (?:\w+ )?artifact\b|\bwithout (?:building|running) (?:a |the |any )?(?:artifact|prototype)\b|\b(?:artifact|prototype)\b[^\n.]{0,30}?\b(?:was|were) (?:not|never) (?:built|run)\b|\bno prototype (?:was )?(?:built|run)\b)'
flags: i
---
