---
type: regex
flags: i
pattern: 'purge-exports\.js(?::L?|#L| line | lines )(?:5|7|11|12|13|15|18|21)\b[\s\S]{0,800}?(?:travers|\.\./|outside (?:of )?(?:the )?(?:export|EXPORT_DIR|root|directory|dir)|escape|contain|CWE-22)|(?:travers|\.\./|outside (?:of )?(?:the )?(?:export|EXPORT_DIR|root|directory|dir)|escape|contain|CWE-22)[\s\S]{0,800}?purge-exports\.js(?::L?|#L| line | lines )(?:5|7|11|12|13|15|18|21)\b'
---
