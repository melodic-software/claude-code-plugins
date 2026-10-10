---
bump: minor
---

### Changed

- **`/multi-agent:route` says how to apply a role to an Agent tool dispatch.** Since Claude Code 2.1.292 the Agent tool takes an `effort` on each call, so the role map's effort now reaches subagents spawned without a named type, not only workflow `agent()` calls. The skill tells the caller to pass the variant's model (or omit it on `inherit`) and its effort on the call, and links the upstream sections that decide which source wins.

### Fixed

- **The routing skill no longer says a named agent always runs at its own pinned model and effort.** A dispatcher can pass `model` or `effort` on the call, so keeping a named agent off a frontier model is the dispatcher's rule. The route gotcha, the setup skill, and the README now say so.

### Added

- **The drift-audit fetch and judging agents start without CLAUDE.md files.** `docs-fetcher` and `drift-checker` set `omitClaudeMd: true`, so a stage that reads untrusted pages opts out of the CLAUDE.md instruction hierarchy. The README records where the field is documented.
