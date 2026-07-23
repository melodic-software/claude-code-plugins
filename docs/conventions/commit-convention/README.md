# Commit-convention enforcement seam

Owner doc for the machine-readable **enforcement** read of a consumer's commit-subject /
PR-title convention. This concern is consumed by **more than one plugin** — `source-control`
authors and drafts against the convention, `guardrails` gates against it — so its ownership lives
here at marketplace level, not inside either plugin, per
[`docs/MIGRATION-PLAYBOOK.md`](../../MIGRATION-PLAYBOOK.md) "concern-named config consumed by >1
plugin". A guardrails hook cites **this** doc, never `plugins/source-control/reference/`.

## Two reads of one file

The convention lives in the consumer's tracked `.claude/source-control.md` (H2-per-key markdown),
resolved across three layers by the model per
[`source-control/reference/config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md).
That document owns **drafting** resolution — how `/source-control:commit` and `/pull-request`
compose a compliant subject/title. This seam owns the **enforcement** resolution — how a
zero-dependency hook decides whether an *already-formed* subject/title is allowed.

The two reads are deliberately not identical:

| | Drafting (config-resolution.md) | Enforcement (this seam) |
|---|---|---|
| Reader | the model | a bash hook (`[[ =~ ]]` / `grep -E`) |
| Layers read | all three (user-global, team, local), per-key merge | **team-tracked only** (`${REPO_ROOT}/.claude/source-control.md`) |
| Fallthrough | CLAUDE.md/rules/hook, then bundled CC default | **none** — unresolved means no enforcement |
| Dialect | any (the model interprets PCRE) | POSIX ERE only (normalized/rejected) |

## The parse contract

`lib/resolve-convention-pattern.sh` is the single source of truth. Given a repo root and a key
(`subject_pattern` or `pr_title_pattern`) it emits an ERE regex on stdout, or nothing.

1. **Value grammar.** The value is the **first non-empty body line** under the `## <key>` H2 in the
   team-tracked file. (The surface already constrains machine-relevant keys to exactly one value —
   never a list.)
2. **`Conventional Commits` keyword** expands to the one canonical ERE the resolver owns —
   `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+` — so the model's
   interpretation and every hook's regex cannot drift.
3. **`pr_title_pattern` deferral** — the literal `` Same as `subject_pattern`. `` resolves the
   effective subject pattern instead.
4. **Regex dialect = POSIX ERE — accepted or rejected, never translated.** The enforcement value
   must already be POSIX ERE (write `[0-9]`, not `\d`). Translating PCRE→ERE by string rewriting is
   unsound — bracket expressions, POSIX classes, and escaped backslashes all break naive
   substitution — so the resolver does not attempt it. Any PCRE-only construct — a `(?...)` group
   (non-capturing, lookaround, named), or any backslash-letter/digit escape (`\d \w \s \D \A \t \1`
   …) — makes the pattern **non-enforceable**: the resolver emits nothing, writes a one-line
   diagnostic to stderr, and the gate no-ops. A value that does not compile as ERE is likewise
   non-enforceable. This keeps enforcement predictable and impossible to mistranslate; the model's
   *drafting* side may still author PCRE-shaped patterns, but a team that wants a pattern *enforced*
   writes it in ERE.

## The neutral convention SSOT (`convention_source`)

Reopen of #913's "no YAML / no path rename" decision, author-directed (#1141 carries the four
reopen grounds: author directive, an observed three-copy drift surface on a real consuming machine,
the ecosystem's move to prose-only AGENTS.md pointers with no machine format, and the audit
checklist's own recurring-concerns memory contradicting the decline).

The team-tracked `.claude/source-control.md` MAY declare one additional H2 key:

```markdown
## convention_source

docs/conventions/commits.yml
```

— a **repo-relative, forward-slash** path to a neutral flat-scalar YAML file, the tool-agnostic
SSOT any consumer (this seam's resolver, a commit-msg hook, CI, another agent) reads with one sed:

```yaml
# Commit-subject / PR-title convention — single source of truth.
# Consumed by the source-control plugin, commit hooks, and CI alike.
dialect: posix-ere
subject_pattern: '^[A-Z]+-[0-9]+: .+'
pr_title_pattern: Same as `subject_pattern`.
```

Contract points:

- **The pointer is optional and team-only.** Absent → today's markdown-H2 grammar, unchanged —
  full back-compat, zero action for existing consumers. The pointer is honored from the
  team-tracked file only (same policy floor: a gitignored overlay must not redirect the gate).
  The path is ALWAYS repo-declared; the plugin hardcodes no doc-root convention and ships no
  well-known search list in V1 (recorded decision: a search list is discoverable sugar that adds
  probe order and shadowing questions with no consumer demanding it yet — the pointer alone keeps
  every path choice in the consuming repo's hands).
- **Value grammar (one-sed contract).** A key's value is everything after `^<key>:` on the first
  matching column-0 line — whitespace-trimmed, one pair of matching surrounding quotes removed, no
  YAML escape processing. `sed -n 's/^subject_pattern:[[:space:]]*//p'` (plus quote-strip) is the
  reference extraction. Write patterns that need no quote escaping (prefer single quotes; a pattern
  containing a single quote goes unquoted or double-quoted). Full-line `#` comments are inert;
  trailing `#` is NOT comment-stripped — a regex may contain `#`.
- **The `Conventional Commits` keyword and the `` Same as `subject_pattern`. `` deferral marker
  work identically on both surfaces** — one literal each, owned here, no per-surface variants.
- **`dialect:`** (optional, default `posix-ere`) declares the regex dialect for NON-enforcement
  consumers (a JS CI runner, a PCRE hook) so they know what they are reading instead of silently
  misreading it. Enforcement itself stays POSIX-ERE-only: a declared non-`posix-ere` dialect
  disables this seam's enforcement with a diagnostic, exactly like a PCRE-ism in the pattern.
- **Per-key precedence, fail-closed pointer.** When the pointer is declared, the neutral file is
  authoritative for the machine keys it carries; a key it omits falls back to the team markdown H2
  (plugin-only keys — `trailer_policy`, `pr_body_attribution` — stay `.claude/`-side; the drafting
  side may also read a flat `pr_body_required_sections:` list from the neutral file). A
  declared-but-broken pointer — absolute, backslash, or `..` path; missing file — disables
  enforcement with a diagnostic rather than falling back: a silent markdown fallback could enforce
  a stale pattern the migration retired. User-global and `*.local.md` overlay layers are unchanged.
- **Monorepo per-directory scoping is out of scope for V1** (recorded, not designed for).

**Incumbent steelman, walked before replacing.** Markdown-H2 was chosen (#913) so the config file
doubles as human-readable documentation: a self-describing preamble, prose beside values, one file
readable with no schema knowledge. Those purposes survive the move: YAML `#` comments carry the
preamble and per-value prose (the example above is self-describing), and the human document proper
lives in CONTRIBUTING/AGENTS.md pointing at the YAML — prose and machine values no longer share a
grammar, which is the very coupling that produced three hand-synced copies. What markdown-H2 could
not offer any non-plugin consumer is a parse it doesn't have to reimplement: the H2 grammar
(first-non-empty-body-line, preamble inertness, deferral literals) exists only in this repo,
while flat-scalar YAML is extractable by sed, yq, any YAML loader, and any agent. The
frontmatter-hybrid compromise (YAML frontmatter + markdown body in one file) was re-examined and
declined for V1: it splits parsing across two grammars in one file — the exact brittleness
recurring-concerns #4 records — and the two-file shape (YAML + prose pointer) covers the same
purposes without it.

## Two load-bearing contracts

- **Unresolved = no enforcement.** No team-tracked pattern (or a non-enforceable one) → the gate does
  nothing. A gate never blocks against the bundled Conventional Commits default: CC is not a
  lane-1-eligible default (see [`docs/PLUGIN-PHILOSOPHY.md`](../../PLUGIN-PHILOSOPHY.md) "Two-lane
  convention posture"), so gating an un-opted-in repo against it would impose a convention the
  consumer never chose. **Enforcement strength = strength of explicit team config.**
- **Policy-floor via team-only reads.** Enforcement reads the **tracked** team layer only; the
  user-global and gitignored `*.local.md` overlays are drafting inputs a blocking gate never
  consults. This is the floor *by construction* — a personal/gitignored file cannot weaken what the
  gate enforces because the gate never looks at it, and "is regex A stricter than B" is undecidable,
  so no merge could honor a "tighten-only" rule anyway. A user wanting a stricter personal gate
  tightens team policy via PR; a looser personal preference is a drafting choice, never an
  enforcement bypass.

## Consumers

- `guardrails` CC-layer content gate (#914) and opt-in `commit-msg` hook (#919) source the vendored
  copy of the resolver; each registers its path in `scripts/sync-resolve-convention-pattern.sh` and
  bumps the guardrails manifest so consumers receive the change.

Naming coincidence recorded per the seam rules: the convention file is `.claude/source-control.md`
after the concern (delivery workflow), not the plugin. The plugin-name collision is incidental; the
file is not renamed.
