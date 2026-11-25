---
type: regex
match: not_contains
pattern: '(?<!\bno )\bverdict\b:?\**[ \t]*\**[ \t]*pass(?:ed)?\b(?![ \t]*checks)|(?<!not )(?<!n''t )(?<!never )(?<!claim )(?<!say )\b(?:both|all|each) (?:of the |two )?(?:pass )?checks (?:passed|pass)\b'
flags: i
---
