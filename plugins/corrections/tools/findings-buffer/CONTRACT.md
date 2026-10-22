# Findings buffer contract

A findings buffer is an append-only pool of observations that unattended scanners write and nobody
fixes on sight. A person reads the grouped view of the pool later. The buffer stores rows and
returns them; it does not interpret them.

The seam follows the shape of the tracker seam
(`plugins/work-items/tools/work-item-tracker/CONTRACT.md`): two verbs per adapter, a
`capabilities.json` handshake, and the same exit codes.

## Contents

- [Rows](#rows)
- [Verbs](#verbs)
- [Exit codes](#exit-codes)
- [Capabilities manifest](#capabilities-manifest)
- [Privacy](#privacy)
- [Adapters](#adapters)
- [Conformance](#conformance)

## Rows

A row is one JSON object on one line (JSONL). Every row carries:

| Field | Meaning |
|---|---|
| `obs_id` | Stable identifier of the observation. The reader dedupes by it. |
| `ts` | UTC ISO-8601 timestamp of the observation, e.g. `2026-10-21T09:30:00Z`. |

Everything else in a row is the scanner's. The core (a later slice) does redaction, `obs_id`
assignment, caps and dedupe before a row reaches an adapter. Adapters only store and return rows.

## Verbs

Each adapter directory holds one script per verb.

### `append.sh < rows.jsonl`

Reads rows from stdin, one per line, and stores each.

- Exits `0` only when every row is durable. On any other exit, assume none, some or all of the rows
  were stored.
- Safe under concurrent calls: rows from different calls never interleave within a line and no row
  is lost.
- A retry may duplicate a row. The reader dedupes by `obs_id`; an adapter does not have to.
- Takes no arguments; any argument is a usage error (exit `2`). A line that is not a single JSON
  object with string `obs_id` and `ts` is a usage error and nothing from that call is stored. Blank
  lines are skipped.

### `read.sh [--since <UTC ISO-8601>]`

Writes stored rows to stdout as JSONL.

- Without `--since`, writes every stored row.
- With `--since`, writes at least every row whose top-level `ts` is `>= since`. It may write older rows too;
  the caller filters by `ts` when it needs an exact cut.
- Never truncates silently. A reader that cannot return every matching row exits non-zero.
- `--since` takes a UTC ISO-8601 value (`YYYY-MM-DDTHH:MM:SS` with optional fraction, then `Z`).
  Anything else, and any other argument, is a usage error (exit `2`).
- Rows come back as stored, so a row appended twice comes back twice.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | ok |
| `1` | internal or storage failure |
| `2` | usage (bad arguments, malformed row) |
| `3` | configuration or credential missing |

## Capabilities manifest

Each adapter directory holds `capabilities.json`:

```json
{"schema_version":"1.0","adapter":"<name>"}
```

`schema_version` is `MAJOR.MINOR`, handshaken as the tracker seam does: a consumer refuses an
adapter whose MAJOR differs from its own, and tolerates a higher MINOR. A missing or unparsable
`schema_version` is refused with exit `3`.

## Privacy

Rows derived from session transcripts never leave the machine. An adapter that stores rows off the
machine (a hosted sink) must not receive them; only the `local-file` adapter may hold such rows.
The core enforces this by routing; an off-machine adapter is not handed transcript-derived rows.

## Adapters

| Adapter | Storage |
|---|---|
| `local-file` | `.work/buffer/findings.jsonl` under the repository root, created on first append. Appends take an exclusive lock, so concurrent calls never interleave or lose a row: `flock` on `.work/buffer/.lock`, or where `flock` is absent (macOS) a `.work/buffer/.lockdir` directory holding the holder's pid. The holder removes that directory on exit, and on HUP, INT or TERM, while its pid file still holds the holder's pid. There is no automatic takeover: on a host without `flock`, an appender killed with SIGKILL (or a power loss) leaves the directory behind, and every later append exits `1` naming it (at once when its pid is no longer running) until an operator removes it. Needs `jq`. Exits `3` outside a git repository or without `jq`. |

Adapter selection through `findings-buffer.yaml` belongs to the core slice, not to this contract.

## Conformance

`conformance.sh <adapter-dir>` runs an adapter in a temporary git repository and exits `0` when it
passes, `1` when a check fails, `2` on a usage error, `3` when `jq` is missing. It checks:

- `capabilities.json` parses as JSON (with `jq`), with `schema_version` `1.0` and an adapter name.
- 8 concurrent `append.sh` calls with distinct rows are all durable, and `read.sh` returns every row
  once per append.
- `read.sh --since` returns every row with `ts >= since`.
- A malformed argument to either verb exits `2`.

`conformance.test.sh` runs the script against `local-file` and against deliberately broken
adapters.
