# map-landscape-redesign

## Brief

### TLDR

- A bare `/architecture:map-landscape` charts the current repository plus its reference graph, one
  hop out; `--repos` and `--root` stay as explicit overrides.
- References become typed, counted edges extracted per source type by a tested script; other-owner
  repositories render as external systems, kept read-only.
- The committed record is `docs/architecture/landscape.json`; both rendered artifacts derive from it
  through a reasoning-free render script, and every re-run reports drift, with `--check` for CI.
- The facts script gains a runtime-versus-development scope axis, prunes `.github/` and other
  dot-directories from runtime probes, and adds a Tooling column.
- `--remote` facts are opt-in and presence-gated; a fixed closing report and a rewritten description
  make single-repository-plus-references the primary use.

### Goal

Rework the `map-landscape` skill so that one run in one repository yields a useful, committed,
re-runnable landscape of that repository and everything it references. Today the skill only reads
local checkouts and stops on a bare invocation, so on a cloud checkout of this repository it drew one
node with no edges even though the tracked files name nineteen other organisation repositories.

### Constraints

- Facts and edges come from tested scripts; the model adds prose annotations only. Rendering scripts
  do only reasoning-free work (tables, alias sanitising, boundary grouping, labels).
- The declared-home doctrine in `plugins/architecture/reference/config.md` stays: an interactive run
  with no home proposes `docs/architecture`, `--out <dir>` overrides one run, and a non-interactive run
  with neither still stops.
- No network call is made unless `--remote` is passed. Externals are never fetched from unless
  `--remote=all`, and nothing ever writes to another repository.
- Scripts stay bash plus POSIX awk/grep/sed, matching `portfolio-facts.sh`; no jq, no python.
- The working directory is never walked for nested repositories.
- Skill bodies follow `.claude/rules/skill-bodies-state-current-rules.md`; validation runs through
  `scripts/affected-tests.sh --run`.

### Acceptance criteria

- A bare run in this checkout produces a landscape with `ci-workflows` and `standards` as nodes and
  typed edges to them, without any argument.
- Every edge cites its source file and type; every fact cites its evidence.
- IF no home is declared and the run is non-interactive, THEN nothing is written.
- IF `--remote` is absent, THEN no network call is made.
- WHILE a committed `docs/architecture/landscape.json` exists, a re-run reports drift instead of
  silently overwriting, and `--check` exits non-zero on drift.
- This checkout no longer reports Python as a runtime; its CI pins appear under Tooling.
- Rendering a fixed facts-plus-edges fixture twice yields byte-identical artifacts.
- Existing evals are updated, and the `no-scope-names-both-forms` eval is replaced by one asserting
  the bare default.

### Captured assumptions

- The GitHub MCP or an authenticated `gh` is available when `--remote` is used; otherwise the flag
  reports unavailability and continues local-only. Revisit if a consumer needs remote facts with
  neither.
- Mermaid stays the default dialect. Revisit if Structurizr becomes the organisation default.
- Same-owner is decided from the current repository's `origin` owner segment. Revisit if a consumer
  has repositories split across owners it considers one enterprise.
- A separate `ci_tooling` bucket was rejected in favour of a scope axis because every surveyed
  standard (CycloneDX scope, SPDX dependency relationships, npm devDependencies, PEP 735 dependency
  groups, GitHub dependency-graph scope) separates runtime from development on scope, and GitHub
  Linguist vendors `.github/` out of language statistics. Revisit if a manifest family appears whose
  scope cannot be read from the file.

### Out-of-scope

- Transitive hops beyond one without `--remote`.
- Branch or worktree hygiene (`/repo-fleet-hygiene:audit`), GitHub organisation settings
  (`/github:audit`), doc-versus-code drift inside one repository (`/codebase-health:audit`), and
  module-level structure (`/architecture:improve`).
- Container-level or component-level C4 views.
- Writing the consumer's root instruction file; `/architecture:setup apply` owns that.

### Deferred questions

None. All twelve interview questions were answered; see the memory-tier ledger.

### Sequencing

One tracking issue with four children, in order, each shipped as its own draft PR:

1. Manifest scope hygiene in `portfolio-facts.sh` (scope axis, dot-directory pruning, Tooling).
2. Core reshape: bare default scope, reference-edge script, `landscape.json` record with drift and
   `--check`, closing report, description and README rewrite, evals.
3. Render script for both dialects.
4. `--remote` facts.

## Plan
