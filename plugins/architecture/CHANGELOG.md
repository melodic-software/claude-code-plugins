# Changelog

All notable changes to the `architecture` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
