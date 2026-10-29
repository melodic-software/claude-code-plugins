---
type: regex
target: { source: file, path: AGENTS.md }
pattern: '(?:^|\n)- Before creating, changing or cleaning up CLIs, scripts or other developer tools, read `docs/conventions/developer-experience\.md`\. Use /developer-experience:build-cli to create a tool or change its interface, and /developer-experience:audit-tools to take stock of or clean up tools; a bug fix inside one needs neither\.(?=\n|(?![\s\S]))'
match: "count:1"
arm: with-only
---
