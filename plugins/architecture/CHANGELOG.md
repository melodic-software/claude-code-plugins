# Changelog

All notable changes to the `architecture` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.1]

### Fixed

- **`map-landscape` no longer fabricates an `owner` from a local-path remote.** A git remote is
  often a plain filesystem path, and `portfolio-facts.sh` stripped its first segment as if it were a
  hosting account: `/srv/code/platform/billing` reported owner `srv`, and `file:///opt/mirror/repo`
  reported `opt`. Both were emitted with `evidence.owner: "origin remote URL"`, so a fabricated
  fact carried a citation, which is worse than the wrong value alone. `remote_owner` now requires a
  host (a `scheme://host/...` authority, or the scp-style `host:owner/repo`) and returns `unknown`
  for every path form. The contract's rule is `unknown` for anything underivable, never a guess.
- **`map-landscape` reads the top-level `dependencies` even when a nested member shares its name.**
  The package.json reader sought the first literal `"dependencies"` in the byte stream, so a
  `pnpm.overrides.dependencies` block appearing earlier in the file shadowed the real one and the
  portfolio listed the override's pins as the project's dependencies. The reader now locates the
  member by position with a container stack rather than by text search.
- Regression cases for both, plus assertions for `path` and for the absent-owner citation.

## [0.8.0]

### Added

- `record-decision`: records one architecture decision into whatever ADR convention the consuming
  repository already has. It discovers the directory, numbering scheme and record shape in use and
  writes exactly one record that follows them; where no convention exists it names what it searched,
  offers common shapes, points at the upstream template catalog by URL, and writes nothing until the
  human chooses. Ships seven eval cases over three fixture trees.
- `reference/adr-discovery.md`: the plugin's single ADR discovery ladder (declared, then existing
  directory, then none) plus the numbering and shape inference rules, read by both skills.

### Changed

- improve: `actions/deepening.md` points at `reference/adr-discovery.md` instead of carrying its own
  inline directory list. The declared-location-first rule is unchanged.

## [0.7.0]

### Added

- **New skill `map-landscape`** (`/architecture:map-landscape`): a C4 System Landscape plus an
  application-portfolio table over a discovered set of repositories. Nothing here answered "what
  systems does this organization have, who owns them, what do they run on, and how do they relate":
  the fleet-hygiene plugin discovers repositories but feeds cleanup, and `improve` works inside one
  codebase. Discovery is argument-selected. `--repos` charts exactly the listed repositories with no
  discovery at all; `--root` delegates bounded discovery and canonical-checkout resolution to
  `/repo-fleet-hygiene:audit --plan-file` when that plugin is installed, filtering the plan's
  `repositories[]` to the requested roots because that collaborator's configured scope is additive,
  and otherwise falls back to an announced bundled walk. Neither argument stops and names both
  forms; the session's working directory is never scanned. Facts come from the tested
  `scripts/portfolio-facts.sh` (owner from CODEOWNERS then the remote's owner segment, never a
  commit author; runtime, target framework, dependencies capped at 25, and a local-HEAD
  `last_touched`), with `unknown` carried through rather than guessed. Relationships are model
  judgment behind a hard evidence rule: an edge exists only where a fact in the source names the
  target, and the matched string IS the edge description. Output is `landscape.dsl` with a
  `systemLandscape` view under the `structurizr` dialect, or `landscape.md` with a `C4Context`
  block under `mermaid` (mermaid ships no landscape diagram type and marks its C4 syntax
  experimental, an asymmetry the skill states rather than papers over), plus `portfolio.md`.
- **New skill `setup`** (`/architecture:setup`): the plugin's consumer-configuration surface, a
  convention doc at the consumer's convention home under the config-cascade expression doctrine.
  `check` is read-only and reports PASS/FAIL/INFO with one remediation line per FAIL, covering a
  missing pointer line, a resolved home with no topic doc, and an unknown key or value. `apply`
  converges exactly two artifacts, the marked `convention-home` pointer region and
  `<home>/architecture/README.md`, idempotently, proposing inferred values and waiting when
  arguments are incomplete, running non-interactively when `home=`, `architecture_dir=` and
  `landscape_dialect=` are all supplied, and re-reading from disk to report the stored values it
  observed. `architecture_dir` has no default on purpose: guessing a directory would write two
  generated files into a tree nobody asked for, so an undeclared and unconfirmed value stops
  `map-landscape` instead. No retired layers; this surface is new.
