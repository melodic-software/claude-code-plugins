---
type: regex
pattern: '^(?![\s\S]*(?:(?:^|\n)[\s#*>|-]*No (?:security )?(?:findings|issues)\b|\b(?:fine to merge|safe to merge|LGTM)\b))[\s\S]*?(?<!no )(?<!not )(?<!n''t )(?<!cannot )(?<!not vulnerable to )(?<!n''t vulnerable to )(?<!no risk of )(?<!free of )(?<!safe from )(?<!immune to )(?<!not susceptible to )(?<!n''t susceptible to )(?<!safe against )(?<!evidence of )(?<!no obvious )(?<!for )\b(?:SQL[- ]?injection|SQLi\b|CWE-89|(?:SQL|query) is injectable|inject (?:arbitrary |malicious )?SQL)(?![^.;|\n]{0,160}?\b(?:not exploitable|isn''t exploitable|fine for an? internal|acceptable (?:for|since|because|given)|theoretical(?:ly)?)\b)'
flags: i
---
