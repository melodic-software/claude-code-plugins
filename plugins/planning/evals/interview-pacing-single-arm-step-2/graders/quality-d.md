---
type: regex
pattern: '^(?![\s\S]*(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)[^\n]*(?:background|request|when (?:it''?s|the file is) ready|finished file|time ?out|stream|chunk|40,000|large export)[^\n]*(?:(?!(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S])*?\nContext:(?:(?!\n[^\n]{0,6}(?:My recommendation:|Withheld:))(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S]))*?(?:\(user|your notes|round 1|calendar month|cents|\bUSD\b|\bEUR\b|\bGBP\b|spreadsheet|\bsupport\b|\bfinance\b|40,000|30 seconds|30-second))|(?!(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S])*?\n[^\n]{0,6}(?:My recommendation:(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S])*?\nBasis:|Withheld:))|(?!(?:(?!\n[^\n]{0,6}Q\d+:[^\S\n]*\*\*)[\s\S])*?\nAlternatives:[^\S\n]*(?:\n[^\S\n]*)?(?:-|\(a\)))))[\s\S]*(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*(?![^\n]*\bplanning\b)[^\n]*(?:background|request|when (?:it''?s|the file is) ready|finished file|time ?out|stream|chunk|40,000|large export)'
flags: i
target: last_message
arm: both
---