- `lib/resolve-convention-home.sh`, vendored through `scripts/sync-resolve-convention-home.sh`, and
  `reference/config.md` documenting the two keys.

## [0.6.10]

### Changed

- improve: the Phase 1.5 reproduction rule is stated without the anecdote of the run that motivated it, in SKILL.md and `actions/deepening.md`; the Gotchas preamble frames the entries as rules, not an incident log; the hot-spot step names the repository-context list this skill gathers instead of a pre-computed block it no longer has; the scan briefing drops the prior-audit finding id and the "instead of Phase 2" contrast; the description drops two phrases that restate 'improve architecture'.
- improve: `research/deepening/html-report.md` describes badge colours, the files list, band shapes, module labels, and the accent palette in the terms the scaffold's own `<style>` block defines instead of Tailwind classes and colours it never ships; the wins bullet drops its word count; the tone line states the goal instead of banned phrases; the round-trip sequence advice moves from Tone into a sixth diagram pattern with a way to build it under the inline-SVG rule.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.6.9]

### Fixed

- **`improve`:** the git pre-compute lines moved out of `## Pre-computed context` into a "Repository
  context. Gather first" body section of individual Bash calls, one command per call, each `head`
  bound kept inside its command and a failure read as an unknown value. The harness composes a
  skill's whole pre-compute block into one shell invocation, and a worktree-isolated session refuses
  a git-bearing compound command, which blocked these skills from loading inside a worktree. Same
  shape as the worktree skill's fix in #1619. Non-git pre-compute lines stay where they were.

## [0.6.8]

### Changed

- **`improve` skill-listing entry tightened.** It was among the marketplace's ten largest listing
  entries. The description now sets off the friction examples and the cross-dimension routing
  clause in parentheses instead of em dashes while keeping every quoted trigger phrase and the
  `Skip when` disambiguation. Claude Code truncates the combined `description` and `when_to_use`
  text at 1,536 characters in the skill listing, and the shared listing budget scales at 1% of the
  model's context window, so every character an entry spends is a character another skill's
  description cannot. Hook-performance program, phase 6 (skill listing budget).

## [0.6.7]

### Changed

- **Dynamic-context probe fallback made reachable.** The working-tree-status injection piped its
  probe into `head` before `||`, so the fallback could never run and a failed probe rendered an
  empty string under a label that reads as a clean tree. The fallback now sits in a brace group with
  the probe and the cap applies outside it. Whole-repo extract-ssot sweep.

## [0.6.6]

### Changed

- **`improve`'s five `research/deepening/` files are reachable in one hop from the hub.** They were
  reachable only through `actions/deepening.md`, which put required reading two levels from
  `SKILL.md` while the citing line calls the target load-bearing for scan quality. A
  `Reference index. Load on demand` section now links each of the five directly, with a read
  condition per row; `actions/deepening.md` keeps all six of its own citations, so a reader arriving
  mid-chain loses nothing. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.6.5]

### Changed

