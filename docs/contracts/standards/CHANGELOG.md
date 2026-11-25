# Changelog for the standards convention

## 1.3.0 - 2026-11-25

Additive. A fifth layer, personal subscriptions: the user-global index's frontmatter may list
`standards_repositories` (`repo`, `topics`, `ref`, `only_in`, `except_in`, in block style) and
`trusted_owners`, both read from that index only. A trusted owner's repository is read live from
its `main`; any other must be pinned to a full commit SHA reachable from one of its branches or
tags, else it is refused. Subscribed layers add or tighten only, below the user-global layer's own
files and below every team-tracked standard; a repository that is also the org layer is read once,
there. Subscriptions add no `REVIEW.md`. `org-standards.sh subscriptions` prints each subscribed
layer with its checkout and its (topic-filtered) index, reports malformed entries, refusals and
index drift, and prints the index diff when a pin moves; `STANDARDS_SUBSCRIPTIONS_DISABLED=true`
skips them for a session. A user index that uses the list declares 1.3.0. An index at 1.2.0 is
older than the bundled contract, so setup offers the guided migration, which changes nothing but
the version.

## 1.2.0 - 2026-11-24

Additive. A fourth layer, the org layer: the team layer of the repository a consumer's
`docs/conventions/source-control.yaml` names in `standards_repository`, read from its `main`
(`STANDARDS_DIR` in CI, else a cached shallow clone) below the team layer, which adds to it or
replaces an org file by name. The review criteria in effect are the org `REVIEW.md` with the
repository's `REVIEW.md` appended, or the repository's alone when its first non-blank line is
`<!-- review-base: replace -->`. Consuming plugins bundle `scripts/org-standards.sh`. A repository
without `standards_repository` resolves exactly as before. An index at 1.1.6 is older than the
bundled contract, so setup offers the guided migration, which changes nothing but the version.

## 1.1.6 - 2026-11-17

Wording only. The index example drops its `csharp` row, the Surface column no longer lists
`csharp`, `python` and `markdown` as example surface ids, and the pointer-pattern bullet drops its
C# directive, so the shipped text names no ecosystem (ADR 0101). The layers, the schema, the index
shape, the resolution ladder and the migration rules are unchanged.

## 1.1.5 - 2026-11-13

Resolution ladder. Planning and implementing skills also read the repository's review-criteria
index, `docs/review/README.md` when present, and load only the files its rows match to the change.
The rungs, the schema, the index shape and the migration rules are unchanged. An index at 1.1.4 is
older than the bundled contract, so setup offers the guided migration.

## 1.1.4 - 2026-11-12

Wording only. The memory-rules pointer in the `.claude/rules` seam no longer carries an as-of date
or recheck trigger, per the upstream-drift convention 5.0.0. The layers, the precedence rule, the
schema, the index shape and the migration rules are unchanged.

## 1.1.3 - 2026-11-04

Wording only. The personal layer, `<standards_dir>/*.local.md`, is called the personal override
rather than the personal overlay, matching the config cascade. The layers, the precedence rule, the
schema, the index shape and the migration rules are unchanged.

## 1.1.2 - 2026-11-01

Resolution ladder. Rung 4 now names a `CODING_STANDARDS.md` and a `CONTRIBUTING.md` at the
resolution root as inference sources, beside docs directories, ecosystem configs and a standards
location declared in `CLAUDE.md`, and setup's bootstrap step 1 reads them too. The other rungs,
the schema, the index shape and the migration rules are unchanged. An index at 1.1.1 is older than
the bundled contract, so setup offers the guided migration.

## 1.1.1 - 2026-10-21

Wording only. The Paved paths section's readers bullets now name a writer: `reuse-or-replace` is
the one skill that writes entries, and only after the user says yes, with other skills proposing
entries to it. It also names `plan`, `implement` (only the entries for the concerns the paths it
edits touch) and review as readers. The index shape, the resolution ladder and the migration rules
are unchanged. An index at 1.1.0 is older than the bundled contract, so setup offers the guided
migration.

## 1.1.0 - 2026-10-04

Additive. The Surface column gains the recommended kind `paved-path`, and a new Paved paths
section says what that row's file holds (per concern: the chosen way and the check that enforces
it) and who reads it: review's `quality-gate` and `fanout` pass the file to the `code-reviewer`
agent, and discipline's `reuse-or-replace` reads it on demand. No plugin ships default paved
paths. The index shape, the resolution ladder and the migration rules are otherwise unchanged. An
index at 1.0.3 or earlier is older than the bundled contract, so setup offers the guided migration.

## 1.0.3 - 2026-10-10

Wording only. The `.claude/rules` seam no longer says a rule fires only on a file read: it says a
rule fires when Claude works with a matching file and points at the memory page's path-specific
rules section for what loads one. The schema, the index shape, the resolution ladder and the
migration rules are unchanged. An index at 1.0.2 is older than the bundled contract, so setup
offers the guided migration.

## 1.0.2 - 2026-10-03

Wording only. The binding copy in a plugin is now generated by `scripts/sync-shared-copies.sh`
with a generated-file header above the contract text, so the contract no longer calls the copy
byte-identical or synced verbatim. The schema, the index shape, the resolution ladder and the
migration rules are unchanged. An index at 1.0.1 is older than the bundled contract, so setup
offers the guided migration.

## 1.0.1 - 2026-09-30

Wording only. The contract's prose drops its em dashes for the punctuation each sentence needs,
and the example index in it carries the new version. The schema, the index shape, the resolution
ladder and the migration rules are unchanged. An index at 1.0.0 is older than the bundled
contract, so setup offers the guided migration.

## 1.0.0 - 2026-07-17

Initial contract:

- Three additive layers on one precedence-inversion rule: user-global
  `~/.claude/standards/`, team-tracked `<standards_dir>/` (default
  `docs/standards/`), gitignored `*.local.md` personal overlays. Personal
  layers add or tighten only; direct conflict → team wins; provenance
  named when a personal rule shapes output.
- Thin routing index at `<standards_dir>/README.md` with a normative
  presence test (`standards-contract` frontmatter key), Surface /
  Applies-when / File columns, external rows with a validation duty, and
  forward-slash paths against the git top-level resolution root.
- SRP standards files (pure prose, no frontmatter) with a soft ~200-line
  size budget and selective section reads.
- Tracked concern file `.claude/standards.yaml` (`standards_dir`), shaped
  by `standards.schema.json`.
- Six-rung resolution ladder with a no-silent-writes guarantee, an
  ambient-content rule, and a tolerant-reader rule.
- `.claude/rules` division of content: rules push, standards pull;
  pointer pattern instead of imports or restated content.
- Normative setup-and-migration procedure: idempotent re-runnable
  bootstrap (run twice, no diff), conforming-index short-circuit,
  hand-authored-README confirmation gate, setup-owned
  `<standards_dir>/.gitignore` for overlays, and DIRECTIONAL version-delta
  handling (older index → guided migration; newer index → best-effort
  read plus "update the plugin", never a downgrade).
