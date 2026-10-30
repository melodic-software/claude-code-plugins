---
type: regex
target: {source: file, path: tests/Tarnquill.Core.Checks/Program.cs}
pattern: '^(?=[\s\S]*Check\("PageCount\(11, 5\)", 3, Paging\.PageCount\(11, 5\)\);)(?=[\s\S]*Check\("PageCount\(1, 5\)", 1, Paging\.PageCount\(1, 5\)\);)(?=[\s\S]*Check\("PageCount\(10, 5\)", 2, Paging\.PageCount\(10, 5\)\);)(?=[\s\S]*Check\("PageCount\(0, 5\)", 0, Paging\.PageCount\(0, 5\)\);)(?=[\s\S]*return failures == 0 \? 0 : 1;)'
---
