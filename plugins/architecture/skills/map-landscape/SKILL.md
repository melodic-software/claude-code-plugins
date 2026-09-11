---
description: "Chart a repository and the systems it references as a C4 System Landscape plus an application-portfolio table: extract typed reference edges and portfolio facts from tested scripts, commit the result as a landscape record, report drift against it, and render both artifacts into the declared architecture home. Use when: 'map our landscape', 'system landscape', 'what systems do we have', 'what does this repo depend on', 'application portfolio', 'who owns which repo', 'what runtimes are we on', 'chart our repositories', 'C4 context across repos', 'inventory our systems', 'has our landscape drifted'. Skip when: the question is module-level structure inside one codebase (shallow modules, seam placement) which is /architecture:improve, fleet cleanup (stale branches, orphaned worktrees) which is /repo-fleet-hygiene:audit, org settings which is /github:audit, or doc-versus-code drift inside one repository which is /codebase-health:audit."
argument-hint: "[--repos <path>[,<path>...]] [--root <dir>] [--out <dir>] [--check] [--remote[=all]]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart a repository and the systems it references as a C4 system landscape and portfolio table
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose tracked files name the rest of the landscape.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way.

## Purpose

Answer "what systems does this organization have, who owns them, what do they run on, and how do
they relate" from what a repository already says about its neighbours. Every fact traces to a named
file; every edge traces to a matched string in a tracked file; both are collected by scripts, never
derived by hand. The committed record makes the answer re-runnable, so the second run reports what
moved instead of quietly replacing the first.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first; it owns the keys, the topic-doc location,
and the resolution order. This skill reports against that contract rather than restating it.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir` and `landscape_dialect`; exit 1 (no pointer
line), 2 (usage), and 3 (FAIL, surface the resolver's own message) all mean there is no declared
home to read.

Per key, in order: `--out <dir>` wins for this run alone, then a declared topic-doc value, then an
inference PROPOSED from repository evidence and confirmed by the operator, then one question. Two
outcomes are non-negotiable when nothing answers: `landscape_dialect` falls back to `mermaid`, and
`architecture_dir` has NO default, so an undeclared and unconfirmed home, including every
non-interactive run, STOPS and points at `/architecture:setup`.

This skill never writes the consumer's root instruction file or its topic doc. `/architecture:setup
apply` owns both.

## Choose the subject repositories

1. **No scope argument**: the current repository, plus every repository its tracked files reference,
   one hop out. This is the default and the primary use. Facts are collected from the current
   checkout; the referenced repositories are nodes with edges and no probed facts unless they are
   also checked out locally or `--remote` is passed.
2. **`--repos <path>[,<path>...]`**: exactly those repositories, facts and edges both. No discovery
   runs at all.
3. **`--root <dir>`** (repeatable): discovery, delegated to the `repo-fleet-hygiene` plugin when it
   is installed and an announced bundled walk when it is not. Read
   [scope-modes.md](${CLAUDE_PLUGIN_ROOT}/skills/map-landscape/reference/scope-modes.md) before
   running this mode; the collaborator's plan is wider than the roots you asked for, and charting it
   unfiltered grows the landscape to the operator's whole configured fleet.

The session's working directory is never WALKED for nested repositories under any mode. Reading the
current repository as the default subject is not a walk: it is one path, resolved from
`git rev-parse --show-toplevel`.

## Build the record

One call assembles both collectors into the committed record:

```bash
"${CLAUDE_SKILL_DIR}/scripts/landscape-record.sh" \
  --source "<how the subject set was chosen>" --remote "<not used | used, owned only | used, all>" \
  --edges-from <subject-repo> <repo-path>...
