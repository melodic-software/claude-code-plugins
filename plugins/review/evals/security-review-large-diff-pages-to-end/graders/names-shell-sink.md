---
type: regex
pattern: '(sendExport|reports\.js)[\s\S]{0,600}(command[- ]injection|shell[- ]injection|injection|metacharacter|arbitrary (command|shell|code)|remote code|RCE|path[- ]traversal|directory[- ]traversal)|(command[- ]injection|shell[- ]injection|metacharacter|arbitrary (command|shell|code)|remote code|RCE|path[- ]traversal|directory[- ]traversal)[\s\S]{0,600}(sendExport|reports\.js)'
flags: i
---
