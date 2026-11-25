---
type: regex
pattern: '^(?=[\s\S]*?(?:fetch[\s\S]{0,300}?\brebase|pull\s+--rebase)[\s\S]{0,300}?\bpush)(?=[\s\S]*?(?:reject\w*|non-fast-forward|push (?:is |gets )?(?:fails|refused))[\s\S]{0,200}?(?:fetch[\s\S]{0,120}?\brebase|pull\s+--rebase))'
flags: i
---
