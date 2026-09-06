# Design threads — cross-repo-landscape

Container #3801. Every thread below is RESOLVED with its rationale recorded, per the
`/planning:design-handoff` gate. Evidence paths are repo-relative to the marketplace root at
`origin/main` `912d6b3ec` (2026-09-06) unless stated.

## T1 — Discovery input grammar (RESOLVED)

**Decision.** `/architecture:map-landscape [--repos <path>[,<path>...]] [--root <dir>]...`
Precedence: `--repos` wins outright (exactly those repositories, no discovery). `--root` triggers
discovery. Neither: the skill stops and names both forms; it never scans the session's working
directory.

**Rationale.** The Brief says discovery comes from "an explicit argument, or from the
repo-fleet-hygiene canonical-repo discovery". That discovery is not argument-free:
`/repo-fleet-hygiene:audit` stops when no scope resolves and treats the project directory as
"not a scope fallback" (`plugins/repo-fleet-hygiene/skills/audit/SKILL.md`, "If no scope
resolves"). So "no explicit list" cannot mean "no argument"; it means "a scan root instead of a
list". Mirroring the collaborator's own scope grammar (`--root`, bare positional path) keeps the
two skills interchangeable for the operator. Rejected: auto-scanning `${CLAUDE_PROJECT_DIR}`'s
parent (the collaborator rejects the same thing for the same reason: it audits whatever tree the
shell sits in).

## T2 — Fleet-hygiene seam (RESOLVED)

**Decision.** When the `repo-fleet-hygiene` plugin is installed and `--root` was given, it owns
bounded fleet discovery and canonical-checkout resolution: resolve the topic slug per the
topic-docs binding, `mkdir -p` the memory slice, then invoke
`/repo-fleet-hygiene:audit <root>... --plan-file <memory_dir>/<topic-slug>/fleet-plan.json`
via the Skill tool, confirm `schema_version` is `1`, and read `repositories[]` keeping only
entries whose `discovered` path lies under a requested root (the collaborator's config-supplied
scope is additive to CLI scope, so an unfiltered read could chart the operator's whole configured
fleet); from the kept entries use `canonical` and `remote`. When the plugin is absent, or the
plan file is missing or carries another `schema_version`, fall back to the bundled walk: recurse
from each root to depth 5, treat a `.git` entry as a repository and do not descend into it, skip
`node_modules`, `vendor`, `.venv`; canonical checkout = first record of
`git worktree list --porcelain`. The fallback is announced in the run summary, as is the fact
that the collaborator's audit collects GitHub evidence and may need `gh` authentication.

**Rationale.** The collaborator's discovery is skill-private beyond its slash invocation
(`docs/PLUGIN-PHILOSOPHY.md` "Do not path-cite into a skill in a different plugin";
`docs/adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md`), so the
seam is the invocation plus the artifact it writes to a caller-chosen path. `--plan-file` is a
documented flag; the plan JSON carries `schema_version: 1` (`audit-fleet.sh` action-plan writer),
which is the only versioned handle available. Reading the human report instead would couple to
undocumented prose layout. The bundled fallback restates the collaborator's minimal discovery
rules (marker, no-descent, default skips, worktree-first canonical) because an installed skill
cannot defer to this repository at runtime. Deferred: asking fleet-hygiene to publish a
`discover`-only mode or a documented plan schema (see PLAN.md deferred questions).

## T3 — Fact derivation and the deterministic collector (RESOLVED)

**Decision.** A helper script `scripts/portfolio-facts.sh <repo-path>...` emits one JSON object
per repository on stdout (`name`, `path`, `remote`, `owner`, `runtime`, `target_framework`,
`dependencies[]`, `last_touched`, `evidence{}`), with `unknown` for any field it cannot derive.
Probes, first hit wins per field:

| Field | Probe order |
|---|---|
| `owner` | `CODEOWNERS` (root, `.github/`, `docs/`) default `*` rule's first owner → owner segment of the `origin` remote URL → `unknown` |
| `runtime` | `*.csproj`/`*.fsproj`/`global.json` → `dotnet`; `package.json` → `node` (or `bun`/`deno` when their lockfile or config is present); `pyproject.toml`/`requirements*.txt`/`setup.py` → `python`; `go.mod` → `go`; `Cargo.toml` → `rust`; `pom.xml`/`build.gradle*` → `jvm`; `Gemfile` → `ruby`; `composer.json` → `php`; `*.sh`/`*.ps1` only → `shell`; else `unknown`. Multiple hits list all, first listed is primary |
| `target_framework` | `<TargetFramework(s)>` from the first `*.csproj`; `engines.node` from `package.json`; `requires-python` from `pyproject.toml`; `go` directive from `go.mod`; `rust-version`/`edition` from `Cargo.toml`; else `unknown` |
| `dependencies` | `<PackageReference Include>` / `<ProjectReference>`; `dependencies` + `peerDependencies` keys; `[project].dependencies` / `requirements*.txt` names; `require` block of `go.mod`; `[dependencies]` of `Cargo.toml`; capped at 25 names per repo, sorted, deduplicated |
| `last_touched` | `git log -1 --format=%cI` on the canonical checkout's HEAD |

**Rationale.** The Brief's captured assumption is that all five columns are derivable from
repository contents and metadata. Counting, matching, and extracting are deterministic; a script
that runs and returns real output beats a model reading twenty repositories by hand, and it is
the only part of the skill a bash test can exercise (`scripts/run-plugin-tests.sh` discovers
`plugins/**/*.test.sh`). `owner` is the weakest column: nothing in a repository states an
organizational owner, so the ladder degrades to the remote owner segment and finally `unknown`,
never a guess from commit authors (authorship is not ownership). `last_touched` is the local
HEAD date because the collaborator never fetches and neither does this skill; the column header
says "local HEAD". Rejected: a prose-only skill (no testable surface; every run re-derives the
probes and drifts).

## T4 — Landscape relationships are model judgment with cited evidence (RESOLVED)

**Decision.** The script emits facts; the model draws `Rel` edges. An edge from A to B exists
only when a fact in A names B: a dependency name equals B's repository name or package id, a
`ProjectReference`/workspace path resolves into B, or B's remote URL appears in A's tracked
config or README. Each edge carries the matched string as its description. No cited match, no
edge. Repositories with no edges still appear as systems.

**Rationale.** Name matching across ecosystems needs judgment (a NuGet id, an npm scope, a
Go module path), but an edge without evidence is a fabrication in a document teams will trust.
The evidence string in the edge makes every line auditable.

## T5 — Output home and dialect: convention doc, resolved by the vendored resolver (RESOLVED)

**Decision.** The consumer declares an architecture topic doc at
`<convention-home>/architecture/README.md` carrying a fenced YAML block with
`architecture_dir` (repo-relative, no default) and `landscape_dialect`
(`structurizr` | `mermaid`, default `mermaid`). The convention home resolves through the
vendored `${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh` (exit 0 resolved, 1 no
pointer, 2 usage, 3 FAIL); the skill runs it and follows the exit code, never parsing the root
file itself. Ladder per key: topic doc → infer from repo evidence (an existing `*.dsl` file →
`structurizr`; an existing `docs/architecture/` or `architecture/` directory → that dir) → ask
once → for `landscape_dialect` the documented default `mermaid`; for `architecture_dir` there is
no silent default: a non-interactive run with no declaration and no confirmed inference stops
and prints the topic-doc recipe, because the Brief says the location is the consumer's, never
this plugin's pick. Inference proposes; only the operator's confirmation binds. Persisting the
declaration (pointer line region plus the topic doc) is owned by `architecture:setup` (T11);
`map-landscape` itself never writes the consumer's root instruction file.

**Rationale.** No "architecture home" declaration exists anywhere in the marketplace (grep of
`architecture home|architecture_dir|structurizr|system landscape`: zero hits), so the plan has to
create one, and
`docs/adr/0018-express-team-shared-conventions-as-consumer-convention-docs.md` already fixes
the shape for team-shared prose configuration with no per-operator axis: a convention doc at
the consumer's convention home, bound by the pointer line
(`docs/conventions/config-cascade/README.md` "Expression doctrine";
`plugins/plugin-quality/reference/config.md` is the pilot). The resolver is shared by vendoring
with a sync gate (`docs/adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md`;
`scripts/sync-resolve-convention-home.sh` canonical copy in `plugins/claude-config/lib/`,
carriers enrolled in its `copies=()` array). Keeping `map-landscape`'s write surface to the two
artifacts matches plugin-quality's "inference proposes, never writes" rule; persistence belongs
to the setup skill the philosophy requires once a consumer configuration surface exists (T11).
Rejected: the topic-docs memory tier `improve` uses (`.work/`, never committed) because a
landscape is a durable team artifact, and `${CLAUDE_PLUGIN_DATA}` because the consumer must
own where its architecture lives.

## T11 — `architecture:setup` owns the configuration surface (RESOLVED)

**Decision.** Phase 1 also ships a thin check-centric `architecture:setup`, mirroring the pilot
`plugins/plugin-quality/skills/setup/SKILL.md`: frontmatter `user-invocable: true`,
`disable-model-invocation: true`, no `metadata` block (the cheat-sheet generator excludes every
skill named `setup` and errors when one carries `workflow-stage`/`summary`/`cadence`), and
`argument-hint: "check | apply [home=<dir>] [architecture_dir=<path>] [landscape_dialect=<structurizr|mermaid>]"`
(double-quoted, `check` leading, as `scripts/validate-plugin-contracts.mjs` requires). The body
documents both `check` and `apply` in code spans. `check` is read-only: it runs the vendored
resolver and prints a PASS/FAIL/INFO table with one remediation line per FAIL, covering no
pointer line (resolver exit 1), a resolved home with no `architecture/README.md`, a topic doc
with an unknown key or value, and a conforming declaration. `apply` converges two things, as
the pilot does: the marked `convention-home` pointer region in the root instruction file
(only inside the markers, preserving unrelated content, only when `home=` is supplied or a
home is confirmed) and the `architecture/README.md` topic doc at the resolved home. It is
idempotent, proposes inferred values and waits for confirmation when arguments are incomplete,
runs non-interactively when `home=`, `architecture_dir=`, and `landscape_dialect=` are all
supplied, and after writing re-reads and reports the stored values it observed. No retired
layers, no retirement records.

**Rationale.** `docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable": a plugin requires
a `setup` skill iff it has a consumer-project configuration surface; T5 creates one. The pilot
(`plugin-quality`) ships one and routes its resolution ladder's ask rung to `setup apply`. The
setup contract is validated by `scripts/validate-plugin-contracts.mjs` (frontmatter and
argument-hint rules for `skills/setup/**`) and the philosophy's setup bullets (idempotent,
transparent, evidence-bearing readback, non-interactive with complete arguments). The pointer
region is machine-owned by design (`docs/conventions/config-cascade/README.md` "Expression
doctrine") and the pilot's `apply` already converges it, so a setup that only printed a recipe
would be a silent second way; `map-landscape` itself still never writes it.

## T6 — Dialect asymmetry (RESOLVED)

**Decision.** `structurizr`: one `workspace` with a `model` of `softwareSystem` elements and
`->` relationships, and a `views { systemLandscape "landscape" { include * autoLayout } }`
block, written to `<architecture_dir>/landscape.dsl`. `mermaid`: a `C4Context` block titled
"System Landscape" with no focal system, every repository a `System` (grouped in an
`Enterprise_Boundary` by remote owner when more than one owner is present), `Rel` lines per T4,
written to `<architecture_dir>/landscape.md` inside a `mermaid` fence. The skill body states
that mermaid has no dedicated landscape diagram type and that its C4 syntax is upstream-marked
experimental.

**Rationale.** Verified 2026-09-06 against `https://docs.structurizr.com/dsl/language`
(`systemLandscape [key] [description] { ... }`; `softwareSystem <name> [description] [tags]`;
`<identifier> -> <identifier> [description] [technology] [tags]`) and
`https://mermaid.js.org/syntax/c4.html` (types: `C4Context`, `C4Container`, `C4Component`,
`C4Dynamic`, `C4Deployment`; "This is an experimental diagram for now. The syntax and properties
can change in future releases."). Recheck trigger: a mermaid release adds a landscape type or
drops the experimental notice. The Brief's captured assumption that both dialects are
"acceptable" holds only with this asymmetry stated; the Brief body is amended accordingly.

## T7 — Portfolio table shape (RESOLVED)

**Decision.** `<architecture_dir>/portfolio.md`: a heading, a generated-on line (date, discovery
source: explicit list / fleet-hygiene plan / bundled walk), then one markdown table with columns
`Repository | Owner | Target framework | Runtime | Dependencies | Last touched (local HEAD)`,
one row per discovered repository, rows sorted by repository name, `unknown` rendered as-is.
Dependencies render as a comma-joined list truncated to the first 10 with `(+N)`; the full list
stays in the script output.

**Rationale.** The five Brief columns plus the row key. A table that renders on GitHub without
tooling is the audience's reading surface; the truncation keeps rows scannable while the JSON
keeps the facts.

## T8 — Coverage rows in the design-handoff gate (RESOLVED)

**Decision.** After the binary gate's verdict (PASS or FAIL alike), emit one advisory table with
six rows, `what`, `how`, `where`, `who`, `when`, `why`, and columns
`Dimension | Covered by | Status`. A row is covered when a thread whose status is RESOLVED or
directional records a decision about that dimension; the cell names the thread and its status.
TAGGED-DEFERRED threads never cover a row. An uncovered row reads `none`. The table is a
judgment read over the thread text (threads carry no dimension field), so the skill instructs a
whole-artifact read and states the reading rule for each dimension in one line each (what =
the thing being built or changed; how = mechanism or algorithm; where = location, topology,
runtime placement; who = actor, owner, operator, caller; when = timing, sequencing, lifecycle;
why = recorded rationale for the decision). On a `design-resolution.md` early-exit the same
table is read over that file. The table appears in the handoff summary and the resume prompt
lists uncovered dimensions verbatim so `/planning:plan` can carry them as open questions. The
table is never written to disk and the gate's pass/fail sentence is unchanged.

**Rationale.** `design-threads.md` has no schema beyond name, options, status, rationale
(`plugins/planning/skills/design/SKILL.md` Phase 2), so coverage cannot be a field lookup; it
must be a stated reading rule or it degrades to vibes. Counting directional threads avoids a
misleading `none` on a dimension the team has agreed a direction for; slice #3817's criterion
wording is amended to say "resolved or directional". Emitting on FAIL costs nothing and gives
the next design round its gap list. `/planning:plan` reads the artifacts on disk, not the
handoff's emitted text, so the table cannot break that hop. Writing coverage into
`design-threads.md` is out of scope by the slice's own exclusion.

## T9 — Framework-free wording in both deliverables (RESOLVED)

**Decision.** Neither SKILL.md names Zachman, TOGAF, or any enterprise-architecture framework.
The six words are introduced as "the six dimensions a design answers". C4 and Structurizr are
named because they are the output formats, not frameworks being taught.

**Rationale.** Brief constraint. Sanity checks grep for the absence and pair it with a presence
check that fails on today's tree.

## T10 — Naming (RESOLVED)

**Decision.** `map-landscape`.

**Rationale.** `map` is not in the fixed verb table (`docs/PLUGIN-PHILOSOPHY.md` "Verb meanings
are fixed"), which fixes the meaning of the verbs it lists rather than closing the set;
`knowledge:map-corpus`, `coupling:reduce`, and `education:explain` are unlisted verbs in the
fleet. The leaf name collides with no other plugin, so no registry entry is needed
(`scripts/skill-leaf-name-registry.txt` records collisions only).