```

The `${CLAUDE_SKILL_DIR}` anchor matters. A bare relative path resolves against the session's working
directory, which is not where the script lives.

`--source` and `--remote` are recorded verbatim, so a later reader can tell an explicit list from a
fleet plan, and a local-only run from one that fetched. `--edges-from` is the repository whose
tracked files supply the edges: the current repository under the default and `--root` modes, the
first path under `--repos` unless the operator names another.

The record carries `repositories[]` from `portfolio-facts.sh` (`name`, `remote`, `owner`, `runtime`,
`tooling`, `target_framework`, `dependencies[]`, `dev_dependencies[]`, `last_touched`, `evidence{}`)
and `edges[]` from `reference-edges.sh` (`from`, `to` as `owner/repo`, `type`, `relation`, `count`,
`files[]`).

It also records `subject_owner`, the organisation the graph was drawn from, resolved by the edge
extractor so the nodes and the edges cannot disagree about it. That is what makes a checkout
internal: having a repository on disk says where someone works, not who owns the system, so a
cross-owner checkout is the same external system the edges to it already call external.

Anything no probe could derive is the literal `unknown`. Carry it through to the artifacts as-is;
never replace it with a guess, and never fill it from a commit author, a directory name, or
ecosystem memory.

`runtime` and `dependencies` are runtime scope, what the repository RUNS ON. `tooling` and
`dev_dependencies` are development scope, what it is BUILT WITH: npm `devDependencies`, PEP 735
dependency groups, a `requirements-ci.txt`, anything under a dot-directory. Report them as separate
facts; a linter is not a runtime.

Edge `relation` is `internal` when the target owner matches the subject's own and `external`
otherwise. An external repository is reference material: drawn and recorded, never written to, never
fetched from unless `--remote=all`. Edges are the script's output, not your judgment: do not add one
the script did not extract, and do not delete one for looking incidental, because a low `cites`
count IS the signal that the reference is weak.

## Report drift, and honour --check

When `<architecture_dir>/landscape.json` already exists, compare before writing anything:

```bash
"${CLAUDE_SKILL_DIR}/scripts/landscape-record.sh" \
  --drift-against "<architecture_dir>/landscape.json" --edges-from <subject-repo> <repo-path>...
```

Exit 0 means the committed record still matches. Exit 3 means it drifted; the report names
repositories and edges added or removed, facts whose value changed, and cited evidence files that no
longer exist. A `last_touched` that moved is reported as `moved on <repo>` and does NOT set the exit
code, because the subject repository advances its own HEAD on every commit. Surface the whole
report, gating and non-gating lines alike, before the artifacts.

`--check` stops there: run the comparison, print the report, write NOTHING, and report the
comparison's exit code as the run's outcome, so a lane invoking the script directly fails on drift.
That is the CI shape, and the only mode in which this skill writes no file at all when a home is
declared. Do not "helpfully" refresh the record so the next run is clean.

## Remote facts, only when asked

Without `--remote`, no network call is made at all and the record says `remote: not used`. That is
the default and it is not negotiable by a referenced repository looking empty.

With `--remote` (or `--remote=all` for externals too), read
[scope-modes.md](${CLAUDE_PLUGIN_ROOT}/skills/map-landscape/reference/scope-modes.md) for the
presence gate, the fact list, the evidence shape, and the rule that a local checkout always wins.

Fetched facts reach the record through `--remote-facts <file>`, one JSON object per line in the
shape `portfolio-facts.sh` emits. Without it the flag records only that a fetch happened, and every
referenced repository stays factless. Pass the same file to the drift run: a merged record compared
against a local-only collection reads every fetched repository as removed.

## Emit artifacts

Render, then annotate. The renderer does the mechanical work; you write only prose.

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-landscape.sh" \
  --record "<architecture_dir>/landscape.json" --out "<architecture_dir>" \
  --dialect "<landscape_dialect>" --notes "<architecture_dir>/landscape-notes.md"
```

Write `landscape.json` first, then render from it. The script writes `landscape.md` (mermaid) or
`landscape.dsl` (structurizr) plus `portfolio.md`, and appends `landscape-notes.md` verbatim when it
exists. `--top-external <N>` sets how many external systems the diagram draws, most referenced
first; every internal system is always drawn and the remainder is counted under the diagram.

`landscape-notes.md` is the ONLY file in the architecture directory you author, and the only one you
never overwrite: read it, extend it, leave what a person wrote alone, and mark an annotation as an
annotation. Annotations say what a system is FOR, which the extractor cannot know.

## Close with the report

End every run with this block, in this order, filled from the record and the script exits:

- **Artifacts**: each path written, or `none written (--check)`.
- **Repositories charted**: internal count, external count.
- **Edges by type**: `uses-workflow`, `installs-plugin`, `depends-on`, `cites`, each with its count.
- **Unknown facts**: how many fields across the record are the literal `unknown`.
- **Discovery source**: default (current repository plus reference graph), explicit list, fleet
  plan, or bundled walk.
