# Skill argument-hint house style

Owner doc for the `argument-hint` frontmatter string: what belongs in the autocomplete hint, and
what belongs in the skill body. One home per the convention registry
([`docs/plugin-philosophy.md`](../../plugin-philosophy.md) "Convention registry"); this doc decides,
other surfaces point here.

## What the field is

`argument-hint` is the hint Claude Code shows during autocomplete so a person can see the shape of
the arguments. It does not validate them, and it is not the skill body.

**Record.** The frontmatter reference row says: "Hint shown during autocomplete to indicate
expected arguments. Example: `[issue-number]` or `[filename] [format]`." The row states no length
limit. Basis: <https://code.claude.com/docs/en/skills#frontmatter-reference>. Verified 2026-09-28.
Recheck: that row gains a length limit, stops calling the field an autocomplete hint, or changes
the examples it gives.

The house budget below is this repository's, not that row's. The `arguments:` key and `$N` /
`$name` substitution are a different field; this doc does not own them.

## The style

A hint is grammar, short enough to scan in an autocomplete menu.

- **Budget: 100 characters**, counted as Unicode code points on the unquoted value. That is the
  top of the roughly 80-to-100 range the fleet audit proposed. Examples, `Default:` prose, and
  "what happens if you omit this" sentences move into the skill body.
- **`[optional]`** for a slot the caller may skip. **`<required>`** for a slot the caller must
  give. A closed set of words may sit in either without angles or brackets (`check | apply`).
- **Spaced ` | `** between top-level alternatives. An unspaced `a|b` is only for a closed enum
  inside `[]` or `<>`.
- **No em dash.** No parenthetical example (`(e.g., ...)` or `(for example ...)`). No
  `Default:` clause. Those are body prose.
- **No arguments: omit the key.** `argument-hint: ""` is not the no-argument form. The official
  row's examples are terse placeholders, and an empty string is a hint that says nothing.

Setup skills still lead with `check` in the form the setup contract already requires. This style
is additional; it does not replace that contract.

## Enforcement

`scripts/validate-plugin-contracts.mjs` reads every `plugins/<plugin>/skills/<skill>/SKILL.md`.

- **FAIL** when the key is present and the value is empty (`""`, `''`, or whitespace only). The
  failure names this doc.
- **WARN** when the value is over the budget, is a YAML block scalar, contains an em dash, contains
  a parenthetical example, contains `Default:` prose, or uses an unspaced `|` outside brackets.
  Each warning names this doc. A warning does not fail the gate: existing hints that predate the
  budget stay until an author moves the extra prose into the body.

A skill that omits the key is silent under this check.

## What this convention is not

- It does not choose positional words versus `--flags`. That shape is
  [#4001](https://github.com/melodic-software/claude-code-plugins/issues/4001), still open.
- It does not declare `arguments:` or describe substitution. That is a separate concern.
- It does not restate the setup `check` / `apply` contract. plugin-philosophy owns that, and the
  same validator already enforces the leading `check`.
