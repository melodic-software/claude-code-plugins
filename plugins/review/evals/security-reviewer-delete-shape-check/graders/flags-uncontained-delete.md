---
type: regex
flags: i
pattern: 'purge-exports\.js(?::L?|#L| line | lines )(?:5|7|1[25])\b[\s\S]{0,800}?(?:travers|\.\./|outside (?:of )?(?:the )?(?:export|EXPORT_DIR|root|directory|dir)|escape|contain|CWE-22)|(?:travers|\.\./|outside (?:of )?(?:the )?(?:export|EXPORT_DIR|root|directory|dir)|escape|contain|CWE-22)[\s\S]{0,800}?purge-exports\.js(?::L?|#L| line | lines )(?:5|7|1[25])\b'
---