- **Remote**: not used, used for owned repositories, used for all, or requested and unavailable with
  the missing backend named.
- **Drift**: none, the drift summary, or no committed record to compare against.

## What this skill does NOT do

- Baseline-versus-target gap analysis, capability maps, or work-breakdown structures.
- Container-level or component-level C4 views. This is the landscape altitude only.
- Transitive hops beyond one. A repository named by a repository this one names is not charted.
- Modify any repository other than the consumer, or write outside `<architecture_dir>` within it.
  External repositories are read-only reference in every mode.
- Reach the network without `--remote`.
- Write the consumer's root instruction file, inside or outside the marked region. That is
  `/architecture:setup apply`.
- Invent a home. No declared, no `--out`, and no confirmed `architecture_dir` is a stop, not a
  default.

## Next

- One repository on the landscape needs its own module-level pass: `/architecture:improve`.
- The landscape settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **The two dialects are not symmetric, and mermaid is the loose one.** Structurizr has a dedicated
  `systemLandscape` view type. Mermaid has no landscape diagram type, so the mermaid output
  is a `C4Context` diagram used without a focal system. The mermaid-C4 experimental fact and
  the recheck trigger (experimental banner drops, or mermaid documents a dedicated landscape
  type) live in `${CLAUDE_PLUGIN_ROOT}/reference/config.md` under C4 dialect surfaces. This
  skill does not carry a second stamp.
- **A referenced repository is not a checked-out one, and the portfolio says so.** Under the default
  scope only the subject repository has probed facts. Everything else is a node with edges and an
  `unknown` row. That is the honest answer without `--remote`, not a gap to fill by guessing.
- **`cites` is the weakest type and the loudest one.** It means a name appears in tracked text,
  nothing more, and on a documentation-heavy repository it outnumbers every other type several times
  over. Read a high `cites` count as "this repository talks about that one", never as a dependency.
- **A dot-directory manifest is tooling, never a runtime.** Cache and build directories (`.venv`,
  `.mypy_cache`, `.tox`) are pruned outright; the CI and container config directories (`.github`,
  `.gitlab`, `.circleci`, `.devcontainer`) are kept, and every manifest under one is pinned to
  development scope whatever its content says. So a repository of shell and markdown whose CI
  installs `ruff` reports `runtime: shell` with `tooling: python`. The same rule makes a
  `package.json` carrying only `devDependencies` report tooling, which is why `target_framework` can
  be `unknown` while a `Tooling` entry is present.
- **A checkout on disk is not a claim of ownership.** A repository whose owner differs from
  `subject_owner` renders as an external system with its probed facts intact, outside every
  enterprise boundary, even though this run read its files. It is drawn whatever `--top-external`
  says: that cap trims the tail of repositories the run only read about, never the set someone
  asked it to chart.
- **A quote or a pipe read out of a manifest is replaced, not preserved.** A target framework, an
  owner from `CODEOWNERS` and a repository name are all repository-controlled text that lands
  inside a quoted string in both dialects and inside a cell in the portfolio table. Neither diagram
  grammar has a portable escape for its own delimiter, so the delimiter is swapped for one that
  cannot close the literal. A value that comes out altered is a value that was never a fact.
- **`owner` is a ladder, and commit authors are not on it.** The `CODEOWNERS` default `*` rule's
  first owner, then the owner segment of the `origin` remote, then `unknown`. Who edits a repository
  most is not who owns it, so neither the script nor the write-up looks at git authorship.
- **`last_touched` is local HEAD unless a remote fact replaced it, and nothing fetches by default.**
  A stale checkout reports a stale date. The generated-on line carries the remote state so a reader
  can tell which it is.
- **The record holds no filesystem paths.** The fact collector reports where each checkout sits and
  the record drops it, because a committed artifact naming one machine's directory layout differs on
  every other machine that regenerates it. Read the collector directly when a run needs the path.
- **The fleet plan is a temp artifact, and wider than the roots you asked for.** Both traps belong
  to `--root` alone and are stated in full in
  [scope-modes.md](${CLAUDE_PLUGIN_ROOT}/skills/map-landscape/reference/scope-modes.md).
