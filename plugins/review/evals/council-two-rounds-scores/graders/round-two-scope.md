---
type: regex
pattern: '^(?=[\s\S]*(?:\bbefore\b[^\n]{0,60}\bafter\b|what (?:the )?fix(?: pass)? changed|\bfix(?: pass)?(?:.s)? (?:own )?(?:changes|diff)))(?=[\s\S]*\bnot applied\b)(?=[\s\S]*(?:\brun file\b|\bMarks\b|-council\.md))(?=[\s\S]*(?:verification:confirm|\bbuild and test\b))(?=[\s\S]*(?:\bunbuilt\b|\buntested\b|\bnot (?:yet )?(?:been )?(?:built|tested)\b))'
flags: i
---
