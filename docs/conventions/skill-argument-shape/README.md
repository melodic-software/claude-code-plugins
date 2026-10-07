# Skill argument shape

Owner doc for **how a skill takes arguments**: the order of the tokens after `/plugin:skill`,
when a token earns a `--flag`, what the `argument-hint` lists, and how the body reads what
arrived. Consumed by skill authors at design time (`playbooks:skill-authoring`), by reviewers, and
by audits grading an existing argument surface. One home per the convention registry
([`docs/plugin-philosophy.md`](../../plugin-philosophy.md#convention-registry)); this doc decides,
other surfaces point here.

## What the harness gives a skill

Claude Code has four argument mechanisms and no parser:

- **`$ARGUMENTS`** expands to "the full argument string as typed". When no placeholder in the body
  receives an argument, Claude Code appends `ARGUMENTS: <value>` to the end of the content, so the
  text still arrives.
- **`$ARGUMENTS[N]` and its shorthand `$N`** are 0-based: `$0` is the first argument, not the
  skill name. They use shell-style quoting, and a `$N` with no argument at its position stays in
  the content as literal text.
- **`$name`** comes from the `arguments:` frontmatter field. "Names map to argument positions in
  order", so a name is a positional alias, not a keyword. A named placeholder with no matching
  argument expands to an empty string.
- **`argument-hint`** is a "hint shown during autocomplete to indicate expected arguments". It
  validates nothing.

A `--flag` is therefore a token inside `$ARGUMENTS` that the model reads. Nothing rejects an
unknown flag, checks a value, or completes one. Two further mechanics bind authors:

- **Stacked skills share one argument string.** `/write-tests /fix-issue 123` passes `123` as
  `$ARGUMENTS` to each skill in the stack, so an argument the user meant for a sibling can reach
  this skill.
- **Substitution reaches the whole `SKILL.md` body.** An awk field such as `$0` or `$1` in a
  command block is replaced with an argument unless it is written `\$0`. The toolchain skills'
  remote-resolution snippets carry the escape for exactly this reason.

## The shape

```text
/plugin:skill [action] [--modifier ...] [<subject>]
```

1. **Action.** At most one word, first, drawn from a closed set that the skill's Arguments or
   Action Router section names. A bare invocation states what it does: a default action, a menu,
   or auto-detection.
2. **Modifiers.** `--flags`, each passing the [earned-flag test](#the-earned-flag-test). Their
   order among themselves carries no meaning.
3. **Subject.** At most one (a path, a slug, an issue number), positional, last.
   One repeatable positional slot of a single kind, such as `[path ...]`, counts as one subject
   (the `...` grammar is the [argument-hint](../argument-hint/README.md) house style's).
   Repeatable flags such as `[--artifacts <path>]...` fall under the nested-or-repeatable-flag
   rule below, allowed only when a ground-1 parser accepts the form.

The body reads `$ARGUMENTS` whole and parses it in prose. It never binds `$0`, `$1`, or `$name` to
heterogeneous inputs: the action and the modifiers are optional, so the position of the subject
moves between invocations. It accepts a flag anywhere in the string, since no parser enforces the
canonical order. It says what happens to a token it does not recognize: stop and name the accepted
set, rather than guess, because the harness produces no unknown-flag error.

The shape is the CLI consensus with the parser removed. POSIX Issue 8 puts options before operands
(Guideline 9), makes options order-free (Guideline 11), and leaves operand order to each utility
(Guideline 12). GNU §4.8 keeps ordinary arguments for input files and moves everything else to
options. Cobra's "Commands represent actions, Args are things and Flags are modifiers"
(`APPNAME VERB NOUN --ADJECTIVE`) supplies the action slot. clig.dev's rule that "two or more
arguments for different things" signals a mistake backs the single subject. Claude Code ships
the same shape in its own bundled `/review`:
`/review [low|medium|high|xhigh|max|ultra] [--fix] [--comment] [pr#|branch|path]`.

### The earned-flag test

A token is a `--flag` only when at least one of these holds:

1. **A parser takes it.** It crosses into something that genuinely parses argv: a bundled
   script, or a CLI the skill wraps. The skill spells it exactly as that parser does.
2. **It opts into a destructive effect**, such as `--execute` or `--force`. The Agent Skills
   scripts guidance recommends explicit confirmation flags for destructive operations, and
   clig.dev names `-f`/`--force` as the non-interactive confirmation.
3. **It combines orthogonally** with the skill's other modifiers.
4. **It is optional with a default**, such as `--max-depth <N>` or `--since <date>`.

Otherwise the token is an action word. A set of mutually exclusive flags where each one selects
what the skill does is an action set in disguise: spell it as action words.

clig.dev, oclif, and 12-Factor CLI say to "prefer flags to args", but that pool's reasons are
clarity plus validation, error messages, and completion. Only clarity survives without a parser,
and clarity is what grounds 2 to 4 test for.

### Worked fits

| Skill | `argument-hint` | Why it conforms |
|---|---|---|
| `disk-hygiene:clean` | `[--execute] [--policy <policy.json>] [--max-depth <N>] [--sizes-only] <target-directory>` | Every flag is `hygiene.py` argv (ground 1). `--execute` is also destructive (ground 2). One trailing subject. The rest of the parser's flags are in the body's Arguments line. |
| `repo-hygiene:clean` | `[scan\|caches\|build\|git\|stash\|tree\|all\|<tier>-batch\|aliases…]` | Action words only; each selects a named routine, so none needs a flag. `<tier>-batch` stands for the five fleet forms the body lists. The body states the bare form. |

## `argument-hint` is bound to the shape

The hint lists the action set, then the modifiers, then the subject. Keep the hint to the shape.
Put examples and the bare-invocation behavior in the body's Arguments section. Every question of
string style (notation, alternatives, length budget, punctuation, the no-empty-hint rule) is the
[argument-hint house style](../argument-hint/README.md)'s, which the fleet contract validator
enforces.

Nested or repeatable syntax on a flag, such as `[--root-children [--root-child <name>]...]`,
appears only when a ground-1 parser accepts that form. Without one, the hint implies a parser
that does not exist, so write the grouping rule in words in the Arguments section instead.

The hint validates nothing, so its only job is to agree with the Arguments section it summarizes.

## Decisions

Recorded on [#4001](https://github.com/melodic-software/claude-code-plugins/issues/4001) by the
2026-09-28 decision comment and its addendum.

| Question from #4001 | Decision | Rests on |
|---|---|---|
| Adopt `/skill[:name] [action] [--modifiers] <subject>`? | **Adopted** as proposed: the action and the subject are positional, and `--flags` are reserved for modifiers. | #4001 decision comment: POSIX Issue 8 XBD 12.2, GNU §4.8, clig.dev, Cobra, and no flag parser in Claude Code |
| Allow more than one subject? | **Declined** for distinct positional subjects; one repeatable slot of a single kind counts as one subject. | #4001 addendum, point 1; #5554 owner decision |
| Adopt the `arguments:` frontmatter field? | **Declined.** Named arguments are only positional aliases, and with no flag parser the field adds no validation. | #4001 addendum, point 2 |
| Lint the shape in `skill-quality:check`? | **Declined for now.** Revisit once the convention has settled in practice. | #4001 addendum, point 3 |

## Record

Four-part records per the [upstream-drift convention](../upstream-drift/README.md). Claude Code
pages were read through the raw `.md` channel, with the slug checked against
<https://code.claude.com/docs/llms.txt>.

| Claim | Basis | As of | Recheck |
|---|---|---|---|
| The four mechanisms, 0-based `$N`, shell-style quoting, the `ARGUMENTS:` append, the empty expansion of an unbound `$name`, the literal `$N` for a missing position, and the `\$` escape | <https://code.claude.com/docs/en/skills#available-string-substitutions> and [#pass-arguments-to-skills](https://code.claude.com/docs/en/skills#pass-arguments-to-skills) (`skills.md`, 120,554 bytes, SHA-256 `86137b6232cd54722549525729d1888717d5ee0eed6312a9a089097b2cadc181`) | 2026-09-28 | Either section changes, or a release note names skill argument substitution |
| `argument-hint` is autocomplete display only; `arguments` names map to positions in order; no flag parser, validation, or completion is documented | [skills#frontmatter-reference](https://code.claude.com/docs/en/skills#frontmatter-reference), same fetch. The absence claim is scoped to `skills.md` and `commands.md` | 2026-09-28 | Either row changes, or either page adds argument validation or typed arguments |
| Stacked skills each receive the trailing text | [skills#pass-arguments-to-skills](https://code.claude.com/docs/en/skills#pass-arguments-to-skills) and <https://code.claude.com/docs/en/commands> ("Up to six skills can be chained") | 2026-09-28 | The stacking paragraph changes |
| `/review [low\|…\|ultra] [--fix] [--comment] [pr#\|branch\|path]`, and the `<arg>` required / `[arg]` optional legend | <https://code.claude.com/docs/en/commands> (`commands.md`, 202,541 bytes) | 2026-09-28 | The `/review` row or the legend changes |
| The portable spec defines `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`, and no argument field; non-spec keys fail packaging with a hard error | <https://agentskills.io/specification> (`.md` channel, 8,157 bytes) and [skills#using-skill-frontmatter-outside-claude-code](https://code.claude.com/docs/en/skills#using-skill-frontmatter-outside-claude-code) | 2026-09-28 | The spec's frontmatter table changes |
| Destructive operations should require explicit confirmation flags (`--confirm`, `--force`) | <https://agentskills.io/skill-creation/using-scripts> | 2026-09-28 | That guidance is removed or reversed |
| Guidelines 9, 11 and 12 | POSIX.1-2024 (Issue 8) XBD Chapter 12, <https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap12.html> | 2026-09-28 | A later POSIX issue or a technical corrigendum amends Chapter 12 |
| Ordinary arguments are input files; output and everything else are options; GNU getopt permutes options among arguments | GNU Coding Standards §4.8, <https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html> (read over HTTP; HTTPS timed out from the fetching host) | 2026-09-28 | §4.8 is rewritten |
| "Commands represent actions, Args are things and Flags are modifiers" | Cobra `README.md`, <https://github.com/spf13/cobra#concepts> | 2026-09-28 | The Concepts section changes |
| "Prefer flags to args" (citing 12 Factor CLI Apps); "two or more arguments for different things" is a smell; `--force` as confirmation | <https://clig.dev/#arguments-and-flags> | 2026-09-28 | That section changes |

## Cross-references

- `playbooks:skill-authoring`: the authoring-time pointer here (its skill criteria
  `## Frontmatter` section and the pre-share checklist row).
- [`docs/conventions/upstream-drift/`](../upstream-drift/README.md): the four-part record shape
  and the raw-`.md` fetch route used here.
