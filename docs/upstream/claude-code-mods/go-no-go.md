# Go / no-go: the Claude Code mods recheck runbook

Run this top to bottom on Windows, compare every output with the recorded baseline, and state go or
no-go. It assumes no memory of the 2026-09-19 investigation. The verdict feeds
[ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md) and the mods row under
"Recorded gate runs" in [docs/plugin-philosophy.md](../../plugin-philosophy.md).

Beside this file: [experiments.md](experiments.md) holds E1 to E6 as rerunnable procedures with
their 2026-09-19 baselines plus the open manual probes; [sources.md](sources.md) indexes every
external link both files rely on; [research-2026-09-19/](research-2026-09-19/) is the frozen
evidence, dated and never current state.

## The verdict rule

Go requires **all five** criteria. Any one failing is **no-go**. They are not weighted and none
substitutes for another.

### Baseline verdict, 2026-09-19, Claude Code 2.1.278, Windows 11: NO-GO

| # | Criterion | State on 2026-09-19 | Outcome |
|---|---|---|---|
| 1 | A test mod loads with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` unset | Does not load. The rollout flag `tengu_plugin_hooks_modules` is off, from the default. | **Fail** |
| 2 | The official documentation mentions the feature | 0 hits across all 197 English pages; the control term still hits 67 times. | **Fail** |
| 3 | Issue [#92533](https://github.com/anthropics/claude-code/issues/92533) is closed | `state: OPEN`, `closedAt: null`. Reproduced locally on Windows at 2.1.278. | **Fail** |
| 4 | Official documentation states throw and timeout semantics, and the engine default is settled | Neither. `code.claude.com` is silent, and the engine default on an uncaught throw is undecided upstream. | **Fail** |
| 5 | The "may change between releases without notice" warning is gone from `mods/README.md` | Present. | **Fail** |

Five of five fail. The verdict is no-go, and it is no-go on the first criterion alone.

## Before you start

**No `--help` check and no documentation grep is an availability check.** `claude plugin test` is a
working but hidden, gate-registered command, absent from `claude plugin --help` whether or not the
variable is set, and the documentation has never named the feature. Both return **false negatives**.
Every criterion below probes behaviour, except 2 and 5, which are first-mention detectors and say so.

Preconditions: Claude Code on `PATH` (record `claude --version`; every baseline is pinned to
**2.1.278**); `gh` authenticated; `curl` and Git Bash. The environment variable must be genuinely
unset for criterion 1, and `env -u` does **not** clear it if it sits in a settings file's `env`
block, so run `grep -c CLAUDE_CODE_ENABLE_FUNCTION_HOOKS ~/.claude/settings.json
~/.claude/settings.local.json` first. Baseline `0` for both; non-zero means criterion 1 is
meaningless until it is removed.

PowerShell equivalents where the syntax differs: set with `$env:CLAUDE_CODE_ENABLE_FUNCTION_HOOKS =
'1'`, clear with `Remove-Item Env:\CLAUDE_CODE_ENABLE_FUNCTION_HOOKS -ErrorAction SilentlyContinue`;
`Push-Location` for `env -C`; `Invoke-WebRequest -OutFile` for `curl -o`; `(Get-Content <f> -Raw)
-replace "`r?`n", ' '` for `tr '\n' ' '`.

### Build the test mod

The 2026-09-19 spike directory was machine-local and will not exist. Build the probe from scratch in
an OS temp directory.

```sh
P=$(cd "$(mktemp -d "$TEMP/mods-recheck-XXXXXX")" && pwd -W)
mkdir -p "$P/mod/.claude-plugin" "$P/mod/hooks" "$P/markers" "$P/work" "$P/out"
```

Two path rules, both load-bearing. Use `$TEMP` / `$env:TEMP`, never a bare `mktemp -d`, which yields
an MSYS `/tmp` path the Bun worker cannot open. And **the path baked into a module must use forward
slashes**: `mktemp -d "$TEMP/…"` returns a backslash path carrying an 8.3 short name,
`C:\…\AppData\Local\Temp/mods-recheck-…`, and in a single-quoted TypeScript literal `\A`, `\L` and
`\T` are identity escapes, so the constant silently becomes `C:…AppDataLocalTemp/…` and the write
lands nowhere. The `cd … && pwd -W` above returns the long forward-slash form; PowerShell readers
derive `$Pfwd = $P -replace '\\', '/'` and use **that** in every module constant.

`$P/mod/.claude-plugin/plugin.json`:

```json
{
  "name": "go-no-go-probe",
  "version": "0.0.1",
  "description": "Writes a marker file from a session.start hooks-module hook",
  "author": { "name": "go-no-go" }
}
```

`$P/mod/hooks/hooks.json`:

```json
{ "description": "Criterion 1 load probe", "modules": ["./register.ts"] }
```

`$P/mod/hooks/register.ts`. The marker path **must be a string literal**: the engine reads `$` and
the module source before loading, so a path computed at run time makes the module refuse to load.
Write the constant by substitution, then append the body from a quoted heredoc so `$.fs.write` and
`($, e, next)` stay literal:

```sh
printf "const MARKER = '%s/markers/loaded.txt';\n" "$P" > "$P/mod/hooks/register.ts"
cat >> "$P/mod/hooks/register.ts" <<'EOF'

