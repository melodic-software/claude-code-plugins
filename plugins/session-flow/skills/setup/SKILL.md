---
description: "Verify the session-flow observer's runtime prerequisites and configuration for this machine, and write the repository's docs/conventions/session-flow.yaml after confirmation. Use when: 'set up session-flow', 'configure the observer', 'is the observer working', 'set worker_continuation for this repo', the SessionStart observer isn't arming, or the observer hook reported a missing prerequisite. Actions: check (read-only, default), apply (writes docs/conventions/session-flow.yaml only). Installs nothing. Re-runnable."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Two configuration surfaces. The **detached observer** (see
[`${CLAUDE_PLUGIN_ROOT}/reference/observer.md`](${CLAUDE_PLUGIN_ROOT}/reference/observer.md)) has
runtime prerequisites (Node.js, Python 3.10+, `jq`) and native `userConfig` tunables; setup reports
both and writes neither (writing `pluginConfigs` is what the setup contract forbids). The plugin
also owns one tracked consumer file, `docs/conventions/session-flow.yaml`, the repository layer of
the keys skills read in their own text (keys, values and layers:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md); schema:
`${CLAUDE_PLUGIN_ROOT}/schemas/session-flow.schema.json`). `check` reports that file; `apply`
writes it and nothing else.

Action routing: no argument or `check` runs the check; `apply` runs the check, then writes.
Re-running either reads the current state again.

## `check` (read-only)

The hook and launcher are the single source of truth for what they require and how they degrade:
`${CLAUDE_PLUGIN_ROOT}/hooks/observer-arm.sh`, `${CLAUDE_PLUGIN_ROOT}/skills/running-retro/scripts/arm_observer.py`,
and `observer.py` beside it.

**Read it first.** Probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the observer is disabled (`observer_enabled` off AND no `arm` invocation in use), every
prerequisite absence downgrades from FAIL to INFO, the hook exits through its opt-in gate before
touching anything, so a deliberately disabled plugin is not broken. Report the probes informationally
and note that re-enabling restores the FAIL semantics.

