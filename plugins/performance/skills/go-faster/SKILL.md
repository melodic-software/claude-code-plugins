---
description: "Sweep the whole AI-assisted development process for ways to go faster without losing accuracy: this session's work, git, hooks and the rest of the setup. Runs in the background, returns evidenced findings ranked by measured size, and offers speedups this session can adopt now. Edits no repository file or setting. Use when: 'go faster', 'how can we go faster', 'speed up this session', 'what is slowing us down', 'whole-process speed sweep'. Skip: ranking candidates already in hand is /performance:target."
user-invocable: true
argument-hint: "[unattended]"
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Whole-process speed sweep with evidenced, ranked findings and adopt-now speedups
---

**Arguments.** `[unattended]`. e.g. /performance:go-faster, or /performance:go-faster unattended
from a scheduled run.

## Purpose

Answers **"where is time going, across everything, and what can we change without losing
accuracy?"** A background sweeper checks each area of the process, current state first and then
the session so far, and returns one report: measured findings ranked by size, unmeasured candidates
in their own list, guards flagged for you only, and every area it could not check with the reason.

`now` findings change only how this session works and are offered item by item as soon as the report
lands. `later` findings go to the skill that owns the fix, or to steps for you.

The finding rules, ranking and lock live in `${CLAUDE_PLUGIN_ROOT}/scripts/findings.py`; the
per-area checks live in [reference/areas.md](reference/areas.md), walked by the
`go-faster-sweeper` agent, and the evidence rows they cite in
[reference/catalog/README.md](reference/catalog/README.md).

## Step 1: Resolve paths and take the lock

Resolved when this skill loaded:

```!
( source "${CLAUDE_PLUGIN_ROOT}/scripts/harness-lib.sh" && harness_require_python && echo "PY=$HARNESS_PYTHON" ) || echo "PY=unresolved"
echo "KEY=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh" || echo unresolved)"
echo "TRANSCRIPT=$(ls "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"${CLAUDE_SESSION_ID}.jsonl" 2>/dev/null | head -1 || true)"
```

If those lines reached you as literal commands, run them yourself with Bash. `PY=unresolved` means
no Python runs here, and `KEY=unresolved` means no hash tool: stop and say which. An empty `TRANSCRIPT` is `none`.

`DATA` is `${CLAUDE_PLUGIN_DATA}/go-faster/<KEY>`, spelled out literally in every later command.
Then take the lock, one sweep per repository and worktree:

```bash
"<PY>" "${CLAUDE_PLUGIN_ROOT}/scripts/findings.py" lock acquire --data "<DATA>" --session "${CLAUDE_SESSION_ID}" --invocation "go-faster $ARGUMENTS"
```

Exit 1 means a sweep is already in flight: print its line and stop. Start nothing else. If
`${CLAUDE_SESSION_ID}` reached you unexpanded, use `unknown` as the session and pass `TRANSCRIPT`
as `none`.

## Step 2: Where the session is

With a transcript, run `"<PY>" "${CLAUDE_PLUGIN_ROOT}/scripts/findings.py" transcript-counts
"<TRANSCRIPT>"`. `EVIDENCE` is `true` when `work_before_invocation` is 1 or more: the session made
tool calls before this sweep was invoked, whether by the slash command or by a prompt that
triggered it. Otherwise this is a fresh session: say "No session evidence yet:
setup scan only." and continue with `EVIDENCE` false.

## Step 3: Start the run and dispatch the sweeper

```bash
"<PY>" "${CLAUDE_PLUGIN_ROOT}/scripts/findings.py" run-start --data "<DATA>" --session "${CLAUDE_SESSION_ID}" --mode <attended|unattended> --session-evidence <true|false>
```

It prints `RUN`. Dispatch the `performance:go-faster-sweeper` agent with a prompt carrying `PY`,
`ROOT` (`${CLAUDE_PLUGIN_ROOT}`), `RUN`, `DATA`, `SESSION`, `TRANSCRIPT`, `MODE` and `EVIDENCE`,
each on its own line. `MODE` is `unattended` when the argument says so, else `attended`.

- **Attended**: an interactive session runs the sweeper in the background. Tell the user in one
  line that the sweep is running, and carry on with the work in hand. Present at the next natural
  break after the sweeper returns, never mid-task.
- **Unattended**: wait for the sweeper's result before doing anything else.

Background and foreground behavior is the harness's choice, not a parameter you set:

- **Pointer**: [Run subagents in foreground or background](https://code.claude.com/docs/en/sub-agents#run-subagents-in-foreground-or-background)
- **As of**: 2026-10-03
- **Recheck trigger**: that section changes which sessions run a subagent in the background.

If the sweeper fails or returns `write-denied`, release the lock (Step 4) and report what it said.

## Step 4: Present and release

Read `<RUN>/report.md` and show it. Then, always, including after a failure or an abort:

```bash
"<PY>" "${CLAUDE_PLUGIN_ROOT}/scripts/findings.py" lock release --data "<DATA>" --session "${CLAUDE_SESSION_ID}"
```

Unattended stops here: print the report path. The findings wait in the data folder for a person, and
nothing is adopted.

## Step 5: Adopt now

When the report has an "Adopt now" section, ask about each item in your reply, one numbered line
per item, and take a yes or no for each. For every yes:

```bash
"<PY>" "${CLAUDE_PLUGIN_ROOT}/scripts/findings.py" adopt --data "<DATA>" --session "${CLAUDE_SESSION_ID}" --findings "<RUN>/findings.json" --id <id> --route-taken <route>
```

`--route-taken` is the finding's suggested route unless the user names the other one; the record
notes an override. Then state the behavior change you follow from here on, its guard, and when you
check it. Stop following an adoption the moment its `revert_if` reading appears, and say so.

Adoptions outlive a compaction only on disk. After a compaction, re-read them with
`findings.py adopted --data "<DATA>" --session "${CLAUDE_SESSION_ID}"`; an adoption whose guard you
can no longer check has expired. Carry adopted items into every subagent brief you write.

Later findings: name each one's owner skill or steps. A speedup worth a numbered target goes through
the performance chain; the next go-faster run re-measures the rest, and `findings.py compare`
reports `cannot-quantify` when the conditions differ.

## Boundary

- **Edits no repository file or setting.** It writes only its own data folder, through findings.py.
- **Applies no fix.** A `later` finding goes to its owner; a `now` finding changes only how this
  session works, and only after a yes.
- **Never removes or weakens a check.** That is `/overengineering:audit`'s to judge.
- **Does not root-cause a failure.** A specific broken behavior is a debugging task.

## Next

- A measured `later` finding worth a numbered target: /performance:goal <the finding's key>.
- A dropped or weakened check: /overengineering:audit.
- Slow hooks or a slow Claude Code install: /harness-ops:audit-performance.
- Candidates you already hold, to rank by evidence: /performance:target.

## Gotchas

- **A `now` adoption is a promise to watch its guard.** If you cannot say when you will check it,
  decline the item.
- **The second invocation is not a second sweep.** It reports the run in flight. A lock whose
  heartbeat is over 60 minutes old is stale and replaced.
- **Timings taken while the session works are contended.** The sweeper labels them tier E3; an
  unattended run gives the cleaner number.