export function register(on: any) {
  on('session.start', async ($: any, e: any, next: any) => {
    await $.fs.write(MARKER, 'go-no-go-probe session.start ' + new Date().toISOString() + '\n');
    return next(e);
  });
}
EOF
```

A hooks module cannot reach `node:fs`; `$.fs.write` is the only channel that leaves evidence. An
agent running this inside this repository will find the `guardrails` plugin refusing shell
file-writes — create the three files with the editor or the Write tool instead, same content.

Two standing mechanics: `--debug-file` **appends**, so use a fresh filename per run; and
`go-no-go-probe` is the grep anchor, appearing in every engine line as `go-no-go-probe@inline`.

## The five criteria

### Criterion 1 — a test mod loads with the variable unset

The only criterion that answers the question a consumer faces. The variable is an override (`??`)
over a rollout gate whose default is `false`, so "it works when I set the variable" says nothing
about anyone else.

```sh
env -C "$P/work" -u CLAUDE_CODE_ENABLE_FUNCTION_HOOKS claude --debug \
  --debug-file "$P/out/c1-unset.txt" --plugin-dir "$P/mod" --model haiku -p "reply ok"
ls "$P/markers/"
grep -E 'go-no-go-probe|tengu_plugin_hooks_modules' "$P/out/c1-unset.txt"
```

Expected today: exit 0, the model answers normally, `$P/markers/` **empty**, nothing on stderr about
plugins, and in the debug file:

```text
[DEBUG] installed plugins' hooks modules not loaded: rollout flag (tengu_plugin_hooks_modules) is off, from the default (a cold GrowthBook cache, no payload yet); built-in plugins load regardless
[DEBUG] hooks module go-no-go-probe@inline not loaded: the rollout flag (tengu_plugin_hooks_modules) is off, which governs installed plugins; built-in plugins load regardless
```

**Met when:** `$P/markers/loaded.txt` exists **and** the debug file carries
`hooks module go-no-go-probe@inline loaded (worker, environment 1, tier user); events: session.start`.

Always run the positive control before trusting a negative — the same command with
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` and a fresh debug file. Recorded 2026-09-19: the marker is
written and the load line appears, with `plugin.register: … admitted` and `session.start settled in
16.0ms`. If the control fails too, the probe is broken and neither arm means anything.

Risks:

- **One machine and one account cannot show a segmented rollout.** A fail proves the gate is off for
  *this* account on *this* build. A local fail is decisive against go; a local pass is the weakest
  possible evidence for it — confirm on a second account before flipping the verdict.
- The source clause is the real control. `from the default (a cold GrowthBook cache, no payload yet)`
  means the server was never consulted: run a plain `claude -p ok` first, or run the arm twice, or a
  rollout that has in fact flipped still reads as off. `from a local override` means the variable
  leaked in; `from GrowthBook` or `from the disk cache` means the flag was genuinely consulted. Where
  GrowthBook is off entirely — a third-party model provider, or telemetry opted out — the gate falls
  to `false` and only the variable can enable it, so criterion 1 can never pass on such a machine and
  a fail there says nothing about upstream.

### Criterion 2 — the official documentation mentions the feature

```sh
curl -sS -o "$P/out/llms-full.txt" -w 'http=%{http_code} bytes=%{size_download}\n' \
  https://code.claude.com/docs/llms-full.txt
grep -icE 'function hook|hooks module|plugin-types|prependPlugins|appendPlugins|engine\.create|CLAUDE_CODE_ENABLE_FUNCTION_HOOKS|sec-default' "$P/out/llms-full.txt"
grep -c 'plugin-dir' "$P/out/llms-full.txt"
curl -sS https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md \
  | grep -icE 'function hook|hooks module|plugin-types|CLAUDE_CODE_ENABLE_FUNCTION_HOOKS|sec-default|prependPlugins|claude plugin test'
```

