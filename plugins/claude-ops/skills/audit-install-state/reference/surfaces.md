# What lives in a Claude Code installation directory, and who owns it

Basis for every row: <https://code.claude.com/docs/en/claude-directory> — read through the raw
markdown endpoint (`.../claude-directory.md`), not a summarizing fetch. Verified 2026-08-26.

The distinction this file exists to make: **a path Claude Code already manages is not a cleanup
candidate, however old its contents look.** Hand-pruning a swept path fights the product's own
retention sweep and produces churn, not space.

## The retention sweep

`cleanupPeriodDays` governs it. Default 30 days, minimum 1; `0` fails with a validation error. Files
under the swept paths below are deleted at startup once older than that window.

Three facts about it that change how a finding should be read:

- **An unparsable settings file pauses the sweep.** Upstream: Claude Code pauses retention cleanup
  and warns in `/status` until the file is fixed — unless managed settings supply
  `cleanupPeriodDays`, in which case the sweep runs at the managed value. A JSON syntax error is
  therefore a retention outage, not only a config error. The engine reports it as `error`.
- **Managed settings can supply the value**, at a machine-scope path that varies by OS
  (`/Library/Application Support/ClaudeCode/`, `/etc/claude-code/`, `%ProgramFiles%\ClaudeCode\`).
- **`.last-cleanup` is the sweep's own watermark.** It advancing is direct evidence the sweep ran.
  A watermark that advances *during* an audit also tells you the tree is not quiesced.

## Cleaned up automatically (age-swept)

| Path under `~/.claude/` | Contents |
|---|---|
| `projects/<project>/<session>.jsonl` | Full conversation transcript |
| `projects/<project>/<session>/subagents/` | Subagent transcripts, removed with the parent |
| `projects/<project>/<session>/tool-results/` | Large tool outputs spilled to separate files |
| `file-history/<session>/` | Pre-edit snapshots for checkpoint restore |
| `plans/` | Plan files written during plan mode |
| `debug/` | Per-session debug logs (`--debug` / `/debug` only) |
| `paste-cache/` | Large pastes |
| `image-cache/` | Attached images. **Different sweep rule:** on each sweep the directories of all *other* sessions are removed whatever their age — so an old `image-cache/<session>/` disappearing immediately is expected, never an `age-exceeds-window` signal |
| `uploads/<session>/` | Remote Control / web attachments |
| `feedback/drafts/` | Feedback drafts — swept after `cleanupPeriodDays` **or** 30 days, whichever is shorter |
| `usage-data/` | `/insights` reports and cached analysis data |
| `session-env/` | Per-session environment metadata |
| `tasks/` | Per-session task lists |
| `shell-snapshots/` | Shell state captured at startup; removed on clean exit |
| `backups/` | Timestamped copies of `~/.claude.json` before config migrations |
| `feedback-bundles/` | Redacted transcript archives written by `/feedback` |
| `todos/`, `statsig/`, `logs/` | Legacy; no longer written. Contents then the directory are removed |

### The unit of retention is not always the file

This is the row most likely to generate a wrong finding, so it gets its own heading.

`older_than_retention` counts files whose **mtime** exceeds the window. That count is a measurement.
The step from it to "the sweep is failing" is an inference, and for several of these paths it is a
wrong one:

- **`file-history/`** retains the **100 most recent checkpoints**. Snapshots no retained checkpoint
  references are deleted — *except each file's first snapshot, which is kept regardless of age.*
  Old mtimes here are the documented behaviour.
- **`projects/<session>/subagents/` and `tool-results/`** are removed *with their parent transcript*.
  A contained file's own mtime is not the unit.
- **`session-env/`, `tasks/`, `debug/`** are per-session. The session directory ages out, not each
  file independently.

For every other swept path the granularity is simply not documented per-file. The engine therefore
emits `age-exceeds-window` with `evidence: inferred` and the sweep unit inline, never a verdict that
reads as a deletion authorisation.

Absence is evidence too: `todos/`, `statsig/`, `logs/`, `image-cache/` and `feedback-bundles/` not
existing is positive proof the sweep completed, including its remove-the-empty-directory step.

## Kept until you delete them

Not covered by automatic cleanup; persist indefinitely.

| Path | Contents |
|---|---|
| `history.jsonl` | Every prompt typed, with timestamp and project path |
| `stats-cache.json` | Aggregated token and cost counts shown by `/usage` |
| `remote-settings.json` | Cached server-managed settings for your organization |
| `cache/changelog.md` | Cached Claude Code changelog |
| `policy-limits.json` | Cached feature policy settings |

Upstream adds: "Other small cache and lock files appear depending on which features you use and are
safe to delete." That sentence is not a licence to delete anything a table does not name — see
"unclassified" below.

## Session-scoped, explicitly not age-swept

`sessions/` holds one small file per running session, used to detect concurrent sessions and
crashes. Claude Code removes each file when its session exits and clears crash leftovers on the next
launch. **Hand-deleting these confuses concurrent-session detection.**

They also churn during an audit. A file present in one listing and gone in the next is the
documented behaviour, not a discrepancy — and it means any orphan count keyed on sessions carries a
margin of error, because a session whose record vanished mid-run is *unknown*, not *dead*.

## Never delete

Upstream is explicit: don't delete `~/.claude.json`, `~/.claude/settings.json`, or
`~/.claude/plugins/` — those hold auth, preferences, and installed plugins.

## Home-root state, outside the swept tree

`~/.claude.json` lives in the home directory, **not** under `~/.claude`, and is not touched by the
retention sweep at any value of `cleanupPeriodDays`. Its growth has one supported remedy:
`claude project purge <path>`, which deletes that project's transcripts and auto memory, its
per-session `tasks/`/`debug/`/`file-history/` entries, its matching `history.jsonl` lines, and its
entry in `~/.claude.json`. It prints the full plan and asks for confirmation; `--dry-run` previews.

`.claude.json.tmp.<n>.<hash>` siblings are failed atomic-write remnants. The leading number *looks*
like a PID; that has not been verified, so the engine attempts no liveness lookup on it.

## Unclassified: everything the tables do not name

The largest population in a real install is state deposited by **plugins**, including sibling
plugins from the same marketplace. The engine inventories these by name, size, and mtime and stops
there:

- it never parses their contents — a plugin owns its own state;
- it never attributes an owner from a directory name;
- it never infers that "not product-managed" means "disposable."

`unclassified-report-only` is a statement about the *evidence*, not about the file. There is no
upstream row, so no retention claim can be made in either direction.

## Secret-bearing paths — never opened

`.credentials.json`, `daemon/control.key`, `daemon/pipe.key`, `ide/*.lock` (the body carries an
`authToken`), and the values inside `~/.claude.json` (MCP server configs can carry tokens). These
appear in the inventory as name/size/mtime line-items only. The rule is enforced in the reader, not
at each call site, so a future check cannot reach one by forgetting to consult the list.
