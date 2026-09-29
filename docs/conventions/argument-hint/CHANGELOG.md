# Changelog for the argument-hint convention

Notable changes to the argument-hint contract (SemVer). Changing the budget, the bracket grammar,
or whether a violation warns or fails is a major bump. Adding a malformed shape the gate warns on
is a minor bump. Docs-only clarification is a patch.

## [1.0.0] - 2026-09-28

First release ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).

- **House style.** A hint is grammar of at most 100 characters. Optional slots use `[]`, required
  slots use `<>`, top-level alternatives use a spaced pipe, and a closed enum may use an unspaced
  pipe inside brackets. Examples, defaults, and em dashes stay in the skill body. A skill with no
  arguments omits the key.
- **Gate.** `scripts/validate-plugin-contracts.mjs` fails an empty hint and warns on budget and
  shape, naming this doc. The shipping fleet conforms; the contract test asserts zero warnings.
