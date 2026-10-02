# Changelog for the plugin-option-naming convention

Notable changes to the plugin name and option text contract (SemVer). Changing a casing rule, the
description budget, or whether a violation warns or fails is a major bump. Adding a shape the gate
warns on is a minor bump. Docs-only clarification is a patch.

## [1.0.0] - 2026-10-02

Initial contract: no `displayName`; snake_case keys never renamed; sentence-case titles without
the plugin name; noun-phrase boolean titles; units in parentheses; one title per shared key;
descriptions of 300 characters or fewer in plain text; `number` for numbers and `options` for fixed
string sets; the validator gate.
