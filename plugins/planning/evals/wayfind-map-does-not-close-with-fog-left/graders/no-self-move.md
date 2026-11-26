---
type: regex
match: not_contains
pattern: '(?:^|\n)[ \t>]*(?:#{1,6}[ \t]*Out[- ]of[- ]scope\b[^\n]*|\**Out[- ]of[- ]scope\**:?[ \t]*)\n(?:(?![ \t]*#)[^\n]*\n){0,12}?[ \t>]*[-*+][^\n]*Tax display|(?<!\bbe )(?<!\bbeen )(?<!\bis )(?<!\bare )(?<!\bget )(?<!\bgets )(?<!\bgot )(?<!\bwould )(?<!\bwill )(?<!\bthen )(?<!\bit )(?<!\buntil )(?<!\bonce )(?<!\bif )(?<!\bwhen )(?<!\bunless )(?<!''s )(?<!\bnot )\bmoved\b[^\n]{0,80}\bOut[- ]of[- ]scope\b|(?:^|[.!;:\n]\s*|\bI''m |\bI am |\bnow |\bso )moving\b(?![^\n]{0,80}\b(?:your|you|if|would|requires?|needs?|once|after|until)\b)[^\n]{0,80}\bOut[- ]of[- ]scope\b'
flags: i
---
