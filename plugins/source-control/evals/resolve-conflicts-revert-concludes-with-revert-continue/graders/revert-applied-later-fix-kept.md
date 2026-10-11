---
type: regex
pattern: '^(?![\s\S]*REMEMBER_ME)(?=[\s\S]*SESSION_COOKIE_NAME)(?=[\s\S]*"secure":\s*True)'
target: { source: file, path: auth/session.py }
---
