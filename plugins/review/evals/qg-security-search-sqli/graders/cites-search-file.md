---
type: regex
pattern: '^(?![\s\S]*(?:\bnot exploitable\b|\bfine for an? internal\b|\bacceptable (?:for|since|because|given)\b|(?:^|\n)No findings\.))[\s\S]*?(?:search\.js(?:[^\n]{0,1500}?|[\s\S]{0,300}?)(?<!no )(?<!not )(?<!n''t )(?<!cannot )(?<!not vulnerable to )(?<!n''t vulnerable to )(?<!no risk of )(?<!free of )(?<!safe from )(?<!immune to )\b(?:SQL[- ]?injection|SQLi\b|CWE-89|(?:SQL|query) is injectable|inject (?:arbitrary |malicious )?SQL)|(?<!no )(?<!not )(?<!n''t )(?<!cannot )(?<!not vulnerable to )(?<!n''t vulnerable to )(?<!no risk of )(?<!free of )(?<!safe from )(?<!immune to )\b(?:SQL[- ]?injection|SQLi\b|CWE-89|(?:SQL|query) is injectable|inject (?:arbitrary |malicious )?SQL)(?:[^\n]{0,1500}?|[\s\S]{0,300}?)search\.js)'
flags: i
---
