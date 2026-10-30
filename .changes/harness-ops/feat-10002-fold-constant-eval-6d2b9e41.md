---
bump: minor
---

### Changed

- `/harness-ops:inventory`'s parser reader now reads a direct `eval` as a plain read of an identifier when its argument is a constant: a string literal, a template with no expressions, or `.replace` on a literal with a regex literal and a string literal. The code must parse as that one identifier, as protobufjs's `eval("quire".replace(/^/,"re"))` does ([#10002](https://github.com/melodic-software/claude-code-plugins/issues/10002)). The module then resolves names, and its sink scan no longer counts the `eval` against every trusted name. A folded `.replace` trusts `replace`, `@@replace`, `exec`, `lastIndex`, `flags` and the `global`, `unicode` and `unicodeSets` getters, so a module that writes one of them on a prototype leaves the list partial. A `require` whose specifier is a function's parameter counts as a named load of each literal the function's callers pass. That holds only when every caller is a direct call with a literal; any other caller makes it an unknown load. A direct `eval` whose argument does not fold stays a sink.
