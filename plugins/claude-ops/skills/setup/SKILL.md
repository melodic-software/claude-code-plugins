---
name: setup
description: "Configure the claude-ops plugin for this repository: decide where the claude-troubleshooting issue registry lives — the default per-machine plugin data directory, or an in-repo git-tracked location that is team-shared — and persist the registry_dir userConfig option. Use when: 'set up claude-ops', 'configure claude-ops', 'claude-ops setup', 'where does the troubleshooting registry live', 'keep the registry in my repo', or a claude-ops skill reports missing or thin config. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
---

## Purpose

Settle the `registry_dir` seam — where `/claude-ops:claude-troubleshooting` keeps its issue registry
(`registry.json`) — and persist the decision so the skill resolves it deterministically instead of the
consumer having to remember which mode they are in. `registry_dir` is a typed string `userConfig` option
(seam 1 of the extensibility contract): its value lives in
`pluginConfigs["claude-ops@melodic-software"].options.registry_dir` and substitutes into skill content as
`${user_config.registry_dir}`.

The seam is a **binary choice**, not a path guess. Leaving `registry_dir` unset is a legitimate — arguably
default — state: the registry falls back to the plugin's per-machine data directory
(`${CLAUDE_PLUGIN_DATA}`, which survives plugin updates). Setting `registry_dir` to a project-relative
directory opts into keeping the registry inside the repo, git-tracked and team-shared, so every contributor
sees the same tracked-issue state. This skill presents that choice and only then asks for a path.

Idempotent: re-running reads the current value and offers an update rather than overwriting blind.

## Task

Apply the convention-resolution ladder — config present → use it; absent → present the binary and persist
the consumer's choice; else the safe default is to leave it unset (per-machine fallback). No baked repo
assumptions.

1. **Read the current value first, in precedence order.** Look for `registry_dir` under
   `pluginConfigs["claude-ops@melodic-software"].options` in all three scopes and resolve the *effective*
   value the way Claude Code does — **Local (`.claude/settings.local.json`) > Project
   (`.claude/settings.json`) > User (`~/.claude/settings.json`)**, local winning. Report the effective
   value (or "unset → per-machine `${CLAUDE_PLUGIN_DATA}`") and which scope supplies it; the interview
   proposes a change against that baseline. If a local override is present, say so explicitly — step 3
   writes the *project* (team) value, which stays shadowed by the local override until the developer
   updates or removes it, so a project-scope edit alone will not change what the plugin uses on that
   machine. Read each scope **narrowly** — query only the single
   `pluginConfigs["claude-ops@melodic-software"].options.registry_dir` key (e.g. with `jq`), never loading
   `.claude/settings.local.json` wholesale: that overlay is secret-bearing (API tokens, env secrets), so do
   not read or echo unrelated settings content.
2. **Interview — the binary, then a path only if needed.** Present two modes with a recommendation:
   - **Per-machine (unset)** — the registry lives in `${CLAUDE_PLUGIN_DATA}`, private to this workstation,
     nothing written into the repo. This is the default; recommend it unless the consumer wants the
     registry shared.
   - **In-repo (set `registry_dir`)** — the registry is git-tracked and team-shared. Only when the consumer
     chooses this, infer a sensible project-relative directory before asking: an existing tracked location
     for Claude operational state (a `.claude/`-rooted path the repo already uses, e.g.
     `.claude/troubleshooting`), else propose one and let the consumer accept or edit it. Keep it to the
     single `registry_dir` knob; do not invent further options (Rule of Three).
3. **Persist to project scope.** For the in-repo choice, write the chosen project-relative value to the
   project `.claude/settings.json` at `pluginConfigs["claude-ops@melodic-software"].options.registry_dir`
   so it is tracked and shared. Create the `pluginConfigs` / `options` path if absent; do not disturb
   unrelated keys. The value is stored verbatim (Claude Code does not normalize or validate a string
   option), so store it exactly as it should resolve relative to `${CLAUDE_PROJECT_DIR}`. For the
   per-machine choice, make the *effective* value resolve to the `${CLAUDE_PLUGIN_DATA}` fallback — the
   claude-troubleshooting skill treats an empty **or** unset `registry_dir` as "use the plugin data dir".
   Which action achieves that depends on **which scope currently supplies the effective value** (from step
   1's read), under the **Local > Project > User** precedence:
   - **No scope supplies a value** → already per-machine; confirm and make no change.
   - **User scope only** (Project and Local absent) → write an **empty string** (`""`) at project scope: a
     project value shadows the User global (Project > User), and the empty value reads as the plugin-data
     fallback — so this repo opts out without disturbing the developer's global default for every other
     repo. Reserve *removing* the User value for when they want to drop the default everywhere.
   - **Project scope supplies it** (no Local override) → remove the project-scope `registry_dir`; if a User
     value would then surface and must also be suppressed, write `""` at project scope instead.
   - **Local scope supplies it** (`.claude/settings.local.json`) → a project-scope write **cannot** override
     it, because Local outranks Project. The opt-out must happen in the local overlay itself: set its
     `registry_dir` to `""` or remove the key. This is the developer's own machine-local file — with their
     go-ahead, edit only the `registry_dir` key in `.claude/settings.local.json` (per the narrow,
     secret-safe handling in step 1); otherwise name the file and guide them to clear it there. Do not
     silently edit it.

   Do not write an empty string at a scope that is outranked by a scope still holding a value, and do not
   report the registry as per-machine until the *effective* value resolves to empty/unset.
4. **Offer the personal overlay.** A per-developer override goes in the local overlay
   `.claude/settings.local.json` (same `pluginConfigs` path); recommend the consumer keep
   `.claude/settings.local.json` gitignored if it is not already.

## Output

An updated project `.claude/settings.json` reflecting the chosen registry location (or a confirmation that
it is intentionally left per-machine), plus a one-line summary of the value written, its scope, and how to
re-run this setup to reconfigure. Note in the summary that `registry_dir` governs only the
claude-troubleshooting registry — observability data locations are controlled by their own env vars
(`CC_OTEL_STORE` and friends), not this option.

## What this skill does NOT do

- Run a troubleshooting scan, health check, or registry operation — that is
  `/claude-ops:claude-troubleshooting`.
- Configure the observability or changelog skills — the OTEL store location and retention are env-var
  driven (see the plugin README), not a `userConfig` seam.
- Write machine-local state — configuration lives in the consumer's tracked settings, never in the plugin
  directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for the registry and generated state
  only).
