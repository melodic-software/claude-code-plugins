# Mods: the recorded experiments and the open probes

The six locally answerable unknowns the 2026-09-19 spike closed, each as a rerunnable procedure with
that day's result as the baseline, followed by the probes that stayed open. This is the "full run"
half of [go-no-go.md](go-no-go.md); the verdict is decided there, by the five criteria, not here.

Two dependencies run the other way: criterion 3 cannot pass without E2, and E5 is the standing reason
a third-party mod is a security decision rather than only a behaviour one.

Every setup below assumes `$P`, the temp directory built in
[go-no-go.md](go-no-go.md#build-the-test-mod), and the two path rules recorded there. `<P>` in a
TypeScript listing stands for that directory, written as a literal by substitution.

Standing caveat, true of the original run and of any rerun: a machine with its own classic hooks and
plugins is **not** a clean room. Each experiment is therefore a paired arm-versus-control on the same
machine, and the control is what the result is read against.

## E1 — `hooks` and `modules` in one `hooks.json`

Question: with a single `hooks/hooks.json` carrying both a classic settings-format `hooks` block and
a `modules` entry, do both layers fire?

Build a second probe under `$P/e1/`, laid out like the criterion-1 probe with `plugin.json` named
`e1-both`. Three more files.

`$P/e1/hooks/marker.js` — the classic arm's writer. A **module** cannot reach `node:fs`, which is
why only the classic arm uses `node`:

```js
const fs = require('node:fs');
const path = require('node:path');
fs.writeFileSync(path.join(__dirname, '..', '..', 'markers', process.argv[2] + '.txt'),
  process.argv[2] + ' ' + new Date().toISOString() + '\n');
```

`$P/e1/hooks/register.ts` — the module arm, built by the same substitution as the criterion-1 probe
(`printf "const DIR = '%s/markers';\n" "$P" > …`, then the body appended from a quoted heredoc):

```ts
const DIR = '<P>/markers';

export function register(on: any) {
  on('session.start', async ($: any, e: any, next: any) => {
    await $.fs.write(DIR + '/B-module-session-start.txt', 'module session.start ' + new Date().toISOString() + '\n');
    return next(e);
  });
  on('tool.call', { tool: 'Bash' }, async ($: any, e: any, next: any) => {
    await $.fs.write(DIR + '/B-module-tool-call.txt', 'module tool.call ' + new Date().toISOString() + '\n');
    return next(e);
  });
}
```

`$P/e1/hooks/hooks.json` — both layers in one file:

```json
{
  "description": "E1 coexistence probe: classic command hooks beside a hooks module",
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/marker.js\" A-classic-sessionstart", "timeout": 10 } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/marker.js\" A-classic-pretooluse", "timeout": 10 } ] }
    ]
  },
  "modules": ["./register.ts"]
}
```

Command:

```sh
rm -f "$P/markers"/*
env -C "$P/work" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude --debug \
  --debug-file "$P/out/e1.txt" --plugin-dir "$P/e1" \
  --model haiku --allowedTools Bash \
  -p "Run the bash command: echo e1probe . Then reply done."
ls "$P/markers/"
```

Baseline 2026-09-19: **both layers fire.** Four markers, in this order:

```text
A-classic-sessionstart  21:04:43.078Z
module session.start    21:04:43.521Z
module tool.call        21:04:46.591Z
A-classic-pretooluse    21:04:46.712Z
```

Decisive debug lines:

```text
[DEBUG] Read hooks.json for plugin spike-e1 (enabled=true): …\hooks\hooks.json
[DEBUG] Loading hooks from plugin: spike-e1
[DEBUG] hooks module spike-e1@inline loaded (worker, environment 1, tier user); events: session.start,tool.call
[DEBUG] plugin.register: spike-e1 (user, spike-e1@inline), judged by core alone: admitted
[DEBUG] hooks module spike-e1@inline tool.call settled in 1256.6ms (worker hop, next() included)
```

The module's `tool.call` marker lands **before** the classic `PreToolUse` marker, so the hooks module
sits above the classic chain and the classic chain runs inside its `next(e)`. That is also why
`settled in 1256.6ms` is large: it wraps the classic chain and the Bash execution.

Pass on rerun: four marker files. Anything fewer means the layers no longer coexist.

**Scope limit that must stay attached.** Issue
[#92675](https://github.com/anthropics/claude-code/issues/92675) reports plugin-native `PreToolUse`
hooks not enforced **in interactive sessions**. This run is headless. A headless pass does not
close that issue; the interactive case is untested and remains open.

## E2 — does a passthrough Bash `tool.call` hook break worktree isolation?

This is the second half of criterion 3. Run it whenever
[#92533](https://github.com/anthropics/claude-code/issues/92533) changes state, and never against a
real repository.

Throwaway repository, created under the OS temp directory:

```sh
D=$(mktemp -d "$TEMP/e2-XXXXXX")
git -C "$D" init -q
git -C "$D" -c user.email=recheck -c user.name=recheck commit -q --allow-empty -m "chore: init"
git -C "$D" rev-parse --show-toplevel
```

The mod is two files. `$P/e2/hooks/hooks.json` is
`{"description": "A pure passthrough tool.call hook matched to Bash", "modules": ["./register.ts"]}`.
`$P/e2/hooks/register.ts` keeps a `session.start` marker hook so the run leaves proof the module
loaded, and adds a bare passthrough — no logic, which is the whole point:

```ts
const DIR = '<P>/markers';

export function register(on: any) {
  on('session.start', async ($: any, e: any, next: any) => {
    await $.fs.write(DIR + '/E2-loaded.txt', 'e2 session.start ' + new Date().toISOString() + '\n');
    return next(e);
  });
  on('tool.call', { tool: 'Bash' }, ($: any, e: any, next: any) => next(e));
}
```

Two arms, identical but for `--plugin-dir`, each to its **own** debug file:

```sh
WT=$(mktemp -d "$TEMP/e2-wtroot-XXXXXX")
PROMPT="Spawn exactly one subagent with the Agent tool using isolation set to worktree, whose whole task is to run the bash command: git rev-parse --show-toplevel  and report its output verbatim. Then run that same command yourself in this session and print both results, labelled SUBAGENT= and PARENT=."

# ARM 1 — with the mod
env -C "$D" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude --debug \
  --debug-file "$P/out/e2-with-mod.txt" --plugin-dir "$P/e2" --model haiku \
  --allowedTools Agent Bash Task -p "$PROMPT"

# ARM 2 — control, no --plugin-dir
env -C "$D" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude --debug \
  --debug-file "$P/out/e2-control.txt" --model haiku \
  --allowedTools Agent Bash Task -p "$PROMPT"

grep -c "blocked shell exec after cwd-override loss" "$P/out/e2-with-mod.txt"
grep -c "blocked shell exec after cwd-override loss" "$P/out/e2-control.txt"
```

Baseline 2026-09-19: **REPRODUCED on Windows at 2.1.278.** Arm 1 returns **2**, arm 2 returns **0**.
Arm 1's subagent returns nothing; arm 2's returns the worktree path. Arm 1's debug file:

```text
[DEBUG] hooks module spike-e2@inline loaded (worker, environment 1, tier user); events: session.start,tool.call
[DEBUG] Created hook-based agent worktree at: …-agent-<id>
[WARN] [worktree] blocked shell exec after cwd-override loss: agentWorktree=…-agent-<id>
[WARN] [worktree] blocked shell exec after cwd-override loss: agentWorktree=…-agent-<id>
[DEBUG] Hook-based agent worktree kept at: …-agent-<id>
```

The reproduction is: arm 1 count greater than 0 **and** arm 2 count equal to 0. A mod whose only
`tool.call` hook is a bare `next(e)` matched to Bash is sufficient — no logic required. The issue was
filed on macOS at 2.1.263 with one independent Windows comment at 2.1.272; this run is a **second**
Windows reproduction, at 2.1.278.

Two limits:

- **The parent session's cwd did not move**, in either arm. The #92533 report's cwd-migration side
  effect is conditioned on the blocked subagent calling `EnterWorktree` to recover; this subagent did
  not, so that half of the report is neither confirmed nor refuted. Exercising it would need a prompt
  that forces the recovery path.
- **Machine-local obstacle, conditional.** If the machine runs a worktree-create gate that refuses a
  worktree root on a different drive from the repository, arm 1 aborts before any worktree exists,
  with a `WorktreeCreate … completed with status 1` line. Clear it per process, writing no settings
  and no git config file, by supplying the root through git's environment-config channel
  (`GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=worktreeroot.path GIT_CONFIG_VALUE_0="$WT"`), and carry it
  **identically in both arms** so it cancels out. Skip this entirely on a machine with no such gate.

Clean-up: both arms leave a locked worktree under `$WT`. Remove with
`git -C "$D" worktree remove --force <path>`, or delete the two temp directories.

## E3 — `/plugin-types` end to end

**NOT RUN, and not runnable headless.** `-p "/plugin-types"` is not resolved as a command on 2.1.278:
the literal string reaches the model as an ordinary prompt, which answers it as prose, and nothing is
written. The debug log contains no command-resolution line for it at all, and `find` over the working
directory afterwards returns nothing.

The binary registers `plugin-types` with kind `"action"`, the same family as `reload-plugins`,
`reload-skills` and `rename` — local REPL actions — and its own remediation text says to "run
`/reload-plugins`, then `/plugin-types` again", which is interactive phrasing.

Two binary strings a future interactive run should settle, because they are source claims and one of
them contradicts the corpus:

1. Output location: `.claude/types/claude-code.d.ts`, plus `.claude/types/claude-code-plugins.d.ts`
   and `.claude/types/claude-code-plugins/<plugin>.d.ts`, relative to the session's working directory.
2. **Per-plugin contracts are claimed to be emitted in 2.1.278** — the string says `/plugin-types`
   "copies each enabled plugin's contract to `.claude/types/claude-code-plugins/<plugin>.d.ts` and
   indexes them". That is the opposite of the `mods/README.md` sentence saying the include goes away
   only *once* the engine writes those contracts. **Unresolved.** Either the README is stale, or the
   string documents the `types` manifest key's intent rather than shipped behaviour.

Rerun, requiring a human at a terminal:

```sh
cd <an empty dir>
CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude --plugin-dir <a mod that declares "types">
# at the prompt:
/plugin-types
# in another shell:
find <that dir>/.claude/types -type f
```

Record whether `claude-code-plugins/` exists and what it contains.

## E4 — `claude plugin validate` over mod-shaped plugins

Question: what does `validate` do with the variable set and unset, with two `modules` entries, and
with both `hooks` and `modules` in one file?

Fixtures: the criterion-1 probe (`modules` only), the E1 probe (`hooks` **and** `modules`), and a
two-entry fixture whose `hooks.json` is:

```json
{
  "description": "Two modules entries",
  "modules": ["./register.ts", "./register2.ts"]
}
```

Command:

```sh
for d in mod e1 fx-two; do
  for arm in set unset; do
    echo "===== $d / env=$arm ====="
    if [ "$arm" = set ]; then
      env CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude plugin validate "$P/$d"
    else
      env -u CLAUDE_CODE_ENABLE_FUNCTION_HOOKS claude plugin validate "$P/$d"
    fi
    echo "EXIT=$?"
  done
done
```

Baseline, re-confirmed on 2026-09-19 with the criterion-1 probe and a two-entry fixture. A
single-module plugin, both arms byte-identical:

```text
  ❯ ./register.ts hooks: session.start
  ❯ ./register.ts calls: $.fs.write
✔ Validation passed
EXIT=0
```

Two `modules` entries, both arms byte-identical:

```text
✘ Found 1 error:
  ❯ modules: hooks.json `modules` names one hooks module per plugin; a second entry is refused
✘ Validation failed
EXIT=1
```

Four findings:

1. **`validate` is not gated by `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`.** Output and exit code are
   identical with the variable set and unset, for every fixture, including the module-source scan.
   That is the opposite of `claude plugin test`, which is not even registered as a subcommand without
   the variable (`error: unknown command 'test'` / `(Did you mean list?)`). **Validate is usable in
   CI with no gate.**
2. Two `modules` entries are refused, exit 1, with the message quoted above. This confirms the
   one-module rule from a live CLI rather than from binary strings.
3. `hooks` and `modules` in one file validate clean, exit 0.
4. **Sharp edge.** With both present, validate prints the module's `hooks:` and `calls:` lines and
   **nothing at all about the classic `hooks` block** — no listing, no count, no acknowledgement. A
   reviewer reading validate output on a coexistence plugin sees half of what the plugin will do. The
   classic block is parsed (a malformed one fails validation); it is simply not reported when it is
   well formed.

Pass on rerun: `EXIT=0` four times and `EXIT=1` twice, with identical bytes across each `set` /
`unset` pair.

## E5 — what a mod's handler receives

Question: does a `prompt.context` hook receive the text of instruction files?

**Yes, and more than the project's own instructions.** Recorded 2026-09-19: a third-party hooks
module loaded from `--plugin-dir` at tier `user`, whose `prompt.context` hook dumped its input and
the value returned by `next(e)`, received in plaintext on the first prompt of the session, before the
model was called:

- **Every instruction file's full text**, as an `instructionFiles[]` array carrying each file's
  absolute path, its `kind`, and its `content` — the text as loaded, comments and frontmatter already
  stripped. In that run the array held four entries: the **user's private global `CLAUDE.md`** at
  kind `user` (5,957 characters), two project-scope files from the repository the session was near —
  one of them a rules file pulled in by a parent instruction file rather than named directly — and
  the working directory's own `CLAUDE.md`.
- The **fully rendered `claudeMd` block** as the model will see it (7,983 characters), opening with
  the engine's own preamble and then the user-global file in full.
- A **`userEmail` block** (272 characters) carrying the account's email address.
- A `currentDate` block.

A unique token planted in the working-directory `CLAUDE.md` appeared twice in the input dump (once
inside the rendered block, once inside that file's `content`) and twice in the value returned by
`next(e)`, so a mod can both **read and rewrite** the instructions the model sees.

The `parent` field was absent on all four entries; no `@`-import chain was exercised.

**The consequence to carry forward.** "A mod can read your `CLAUDE.md`" understates it. A handler
gets the user-global instruction file — which on a developer machine routinely carries private
operational detail — and the account email, on the first prompt of every session, before the model
is called. Any review posture for third-party mods has to treat `prompt.context` as an exfiltration
surface. That `$.http` is reachable from the same worker is a corpus claim from the declarations'
noun list, not something this experiment exercised.

Rerun:

1. Create an empty working directory with a `CLAUDE.md` containing one unique token.
2. Build a probe under `$P/e5/`, `modules`-only, whose `register.ts` is:

   ```ts
   const DIR = '<P>/markers';

   export function register(on: any) {
     on('prompt.context', async ($: any, e: any, next: any) => {
       const dump = (label: string, v: any) => {
         try {
           return label + ' keys=' + JSON.stringify(Object.keys(v ?? {})) + '\n' + JSON.stringify(v, null, 2) + '\n';
         } catch (err: any) {
           return label + ' THREW ' + String(err) + '\n';
         }
       };
       await $.fs.write(DIR + '/E5-input.json', dump('input', e));
       const r = await next(e);
       await $.fs.write(DIR + '/E5-result.json', dump('result', r));
       return r;
     });
   }
   ```

3. Run `claude --debug --plugin-dir "$P/e5" -p "reply with the single word ok"` with the variable
   set, from that directory.
4. Grep both markers for the token. Baseline: **2** hits in each. `E5-input.json` opens
   `input keys=["blocks","instructionFiles"]`.

Redact before recording anything: the dumps contain the account email and the full text of every
instruction file on the machine. Record lengths, kinds and counts, never contents.

## E6 — latency per fire

Question: what does one trivial hook cost per fire as (a) a classic `node` command hook, (b) a
classic `bash` command hook, (c) a mod `tool.call` passthrough?

Read the method before the numbers.

- `claude --debug` emits **no per-hook duration for classic command hooks**. So the design is paired
  arm-versus-control on the same machine, and the reported cost of a mechanism is the **difference
  from the control**, not an absolute.
- The measured window, `chainWindowMs`, runs from the first `Skipping hook due to if condition` line
  of a Bash call's `PreToolUse` chain to that call's `[Stall] tool_dispatch_start`. It excludes model
  latency and the tool's own execution.
- `hooks module X tool.call settled in Nms` is **not** comparable to `chainWindowMs`. It is stamped
  after `[Stall] tool_dispatch_end` and after the classic `PostToolUse` chain, so it wraps the
  pre-chain, the permission decision, the tool and the post-chain. Arm (c) is analysed by decomposing
  `settled` into independently measured components and asking what is left over.

Arms: (a) a classic `PreToolUse` command hook running `node` on a file whose whole body is one
`process.stdout.write`; (b) the same shape running `bash` on a file whose whole body is `echo`;
(c) the E2 bare-`next(e)` module; control loads no `--plugin-dir`.

Arm (c) reuses `$P/e2` from
[E2](#e2--does-a-passthrough-bash-toolcall-hook-break-worktree-isolation). Arms (a) and (b) are
three files each, reconstructed here to the descriptions above — like the parser below, the
2026-09-19 originals were machine-local and not committed, so the medians are the shape to
reproduce, not bytes to match. The loop will not find the two directories otherwise:

```sh
mkdir -p "$P/e6a-node/.claude-plugin" "$P/e6a-node/hooks" \
         "$P/e6b-bash/.claude-plugin" "$P/e6b-bash/hooks"
```

`$P/e6a-node/.claude-plugin/plugin.json`, and the same with `e6b-bash` twice over for arm (b):

```json
{ "name": "e6a-node", "version": "0.0.1", "description": "E6 arm (a) latency probe",
  "author": { "name": "e6" } }
```

`$P/e6a-node/hooks/hooks.json`, and for arm (b) the same with `bash` and `probe.sh`:

```json
{
  "description": "E6 arm (a)",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/probe.js\"",
          "timeout": 60 } ] }
    ]
  }
}
```

The probe bodies, one statement each so the arm measures the mechanism and not the work.
`$P/e6a-node/hooks/probe.js` is `process.stdout.write('{}');` and `$P/e6b-bash/hooks/probe.sh` is
`echo '{}'`. Neither needs an exec bit — both are invoked through their interpreter. Inside this
repository the `guardrails` plugin refuses shell file-writes, so create all six files with the
editor or the Write tool.

```sh
PROMPT="Run the Bash tool exactly 20 times, one call at a time and never in parallel, each with the command: true . Then reply done."

env -C "$P/work" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude --debug \
  --debug-file "$P/out/e6-control.txt" --model haiku --allowedTools Bash -p "$PROMPT"

for arm in a:e6a-node b:e6b-bash c:e2; do
  n=${arm%%:*}; d=${arm##*:}
  env -C "$P/work" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude --debug \
    --debug-file "$P/out/e6-arm-$n.txt" --plugin-dir "$P/$d" \
    --model haiku --allowedTools Bash -p "$PROMPT"
done

grep -c 'tool_dispatch_start tool=Bash' "$P/out/e6-control.txt"
```

Each run must produce exactly 20 `tool_dispatch_start tool=Bash` lines, or N is not 20.

Extracting the numbers needs a small parser keyed on three anchor lines — `Skipping hook due to if
condition`, `[Stall] tool_dispatch_start` / `tool_dispatch_end`, and `tool.call settled in` —
reporting the median and maximum of `chainWindowMs`, the hook count inside that window, the
permission time, the tool duration, and for arm (c) `settled` and the gap between `settled` and
`tool_dispatch_end`. The 2026-09-19 parser was machine-local and is not committed; rewrite it from
those anchors or read the medians by hand.

Baseline medians, N = 20 per arm:

| Arm | `chainWindowMs` median / max | hooks in window | Cost of the probe, per fire |
|---|---|---|---|
| control | 162.0 / 319.0 | 2 | baseline |
| (a) classic `node` | 221.5 / 354.0 | 3 | **about +60 ms** |
| (b) classic `bash` | 174.5 / 256.0 | 3 | **about +12 ms** |
| (c) mod passthrough | 180.5 / 355.0 | 2 | see decomposition |

Arm (c)'s median `settled` was 333.9 ms, decomposing as pre-chain 180.5 plus permission 6.0 plus
tool 95.5 plus post-chain gap 57.0 = 339.0 against an observed 333.9, a residue of −5.1 ms. **No
measurable residue is left for the module's own per-fire cost.** Arm (c)'s maximum, 1,943.8 ms, is
the session's first dispatch — the one-off worker start; the next two dispatches settled in 332.4 ms
and 408.5 ms.

Verdict on this machine, at 2.1.278, for a trivial hook, per fire: a classic `node` hook costs about
60 ms (process spawn dominates), a classic `bash` hook about 12 ms (Git Bash already warm), and a mod
`tool.call` passthrough less than this method can resolve, after a one-off worker start of about
1.5 s. The resolution floor is about ±19 ms — arm (c)'s pre-chain window ran 18.5 ms above the
control's while containing the same two hooks, which is nothing the mod did.

So after its one-off worker start the mod is cheaper per fire than a classic `node` hook and
indistinguishable from a warm classic `bash` hook. The measurement **does not** support "faster than
bash", only "not slower".

**Disagreement with the indexed third-party figure.** claudefa.st argues Windows gains most from mods
because there is no shell in the execution path, citing about 90 ms of process-spawn latency on
Windows for classic bash hooks. This run measured about **12 ms** for the same mechanism, seven times
cheaper, and `bash` was the cheapest classic arm here rather than the bottleneck. Different machines,
different methods, and neither is a benchmark — record the disagreement, do not pick a winner, and do
not build a performance argument for adoption on either number.

Honest limits, restated because they are larger than some of the effects: one session per arm, one
machine, `true` as the command, pre-existing classic hooks in every run, and arm (c)'s number
obtained by decomposition rather than read directly. The ±19 ms floor is larger than arm (b)'s whole
effect, so treat the `bash` number as an order of magnitude.

## Open probes a rerun should try to close

### Claude Desktop

Unanswered: does Desktop's Code tab load a **user-authored** mod? Desktop is not this repository's
primary audience, so this stayed a manual probe. It is worth running if a consumer reports using
these plugins mainly through Desktop.

There is **no documented way to point Desktop at a local plugin directory** — `--plugin-dir` has no
Desktop equivalent. The route below works only because Desktop and the CLI read the same
configuration: settings in `~/.claude.json` and `~/.claude/settings.json` are shared, so a plugin
installed at user scope by the CLI is visible to Desktop local sessions. If the probe comes back
negative, that shared-configuration premise is one of the things that could be wrong, not only the
mods gate.

The procedure, by hand:

1. Build the criterion-1 probe mod, then wrap it in a throwaway local marketplace: a sibling
   directory holding `.claude-plugin/marketplace.json` with a `name`, an `owner`, and one `plugins`
   entry naming the probe by relative path. Confirm both pass `claude plugin validate`.
2. Install it at user scope from a normal terminal, and confirm it is listed and enabled:

   ```sh
   claude plugin marketplace add <marketplace dir>
   claude plugin install go-no-go-probe@<marketplace name>
   claude plugin list
   ```

3. Turn function hooks on for the Desktop process. Two documented levers; prefer the first. (a)
   Desktop's own environment editor: open the environment dropdown in the prompt box, hover over
   **Local**, click the gear, and add `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = 1`. (b) The `env` key in
   `~/.claude/settings.json`, which is user-global and affects the CLI too — undo it afterwards.
   That either route actually reaches the Desktop-bundled CLI process is **inference, not
   documented**, and is one of the two things the probe tests.
4. Fully quit Claude Desktop, tray icon included, and start it again. Environment variables and
   plugin enablement are read at session start.
5. In the Code tab open a **local** session, not a cloud session — the plugin browser and locally
   installed plugins are documented as unavailable in cloud sessions. Any folder. Send one message.
6. Check the marker file.

Reading the result: marker present and newer than the probe run means **loads**. No marker but the
plugin listed means **does not load**, a negative with three causes the probe cannot separate —
Desktop's bundled CLI may predate hooks modules (find its version under Settings, About), the
variable may not reach that process, or the session may have been a cloud session. Narrow it before
reporting, and cross-check that the same plugin loads in the CLI on the same machine. No marker and
the plugin not listed means the install did not take: nothing about Desktop was tested.

Undo: uninstall the plugin, remove the marketplace, remove the environment variable from whichever
lever was used, delete the temp directory.

### Team and Enterprise rollout state

No Team or Enterprise account was available, so the rollout-switch question is unanswered: whether an
organisation can turn `tengu_plugin_hooks_modules` on for its members, and whether managed settings
expose it. Related and equally unexercised: `prependPlugins`, the managed-settings key that changes
seating, which is implemented in 2.1.278 but has zero issue-tracker hits and is undocumented. Revisit
if such an account becomes available.

### Interactive `/plugin-types`

E3 above. Needs a human at a terminal, and settles the contradiction between the binary's own string
and `mods/README.md` about per-plugin contracts.

### Interactive #92675

E1 shows classic hooks and a hooks module coexisting and both firing **headless**. #92675 reports
plugin-native `PreToolUse` hooks not enforced **interactively**. Reproducing it needs an interactive
session with a plugin-native `PreToolUse` hook and a tool call that should trip it. Until then the
coexistence story holds only for the headless path.

### Adjacent open defects

Three more issues were OPEN on 2026-09-19. None gates the verdict; each would change what a mod
written here could rely on.

```sh
for n in 92469 92440 95328; do
  gh issue view "$n" -R anthropics/claude-code --json number,state,stateReason
done
```

[#92469](https://github.com/anthropics/claude-code/issues/92469) and
[#92440](https://github.com/anthropics/claude-code/issues/92440) are generated-type incompleteness
and drift: the declarations `/plugin-types` writes already omit events the engine's own load line
lists, and a doc comment already disagrees with the type beside it.
[#95328](https://github.com/anthropics/claude-code/issues/95328) is a `session.compact` hook's
compaction undone on resume.
