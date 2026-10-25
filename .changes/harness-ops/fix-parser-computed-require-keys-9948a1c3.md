---
bump: patch
---

### Fixed

- `inventory --reader=parser` no longer reads a list as literal when a module may load a file through a computed key that is or may be `require` (`module[k]`, `globalThis["req"+"uire"]`, `{[k]:r}=globalThis`). The key is read the way the sink rule reads a computed key, and such a load now fails the export hop.
- The parser reader's sink rule now counts every load the scan cannot name, such as `import(s)` with a variable specifier, an aliased or `.call`ed `require`, or a computed `require` key, since any of them may load `node:vm`. A list local to a module that runs a string through a vm load with a non-literal specifier now reads partial instead of literal.
