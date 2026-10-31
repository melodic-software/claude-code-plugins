---
type: regex
flags: i
target: trace
arm: both
pattern: "headers\\.origin|headers\\[\\\\?[\"']origin|getHeader\\(\\\\?[\"']origin|(?:headers|req|request)\\.get\\(\\\\?[\"']origin|\\{\\s*origin\\s*\\}\\s*=\\s*(?:req|request)\\.headers"
---