- **Repo-wide `/ai-slop:audit fix` pass (#3359).** The deepening research files
  legitimately carry flagged vocabulary: `html-report.md` quotes the banned phrase
  its tone rule forbids (now covered marker-free by the detector's quoted-span
  exemption, ai-slop 0.4.0), and `interface-design.md` plus `vocabulary.md` use
  "leverage" as the lens's defined term, closed by the consuming repo's
  `rule_allowed_paths` config entry rather than per-line markers.

## [0.6.4]

### Changed

- **Instruction-surface de-slop (#2891, architecture cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.

## [0.6.3]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.6.2]

### Fixed

- **The `graft-record` field now has a writer.** 0.6.0 added `graft-record:` to the durable
  candidate schema in `skills/improve/actions/deepening.md` and told the Design-It-Twice research
  file that the record "travels into `agreed-shape`" — but no step ever wrote it: the Handoff step
  named `status` and `agreed-shape` and stopped. A schema field nothing fills is a field that is
  always empty, so the left-behind half of a graft survived nowhere, and that is the half that
  stops a later explorer re-proposing a shape this exploration already weighed and dropped. Handoff
  now fills it in the same edit, and states that it is a sibling field rather than part of
  `agreed-shape` and that this is the only step that writes it.
  `skills/improve/research/deepening/interface-design.md` said the record "travels into
  `agreed-shape`" — the wrong field, since the record is that field's sibling. That sentence is
  replaced rather than annotated: leaving it standing beside the correction would have shipped a
  file that names two different destinations for one record. It now names the Handoff step and the
  moment it runs.
- **Declared correction inside the released 0.6.0 body.** That entry read "the five-part schema was
  pinned in three places"; the eval pins it in two — the `expected_output` line and the
  subagent-brief expectation. Corrected in place under the changelog contract's sanctioned form for
  released bodies: the heading is untouched, and the edit is named here and in the PR body.

## [0.6.1]

### Changed

- **`improve`: the glossary hand-offs name the Skill tool (#3002).** Both
  `/domain-driven-design:curate-language` invocations — the interview-loop table row and the
  deepening action's "new concept or sharpened term" step — now say "via the Skill tool". Wording
  only; presence gates and fallbacks unchanged. Follows the invocation-mode rubric's cross-skill
  phrasing rule, now unconditional after the fleet sweep.

## [0.6.0]

### Added

- **`improve` Design-It-Twice: a sixth return part, a read of the spread, and a graft record.**
  Three additions to the deepening interview's Design-It-Twice mode, absorbed from an upstream
  skill this marketplace decided not to ship (`docs/upstream/cursor-pstack.md`, the `arena` row).
  (1) Each subagent's structured result gains **rejected shapes** — the alternatives that design
  considered and turned down, each with its `rejected-reason`, deliberately reusing the field name
  the durable candidate artifact already carries so one vocabulary covers both. Without it a
  design's structure reads as principled and accidental alike, and a reader grafting from it cannot
  tell which. The part is fenced: it never travels into a fresh-eyes dispatch, because the
  delegation contract hands a reviewer the artifact and not the story, and importing the author's
  reasoning re-imports the bias the fresh context exists to remove. It is safe in this flow only
  because the step-3 comparison is done by the parent, which already holds that reasoning; the
  fence names adding an independent judge as the trigger to stop it at the parent.
  (2) **Read what the spread itself tells you** — a new step-3 section splitting three readings of
  the fan-out's disagreement. Convergence *despite* orthogonal constraints is a stronger consensus
  signal than agreement between same-brief candidates, precisely because this fan-out was built to
  prevent it. Shape-divergence is the designed null result and never a reason to re-frame — the
  orthogonality is deliberate, so a rule that fired on it would fire on every healthy run.
  Assumption-divergence about callers, invariants, or ordering is the real signal: those designs
  answered different questions, which means step 1's framing left those facts open, and choosing
  between the returns would be picking a question rather than a design.
  (3) A proposed hybrid now carries a **graft record** — what was taken from which design, and what
  was considered and left behind with its reason — which travels into `agreed-shape` when the shape
  is grilled. The durable candidate schema in `actions/deepening.md` gains a matching
  `graft-record:` field; without it the ledger would live only in conversation prose and evaporate.
  Evals updated: the five-part schema was pinned in two places.

## [0.5.4]

### Changed

- **`improve`: cross-dimension improvement asks now route to `/improvement:find` in the listing
  description.** The new `improvement` plugin's finder claims the general "what should we improve" /
  "find improvements" / "highest-impact improvement" asks, and one-sided boundaries cannot resolve an
  auto-invocation race — both descriptions must route. The Skip-when clause now hands a
  cross-dimension or evidence-driven ask to `/improvement:find` and names this skill as the
  single-lens architecture-depth pass, mirroring `improvement:find`'s own Skip-when, which hands
  single-lens architecture deepening here. Every base trigger phrase is preserved verbatim
  ('what should we improve' moved into the routing clause, still quoted); guarded by the
  skill-quality trigger-continuity check. Description-only — no body or behavior change.

## [0.5.3]

### Changed

- **The binding's Guards section now defers on invalid roots as well as stating the guard.** It said
  the self-ignore guard "applies on first write (verify-or-create `.gitignore`)" and named none of
  the roots at which the contract says the guard does **not** run — so a reader landed on text
  reading as unconditional, including for the no-project-root default where this plugin's memory
  writes go. The section now states that such roots exist and points at the convention's "Runtime
  guards" for them, **enumerating none**: a second copy of the list is how one rule ends up stated
  several ways.

## [0.5.2]

### Fixed

- **The `improve` Gotcha now states why `${CLAUDE_PLUGIN_DATA}` is wrong for per-project artifacts
  beyond substitution mechanics** (#2207).

## [0.5.1]

### Fixed

- **The `improve` Gotcha no longer asserts `${CLAUDE_PLUGIN_DATA}` cannot substitute in skill content
  (#2207).** The plugins reference puts skill and agent content in the "anywhere the placeholder
  appears" row (<https://code.claude.com/docs/en/plugins-reference>, Environment variables, fetched
  2026-08-12). The operative rule is unchanged — never store the durable candidate artifact there;
  even resolved it is plugin-global and collides per-codebase candidates across projects. The 0.3.6
  changelog entry's wording is preserved per
  [upstream-drift](../../docs/conventions/upstream-drift/README.md).

## [0.5.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.4.4]

### Added

- **`improve`: YAGNI scoping filter opens the deepening scan.** Phase 1 now decides *where* to
  look before looking: a user-named direction scopes the scan outright; otherwise the recent
  commit history's hot spots pull attention first (the pre-computed context now ships 20 recent
  commits instead of 10), widening the net only when changes are scattered. The chosen scope
  feeds each scan subagent's assigned area, which previously had nothing choosing it.
  (Mechanism from upstream mattpocock/skills `improve-codebase-architecture` v1.2; registry:
  the marketplace repository's `docs/upstream/mattpocock-skills.md`.)

## [0.4.3]

### Changed

- **`improve`: listing description tightened (1,057 → 900 chars)** — trimmed the explanatory
  prose from the frontmatter `description` toward the shared skill-listing budget
  (claude-code-plugins#2022, option 2). Every single-quoted trigger phrase is preserved verbatim
  (skill-quality check 3); the scan-present-pick process and lens model are unchanged in the body.

## [0.4.2]

### Changed

- The deepening HTML report resolves its output location through the
  topic-docs **ephemeral tier** rather than an unqualified "OS temp
  directory": one file per run through the platform's temp API, resolved
  deterministically and never branched on an injected scratchpad path or
  `CLAUDE_JOB_DIR`. The executable Phase 2 step in `actions/deepening.md`
  carries the rule, not only the format reference — that step is what
  `/architecture:improve deepening` actually follows. Its `mktemp` form is
  now a positional absolute template naming a run **directory**
  (`mktemp -d "${TMPDIR:-/tmp}/deepening-review-XXXXXX"`, with `report.html`
  written inside), replacing the `--tmpdir` / `-t` examples: `--tmpdir` is
  GNU-only, `-t` is deprecated there, and a bare relative template creates
  the report in the current working directory — the consumer's repository.
  The directory form is required rather than cosmetic: BSD `mktemp` on
  macOS substitutes only **trailing** `XXXXXX`, so the file template that
  appended `.html` after the placeholders could not create the report on
  macOS at all. A directory keeps the placeholders trailing while still
  giving the report a meaningful filename. See
  `docs/conventions/topic-docs/README.md` §"The ephemeral tier".

## [0.4.1]

### Added

- Deepening lens: ADRs now get the same discovery discipline as the domain
  glossary — honor a project-declared decisions location, else walk a short
  ladder of common homes (`docs/adr/`, `docs/decisions/`, `.adr/`, …) from the
  examined directory up to the repo root, instead of one shallow glob that
  missed most layouts (F6).
- Phase 3 interview loop: validate an exemplar call site by reading it before
  locking the deepened shape around it — an exemplar chosen from memory can turn
  out not to fit; search for one that does rather than shaping the interface
  around the wrong site (audit appendix).
- `improve` skill: a `## Gotchas` surface recording the observed failure history
  — the `${CLAUDE_PLUGIN_DATA}` artifact-path trap (F1) and the unverified
  scan-claim shipping risk that Phase 1.5 now guards (F2) (F5).

Declined (F5, with evidence): the audit's markdownlint failures (MD041/MD013/
MD060) do not reproduce under this repo's `.markdownlint-cli2.jsonc` — all three
are disabled there, and `markdownlint-cli2` over the skill reports 0 issues.
Docs-only + discovery guidance; no behavior change to the scan/verify/report
pipeline. Follow-up to the SW2030 consumer audit of 0.3.5 (#1158).

## [0.4.0]

### Added

- Deepening lens: canonical scan-subagent briefing template
  (`research/deepening/scan-briefing.md`) — vocabulary primer, friction checklist,
  dependency categories, both badge-acceptance heuristics, and a per-candidate
  return schema (incl. `shallow-signal` and `runtime-claim` fields). Phase 1 now
  briefs every scan agent from it, so scan quality no longer varies run-to-run and
  confidence is calibrated against the acceptance heuristics at scan time rather
  than arriving only at report time (F3, F4).
- Deepening lens: a verification gate (Phase 1.5) between the scan and the HTML
  report. Every `Strong`-badge candidate has its `shallow-signal` reproduced, and
  every runtime-bug / dead-code claim is checked against the actual code, before it
  reaches the user-facing report — closing the gap where an overstated scan claim
  shipped with the report's authority (F2). Phase 2 opens with an explicit re-badge
  against the two acceptance heuristics plus the verification result. The durable
  candidate artifact gains a `shallow-signal` field so the verified evidence
  survives the handoff.

Pure-ADD extension: existing phase contracts and vocabulary discipline are
unchanged. Minor version bump — new capability, no behavior removed. Follow-up to
the SW2030 consumer audit of 0.3.5 (#1157).

## [0.3.6]

### Fixed

- Deepening lens: the durable candidate artifact's default location no longer uses
  `${CLAUDE_PLUGIN_DATA}` — that token does not substitute in skill markdown content
  (it is a path substitution for hook/monitor commands and MCP/LSP server configs
  only), so consumers following the default literally wrote to an unexpanded
  `${CLAUDE_PLUGIN_DATA}/…` directory; and even resolved it points at the
  plugin-global data dir, colliding per-codebase candidates across projects. The
  artifact now resolves through the marketplace topic-docs convention via a new
  `reference/topic-docs.md` binding: memory tier,
  `<memory_dir>/<topic-slug>/deepening-candidates-<timestamp>.md` (default
  `.work/<topic-slug>/`, self-ignored — scan output cannot leak into git
  history), honoring the consuming repo's `.claude/topic-docs.yaml` or declared
  working-docs convention first. Eval #1 and the README persistence note
  updated to match. (#1156; topic-docs routing per PR #1160 review)

## [0.3.5]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.4]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.3]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/domain-driven-design:curate-language`); behavior unchanged.

## [0.3.2]

### Changed

- Soft references to the moved vocabulary skill now invoke `/domain-driven-design:curate-language` (was `/planning:domain-modeling`). Version bumped so existing installs receive the retargeted references.

## [0.3.1]

### Changed

- Deepening now delegates resolved vocabulary to `/planning:domain-modeling` when that skill is
  available, while retaining a discovery-first consumer-owned fallback when it is unavailable.

## [0.3.0]

### Changed

- Renamed the plugin `improve-architecture` → `architecture` and its skill
  `improve-architecture` → `improve`; the invocation is now `/architecture:improve`. Existing
  installs migrate automatically through the marketplace renames map.

## [0.2.0]

### Added

- **Design-It-Twice exploration mode.** The deepening interview loop gains a named branch for
  exploring alternative interfaces on the selected candidate: frame the problem space (constraints,
  dependency categories, an illustrative sketch that is explicitly not a proposal) and show it to the
  user, fan out 3–4 parallel subagents each under a deliberately orthogonal design constraint
  (minimal interface, maximum flexibility, optimize the common caller, ports and adapters when
  cross-seam dependencies warrant), present the structured five-part designs sequentially, compare on
  interface depth/leverage, locality of change, and seam placement, and close with an opinionated
  recommendation — hybrid allowed. Grounded in Ousterhout's design-it-twice principle.
- **Two-adapter rule in candidate evaluation.** An abstraction or port earns its existence only with
  two real consumers/adapters; a candidate whose value hinges on a one-adapter abstraction is
  speculative indirection and is badged `Speculative` at best.
- **Deletion test as candidate acceptance heuristic.** A deepening candidate earns a strong badge
  only if a future maintainer, finding the module gone, would rebuild it substantially the same way —
  otherwise the module boundary is arbitrary and the candidate is weak.
- **Eval for the exploration mode.** A fourth eval asserts the branch frames before designing, fans
  out orthogonally-constrained subagents, compares on the three axes, and ends with a strong read
  rather than a menu.

## [0.1.3]

### Fixed

- **Model invocation re-enabled.** `disable-model-invocation` in the `improve-architecture` skill's
  frontmatter is flipped back to `false`. The migration flipped it to `true`, silently disabling the
  automatic triggering the skill's description advertises ("Use when: 'improve architecture', 'find
  deepening opportunities', …") — the pre-migration original set `false`, and no rationale for the flip
  exists anywhere. With this fix the skill again triggers automatically when a request matches its
  description, in addition to explicit `/improve-architecture` invocation.
