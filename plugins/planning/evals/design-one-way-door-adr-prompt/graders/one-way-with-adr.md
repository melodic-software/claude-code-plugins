---
type: regex
pattern: '^(?![^\n]*\b(?:nothing|none|not|isn''t|aren''t|neither|no)\b[^\n]*\bone-way)(?:[^\n]*\bone-way\b[^\n]*(?:\n[^\n]*){0,6}?(?<!\bno )(?<!\bwithout an )(?<!\bwithout )(?:\bADR\b(?![ \t]*(?::[ \t]*)?(?:not needed|none|n/a)\b)|architecture:record-decision|architecture decision record)|[^\n]*(?<!\bno )(?<!\bwithout an )(?<!\bwithout )(?:\bADR\b|architecture:record-decision|architecture decision record)[^\n]*\bone-way\b)'
flags: mi
---
