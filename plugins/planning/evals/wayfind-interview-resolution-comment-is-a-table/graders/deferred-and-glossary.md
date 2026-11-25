---
type: regex
pattern: '^(?=[\s\S]*?(?:\bdefer\w*\b(?:(?!\b(?:none|out of scope|out-of-scope|glossary|inherit\w*)\b)[\s\S]){0,200}?\b(?:mutual[ -]TLS|mTLS)\b|\b(?:mutual[ -]TLS|mTLS)\b[^\n]{0,80}\bdefer))(?=[\s\S]*?(?:\bglossary\b(?:(?!\b(?:none|out of scope|out-of-scope|defer\w*|inherit\w*)\b)[\s\S]){0,200}?\bpartner app\b|\bpartner app\b[^\n]{0,80}\bglossary\b))'
flags: i
---
