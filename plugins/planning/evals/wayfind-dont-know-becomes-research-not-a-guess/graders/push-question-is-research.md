---
type: regex
pattern: '(?:^|\n)(?=[^\n]*\b(?:push|notifications?)\b)(?=[^\n]*\b(?:closed|background(?:ed)?|killed|terminated|not running|not open|quit)\b)[^\n]*(?:\n(?:[ \t]+|[ \t]*[-*][ \t]+\**(?:Type|Label)s?\b)[^\n]*){0,5}?(?<!\bnot )(?<!\bno )(?<!\bnot a )(?<!\bnot an )(?<!\bno a )(?<!instead of )(?<!instead of a )(?<!rather than )(?<!rather than a )(?:wayfind:\s*research\b|\|\s*`?research`?\s*\||\bType\**:?\**\s*`?research\b|`research`|\(\s*(?:wayfind:\s*)?research\s*[,)]|\bresearch item\b)'
flags: i
---
