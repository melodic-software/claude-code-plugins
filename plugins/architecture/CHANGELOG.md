# Changelog

All notable changes to the `architecture` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
