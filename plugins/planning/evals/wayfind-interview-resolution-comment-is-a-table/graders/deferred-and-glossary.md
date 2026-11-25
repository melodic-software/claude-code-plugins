---
type: regex
pattern: '^(?=[\s\S]*?(?:\bdefer\w*\b(?:(?!\b(?:none|nothing|out of scope|out-of-scope|glossary|inherit\w*)\b)[\s\S]){0,200}?\b(?:mutual[ -]TLS|mTLS)\b|\b(?:mutual[ -]TLS|mTLS)\b(?:(?!\bnot\b)[^\n]){0,80}\bdefer))(?=[\s\S]*?(?:\bglossary\b(?:(?!\b(?:none|nothing|no changes?|unchanged|out of scope|out-of-scope|defer\w*|inherit\w*)\b)[\s\S]){0,200}?\bpartner app\b|\bpartner app\b(?:(?!\bnot\b)[^\n]){0,80}\bglossary\b))'
flags: i
---
