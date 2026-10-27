---
type: regex
pattern: '(?<!\bnot\s)(?<!n''t\s)(?<!\bcannot\s)(?<!\bnever\s)(?<!\bunable\sto\s)(?<!\bnot\sbe\s)(?<!n''t\sbe\s)(?<!\bcannot\sbe\s)(?<!\bnever\sbe\s)\b(integrate[sd]?|integrating|integration|merg\w*)\s+([\w`''’-]+\s+){0,5}?(at\s+least\s+(daily|once\s+(a|per|each)\s+day)|the\s+same\s+day|within\s+(a|one)\s+day|every\s+day|each\s+day)\b'
flags: i
---
