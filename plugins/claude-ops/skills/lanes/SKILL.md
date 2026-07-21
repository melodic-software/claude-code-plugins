---
name: lanes
description: "Start, restart, stop, and check loop lanes as named background Claude Code sessions seeded from canonical prompt files — the scripted replacement for the manual morning refresh (cancel loop, clear, re-paste the canonical prompt) across N lanes on a machine. `start`/`restart` first pull the repo and refresh the plugin marketplace, then launch each configured lane with its per-lane model/effort. Use when: 'launch my lanes', 'restart the loop lanes', 'start the work lanes', 'morning lane refresh', 'stop a lane', 'which lanes are running', 'lane status'. Mutating and operator-initiated; never touches a session whose name is not a configured lane."
argument-hint: "[start|restart|status|stop] [lane...] — start (default); restart/stop accept lane names; --config, --repo, --dry-run, --no-pull, --no-update"
user-invocable: true
disable-model-invocation: true
---

## Pre-computed context

claude CLI: !`command -v claude >/dev/null 2>&1 && echo "present ($(claude --version 2>/dev/null))" || echo "MISSING (required)"`
jq: !`command -v jq >/dev/null 2>&1 && echo "present" || echo "MISSING (required)"`
Repo root: !`git rev-parse --show-toplevel 2>/dev/null || echo "unknown (pass --repo)"`
Lane config: !`c="${CLAUDE_OPS_LANES_CONFIG:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.work/lanes.json}"; [[ -f "$c" ]] && echo "$c ($(jq -r '(.lanes//[])|length' "$c" 2>/dev/null) lanes)" || echo "absent ($c) — author one (see context/config.md)"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Running N loop lanes on a machine means a daily ritual: for each lane, cancel its
loop, clear, and re-paste its canonical prompt. This skill collapses that to one
command. `start`/`restart` pull the repo and refresh the plugin marketplace once,
then launch each configured lane as a **named background session** seeded from the
lane's canonical prompt file, mirroring that lane's model/effort onto the launch.
`status`/`stop` read and manage those sessions through the CLI's own
background-session surface.

**Owns only its own lanes.** `stop`/`restart` act on a session **only** when its
name is a lane in the resolved config — a hand-started session (e.g. an interactive
`work` window, or an unrelated `PR Babysit`) is never stopped by this skill.

## Run it

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/lanes/scripts/lane-launcher.sh" $ARGUMENTS
```

Print the script's output verbatim — it is the deliverable. Preview any mutating
run first with `--dry-run` (prints the exact `claude`/`git` commands, seeds
nothing, kills nothing).

## Action Router

Parse `$ARGUMENTS` for the action (first token); remaining tokens are lane names
(targets for `restart`/`stop`; an unknown name is rejected).

| Action | Mutates | Description |
|---|---|---|
| `start` (default) | Yes | Pull + marketplace update, then launch every configured lane **not already running** |
| `restart [lane...]` | Yes | Pull + marketplace update, then stop-and-relaunch each target lane (all, or named) |
| `status` | No | Per-lane table: model, effort, running/stopped, and the live sessionId |
| `stop [lane...]` | Yes | Stop each running target lane (all, or named) via `claude stop <sessionId>` |

Options: `--config FILE`, `--repo DIR`, `--no-pull`, `--no-update`, `--dry-run`,
`--agents-json FILE` (read the session list from a file instead of the live CLI —
offline/scripted reuse). Exit codes: `0` ok · `3` bad argument/config · `4`
prerequisite missing or repo/config unresolved.

## Lane config

Lanes are defined in a JSON config, resolved first-hit-wins:
`--config FILE` → `$CLAUDE_OPS_LANES_CONFIG` → `<repo>/.work/lanes.json`. Each lane
carries a `name`, a `prompt` file path, and optional `model`/`effort`. The full
schema, resolution rules, and the prompt-storage seam live in
[context/config.md](context/config.md) — read it before authoring a config.

**Prompt storage is provisional (composes with #480).** Today prompt files live in
a session-local `.work` dir (`prompt_dir`, default `.work`). Issue #480 (loop-prompt
authoring skill) is slated to own durable prompt storage. When it lands, repoint
`prompt_dir` at that home; the launcher resolves the prompt dir in exactly one place
(`resolve_prompt_dir` in the script), which is the single seam to update.

## Mid-session staleness & restart cadence

