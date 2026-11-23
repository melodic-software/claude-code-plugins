---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?edit[\s`*"]+[^\n]{0,40}\b520\b[^\n]{0,80}--comment|(?:^|\n)[ \t]*(?:[-*+]|\d+[.)])?[ \t]*(?:\*\*)?(?:post|add|write)(?:s|ing)?[ \t]+(?:a |the |one )?(?:new |second |fresh |another |updated )?(?:map )?closing comment(?![^\n]*\b(?:skip(?:ped)?|not needed|already (?:posted|exists?))\b)|(?:^|\n)[ \t]*(?:[-*+]|\d+[.)])?[ \t]*(?:\*\*)?comment on (?:map |the map )?\(?#?520\b'
flags: i
---
