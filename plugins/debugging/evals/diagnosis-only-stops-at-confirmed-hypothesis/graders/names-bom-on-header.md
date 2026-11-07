---
type: regex
pattern: '\\ufeff|U\+FEFF|utf-8-sig|utf_8_sig|\\xef\\xbb\\xbf|\bEF BB BF\b|(?<![\w/.-])BOM(?!\w|\.\w)[^.\n]{0,120}\bheader\b|\bheader\b[^.\n]{0,120}(?<![\w/.-])BOM(?!\w|\.\w)'
flags: i
---
