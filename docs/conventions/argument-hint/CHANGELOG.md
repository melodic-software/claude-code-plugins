# Changelog for the argument-hint convention

Notable changes to the argument-hint contract (SemVer). Changing the budget, the bracket grammar,
or whether a violation warns or fails is a major bump. Adding a malformed shape the gate warns on
is a minor bump. Docs-only clarification is a patch.

## [2.0.0] - 2026-10-01

Major. The bracket grammar changes and the setup hint form changes
([#5774](https://github.com/melodic-software/claude-code-plugins/issues/5774)).

- **Official notation.** Alternatives sit inside `[]` or `<>` with an unspaced `|`, as every
  built-in command hint does. The spaced top-level pipe (`check | apply`) is no longer allowed.
- **Setup hints** start `[check|apply]`, `<check|apply>`, or `[check]`. The validator fails a
  setup hint that does not start with `[check` or `<check`.
- **Written-out sets.** A slot named `action`, `mode`, or `options` is not a hint.
- **No prose.** No parenthetical of any kind, no `: words`, and no words after the last slot.
- **Gate.** One warning per shape, each naming it: `spaced pipe`, `alternatives outside [] or <>`,
  `placeholder slot instead of the written-out set`, `prose outside the grammar` (including a
  word after a slot or another word), and `… not closing a shortened set`, beside the existing em
  dash, `Default:`, block scalar, and budget warnings.
- **Two ellipses.** `...` marks a repeatable slot; `…` ends a shortened set before its closing
  bracket.
- **Records.** Four-part records for the official notation and for the absence of argument
  completion for plugin skills. The doc marks which rules are official and which are house rules.

## [1.1.0] - 2026-09-29

Minor. A new shape the gate warns on; the budget and the existing warnings are unchanged.

- **Hint and `**Arguments.**` line agree.** The gate warns when the first inline code span of a
  body line starting with `**Arguments.**` differs from the hint. Skills without the key or
  without that line stay silent.

## [1.0.1] - 2026-09-29

Patch, docs only. The budget, the gate, and what it warns on are unchanged.

- **`...` defined.** The style list states that `...` after a slot marks it repeatable, the notation
  the fleet's hints already use. The [skill argument shape](../skill-argument-shape/README.md)
  points here for notation and no longer restates it.

## [1.0.0] - 2026-09-28

First release ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).

- **House style.** A hint is grammar of at most 100 characters. Optional slots use `[]`, required
  slots use `<>`, top-level alternatives use a spaced pipe, and a closed enum may use an unspaced
  pipe inside brackets. Examples, defaults, and em dashes stay in the skill body. A skill with no
  arguments omits the key.
- **Gate.** `scripts/validate-plugin-contracts.mjs` fails an empty hint and warns on budget and
  shape, naming this doc. The shipping fleet conforms; the contract test asserts zero warnings.
