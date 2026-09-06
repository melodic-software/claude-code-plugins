# Hook Telemetry Contract — Changelog

Notable changes to the hook-telemetry envelope contract. The envelope is versioned by `schema_version`
(SemVer) and evolves independently of per-hook `data` schemas, which churn additively (README "Forward
compatibility"). Removal, rename, or type-change of a field is a major `schema_version` bump; a field is
marked deprecated here for one minor cycle before removal.

## 1.1 — 2026-09-05

Additive minor: four optional correlation keys on the envelope spine (#3758, closing the thread #930
opened).

- `session_id`, `prompt_id`, `tool_use_id`, `agent_id`: optional strings matching `[A-Za-z0-9._-]+`,
  each copied verbatim from the hook payload by `hook::emit_telemetry` when present and well-formed,
  omitted otherwise. Placed between `duration_ms` and `data`.
- Read from the payload ROOT only: a same-named key nested inside `tool_input` or `tool_response` is
  never taken, so tool-supplied arguments cannot put a value on the spine, at any payload size, and
  on a payload that is malformed or cut off mid-write as well as on a well-formed one. Above
  a 65536-byte payload the library selects by depth in a 16384-byte window at each END of the payload
  rather than over the whole of it, both read FORWARD from the payload's first byte, so all four keys
  of the documented payload are in reach up to a 294912-byte payload; the four things a window cannot
  reach are listed in the README's "Correlation keys", and every one of them omits rather than
  guesses (#3784). The first release of this contract read only the region ahead of the first nested
  container up there, which omitted `tool_use_id` and `agent_id` on every payload over 64 KiB.
- The library reads the payload from `HOOK_TELEMETRY_PAYLOAD`, else the producer's `INPUT` variable;
  no producer change is needed for a hook that buffers stdin the fleet way.
- The claude-ops reference sink routes on the spine `session_id` first and falls back to
  `data.session_id`, so envelopes from 1.0 producers keep their route.
- No field removed, renamed, or type-changed; a 1.0 consumer ignores the four keys under the
  tolerate-unknown rule.

## 1.0 — 2026-06-24

Initial published contract.

- Common envelope: `schema_version`, `timestamp`, `hook`, `hook_event`, `status`, `duration_ms`, `data`.
- `status`: documented value set `ok | error | skipped | blocked` — a documented open string, not a closed
  JSON-Schema enum (mirrors `hook_event`), so a future value never trips a schema-derived validator.
- First per-hook `data` schema: `markdown-format` (`tool`, `file`, `findings`).
- Sink path resolution: `HOOK_TELEMETRY_SINK` is a single executable path, absolute or relative to the
  consuming repo root (producer-resolved). Relative is the portable, tracked-wiring form. Not an envelope
  field, so no `schema_version` change.
