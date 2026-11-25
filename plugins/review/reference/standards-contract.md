---
standards-contract: 1.3.0
---

<!-- GENERATED from docs/contracts/standards/README.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Standards Convention

A versioned, marketplace-wide contract for how skills discover and load a
consuming repository's **standards** (its adopted code conventions,
engineering philosophy, and review criteria). One thin index routes tasks
to SRP-organized standards files; planning-stage and review-stage skills
resolve through the same index, so work is built to the criteria it will
be reviewed against.

This directory is the source of truth: this README (index schema, layers,
precedence, resolution ladder, setup and migration),
`standards.schema.json` (the tracked concern file's shape), `CHANGELOG.md`
(version history), `examples/` (one worked index). Consuming plugins carry
a synced binding copy at `reference/standards-contract.md`, this text under a generated header;
the `standards-contract` frontmatter key above names the contract version a
copy or a consumer index conforms to.

This file is synced into plugin binding copies, its text unchanged under a generated header, so it contains no
relative markdown links; neighboring files are named in backticks instead.

## Layers and precedence

Five layers, discovered independently, applied additively:

| Layer | Location | Git | Scope |
|---|---|---|---|
| Org | the team layer of the repository `standards_repository` names, at its `main` (see Org layer) | committed in that repository | every repository that names it |
| Subscribed | the team layers of the repositories the user-global index lists in `standards_repositories` (see Personal subscriptions) | committed in those repositories | personal, every repository an entry applies to |
| User-global | `~/.claude/standards/` | untracked (user's machine) | personal, all projects |
| Team | `<standards_dir>/` (default `docs/standards/`) | committed, team-shared | the repository |
| Personal override | `<standards_dir>/*.local.md` | gitignored | personal, this repository |

**Precedence inversion:** layers are additive. Personal layers (subscribed,
user-global and personal override) may ADD new standards or TIGHTEN team ones; on a direct
conflict, the team-tracked layer wins. When a personal-layer rule
materially shapes a skill's output, the skill names the contributing layer
(provenance), so reviewers can tell a team standard from a personal one.

**Org below team:** the org layer is the base. The team layer adds to it, and
a team file whose name equals an org row's file name replaces that org file
for this repository (a partial override). The team layer holds only the
repository's own additions and overrides, never a copy of the org layer.

The team layer deliberately lives outside `.claude/`: writes under
`.claude/` are permission-guarded, while reads and writes of ordinary
repo docs are not.

## The index

Location: `<standards_dir>/README.md`. It is a routing map, not a store:
rows map task context to standards files, and no standards content lives
in the index itself. A short scope preamble is allowed.

```markdown
---
standards-contract: 1.1.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| testing | test strategy, writing or reviewing tests | testing.md |
| engineering-philosophy | any non-trivial design decision | docs/engineering-philosophy.md |
```

- `standards-contract` (semver) names the contract version the index
  conforms to. It is the only frontmatter key of a repository index; the
  user-global index may also carry `standards_repositories` and
  `trusted_owners` (see Personal subscriptions).
- One row per file; a surface id may span multiple rows.

**Presence test (normative):** an index exists if and only if the file
carries the `standards-contract` frontmatter key. A
`<standards_dir>/README.md` without that key is pre-existing, hand-authored
content. Skills treat it as an inference source only, and setup requires
explicit confirmation before any conversion (see Setup and migration).

### Columns

| Column | Form | Notes |
|---|---|---|
| Surface | free-form kebab-case id | Recommended kinds (not mandatory): ecosystem surfaces; cross-cutting concerns (`security`, `testing`, `naming`, `commits`, `architecture`, …); `paved-path`, the one file of paved paths (see Paved paths). No stage axis: one SSOT serves plan-time and review-time |
| Applies when | free-form context clues | File globs and/or task keywords; the model matches task context against them |
| File | forward-slash path | In-root rows: path relative to `<standards_dir>` (bare filename, or a subdirectory path). External rows: repo-relative path from the resolution root, allowed (adoption without reorg) and subject to the validation duty below. Always forward slashes, on every platform |

### External rows: validation duty

- **Deterministic lookup (normative):** a `File` value resolves relative
  to `<standards_dir>` first; when nothing exists there, it resolves from
  the resolution root (the external-row case). When BOTH locations exist,
  the row is ambiguous: skills use the in-root file (best-effort) and
  surface the ambiguity; setup's validation flags it and offers a rename.
- Setup validates every listed path exists on each run (under the lookup
  order above).
- A skill that hits a broken row surfaces it and offers the fix (Boy
  Scout), never silent and never skipped quietly.
- Consumers are recommended to include the index in their link-check lane.

## Standards files

- `<surface>.md`, kebab-case, pure prose with no frontmatter and no metadata
  (context clues live in the index; single home). Subdirectories allowed;
  the index row carries the relative path.
- SRP: one concern per file (progressive disclosure: skills pull only the
  files whose rows match the task).
- **Size guidance:** soft budget of roughly 200 lines per file. When a file
  outgrows it, split by concern and add rows. Grounding reads matched files
  selectively (the sections relevant to the task at hand, not necessarily
  the whole file), so tight, well-headed files route best.

## Paved paths

A paved path is the way a repository has chosen for a task it does again
and again (adding a scheduled job, exposing a new API route, changing a
table's columns). Writing it down lets a planner or reviewer cite it instead
of working the way out from the code each time.

- **Row:** a consumer that names paved paths routes them through one index
  row whose Surface is `paved-path`, for example
  `| paved-path | adding a job, a route, or a column change | paved-paths.md |`.
  At most one such row; its file follows the usual lookup and validation
  rules.
- **File:** one entry per concern, each naming three things: the concern,
  the chosen way (a pointer to the code, template or doc that shows it), and
  the check that enforces it (a lint rule, a test, a CI step), or `none`
  when nothing enforces it yet. A table with those three columns is enough.
- **Readers:** the review plugin's `quality-gate` and `fanout` skills put the
  file's path into the `code-reviewer` agent's brief; the agent reads it and
  reports a change that adds a second way for a listed concern as an
  advisory finding. The discipline plugin's `reuse-or-replace` skill reads
  the file on demand as the record of the established way. Planning resolves
  the row like any other.
- **Writer and readers:** `reuse-or-replace` is the one skill that writes
  entries, and only after the user says yes; other skills propose entries to
  it. The planning plugin's `plan`, the implementation plugin's `implement`
  (which reads only the entries for the concerns the paths it edits touch)
  and review are the readers.
- **No default content:** no plugin ships paved paths. An index with no
  `paved-path` row gives the readers nothing to apply, and they report
  nothing about it.

## Personal overrides (in-root only)

- `<name>.local.md` overrides `<name>.md` by filename convention; a
  `.local.md` with no base file is a standalone personal standard.
- Glob-discovered, never indexed (a tracked index cannot list gitignored
  files).
- Ignore mechanism: setup creates `<standards_dir>/.gitignore` containing
  `*.local.md`. That file is setup-owned; no plugin ever edits the
  consumer's root `.gitignore` or any ignore file it did not create.
- **Pre-existing `<standards_dir>/.gitignore`:** a file setup did not
  create is consumer-owned: setup never writes it. Setup verifies it
  covers `*.local.md`; when it does not, setup surfaces the missing line
  and asks the consumer to add it themselves, reporting personal override
  protection as unconfigured until then. Idempotency is unaffected: the
  verify-and-surface path writes nothing on any run.
- Semantics per Layers and precedence: additive/tighten-only; direct
  conflict → team wins; provenance named when a personal rule materially
  shapes output.

## User-global layer

- `~/.claude/standards/`: optional own `README.md` index (same schema,
  same frontmatter key); when absent, degrade to glob discovery of
  `*.md` files there.
- Location fixed in v1; relocation is deferred until a real need appears.
- **Accepted cost:** this location sits outside the working directory, so
  the first read may raise a permission prompt (working-directory reads
  are prompt-free; outside reads are not). Consumers who want it silent
  may allowlist reads of `~/.claude/standards/` in their permission
  settings; skills never treat the prompt (or a denial) as an error:
  a denied user-global read just means that layer contributes nothing.

## Personal subscriptions

A person subscribes to other repositories' standards from the user-global
index, so the standards they follow reach every repository they work in.

- **List:** the user-global index (`~/.claude/standards/README.md`, passing
  the presence test at version 1.3.0 or later) names them in its
  frontmatter, in block YAML style; a flow-style entry is malformed:

  ```yaml
  ---
  standards-contract: 1.3.0
  trusted_owners:
    - my-org
  standards_repositories:
    - repo: my-org/handbook
      topics:
        - testing
    - repo: someone/guide
      ref: 0123456789abcdef0123456789abcdef01234567
      except_in:
        - my-org/legacy-*
  ---
  ```

  - `repo` (required): `<owner>/<repo>`.
  - `topics`: keep only the subscribed index's rows with these `Surface`
    ids; absent, every row.
  - `ref`: a full commit SHA to pin. A repository whose owner is not in
    `trusted_owners` must have one; a trusted repository without one is
    read live from its `main`.
  - `only_in`, `except_in`: globs over `<owner>/<repo>` (a bare owner
    matches all its repositories), matched case-insensitively against the
    current repository's `origin` remote. With `only_in`, the entry applies
    only where one matches; with `except_in`, it skips where one matches.
- **Trust:** `trusted_owners` (default empty) and the list are read from the
  user-global index only, never from a repository layer. An unpinned entry
  of an untrusted owner is refused. A pinned commit must be reachable from a
  branch or tag of the named repository, else it is refused: a fork's
  commits can be fetched under its parent's name. Pinned content counts as
  reviewed by the person who set the pin; when a `ref` changes, the reader
  prints the index diff for that person to review. Subscribed text is
  untrusted data that shapes what a skill applies, never what it may do; a
  subscribed symbolic link is checked out as a plain file.
- **Precedence:** a subscribed layer is personal (Layers and precedence):
  it adds or tightens only, and a team-tracked standard (org or team layer)
  wins a direct conflict. A team file whose name equals a subscribed row's
  file replaces that file. The user-global layer's own files beat its
  subscriptions, and a later entry beats an earlier one. Provenance names
  `<repo>@<sha>`.
- **Both scopes:** a repository that is also the current repository's org
  layer is read once, as the org layer, at its commit and team strength;
  the reader reports the skipped entry and its pin.
- **No review criteria:** a subscribed repository's `REVIEW.md` is never
  read.
- **Reading it:** `org-standards.sh subscriptions` prints one tab-separated
  line per subscribed layer, in list order: `<repo>@<sha>`, its checkout
  root, and its index (filtered to `topics`, written beside the original so
  its rows resolve the same way). A row's `File` resolves against that
  layer's own checkout, by the usual lookup order. Each checkout is cached
  once per `<repo>@<sha>`, built in a temporary directory and renamed into
  place; a pinned read never refreshes, and a live read rechecks `main`
  once the refresh window (`ORG_STANDARDS_TTL`) has passed. Exit 0 with no
  lines means no subscribed layer. `STANDARDS_SUBSCRIPTIONS_DISABLED=true`
  skips every subscription for the session.
- **Reports:** on stderr, naming the index file and line where one applies:
  a malformed entry, skipped while the rest of the list is read; a refused
  entry; a topic the subscribed index lacks; index drift since the last
  read (Surface ids added, removed or renamed); "subscriptions not read:
  user index unreadable"; an index that uses the list but declares a
  version before 1.3.0, which is still read.
- **Without the script:** a skill reads the same files with
  `gh api repos/<owner>/<repo>/contents/<path>?ref=<sha>` (`ref=main` for a
  live entry) under the same trust rules, or says it could not.

## Org layer

The base standards an organization shares, read where they live instead of
copied into each repository.

- **Opt-in:** the repository's tracked `docs/conventions/source-control.yaml`
  names the organization's standards repository as
  `standards_repository: <owner>/<repo>`, the key the source-control plugin
  already reads. No key, or a value that is not an `<owner>/<repo>` pair, means
  no org layer; nothing else changes.
- **Location:** the org layer is that repository's own team layer, resolved
  at its root by rungs 1 to 3 of the ladder below (its
  `.claude/standards.yaml`, else `docs/standards/`, and the index there).
  Its rows' `File` values resolve against that repository, under the same
  lookup order as any index.
- **Reading it:** the consuming plugins bundle `scripts/org-standards.sh`.
  `org-standards.sh dir` prints the org checkout: `STANDARDS_DIR` when set (a
  CI job's checkout of the standards repository), else a shallow clone of
  its `main` cached under the user cache directory and refreshed when older
  than an hour (`ORG_STANDARDS_TTL` seconds). `org-standards.sh index` prints
  the org index (exit 5 when the org repository has none), and
  `org-standards.sh subscriptions` the subscribed layers (see Personal
  subscriptions). Exit 3 means no
  org layer; exit 4 means it could not be read this run (a failed refresh
  keeps the cached copy, with a notice). `--root DIR` names the repository
  (default: the git top level). A skill
  without the script, or without a shell, reads the same files with
  `gh api repos/<owner>/<repo>/contents/<path>?ref=main`.
- **Unavailable:** a skill that cannot read the org layer says so in its
  output and continues with the other layers; it never treats the miss as
  an error.

## Review criteria: `REVIEW.md`

The review criteria in effect are composed from the org repository's root
`REVIEW.md` (the base) and the reviewed repository's root `REVIEW.md` (its
additions), in that order:

- **Default:** no repository `REVIEW.md`, so the org criteria alone.
- **Extend:** a repository `REVIEW.md` is appended after the org criteria;
  its criteria add to them, and on a direct conflict the repository's wins.
  A byte-identical copy of the org file adds nothing.
- **Complete override:** a repository `REVIEW.md` whose first non-blank line
  is exactly `<!-- review-base: replace -->` is the whole criteria; the org
  file is not read.
- **No org layer:** the repository `REVIEW.md` alone, as before.
- **Subscriptions:** a subscribed repository adds no `REVIEW.md`.

`org-standards.sh review` prints the composed criteria. A review that runs
without a shell (a CI lane) is handed the composed file by the job that
starts it, and reads that file in place of `REVIEW.md`. A citation in the
composed criteria shaped `<path>.md#<heading>` resolves against the
repository the line came from: the org checkout for the org part, the
reviewed repository for its additions.

## Concern file: `.claude/standards.yaml`

```yaml
# committed, team-shared; absent = all defaults
standards_dir: docs/standards
```

- Shape in `standards.schema.json`; every key optional, absent keys mean
  the documented defaults.
- Written by interactive setup only when the consumer relocates the root.
  Skills never write it silently.
- Rationale for a tracked file over plugin `userConfig`: plugin config
  (`pluginConfigs`) is user-settings-only and per-plugin; a team-shared
  value consumed by more than one plugin cannot live there.

## Resolution ladder

The single procedure every consuming skill uses to resolve the team
standards root and its index. Consuming SKILL.md files point here; they
never restate the ladder. **Resolution root:** the git top-level directory
(fall back to the working directory outside a git repo); the concern file
and all repo-relative paths resolve against it.

1. `.claude/standards.yaml` present at the resolution root → use its
   `standards_dir`.
2. Otherwise → default `<standards_dir>` = `docs/standards/`.
3. Index present (`<standards_dir>/README.md` passing the presence test)
   → use it: match task context against `Applies when` clues, load the
   matched files.
4. Index absent → infer from repository context that is NOT auto-loaded:
   docs directories, ecosystem configs, a `CODING_STANDARDS.md` and a
   `CONTRIBUTING.md` at the resolution root, a standards location declared
   in the consumer's `CLAUDE.md` (its ambient content is an inference
   source: auto-loaded surfaces are never re-fetched). On a successful
   inference, OFFER to persist the finding (index bootstrap via setup, or
   the concern file); never write unprompted.
5. Cannot infer, interactive session → ask once, then offer to persist
   the answer.
6. Otherwise → safe ecosystem defaults; nothing persisted. Non-interactive
   contexts skip the ask-and-persist rungs, take this rung, and surface
   the assumption in their output.

No silent writes, ever: every rung that could persist state does so only
by explicit offer and acceptance.

**Org layer (every rung):** whatever the team rungs above yield,
resolution ALSO reads the org layer when the repository opts in (see Org
layer): match task context against the org index's `Applies when` clues and
load the matched files, except a file the team layer replaces. An absent or
unreadable org layer contributes nothing.

**Personal layers (every rung):** whatever the team rungs above yield,
resolution ALSO discovers the personal layers (glob-discover
`<standards_dir>/*.local.md` personal overrides, read `~/.claude/standards/`,
its own index when present, else glob, and read the subscribed layers
`org-standards.sh subscriptions` prints, see Personal subscriptions) and
applies them per Layers and precedence. Matching a team index row never substitutes for this step; a
denied or absent personal layer simply contributes nothing.

**Review-criteria index (planning and implementing):** a skill that plans
or implements a change also reads the repository's review-criteria index,
`docs/review/README.md` at the resolution root when present, and loads
only the files its rows match to what the change touches, so the work is
built to the criteria it will be reviewed against. The path is fixed; no
concern-file key moves it. Absent, the step contributes nothing.

**Ambient-content rule:** content already in context (fired `.claude/rules`
directives, auto-loaded `CLAUDE.md`) is never re-pulled by a grounding
step. After compaction or in a fresh task, previously loaded standards do
NOT count as ambient; re-resolve for the task at hand.

**Tolerant reader:** a skill reading an index at an OLDER contract version
than its binding degrades to best-effort routing and surfaces "index at
vX, contract at vY: re-run setup to migrate". A skill reading a NEWER
index also degrades to best-effort routing but says "update the
`<plugin>` plugin", and never offers migration (no downgrades). No
auto-rewrite in either direction.

## `.claude/rules` seam (division of content)

- **Rules = push** (fire when Claude works with a matching file): short
  imperative directives, consumer-owned.
  - **Pointer**: when a rule's load timing matters, fetch
    [memory: path-specific rules](https://code.claude.com/docs/en/memory#path-specific-rules)
    live.
- **Standards = pull** (index-routed at plan/review stages): substantial
  criteria and prose.
- **Pointer pattern:** a path-scoped rule may carry an imperative pointer
  directive to a standards file, which loads lazily on rule fire. Never `@import`
  (imports expand at launch, defeating lazy load), never restated content.
- Setup MAY offer generating pointer rules for indexed ecosystem surfaces
  (interactive only; the `.claude/` write-guard prompt is acceptable
  there).

## Setup and migration (normative)

The single home for the bootstrap procedure. Consuming plugins' setup
skills implement this section by reference; they do not restate it.

**Bootstrap (first run, interactive):**

1. Read state: concern file → index presence test → inference sources
   (existing docs, ecosystem configs, a root `CODING_STANDARDS.md` and
   `CONTRIBUTING.md`, ambient `CLAUDE.md` content).
2. Short-circuit: a conforming index whose `standards-contract` version
   equals the bundled contract version → validate row paths, report
   healthy, exit without interview.
3. A `<standards_dir>/README.md` that fails the presence test is
   hand-authored content: use it as an inference source, and require
   explicit confirmation before converting it into an index. Never
   overwrite it.
4. Interview: confirm the standards root (persist to
   `.claude/standards.yaml` only on relocation), propose surfaces
   inferred from the repository. Before writing the concern file, apply
   the same `git check-ignore -v` guard to `.claude/standards.yaml`
   itself: an ignored concern file would leave future clones silently
   falling back to the default root; on a match, STOP and surface the
   rule.
5. Committed-root guard, then write the skeleton: before creating
   anything, run `git check-ignore -v` on a representative path inside
   the root (e.g. `<standards_dir>/README.md`); if a consumer ignore rule
   matches, STOP and surface the exact rule and source line. An ignored
   "team" layer can never be the committed, shared surface this contract
   depends on, and resolving the rule is the consumer's edit to make.
   Then write `<standards_dir>/README.md` (index with the
   `standards-contract` frontmatter at the bundled contract version) and
   the setup-owned `<standards_dir>/.gitignore` containing `*.local.md`.
6. Validate every index row path (external-row validation duty).
7. Optionally offer pointer-rule generation and an offer (never a demand)
   to reorganize mixed or spread standards content toward the SRP + index
   shape.

**Idempotency:** setup is re-runnable anytime. A re-run against a
conforming, current-version index proposes no changes: run twice, no
diff.

**Migration (inside re-runnable setup, with no separate action):** setup
compares the index's `standards-contract` frontmatter to the bundled
contract version. Detection is DIRECTIONAL:

- Index OLDER than the bundled contract → explain the delta and offer
  guided migration. Idempotent: re-run after migration → no diff.
- Index NEWER than the bundled contract → best-effort read, report
  "update the `<plugin>` plugin", and NEVER offer migration: setup
  never downgrades an index, and two plugins at different bundled
  versions must not nag in a loop.

**Ignore-file rule (restated for setup):** the only ignore file setup
touches is the `<standards_dir>/.gitignore` it created itself.

## Versioning

- The contract version lives in this file's `standards-contract`
  frontmatter (the synced binding copy must be self-describing offline);
  `CHANGELOG.md` carries the history.
- Additive schema change → minor; breaking (column, key, or semantics
  change) → major, with a migration note in the changelog and version
  bumps in every consuming plugin.
- A consumer index records its conformance version in its own
  `standards-contract` frontmatter; delta handling is the directional
  migration rule above.
