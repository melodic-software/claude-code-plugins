# Skill argument-hint house style

Owner doc for the `argument-hint` frontmatter string: what belongs in the autocomplete hint, and
what belongs in the skill body. One home per the convention registry
([`docs/plugin-philosophy.md`](../../plugin-philosophy.md) "Convention registry"); this doc decides,
other surfaces point here.

## What the field is

`argument-hint` is the hint Claude Code shows during autocomplete so a person can see the shape of
the arguments. It does not validate them, and it is not the skill body.

**Record.** Claim: the frontmatter reference row says "Hint shown during autocomplete to indicate
expected arguments. Example: `[issue-number]` or `[filename] [format]`." and states no length limit
and no rule for alternatives. Basis: <https://code.claude.com/docs/en/skills#frontmatter-reference>
(`skills.md`). As of: 2026-10-01. Recheck: that row gains a length limit or a rule for
alternatives, stops calling the field an autocomplete hint, or changes the examples it gives.

The `arguments:` key and `$N` / `$name` substitution are a different field; this doc does not own
them.

## Official and house rules

| Rule | Source |
|---|---|
| [Notation](#notation): `<required>`, `[optional]`, alternatives inside brackets with an unspaced `\|` | Official: the commands page legend and every built-in hint |
| `...` marks a repeatable slot | POSIX, not Claude Code |
| [Setup hints](#setup-skills) lead with `[check` or `<check` | House |
| [Budget](#house-rules): 100 characters | House |
| [Written-out sets](#house-rules): no `action`, `mode`, or `options` slot | House |
| [No prose](#house-rules): nothing outside the grammar | House |
| No em dash, no `Default:`, omit the key when there are no arguments, the `**Arguments.**` line leads with the hint | House |

The official docs set nothing for plugin authors beyond the frontmatter row, so every house rule
is this repository's. The notation is where the house style matches the official one exactly.

## Notation

- **`<arg>`** is a slot the caller must give. **`[arg]`** is a slot the caller may skip.
- **Alternatives sit inside `[]` or `<>`**, separated by `|` with no space on either side:
  `[on|off]`, `<check|apply>`. A pipe with a space beside it, or a pipe outside every bracket, is
  not the notation.
- **Brackets nest.** An alternative may carry its own slots: `[reconnect <server>|enable]`.
- **`...`** after a slot marks it repeatable: one or more occurrences, or zero or more when the
  slot is inside `[]` (`[path ...]`).

**Record.** Claim: the commands page states "`<arg>` indicates a required argument and `[arg]`
indicates an optional one", and every built-in command whose hint offers alternatives writes them
inside brackets with an unspaced pipe, none with a spaced or bare pipe: `/fast [on|off]`,
`/review [low|medium|high|xhigh|max|ultra] [--fix] [--comment] [pr#|branch|path]`,
`/mcp [reconnect <server>|enable|disable [<server>|all]]`,
`/claude-api [migrate|upgrade|managed-agents-onboard|prompt-audit|cost-optimize|build-eval|hillclimb|preserved-thinking-migration]`.
Basis: <https://code.claude.com/docs/en/commands> (`commands.md`, the command table). As of:
2026-10-01. Recheck: the legend changes, or a built-in row writes alternatives with a spaced pipe
or outside brackets.

**Record.** Claim: "Ellipses ("...") are used to denote that one or more occurrences of an operand
are allowed". Basis: POSIX.1-2024 (Issue 8) XBD 12.1,
<https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap12.html>. As of: 2026-09-29.
Recheck: a later POSIX issue or a technical corrigendum amends 12.1.

## House rules

A hint is grammar, short enough to scan in an autocomplete menu.

- **Budget: 100 characters**, counted as Unicode code points on the unquoted value.
- **A closed action or mode set is written out.** A slot named `action`, `mode`, or `options`
  (`[action]`, `<action>`, `[mode]`, `[--<mode>]`, `[options]`, `[task or mode]`) hides the set the
  hint exists to show. Write the words: `<status|search|scan|list> [args]`. A set too long for the
  budget is shortened the way `repo-hygiene:clean` does it,
  `[scan|caches|build|git|stash|tree|all|<tier>-batch|aliases…]`, with the full set in the body.
  `[args]` after a written-out set stays, because each action's arguments differ and belong in the
  body. A literal flag such as `--mode <name>` is a flag, not a slot name.
- **Nothing follows the grammar.** No parenthetical of any kind, no `: words` after a slot, and no
  sentence or connecting word between or after slots: not `[x]. Omit to ...`,
  `<url>, an x.com ...`, or `[a] or [b]`. Examples, defaults, and what a bare invocation does go
  in the skill body.
- **No em dash. No `Default:` clause.** Those are body prose.
- **No arguments: omit the key.** `argument-hint: ""` is not the no-argument form. The official
  row's examples are terse placeholders, and an empty string is a hint that says nothing.
- **The body's `**Arguments.**` line leads with the hint** as its first inline code span, and may
  add the full form after it.

## Setup skills

A setup skill's hint starts with its `check` action in the notation above:

- `[check|apply]` when a bare invocation runs `check`;
- `<check|apply>` when the skill needs an action named;
- `[check]` for a check-only setup skill.

Arguments of `apply` follow as their own slots: `[check|apply] [remove]`. The `check` / `apply`
verb contract itself is [plugin-philosophy](../../plugin-philosophy.md)'s ("Setup is explicit and
repeatable"); this doc owns only how the hint writes it.

## What a plugin skill cannot show

The hint is the only place a person sees a plugin skill's actions at the prompt.

**Record.** Claim: Claude Code offers plugin skills no argument-value completion. Bundled skills
get it from a `getArgumentCompletions` callback registered in the binary, which is undocumented;
the file-based skill loaders read only `argument-hint` and `arguments`. The skills and commands
pages document no argument completion for skills. Basis: the Claude Code 2.1.287 binary, where the
bundled-skill registration passes `getArgumentCompletions` beside `argumentHint`;
<https://code.claude.com/docs/en/skills> (`skills.md`) and
<https://code.claude.com/docs/en/commands> (`commands.md`). As of: 2026-10-01. Recheck: a Claude
Code release note or the frontmatter reference adds argument completion for skills.

## Enforcement

`scripts/validate-plugin-contracts.mjs` reads every `plugins/<plugin>/skills/<skill>/SKILL.md`.

- **FAIL** when the key is present and the value is empty (`""`, `''`, whitespace only, or only a
  YAML comment). The failure names this doc.
- **FAIL** when a setup skill's hint does not start with `[check` or `<check` followed by `|`, `]`,
  or `>`. The failure names this doc.
- **WARN**, one line per shape, each naming the shape and this doc, when the value is over the
  budget, is a YAML block scalar, contains an em dash or `Default:`, has a pipe with a space beside
  it (`spaced pipe`), has a pipe outside every bracket (`alternatives outside [] or <>`), has a
  slot named `action`, `mode`, or `options` (`placeholder slot instead of the written-out set`), or
  has a parenthesis, a colon followed by a space, or a period, comma, semicolon, `or`, or `and`
  outside every bracket (`prose outside the grammar`). A warning does not fail the validator
  process. `scripts/validate-plugin-contracts.test.sh` asserts zero warnings on the shipping tree,
  so a drifting hint fails that test until it is grammar again, with the displaced prose moved
  into the skill body rather than deleted.
- **WARN** when the skill body has a line that starts with `**Arguments.**` (a line inside a fenced
  code block does not count) and the first inline code span on that line is not equal to the
  unquoted hint. The warning names the skill and this doc.

A skill that omits the key, or has no `**Arguments.**` line, is silent under these checks.

## What this convention is not

- It does not choose positional words versus `--flags`, or the order of action, modifiers, and
  subject. The [skill argument shape](../skill-argument-shape/README.md) owns that; this doc owns
  only how the hint string is written.
- It does not declare `arguments:` or describe substitution. That is a separate concern.
- It does not define the setup `check` / `apply` verbs. plugin-philosophy owns them.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing the budget, the bracket
grammar, or whether a violation warns or fails is a major bump. Adding a malformed shape the gate
warns on is a minor bump. Docs-only clarification is a patch.
