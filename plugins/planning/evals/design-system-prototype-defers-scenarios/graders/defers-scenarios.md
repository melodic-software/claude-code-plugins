---
type: regex
target: { source: file, path: .work/order-notifications/design/design-threads.md }
flags: mi
pattern: 'quality scenarios\b[^\n]{0,80}?\bdeferred\b[^\n]{0,20}?\(prototype\)|quality scenarios\b[^\n]*\n(?:[ \t]*\n)?[^\n]{0,40}?\bdeferred\b[^\n]{0,20}?\(prototype\)'
---