1. **Node.js on PATH**, every hook row runs through `node ${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs`.
   Probe `node --version` through Bash. FAIL if absent: the hook does not launch, so the observer
   never arms. Remediation: install Node.js on PATH (<https://nodejs.org/en/download>).
2. **Python 3.10+**, the launcher and tailer are stdlib-only Python 3.10+. Probe the same interpreter
   detection the hook uses (`python3` then `python`, requiring `sys.version_info >= (3, 10)`). FAIL if
   none qualifies: without it the hook silently skips arming. Remediation: install Python 3.10+ on PATH.
3. **`jq`**, the SessionStart hook parses its stdin (`session_id`, `transcript_path`, `source`,
   `agent_type`) with `jq`. FAIL (auto-arm path only) if absent: the hook exits early and never arms.
   The manual `arm` action resolves inputs without `jq`, so absence is INFO for that path. Remediation:
   install `jq` (<https://jqlang.org/download/>).
4. **`claude` CLI on PATH**, the autonomous analysis leg invokes `claude -p`. INFO if absent: the
   observer still distills and retains observations under its plugin work dir; the analysis run is
   skipped and nothing is written to the ledger.
5. **Observer config**. Report the effective value of each native key (an unexpanded `${user_config.…}`
   token or empty means the default): `${user_config.observer_enabled}` (default off),
   `${user_config.observer_analysis_enabled}` (default on), `${user_config.observer_analysis_model}`
   (default `claude-haiku-4-5`), `${user_config.observer_analysis_bare}` (default off),
   `${user_config.observer_idle_seconds}` (default 900), `${user_config.observer_poll_seconds}`
   (default 5), `${user_config.observer_max_seconds}` (default
   86400). Call out two hazards: `observer_analysis_bare` on is a FAIL on an OAuth-login install (the
   analysis run reports "Not logged in"); `observer_idle_seconds` below the machine's longest expected
   single turn risks firing analysis on a partial transcript.
6. **Hook registration**. INFO: confirm the plugin is enabled for this project (`/plugin` → Installed)
   rather than parsing settings files. The SessionStart hook only auto-arms when `observer_enabled` is on.
7. **Repository settings.** Run `node "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from
   the project root. INFO when `docs/conventions/session-flow.yaml` is absent (every key comes from
   `userConfig` or its default); PASS with each key's value when the file validates; WARN, never
   FAIL, when it does not (an invalid value, an unknown or repeated key, an empty or non-scalar
   value, or a path that is not a plain file), quoting the line the script prints. An invalid
   value never stops a session-flow skill: the skill names it and drops that layer. `apply`
   overwrites only a value that is out of the list, empty or null; it refuses every other shape
   (a repeated or unknown key, a map or list, an empty quoted string), which the operator fixes by
   hand.

## `apply` (writes `docs/conventions/session-flow.yaml` only)

1. Run `check` and show its table.
2. **Resolve the values.** With complete `<key>=<value>` arguments, use them. Otherwise ask one key
   at a time, recommendation first, from the table in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`
   (`worker_continuation`: `resume`, the default, unless the team wants each new unit in a fresh
   worker; `encode_policy`: `promote-when-must-hold`, the default, unless the team wants every
   lesson proposed at its strongest rung; `review_mining_prs`: `20`, the default, an unquoted
   integer from 2 to 200). Never invent a key the schema does not list.
3. **Write.** One call with every value:

   ```bash
   node "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" worker_continuation=respawn
   ```

   The script checks each value against the schema, refuses a key given twice, validates the
   existing file first (refusing it unless every problem is a value out of the list, empty or
   null), and validates the whole resulting file (no unknown or repeated key, one non-empty scalar
   per key) before it writes; any refusal exits 1 and writes nothing. It writes only `<git toplevel>/docs/conventions/session-flow.yaml`:
   it refuses a symlink on that path or on `docs/conventions`, a directory resolving outside the
   repository, and a target with more than one hard link, and writes through a temp file renamed
   into place. A missing file is created. A value already in place prints `already configured` and
   writes nothing.
4. **An existing file that would change** exits 3 and prints a unified diff without writing. Show
   the operator that diff and ask whether to write it. Only on an explicit yes, re-run the same
   call with `--yes`; on anything else, stop with the file unchanged. A request to "set it" is not
   a yes to a diff the operator has not seen.
5. **Verify.** Re-run `check` and report the value from its table, not from the write. Then the
   tracked-file pair: `git check-ignore -v docs/conventions/session-flow.yaml` reports no match (a
   match means the team never receives the file: say so, and leave `.gitignore` to the operator),
   and `git ls-files --error-unmatch docs/conventions/session-flow.yaml` exits 0. Non-zero right
   after a fresh write means "written but untracked: commit it to share with the team", never
   success.

## Remediation guidance (printed by `check`; the operator applies it)

For the observer there is no write path. For each FAIL, `check` closes by offering the remediation: install the missing
tool, or route observer reconfiguration through Claude Code's native flow.
Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`.

Reconfigure the observer's `userConfig` keys through Claude Code's native flow, per the
marketplace's plugin-reconfiguration convention
(<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
which owns the verified-version record): interactive `/plugin configure session-flow@<marketplace>`
any time, or headless `claude plugin install session-flow@<marketplace> -s <scope> --config <key>=<value>`
(repeatable per key). Against an already-installed plugin it prints `already installed` and still
writes the value. Do **not** uninstall to reconfigure: that drops the stored `pluginConfigs` entry
outright, resetting every option in the README's Options reference to its manifest default, with
nothing left to read the old values from. `-s` defaults to `user`; pass the scope
`claude plugin list` reports, and run from that project's directory for a `project`/`local` scope,
or the rerun adds a second install record at the scope passed and enables the plugin there; the
value itself always lands in user settings. A rejected value prints a warning yet exits 0, so
read the output. Afterwards rerun `check` in a **fresh session**:
the rendered `${user_config.*}` is injected at skill load and each hook's `CLAUDE_PLUGIN_OPTION_*`
is fixed at session start, so a same-session `check` still reports the OLD value; report the
observed effective value, never an unobserved change.

## Output

`check`: the PASS/FAIL/INFO/WARN table with one remediation line per FAIL. `apply`: the table
before and after, the diff when one was shown, the written path, and whether the file is tracked.

## Next

`/session-flow:orchestrate`, which reads `worker_continuation`; `/session-flow:retro codify`,
which reads `encode_policy` and `review_mining_prs`.

## Gotchas

- **Prerequisites are the observer's, plus `gh` and `jq` for `retro codify reviews`.** The other
  session-flow skills need no installed tool. The repository settings are `worker_continuation`,
  read by `/session-flow:orchestrate`, and `encode_policy` and `review_mining_prs`, read by
  `/session-flow:retro codify`.
- **The repository file reaches the team only once committed.** `apply` leaves it uncommitted on
  purpose, and the tracked-file pair says so.
- **`observer_analysis_bare` and auth.** `--bare` drops the login credential state on OAuth-login
  installs. Leave it off unless auth is an env-var API key. Full detail in
  `${CLAUDE_PLUGIN_ROOT}/reference/observer.md`.
