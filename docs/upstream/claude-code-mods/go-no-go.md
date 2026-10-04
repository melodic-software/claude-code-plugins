# Go / no-go: the Claude Code mods recheck runbook

Run this top to bottom on Windows, compare every output with the recorded runs, and record each
criterion's state. It assumes no memory of the 2026-09-19 investigation. The runs feed
[ADR 0052](../../adr/0052-adopt-claude-code-mods.md), which supersedes
[ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md), and the
mods row under "Recorded gate runs" in [docs/plugin-philosophy.md](../../plugin-philosophy.md).

Beside this file: [experiments.md](experiments.md) holds E1 to E6 as rerunnable procedures with
their 2026-09-19 baselines, E7 and E8 from the 2026-10-02 run, the Desktop probe the maintainer ran
by hand (a user-authored mod loads in Desktop's Code tab, 2026-09-19, `OBSERVED`; the flag-unset,
cloud-session, Cowork and UI-drawing arms stay untested), and the manual probes that are still
open; [sources.md](sources.md) indexes every external link both files rely on;
[research-2026-09-19/](research-2026-09-19/) is the frozen evidence, dated and never current state.

## The verdict rule

[ADR 0052](../../adr/0052-adopt-claude-code-mods.md) decides: mods are adopted with no policy
narrowing of what a mod may do, and criterion 5 is replaced by the check under
[Criterion 5 as replaced](#criterion-5-as-replaced). A run records each criterion's state. A
criterion that changes state is a reason to re-derive ADR 0052, not a verdict by itself.

ADR 0035's rule, which decided the 2026-09-19 baseline: go requires **all five** criteria. Any one
failing is **no-go**. They are not weighted and none substitutes for another.

### Baseline verdict, 2026-09-19, Claude Code 2.1.278, Windows 11: NO-GO

| # | Criterion | State on 2026-09-19 | Outcome |
|---|---|---|---|
| 1 | A test mod loads with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` unset | Does not load. The rollout flag `tengu_plugin_hooks_modules` is off, from the default. | **Fail** |
| 2 | The official documentation mentions the feature | 0 hits across all 197 English pages; the control term still hits 67 times. | **Fail** |
| 3 | Issue [#92533](https://github.com/anthropics/claude-code/issues/92533) is closed | `state: OPEN`, `closedAt: null`. Reproduced locally on Windows at 2.1.278. | **Fail** |
| 4 | Official documentation states throw and timeout semantics, and the engine default is settled | Neither. `code.claude.com` is silent, and the engine default on an uncaught throw is undecided upstream. | **Fail** |
| 5 | The "may change between releases without notice" warning is gone from `mods/README.md` | Present. | **Fail** |

Five of five fail. The verdict is no-go, and it is no-go on the first criterion alone.

### Run record, 2026-10-02, Claude Code 2.1.288

Versions: `claude --version` printed `2.1.288 (Claude Code)`, and npm `latest` was
`"version":"2.1.288"`. The platform was Linux under WSL2, not the Windows the procedures below are
written for. The probe mod was the `usage-band` spike for
[#5777](https://github.com/melodic-software/claude-code-plugins/issues/5777), not the marker-file
probe under [Build the test mod](#build-the-test-mod); its procedure is
[E7](experiments.md#e7-usage-band-spike-2026-10-02), and the #92533 probe is
[E8](experiments.md#e8-92533-three-arm-probe-2026-10-02).

| # | Criterion | State on 2026-10-02 | Outcome |
|---|---|---|---|
| 1 | A test mod loads with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` unset | Loads in a `-p` run and in an interactive session with the variable unset. Claude Code 2.1.287 and later ignore the variable. | **Holds** |
| 2 | The official documentation mentions the feature | The docs index lists ten pages under `docs/en/plugins/mods/`. The corpus sweep returns 77 hits, with the control at 154. | **Holds** |
| 3 | Issue [#92533](https://github.com/anthropics/claude-code/issues/92533) is closed | `state: OPEN`. The 2.1.288 changelog lists a fix, and E8 found no failure in any arm on Linux. The file-search half and Windows are untested, and a 2026-10-02 comment reports `$.session.cwd()` returning the parent directory in a worktree subagent, on 2.1.287. | **Fails as written** |
| 4 | Official documentation states throw and timeout semantics, and the engine default is settled | The events page states both, the default included. | **Holds** |
| 5 | The "may change between releases without notice" warning is gone from `mods/README.md` | Present, at lines 114 to 116 of the README on `main` at `1c229fcd`. The 2.1.288 types header carries it too. No docs page under `plugins/mods/` carries it. | **Fails as written** |

Mods are adopted with criteria 3 and 5 failing as written: the Bash half of #92533 did not
reproduce at 2.1.288 (E8), and criterion 5 is replaced. The replaced check is recorded below.

**Criterion 1.** `$MOD` is the absolute path of the spike folder.

```sh
printenv CLAUDE_CODE_ENABLE_FUNCTION_HOOKS
claude plugin validate "$MOD" --json
claude -p "/usage-now" --plugin-dir "$MOD"
```

The first exited 1 with no output, so the variable was unset in the process environment. The
second exited 0 with `"success": true`. The third exited 0 and printed the mod's command reply,
which begins:

```text
usage-band: {
  "live": { "startedAt": 1790980674146, "context": { "window": 1000000 }, "rateLimits": [],
```

Interactive arm: `tmux new-session -d -s usage-band-poc -x 160 -y 45 claude --plugin-dir "$MOD"`,
one prompt sent with `tmux send-keys`, then `tmux capture-pane -p`. The mod's band was drawn above
the prompt, beginning `ctx 10% (98k/1000k)`. Not checked: a settings file's `env` block, because the
permission layer refused the grep. That gap does not change the result, since 2.1.287 and later
ignore the variable
([overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off)).

**Criterion 2.** The index listing is a presence check, which a curated index cannot fake; an
absence check still needs `llms-full.txt`.

```sh
curl -sS -o llms.txt -w 'http=%{http_code} bytes=%{size_download}\n' https://code.claude.com/docs/llms.txt
grep -o 'docs/en/plugins/mods/[a-z-]*\.md' llms.txt | sort -u
curl -sS -o llms-full.txt -w 'http=%{http_code} bytes=%{size_download}\n' https://code.claude.com/docs/llms-full.txt
grep -icE 'function hook|hooks module|plugin-types|prependPlugins|appendPlugins|engine\.create|CLAUDE_CODE_ENABLE_FUNCTION_HOOKS|sec-default' llms-full.txt
grep -c 'plugin-dir' llms-full.txt
```

Output: `http=200 bytes=52888`; ten paths, `admin`, `api`, `create`, `events`, `gallery`,
`interface`, `overview`, `reference`, `test` and `troubleshoot`; `http=200 bytes=8667624`; `77`;
`154`.

**Criterion 3.**

```sh
gh issue view 92533 -R anthropics/claude-code --json state,stateReason,closedAt,updatedAt
curl -sS https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | sed -n '3,60p' | grep -n -i worktree
```

Output: `{"closedAt":null,"state":"OPEN","stateReason":"","updatedAt":"2026-10-02T03:43:05Z"}`. The
changelog's `## 2.1.288` heading is on line 3, and its entry fixing a plugin's `tool.call` hook in
worktree subagents is on line 27 of the file. E8 replaces E2 for this run; E2 itself, on Windows,
was not re-run.

**Criterion 4.** The pointer is
[events: handle a hook that fails](https://code.claude.com/docs/en/plugins/mods/events#handle-a-hook-that-fails),
read from the raw page fetched under [Criterion 5 as replaced](#criterion-5-as-replaced)
(`### Handle a hook that fails` at line 305 of `mods-events.md`). The 2.1.288 `plugin-authoring`
types state the same skip-and-continue behavior in the doc comment on the engine's event table.

**Criterion 5.**

```sh
curl -sS -o mods-readme.md -w 'http=%{http_code} bytes=%{size_download}\n' https://raw.githubusercontent.com/anthropics/claude-code/main/mods/README.md
tr '\n' ' ' < mods-readme.md | grep -c 'may change between releases without notice'
tr '\n' ' ' < mods-readme.md | grep -ci 'hooks module'
gh api 'repos/anthropics/claude-code/commits?path=mods&per_page=1' --jq '.[0] | .sha + " " + .commit.committer.date'
gh api repos/anthropics/claude-code/commits/main --jq '.sha'
```

Output: `http=200 bytes=6470`; `1`; `1`;
`6160717d8994f236ab381cf534fc1cde5347c12f 2026-10-01T05:23:04Z`;
`1c229fcd1e1e4e452e29a8f116b45fe4cfe2c528`.

## Before you start

**No `--help` check and no documentation grep is an availability check.** `claude plugin test` is a
working but hidden, gate-registered command, absent from `claude plugin --help` whether or not the
variable is set, and the documentation did not name the feature before 2.1.287. Both return
**false negatives**.
Every criterion below probes behavior, except 2 and 5, which are first-mention detectors and say so.

Preconditions: Claude Code on `PATH` (record `claude --version`; the baseline is pinned to
**2.1.278** and the 2026-10-02 run to **2.1.288**); `gh` authenticated; `curl` and Git Bash. The environment variable must be genuinely
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
file-writes, so create the three files with the editor or the Write tool instead, same content.

Two standing mechanics: `--debug-file` **appends**, so use a fresh filename per run; and
`go-no-go-probe` is the grep anchor, appearing in every engine line as `go-no-go-probe@inline`.

### Fetch the upstream README

Criteria 4 and 5 both grep `mods/README.md`. Fetch it once, here, so a top-to-bottom run has the file
before criterion 4 reads it.

```sh
curl -sS -o "$P/out/mods-readme.md" -w 'http=%{http_code} bytes=%{size_download}\n' \
  https://raw.githubusercontent.com/anthropics/claude-code/main/mods/README.md
```

Expected on 2026-10-02: `http=200 bytes=6470` (it was 6347 on 2026-09-19). Anything else and
criteria 4 and 5 are both reading an error page or a moved file; settle it with the sha pin under
criterion 5 before reading either count.

## The five criteria

Each "Expected today" below is the 2026-09-19 baseline at 2.1.278. The 2026-10-02 outputs at
2.1.288 are in the [run record](#run-record-2026-10-02-claude-code-21288); criteria 1, 2 and 4 now
return different results.

### Criterion 1: a test mod loads with the variable unset

The only criterion that answers the question a consumer faces. At 2.1.278 the variable was an
override (`??`) over a rollout gate whose default was `false`, so "it works when I set the variable"
said nothing about anyone else. From 2.1.287 the variable is ignored and mods are on by default
([overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off),
as of 2026-10-02; recheck when that section changes the minimum version or the default).

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

Always run the positive control before trusting a negative: the same command with
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` and a fresh debug file. Recorded 2026-09-19: the marker is
written and the load line appears, with `plugin.register: … admitted` and `session.start settled in
16.0ms`. If the control fails too, the probe is broken and neither arm means anything.

Risks:

- **One machine and one account cannot show a segmented rollout.** A fail proves the gate is off for
  *this* account on *this* build. A local fail is decisive against go; a local pass is the weakest
  possible evidence for it, so confirm on a second account before flipping the verdict.
- The source clause is the real control. `from the default (a cold GrowthBook cache, no payload yet)`
  means the server was never consulted: run a plain `claude -p ok` first, or run the arm twice, or a
  rollout that has in fact flipped still reads as off. `from a local override` means the variable
  leaked in; `from GrowthBook` or `from the disk cache` means the flag was genuinely consulted. Where
  GrowthBook is off entirely (a third-party model provider, or telemetry opted out), the gate falls
  to `false` and only the variable can enable it, so criterion 1 can never pass on such a machine and
  a fail there says nothing about upstream.

### Criterion 2: the official documentation mentions the feature

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
`grep -icwE "mods?"` over it also returns `0`. `67` is the live control: `plugin-dir` is a
documented flag, so a non-zero control proves the sweep reached real text.

**Met when:** either sweep returns a non-zero count while the control is still non-zero (recorded
baseline `67`; a materially lower control means re-read the corpus before trusting either arm).

Risks: always grep `llms-full.txt`, never the curated `llms.txt`, which greps clean against a
documented feature. This is a **first-mention detector only**: `/diff` and AGENTS.md are documented
features whose implementations are mods and whose documentation never names the mechanism, so
silence is compatible with full availability; the criterion exists because a first mention is the
strongest single signal that the surface left early access. A control of 0 means the fetch failed or
the format changed: inconclusive, neither pass nor fail.

### Criterion 3: issue #92533 is closed

```sh
gh issue view 92533 -R anthropics/claude-code --json state,stateReason,closedAt
```

Expected today: `{"closedAt":null,"state":"OPEN","stateReason":""}`.

**Met when:** `state` is `CLOSED` **and** the local reproduction in
[experiments.md](experiments.md) (E2) no longer reproduces. Both halves are required, because
**closed does not prove fixed**: a `stateReason` of `not_planned` closes without a fix, and a
`completed` close can be against macOS, where the issue was filed, while Windows still breaks. Run
E2 against a throwaway git repository, never a real one.

Risks: the hazard is a green `gh` line with no reproduction run. An unauthenticated `gh` returns an
error, not a state; treat it as inconclusive. And the defect is not opt-in for consumers, because
the variable only overrides the rollout gate, a plugin shipping a `tool.call` hook on Bash could
break worktree isolation for someone who never set it, should the gate flip. That is why this gates
go and not merely guard conversion.

### Criterion 4: official documentation states throw and timeout semantics

```sh
grep -icE 'HookBudget|fail-open|fails open|hook that throws' "$P/out/llms-full.txt"   # docs site
grep -icE 'throw|budget|timeout|catch' "$P/out/mods-readme.md"                        # mods/README.md
curl -sS https://raw.githubusercontent.com/anthropics/claude-code/main/mods/types/claude-code.d.ts \
  | grep -nE 'HookBudget|Registration.catch|overruns its budget' | head -20           # JSDoc
gh issue view 91870 -R anthropics/claude-code --json state,updatedAt,body | head -40  # roadmap
```

Expected today: `5`, then `1`, then eight JSDoc lines (3209, 4180, 5245, 5260, 5395, 7264, 7267,
9315), then `"state":"OPEN"`. **Not one of those counts is a pass.** The `5` is entirely Claude Apps
Gateway spend-limit text, the `1` is a bare `catch`, and the JSDoc hits are the false positive the
met-bar excludes by name. See Risks before reading any of them.

State on 2026-09-19 is three things and must be recorded as three:

- **Observed behavior is fail-open, twice over.** A hook that throws with no `.catch` is skipped and
  the chain beneath answers, indistinguishable from a chain in which nothing failed. A hook that
  overruns the 10 s `HookBudget` is cut (measured live at 10,249.9 ms), and `next(e)` runs on its
  behalf, so core runs and the tool executes. The only witness either time is an `[ERROR]` line in
  `--debug-file`. `on(...).catch(($, e, next) => ({ deny: … }))` converts either failure into a
  refusal within a 1,000 ms grace; without it a mod-based guard is strictly weaker than the classic
  command hook it would replace, since a classic hook exiting with code 2 blocks.
- **The generated `.d.ts` JSDoc already states the mechanism**: the per-event doc and
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
semantics **and** the engine's default on an uncaught throw is settled upstream, not when the
generated `.d.ts` JSDoc mentions them, which it already does.

Risks: a `.d.ts` hit is a **false positive** for this criterion, as is a bare hit on the word
`catch` in `mods/README.md`. So is the docs-site count: `fail-open` and `fails open` also match the
Claude Apps Gateway spend-limit pages, which on 2026-09-19 is all 5 hits and none of them about
hooks. Read every hit's surrounding sentence, never decide from the count, and check both halves of
the bar.

### Criterion 5: the early-access warning is gone from `mods/README.md`

Reuses the `mods/README.md` fetched under ["Fetch the upstream README"](#fetch-the-upstream-readme).

```sh
tr '\n' ' ' < "$P/out/mods-readme.md" | grep -c 'may change between releases without notice'
tr '\n' ' ' < "$P/out/mods-readme.md" | grep -ci 'hooks module'
```

Expected today: `1`, then `1`. Both are `1` because `tr` collapses the file to one line; the second
is the control, proving the fetched bytes are the mods README and not an error page. **Met when:**
the sentence count is `0` while that fetch returned `http=200` and the control is `1`.

**The `tr` is not cosmetic.** In the recorded file the sentence wraps across two lines:

```text
Early access: hooks modules load only where function hooks are enabled, and
the API these mods are written against may change between releases without
notice.
```

A line-oriented `grep 'may change between releases without notice'` returns **0** against a file that
plainly contains it. Taken at face value that reads as "warning gone", a false positive for go on
the criterion that most directly tracks early-access status. Always flatten first, always check the
control.

Risks: a 404, a rename, or a moved `mods/` tree also returns 0. Settle it with
`gh api 'repos/anthropics/claude-code/commits?path=mods' --jq '.[0].sha'`; pin `6160717d`, the
newest commit touching `mods/` on 2026-10-02 (it was `92ec78f2` on 2026-09-19). An unchanged sha
means the 0 is genuinely about the sentence. A different sha means re-read what changed: diff
against `https://github.com/anthropics/claude-code/blob/6160717d/mods/README.md` for the 2026-10-02
run, and against `https://github.com/anthropics/claude-code/blob/92ec78f2/mods/README.md` for the
source-based claims in the frozen snapshot. A reworded but equivalent warning also returns 0 and is
a genuine false positive: read the file's last paragraph, do not only count.

### Criterion 5 as replaced

ADR 0052 judges stability on the ten docs pages and on the header of the `plugin-authoring` types
for the build in use. The README check above is still run and recorded; it no longer gates.

```sh
for p in overview create events interface api test troubleshoot admin reference gallery; do
  curl -sS -o "$P/out/mods-$p.md" -w "$p http=%{http_code} bytes=%{size_download}\n" \
    "https://code.claude.com/docs/en/plugins/mods/$p.md"
done
grep -il 'without notice' "$P"/out/mods-*.md
grep -ic 'early access' "$P"/out/mods-*.md
```

Then read lines 1 and 4 of the types for the build under test. Loading the `plugin-authoring`
skill in an interactive session writes them and names the file, and a mod loaded interactively with
`--plugin-dir` gets the same header in `.claude-plugin/types/claude-code/index.d.ts`. A `-p` run
writes no types.

Recorded 2026-10-02 at 2.1.288: ten `http=200` lines; no file matches `without notice` (grep exit
1); `early access` counts 1 in `mods-overview.md`, 1 in `mods-admin.md` and 0 elsewhere, each a
note to remove the old enable variable rather than a stability warning; types line 1 is
`// Written by Claude Code 2.1.288.` and line 4 is the early-access line. Adoption accepted that
header as it stood.

**Re-derive ADR 0052 when** a docs page gains an early-access or "without notice" warning. Record
any change to the types header in the run, with the build that wrote it.

## Quick check for a Claude Code pin bump

Any pull request bumping the `@anthropic-ai/claude-code` pin in `package.json` runs **criteria 1 to 3
and the replaced criterion 5**. A few minutes. Owned by whoever bumps the pin. This is ADR 0052's
first recheck trigger.

1. Record the version three ways, because every baseline is pinned to a build and a minor bump can
   change behavior:

   ```sh
   claude --version
   curl -sS https://registry.npmjs.org/@anthropic-ai/claude-code/latest | grep -o '"version":"[^"]*"'
   gh api repos/anthropics/claude-code/tags?per_page=3 --jq '.[].name'
   ```

   Pin-time: `2.1.278 (Claude Code)`; npm `latest` published 2026-09-19T01:48:59Z; release
   `v2.1.278` published 2026-09-19T03:10:40Z. On 2026-10-02: `2.1.288 (Claude Code)`, npm
   `"version":"2.1.288"`, newest tags `v2.1.288`, `v2.1.287`, `v2.1.286`. The installed `claude` and
   the pin being bumped are not necessarily the same version, so record both.
2. Build the test mod, or reuse `$P` from an earlier run in the same session.
3. Criterion 1, unset arm plus the positive control. From 2.1.287 the variable is ignored, so the
   control and the unset arm should agree.
4. Criterion 2, the documentation greps and the changelog grep.
5. Criterion 3, the `gh` query only. E2 and E8 are not part of the quick check; a state change is
   what escalates.
6. [Criterion 5 as replaced](#criterion-5-as-replaced): the docs-page greps and the
   types header.

All unchanged from the last run: record the run, nothing else to do. Any one changed: do the full
run (criterion 4 and the README check here, then every experiment and open probe in
[experiments.md](experiments.md)), re-derive
[ADR 0052](../../adr/0052-adopt-claude-code-mods.md), and update the mods
row in [docs/plugin-philosophy.md](../../plugin-philosophy.md).

## After a run

Record the run whatever the outcome. A run that is not written down gets re-derived from scratch.

- **[docs/plugin-philosophy.md](../../plugin-philosophy.md)**, the mods row: update the `As of`
  date every run, and the row's reason if the *reason* for the verdict moved.
- **[ADR 0052](../../adr/0052-adopt-claude-code-mods.md)**: leave it alone while its decisions and
  verdict hold. If a re-derivation changes either, a superseding record or an amendment carries the
  new decision; a runbook run does not amend an ADR by itself.
  [ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md) is superseded and stays
  as it was written.
- **[research-2026-09-19/](research-2026-09-19/)** is frozen: if the research is redone, write a new
  dated snapshot folder beside it and never edit a dated one. **[sources.md](sources.md)** gains a
  row for any external URL a rerun newly relies on, and a refreshed `Fetched` column for rows it
  re-fetched.

**Guard conversion is a parity question, not a criterion.** ADR 0035 kept three conditions on
converting a guard hook to a mod; ADR 0052 replaces them with one rule: a guard moves into a mod
only when the mod matches every behavior of the hook it replaces, and a settings hook stays where it
must run with mods off. Passing criteria says a consumer who installs one of this repository's
plugins gets a working mod, which is a distribution question. Whether a *guard*, a hook whose whole
job is to refuse, is as strong as a mod is answered by that parity check. A guard written as a mod
is fail-open on throw and on overrun unless it attaches `.catch(() => ({ deny }))`. Two structural
facts are in no criterion: a mod takes no per-repository option values, because a project's
`.claude/settings.json` is not read for `pluginConfigs` (a project turns the plugin on or off
through `enabledPlugins`); and a mod cannot choose its own registration order, so a guard at the
`user` tier binds the model's tool calls but not sibling plugins.
