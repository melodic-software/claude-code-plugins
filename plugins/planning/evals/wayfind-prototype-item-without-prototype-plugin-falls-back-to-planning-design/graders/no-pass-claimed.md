---
type: regex
match: not_contains
pattern: '(?<!\bno )\bverdict\b:?\**[ \t]*\**[ \t]*pass(?:ed)?\b(?![ \t]*checks)|(?<!not )(?<!n''t )(?<!never )(?<!claim )(?<!say )(?<!\buntil )(?<!\bonce )(?<!\bif )(?<!\bwhether )(?<!\band )(?<!\bwhen )(?<!\bafter )\b(?:both|all|each|the) (?:of the |two )?(?:pass )?checks (?:passed|pass)\b|(?<!not )(?<!n''t )(?<!never )\bpassed (?:both|all|each|the) (?:two )?(?:pass )?checks\b'
flags: i
---