Expected today: `http=200 bytes=9590632`, then `0`, `67`, `0`. The corpus is all 197 English pages;
the changelog is 7,158 lines from `## 2.1.278` down to `## 0.2.21`, and a word-bounded
`grep -icwE "mods?"` over it also returns `0`. `67` is the live control — `plugin-dir` is a
documented flag, so a non-zero control proves the sweep reached real text.

**Met when:** either sweep returns a non-zero count while the control still returns 67 or more.

Risks: always grep `llms-full.txt`, never the curated `llms.txt`, which greps clean against a
documented feature. This is a **first-mention detector only** — `/diff` and AGENTS.md are documented
features whose implementations are mods and whose documentation never names the mechanism, so
silence is compatible with full availability; the criterion exists because a first mention is the
strongest single signal that the surface left early access. A control of 0 means the fetch failed or
the format changed: inconclusive, neither pass nor fail.

### Criterion 3 — issue #92533 is closed

```sh
gh issue view 92533 -R anthropics/claude-code --json state,stateReason,closedAt
```

Expected today: `{"closedAt":null,"state":"OPEN","stateReason":""}`.

**Met when:** `state` is `CLOSED` **and** the local reproduction in
[experiments.md](experiments.md) (E2) no longer reproduces. Both halves are required, because
**closed does not prove fixed**: a `stateReason` of `not_planned` closes without a fix, and a
`completed` close can be against macOS — where the issue was filed — while Windows still breaks. Run
E2 against a throwaway git repository, never a real one.

Risks: the hazard is a green `gh` line with no reproduction run. An unauthenticated `gh` returns an
error, not a state; treat it as inconclusive. And the defect is not opt-in for consumers — because
the variable only overrides the rollout gate, a plugin shipping a `tool.call` hook on Bash could
break worktree isolation for someone who never set it, should the gate flip. That is why this gates
go and not merely guard conversion.

### Criterion 4 — official documentation states throw and timeout semantics

```sh
grep -icE 'HookBudget|fail-open|fails open|hook that throws' "$P/out/llms-full.txt"   # docs site
grep -icE 'throw|budget|timeout|catch' "$P/out/mods-readme.md"                        # mods/README.md
curl -sS https://raw.githubusercontent.com/anthropics/claude-code/main/mods/types/claude-code.d.ts \
  | grep -nE 'HookBudget|Registration.catch|overruns its budget' | head -20           # JSDoc
gh issue view 91870 -R anthropics/claude-code --json state,updatedAt,body | head -40  # roadmap
```

State on 2026-09-19 is three things and must be recorded as three:

- **Observed behaviour is fail-open, twice over.** A hook that throws with no `.catch` is skipped and
  the chain beneath answers, indistinguishable from a chain in which nothing failed. A hook that
  overruns the 10 s `HookBudget` is cut — measured live at 10,249.9 ms — and `next(e)` runs on its
  behalf, so core runs and the tool executes. The only witness either time is an `[ERROR]` line in
  `--debug-file`. `on(...).catch(($, e, next) => ({ deny: … }))` converts either failure into a
  refusal within a 1,000 ms grace; without it a mod-based guard is strictly weaker than the classic
  command hook it would replace, since a classic hook exiting with code 2 blocks.
- **The generated `.d.ts` JSDoc already states the mechanism** — the per-event doc and
  `Registration.catch` both say it. So "documented nowhere" is wrong and "documented only inside the
  early-access tree" is right; those declarations are generated by `/plugin-types` and are themselves
  covered by the warning criterion 5 tracks.
