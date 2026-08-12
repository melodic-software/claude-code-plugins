# Changelog

All notable changes to the `architecture` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.1]

### Fixed

- **`improve`: the `${CLAUDE_PLUGIN_DATA}` Gotcha stated a false mechanism; the rule it justified
  now rests on the true one.** The bullet asserted that the token "does not substitute in skill
  markdown content (it is a hook/monitor/MCP path substitution only)". It **does** substitute: the
  plugins reference's per-component table puts *skill and agent content* in the "anywhere the
  placeholder appears" row, alongside hook and monitor commands, with no version qualifier
  (<https://code.claude.com/docs/en/plugins-reference>, §Environment variables, re-fetched
  2026-08-12 UTC over the raw-markdown channel — `200`, `text/markdown`, 95,338 bytes / 1,314
  lines, first heading `# Plugins reference`, slug confirmed canonical against `llms.txt`, SHA-256
  `f6627de35a3f285d18cf22494843bb328d65e3b867fbc1856865caa47ea3ea64`). The routing decision the
  sentence defended is **unchanged and still correct**, on three legs the same page supplies and
  this release states in its place: the token resolves to `~/.claude/plugins/data/{id}/`, which has
  no project dimension and so collides candidates across codebases; uninstalling from the last
  remaining scope deletes that directory by default; and its named use is installed dependencies,
  generated code, and caches. The corrected sentence lands as a conforming upstream-drift record —
  basis, as-of date, and a recheck trigger — so a later reader can tell a fresh claim from a stale
  one, which is what let this one survive four releases. (Closes
  melodic-software/claude-code-plugins#2207. The same false sentence was authored into
  `plugin-quality` and corrected there in 0.4.0 via #1808; both plugins' histories now converge on
  one explanation.)

### Erratum — the 0.3.6 entry's stated reason, left as it shipped

- **The 0.3.6 "Fixed" entry below gives a false reason for a change that was itself correct, and is
  deliberately not edited.** It says the artifact path stopped using `${CLAUDE_PLUGIN_DATA}`
  because that token "does not substitute in skill markdown content" — the claim corrected above.
  The *path* change 0.3.6 made was right and stays right; only its stated mechanism was wrong. The
  0.4.1 entry's promotion of that rationale to a permanent Gotcha is left standing for the same
  reason: shipped history is never rewritten, so an erratum points forward rather than editing the
  record (`docs/conventions/upstream-drift/README.md` §Adopters). This note does **not** claim the
  0.3.6 symptom was imaginary. What a 0.3.5 consumer observed is not settled here and is out of
  scope: an unexpanded token reaching a consumer is fully consistent with the correction above,
  since reading a file returns its literal bytes whatever the loader substitutes at load time, and
  0.3.5 carried the token in a `Read`-loaded `actions/*.md` step rather than in a `SKILL.md` body.

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