A **running** lane keeps the skill versions it loaded at launch: a fix merged to a
plugin the lane runs does **not** reach that lane mid-session. This is not a missing
feature to build around — it is verified Claude Code behavior (a live session keeps
its launch-time plugin versions, `/loop` never re-reads a skill's body on later
cycles, and a loop can't self-trigger `/reload-plugins`). Restart is the honest
refresh mechanism — the same `restart` that clears context bloat (#496). Detect an
unconsumed self-fix with a read-only git probe against the repo's default branch,
then restart that lane at its next cycle boundary. Full reasoning, the probe, and the cadence
live in [context/refresh.md](context/refresh.md) — read it before answering "why is
my merged fix not live in the lane?" or setting a restart frequency.

## Verified CLI surface

The launcher shells out only to primitives confirmed on this machine's `claude`
(`--help` / real invocation): `claude --bg -n <name> [--model M] [--effort E]
"<prompt>"` (launch a named background session, return immediately),
`claude agents --json` (list active sessions: pid, cwd, kind, startedAt,
sessionId, name, status),
`claude stop <sessionId>` (stop one session; conversation kept, resumable with
`claude attach`), and `claude plugin marketplace update`. There is no
`claude agents stop` verb — stop resolves the sessionId from `agents --json` and
only for a configured lane name.

## Gotchas

- **No durable prompt home yet.** `.work` is session-local; a fresh machine/session
  has no prompts until they are authored there (or `prompt_dir` is pointed at a
  committed dir). This is the #480 dependency, not a bug.
- **Name is the identity.** Lanes are matched by session `name` **and** `kind:
  background` — every lane is launched with `--bg`, so an interactive window sharing
  a lane name is never matched or stopped. Two lanes must not share a name; a
  hand-started *background* session sharing a lane name would still be treated as
  that lane, so keep lane names distinct from ad-hoc background session names.
- **`start` is idempotent-ish, `restart` is not.** `start` skips a lane already
  running; `restart` always stops-and-relaunches (discarding the running lane's
  in-flight conversation). Use `start` for "bring up whatever is down".
- **A missing/empty prompt file skips that lane** (with an error) rather than
  launching an empty session. `status` flags `[prompt MISSING]`.

## Per-cycle deterministic scripts (#538)

Two lane-cycle mechanics need no reasoning, so they are scripted here and a lane
prompt references the script instead of re-deriving the work every cycle. Both
follow `lane-launcher.sh`'s conventions (jq CRLF wrapper, the `--help` header as
the full contract, explicit exit codes). The header is the source of truth for
each — the summary below is a pointer, not a copy.

- **`scripts/machine-behavior.sh`** — emits the lane's MACHINE-BEHAVIOR block (gh
  identity, clone path, worktree inventory, installed plugin versions) as a
  verbatim-printable text block. Pure environment inspection: it emits only
  mechanically unambiguous facts and deliberately does NOT compute "deviations
  from standing rules" — that stays a model judgment made by reading these facts
  against the prose rules. Plugin versions are the INSTALLED runtime versions,
  which per [context/refresh.md](context/refresh.md) can lag repo HEAD mid-session
  (the honest number for a running lane). `--plugin <id>` (repeatable) scopes the
  block to the plugins a lane runs.

- **`scripts/telemetry-upsert.sh`** — maintains exactly ONE marker-identified
  telemetry comment on a tracking issue, editing it in place instead of posting a
  second (the interim home of the #502 telemetry contract). Given `--issue N
  --marker STR --body-file PATH`, it writes a machine-detectable sentinel `<!--
  claude-ops:lane-telemetry marker=STR -->` as the comment's first line, finds
  that sentinel across ALL comments (paginated — a match on any page prevents a
  duplicate) and PATCHes it; failing that (first migration off a hand-authored
  comment) it adopts the most recent comment BY THE AUTHENTICATED USER carrying the
  raw marker text; else it creates one. `STR` is `[A-Za-z0-9:._-]+` (so it can
  never close the HTML comment early), and one writer identity owns a given marker.

## Cross-references

- [context/refresh.md](context/refresh.md) — why a running lane can't hot-reload a
  merged fix to its own skills, the git staleness probe, and the restart cadence
  (#514).
- `/claude-ops:plugins` — the authoritative, richer plugin-fleet sync (scope
  divergence, new-catalog installs). This skill's marketplace refresh is the light
  `claude plugin marketplace update` step of a launch, not a substitute.
- `/claude-ops:morning-brief` — reads the loop-lane **telemetry** (per-lane
  last-cycle freshness). This skill starts/stops the lanes that emit it.
- #480 (loop-prompt authoring skill) — forward dependency that will own durable
  prompt storage. #496 (context economy / restart discipline) — why lanes get
  restarted. #502 (telemetry) — the per-lane telemetry the running lanes feed.