- **What is missing** is any statement on `code.claude.com`, and an upstream decision on the engine's
  *default* for an uncaught throw. The maintainer's position moved four times across
  [#91870](https://github.com/anthropics/claude-code/issues/91870) between 2026-09-03 and 2026-09-08
  and settled on "construct fail-closed yourself with `.catch`" rather than on a default. Full
  evidence:
  [research-security-and-semantics.md](research-2026-09-19/research-security-and-semantics.md).

**Met when:** Anthropic's official documentation on `code.claude.com` states the throw and timeout
semantics **and** the engine's default on an uncaught throw is settled upstream — not when the
generated `.d.ts` JSDoc mentions them, which it already does.

Risk: a `.d.ts` hit is therefore a **false positive** for this criterion, as is a bare hit on the
word `catch` in `mods/README.md`. Read the sentence, and check both halves of the bar.

### Criterion 5 — the early-access warning is gone from `mods/README.md`

```sh
curl -sS -o "$P/out/mods-readme.md" -w 'http=%{http_code} bytes=%{size_download}\n' \
  https://raw.githubusercontent.com/anthropics/claude-code/main/mods/README.md
tr '\n' ' ' < "$P/out/mods-readme.md" | grep -c 'may change between releases without notice'
tr '\n' ' ' < "$P/out/mods-readme.md" | grep -ci 'hooks module'
```

Expected today: `http=200 bytes=6347`, then `1`, `1`. Both are `1` because `tr` collapses the file to
one line; the second is the control, proving the fetched bytes are the mods README and not an error
page. **Met when:** the sentence count is `0` while `http=200` and the control is `1`.

**The `tr` is not cosmetic.** In the recorded file the sentence wraps across two lines:

```text
Early access: hooks modules load only where function hooks are enabled, and
the API these mods are written against may change between releases without
notice.
```

A line-oriented `grep 'may change between releases without notice'` returns **0** against a file that
plainly contains it. Taken at face value that reads as "warning gone" — a false positive for go on
the criterion that most directly tracks early-access status. Always flatten first, always check the
control.

Risks: a 404, a rename, or a moved `mods/` tree also returns 0. Settle it with
`gh api 'repos/anthropics/claude-code/commits?path=mods' --jq '.[0].sha'`; pin `92ec78f2`. An
unchanged sha means the 0 is genuinely about the sentence. A different sha invalidates the
source-based claims in the frozen snapshot — diff against
`https://github.com/anthropics/claude-code/blob/92ec78f2/mods/README.md` and re-read what changed.
A reworded but equivalent warning also returns 0 and is a genuine false positive: read the file's
last paragraph, do not only count.

## Quick check for a Claude Code pin bump

Any pull request bumping the `@anthropic-ai/claude-code` pin in `package.json` runs **criteria 1 to 3
only**. About a minute. Owned by whoever bumps the pin.

1. Record the version three ways, because every baseline is pinned to a build and a minor bump can
   change behaviour:

   ```sh
   claude --version
   curl -sS https://registry.npmjs.org/@anthropic-ai/claude-code/latest | grep -o '"version":"[^"]*"'
   gh api repos/anthropics/claude-code/tags?per_page=3 --jq '.[].name'
   ```

   Pin-time: `2.1.278 (Claude Code)`; npm `latest` published 2026-09-19T01:48:59Z; release
   `v2.1.278` published 2026-09-19T03:10:40Z. The installed `claude` and the pin being bumped are not
   necessarily the same version — record both.
2. Build the test mod, or reuse `$P` from an earlier run in the same session.
3. Criterion 1, unset arm plus the positive control.
4. Criterion 2, the documentation greps and the changelog grep.
5. Criterion 3, the `gh` query only. E2 is not part of the quick check; a state change is what
   escalates.

All three unchanged: record the run, nothing else to do. Any one changed: do the full run — criteria
4 and 5 here, then every experiment and open probe in [experiments.md](experiments.md) — and update
the Defer row in [docs/plugin-philosophy.md](../../plugin-philosophy.md). A changed criterion 1, 2 or
3 is never a go on its own, because go needs all five.

## After a run

Record the run whatever the outcome. A no-go that is not written down gets re-derived from scratch.

- **[docs/plugin-philosophy.md](../../plugin-philosophy.md)**, the mods row: update the `Verified`
  date every run, and the row's basis if the *reason* for the verdict moved — criterion 1 starting to
  pass while criterion 3 still fails changes the stated reason without changing the verdict.
- **[ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md)**: leave it alone
  while the verdict holds. If the verdict flips, its status changes and a superseding record carries
  the new decision; a runbook run does not amend an accepted ADR by itself.
- **[research-2026-09-19/](research-2026-09-19/)** is frozen: if the research is redone, write a new
  dated snapshot folder beside it and never edit a dated one. **[sources.md](sources.md)** gains a
  row for any external URL a rerun newly relies on, and a refreshed `Fetched` column for rows it
  re-fetched.

**A flip to go does not lift the three guard-conversion conditions in ADR 0035 — it reopens them.**
A go verdict says a consumer who installs one of this repository's plugins gets a working mod without
setting an undocumented variable, which is a distribution question. The three conditions ask whether
a *guard* — a hook whose whole job is to refuse — is as strong as the classic command hook it
replaces, and a guard written as a mod is fail-open on throw and on overrun unless it attaches
`.catch(() => ({ deny }))`. Evaluate them on their own evidence. Two structural misfits survive a go
verdict and are in no criterion: a mod cannot take per-repository configuration, because a project's
`.claude/settings.json` is not read for plugin options; and a mod cannot choose its own registration
order, so a guard at the `user` tier binds the model's tool calls but not sibling plugins.
