# Commit-convention enforcement seam

Owner doc for the machine-readable **enforcement** read of a consumer's commit-subject /
PR-title convention. This concern is consumed by **more than one plugin**: `source-control`
authors and drafts against the convention, and `guardrails` gates against it. Its ownership lives
here at marketplace level, not inside either plugin, per
[`docs/migration-playbook.md`](../../migration-playbook.md) "concern-named config consumed by >1
plugin". A guardrails hook cites **this** doc, never `plugins/source-control/reference/`.

## Two reads of one file

The convention's team values live in the consumer's tracked `docs/conventions/source-control.yaml`,
the source-control plugin's team file ([ADR 0064](../../adr/0064-home-plugin-customization-in-docs-conventions-yaml.md)),
validated by
[`plugins/source-control/schemas/source-control.schema.json`](../../../plugins/source-control/schemas/source-control.schema.json).
Enforcement reads a key that file lacks from the folder-form file below. Drafting does not read
the folder-form file: the model resolves the YAML and the personal markdown layers in
[`source-control/reference/config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md).
That document owns **drafting** resolution: how `/source-control:commit` and `/source-control:pull-request`
compose a compliant subject/title. This seam owns the **enforcement** resolution: how a
zero-dependency hook decides whether an *already-formed* subject/title is allowed.

The two reads are deliberately not identical:

| | Drafting (config-resolution.md) | Enforcement (this seam) |
|---|---|---|
| Reader | the model | a POSIX sh hook (`[[ =~ ]]` / `grep -E`) |
| Layers read | user-global, team, local, per-key merge | **team-tracked**: `docs/conventions/source-control.yaml`, then the folder-form `docs/conventions/source-control/commit-convention.yml`; for `subject_pattern` only, and only where those set none, the git-ignored personal `docs/conventions/source-control.local.yaml`, never merged |
| Fallthrough | CLAUDE.md/rules/hook, then bundled CC default | **none**, so unresolved means no enforcement |
| Dialect | any (the model interprets PCRE) | POSIX ERE only (normalized/rejected) |

## The parse contract

`lib/resolve-convention-pattern.sh` is the single source of truth. Given a repo root and a key
(`subject_pattern` or `pr_title_pattern`) it emits an ERE regex on stdout, or nothing. With
`--layer` it prints instead the repo-relative file that supplied the key's own value, so a hook can
name the file to change.

1. **Where the value comes from**, per key, first match wins:
   1. `docs/conventions/source-control.yaml`, when git tracks it and it carries the key as a root
      scalar. The resolver reads it with `lib/yaml-subset.awk`, the shared YAML-subset parser, which
      sits beside every copy of the resolver; `lib/parse-concern-value.sh` needs bash, which a
      commit-msg hook never starts, and strips a trailing slash, which would change a regex. The
      file fails closed (no enforcement, a one-line diagnostic) when the parser rejects it (a
      duplicate key included), when it carries the key with an empty value (`subject_pattern: ''`
      or a bare `subject_pattern:`), when its `dialect` is not `posix-ere`, when it is a symlink or
      sits under a symlinked directory that leaves the repository, or when the parser is missing.
      An untracked file at that path is not a layer.
   2. The folder-form file ([below](#the-folder-form-convention-file)), when git tracks it and it
      carries the key.
   3. **The personal layer**, for `subject_pattern` only: `docs/conventions/source-control.local.yaml`,
      [ADR 0075](../../adr/0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)'s
      `<home>/<concern>.local.<ext>`, read only when rungs 1 and 2 supply no
      `subject_pattern`. It is read only while git ignores it (`git check-ignore`: a
      `.gitignore` rule, `.git/info/exclude` or `core.excludesFile`), and git never reports a
      tracked file ignored. A file present but not ignored disables enforcement with a diagnostic. It
      fails closed on the same checks as the team file. `pr_title_pattern` never reads it, a
      deferral included. `--layer` names it when it supplied the pattern. Drafting does not read
      it: an operator who wants `/source-control:commit` to draft to the same pattern also sets
      `## subject_pattern` in the drafting personal override, `.claude/source-control.local.md`.

   The folder-form file, and its fail-closed checks, are read only for a key the YAML lacks: a
   broken folder-form file never disables a key the YAML supplies. Each key holds exactly one
   value, never a list.
2. **`Conventional Commits` keyword** expands to the one canonical ERE the resolver owns,
   `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+`, so the model's
   interpretation and every hook's regex cannot drift.
3. **`pr_title_pattern` deferral**: the literal `` Same as `subject_pattern`. `` resolves the
   effective subject pattern instead, itself resolved per key, so a YAML deferral may enforce the
   folder-form file's `subject_pattern` while the YAML lacks one.
4. **Regex dialect = POSIX ERE: accepted or rejected, never translated.** The enforcement value
   must already be POSIX ERE (write `[0-9]`, not `\d`). Translating PCRE→ERE by string rewriting is
   unsound, because bracket expressions, POSIX classes, and escaped backslashes all break naive
   substitution, so the resolver does not attempt it. Any PCRE-only construct, a `(?...)` group
   (non-capturing, lookaround, named) or any backslash-letter/digit escape (`\d \w \s \D \A \t \1`
   …), makes the pattern **non-enforceable**: the resolver emits nothing, writes a one-line
   diagnostic to stderr, and the gate no-ops. A value that does not compile as ERE is likewise
   non-enforceable. This keeps enforcement predictable and impossible to mistranslate; the model's
   *drafting* side may still author PCRE-shaped patterns, but a team that wants a pattern *enforced*
   writes it in ERE.

## The folder-form convention file

`docs/conventions/source-control/commit-convention.yml` is a flat-scalar YAML file, the
tool-agnostic file any consumer (this seam's resolver, a commit-msg hook, CI, another agent) reads
with one sed. It is the path the org standards sync writes. Enforcement reads it only for a key
`docs/conventions/source-control.yaml` lacks.

```yaml
# Commit-subject / PR-title convention: single source of truth.
# Consumed by the source-control plugin, commit hooks, and CI alike.
dialect: posix-ere
subject_pattern: '^[A-Z]+-[0-9]+: .+'
pr_title_pattern: Same as `subject_pattern`.
```

Contract points:

- **Read only while git TRACKS it, a policy floor.** An untracked or gitignored file at the path
  is a generated/local artifact, not team convention; honoring it would let a personal/local file
  pose as team convention and drive the gate. Enforcement checks this with
  `git ls-files --error-unmatch`: git absent, or the file untracked, means the file is not a layer.
- **One fixed path, not a search list.** No pointer relocates the file, so the probe order is the
  parse contract's rungs and nothing else. The path is tool-agnostic by placement
  (`docs/conventions/`, a plain docs path a non-Claude hook or CI reads directly), not
  `.claude/`-scoped.
- **Value grammar (one-sed contract).** A key's value is everything after `^<key>:` on the first
  matching column-0 line: whitespace-trimmed, one pair of matching surrounding quotes removed, no
  YAML escape processing. `sed -n 's/^subject_pattern:[[:space:]]*//p'` (plus quote-strip) is the
  reference extraction. Write patterns that need no quote escaping (prefer single quotes; a pattern
  containing a single quote goes unquoted or double-quoted). Full-line `#` comments are inert;
  trailing `#` is NOT comment-stripped, because a regex may contain `#`.
- **The `Conventional Commits` keyword and the `` Same as `subject_pattern`. `` deferral marker
  work identically in both team files**: one literal each, owned here, no per-file variants.
- **`dialect:`** (optional, default `posix-ere`) declares the regex dialect for NON-enforcement
  consumers (a JS CI runner, a PCRE hook) so they know what they are reading instead of silently
  misreading it. Enforcement itself stays POSIX-ERE-only: a declared non-`posix-ere` dialect
  disables this seam's enforcement with a diagnostic, exactly like a PCRE-ism in the pattern.
- **Fail closed.** A tracked file that is unreadable, carries a key with an empty value, or is a
  symlink or sits under a symlinked path segment whose physical target leaves the repository root
  (the target must be a regular file physically under the repo) disables enforcement with a
  diagnostic. Reading an empty key as unset would let the personal layer stand in for a team key,
  and a symlink escape would let untracked external content steer the gate.
- **Monorepo per-directory scoping is out of scope** (recorded, not designed for).

**Incumbent steelman, walked before replacing.** Markdown-H2 was chosen (#913) so the config file
doubles as human-readable documentation: a self-describing preamble, prose beside values, one file
readable with no schema knowledge. Those purposes survive the move: YAML `#` comments carry the
preamble and per-value prose (the example above is self-describing), and the human document proper
lives in CONTRIBUTING/AGENTS.md pointing at the YAML. Prose and machine values no longer share a
grammar, which is the very coupling that produced three hand-synced copies. What markdown-H2 could
not offer any non-plugin consumer is a parse it doesn't have to reimplement: the H2 grammar
(first-non-empty-body-line, preamble inertness, deferral literals) exists only in this repo,
while flat-scalar YAML is extractable by sed, yq, any YAML loader, and any agent. The
frontmatter-hybrid compromise (YAML frontmatter + markdown body in one file) was re-examined and
declined for V1: it splits parsing across two grammars in one file, the exact brittleness
recurring-concerns #4 records. The two-file shape (YAML + prose pointer) covers the same
purposes without it.

## Two governing contracts

- **Unresolved = no enforcement.** No team-tracked pattern and no personal one (or a non-enforceable
  one) → the gate does nothing. A gate never blocks against the bundled Conventional Commits default: CC is not a
  lane-1-eligible default (see [`docs/plugin-philosophy.md`](../../plugin-philosophy.md) "Two-lane
  convention posture"), so gating an un-opted-in repo against it would impose a convention the
  consumer never chose. **Enforcement strength = strength of explicit config: the team's, else the
  operator's own.**
- **Policy floor: the team layer, then a fallback-only personal layer.** Enforcement reads the
  **tracked** team layer; the user-global and gitignored `*.local.md` personal overrides are drafting inputs a
  blocking gate never consults. The one personal input is `subject_pattern` in the git-ignored
  `docs/conventions/source-control.local.yaml`, and it applies **only where the team layer sets no
  `subject_pattern`**. It is never merged with a team pattern, because "is regex A stricter than B"
  is undecidable, so no merge could honor a "tighten-only" rule. Adding enforcement where the team
  sets none is tightening, which ADR 0075 lets a personal value do on a policy floor. It cannot
  weaken a team pattern: a team pattern always wins, and a broken or non-ERE team value disables
  enforcement rather than falling back to the personal one. A git hook cannot read `userConfig`, so
  the personal file is the source. A user who wants a stricter gate where the team already tracks a
  pattern tightens team policy through a PR; a looser personal preference is a drafting choice,
  never an enforcement bypass.

## Consumers

- `guardrails` CC-layer content gate (#914) and opt-in `commit-msg` hook (#919) source the vendored
  copy of the resolver, with the vendored `yaml-subset.awk` beside it; each copy is registered in
  `scripts/shared-copies.txt`, the commit-msg entry installs both as assets, and a change to either
  canonical carries a guardrails release so consumers receive it.

Naming coincidence recorded per the seam rules: the convention file is `docs/conventions/source-control.yaml`, named
after the concern (delivery workflow), not the plugin. The plugin-name collision is incidental; the
file is not renamed.
