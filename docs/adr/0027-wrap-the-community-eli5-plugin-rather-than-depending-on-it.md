# Wrap the community `eli5` plugin rather than depending on it or reimplementing it

- Status: accepted
- Date: 2026-09-01

## Context

`anthropics/claude-plugins-community` ships an `eli5` plugin: a single skill whose whole body is one
sentence asking for a visual HTML explainer. This marketplace had no equivalent lane. `education:explain`
drops altitude in prose and had carried the ELI5 branding, but a picture is a different medium, not a
lower rung.

Adding the lane meant choosing how to relate to that upstream plugin. Three options were live, and the
official mechanism was not the obvious winner.

## Decision

`education:eli5` **wraps** the upstream skill: it delegates to `eli5@claude-community` through the Skill
tool when that plugin is installed, prints (never runs) the install commands when it is not, and performs
the behavior itself in either case. It declares **no `dependencies[]` entry** on the upstream plugin.

## Alternatives considered

- **Hard cross-marketplace dependency** (`dependencies: [{name: eli5, marketplace: claude-community}]`).
  This is the only inter-plugin mechanism the official docs define, which made it the default candidate.
  Declined on blast radius: a dependency is installed for every consumer of the whole plugin, so everyone
  who wants `teach` or `quiz-me` would acquire a second marketplace's plugin, and an unresolved dependency
  **disables the dependent plugin** rather than degrading. The gate that admits such a dependency
  (`allowCrossMarketplaceDependenciesOn`) is set by the root marketplace's maintainer, so a downstream
  republisher can still opt into it; `plugins/education/README.md` documents that path.
- **Reimplement the pattern natively.** Rejected as duplication of a capability that already ships and is
  maintained upstream, and as a fork that would silently drift.
- **Vendor the upstream files.** Rejected: the upstream skill is one sentence, so there is nothing worth
  copying, and copying would import an attribution obligation for no benefit.

## Consequences

- Interception is **best-effort, not guaranteed**, and the skill says so rather than claiming otherwise.
  The wrapper declares no frontmatter `name`, so bare `/eli5` reaches the upstream skill directly when
  that plugin is installed; only `/education:eli5` is guaranteed to reach the wrapper. No documented
  arbitration rule exists for two model-invocable skills whose descriptions both match.
- The wrapper adds nothing on routings that reach upstream directly. This is irreducible and accepted.
- The upstream plugin is a moving target. The skill carries a dated verification stamp
  (upstream commit `863e70d`, v1.0.0) and a commit-anchored recheck trigger, because a rename of its skill
  or plugin id breaks the delegation address silently: the fallback simply always fires.
- If upstream `eli5` ever ships as an official or bundled surface, this decision's premise changes from
  "wrap a community plugin" to "duplicate something native". The skill records that as a trigger to re-run
  `/claude-ops:audit-native-overlap` and re-decide the lane. Nothing watches for it automatically.
