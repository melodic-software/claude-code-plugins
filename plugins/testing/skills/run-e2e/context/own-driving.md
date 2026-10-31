# Own driving

Loaded when SKILL.md Step 1 picks own driving: app-control does not drive this run, so this skill
launches, operates and captures itself. Prerequisites, Resolve run config and the browser-driver
check in Drive run first, in that order, before the drive subagent is dispatched; a stop in any of
them dispatches no subagent and opens no browser session. The drive subagent runs the rest. The
three commands that carry the run's settings stay in SKILL.md, under "Own driving", because only
that file expands the values they need; the steps below name them.

## Contents

- Prerequisites
- Resolve run config
- Native step: run (bundled skill)
- Drive
- Workspace environment
- Session names
- Control skill on this path
- Teardown

## Prerequisites

Check tool availability per the prerequisite matrix in [e2e.md](e2e.md). When the consuming project names a prerequisite orchestrator tool/MCP, its absence hard-fails: STOP and report what's missing and how to fix it. Attempt no workaround: a substitute path produces unverified pass/fail results, defeating live verification.

On a hard-fail, before stopping, write a structured verification-environment gap report to the run's evidence output: what is missing (each key, CLI, MCP, or environment the run needs) and what the operator must provide to make the run possible. The STOP still holds; the report gives the operator a precise list to supply instead of a bare failure.

## Resolve run config

Five keys govern this path: `recording` (`video | gif | off`), `browser_mode` (`headed | headless`), `e2e_driver` (`auto | harness | run | playwright | chrome`), `reuse_running_instance` (`auto | true | false`) and `browser_driver`. [e2e-config.md](e2e-config.md) owns their surfaces, definitions, defaults, and precedence. Resolve them before driving, and report which layer supplied each effective value:

- `recording` and `browser_mode`: anchor at the repo root, read every layer of `.claude/testing/e2e.md` that exists (user-global, team, local overlay), and merge the two keys per key. The generic layer mechanics (anchoring, reading every layer, provenance, soft-degrade) are the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/contracts/config-cascade/README.md)'s; this step names only the surface path, the keys, and the per-key merge.
- `e2e_driver` and `reuse_running_instance`: run SKILL.md's resolve command (Own driving) as one Bash call. It prints one line per key, `<key> <tab> <value> <tab> <source>`, the source
  being the file that set it, `userConfig`, or `default`, and names on stderr any value it
  rejected. Use the printed values; a rejected value has already resolved to the default.
- `browser_driver` (the command name of the browser tool a `playwright` drive uses, default
  `playwright-cli`): run SKILL.md's browser-driver resolve command as a separate Bash call and use its
  `browser_driver` line, `<key> <tab> <value> <tab> <source>`;
  the other lines it prints repeat the call above. [e2e-config.md](e2e-config.md) owns the key.
- An explicit instruction in the session prompt overrides every layer for that run; the keys are defaults only. The precedence ladders are in [e2e-config.md](e2e-config.md).

## Native step: run (bundled skill)

When the bundled `run` skill resolves in this session, the drive subagent invokes it through
the Skill tool as `run`, asking it only to launch the app and report how to reach it (URL, port,
process). Driving, prerequisites, run config, evidence and handoff stay with this skill:
screenshots, responses and logs are layered on `run`'s result under the evidence contract in
[e2e.md](e2e.md). The step runs only under the
one-launch-path rule in SKILL.md's Boundary section: it is skipped when the project's orchestrator governs
the start, when the app is already running, and on the non-UI route, where there is no app to
launch.

**Identity check.** The name is in the skill listing; the description is advisory. A listed `run`
that reads as a project skill is not a skip: the bundled skill itself defers to a project skill of
that name ([bundled-run.md](bundled-run.md)). A description that reads as an
unrelated surface is an identity mismatch: skip with a warning and use this skill's own launch
playbook. A name with no description (`name-only`, listing-budget overflow) is invoked with the
warning "identity confirmed by name alone".

**Mutation.** `run` starts processes rather than editing files. The drive subagent saves
`git diff HEAD` to a scratch file outside the tree immediately before and after the invocation, as
individual Bash calls, and compares the two files with `cmp`. Any difference is **mutation detected
after a scoped invocation**: the run exits degraded and the report names the paths whose
`diff --git` section differs between the files. A path that was already dirty and is unchanged is
not named.

**Already running.** [e2e.md](e2e.md) requires a running app; on this path the launch meets that
requirement, so Prerequisites does not stop on a missing app. Before invoking `run`, or
before `up` when a Workspace environment entry exists, the drive subagent probes the URL or
port the scenario or the project's documented start command names. The scenario is free-form input,
so the target is used only when it is a bare
`http://` or `https://` URL on `localhost` or `127.0.0.1`, or a bare port number, with no
whitespace or shell metacharacters; the subagent passes it as one quoted argument
(`curl -fsS --max-time 5 "<url>"`, or a connect to the port). Any other value is not probed. A
response means an app is already answering, and the resolved `reuse_running_instance` (Resolve run
config), with whether origin's default branch declares a Workspace environment entry, decides:

| `reuse_running_instance` | Entry | What the run does |
|---|---|---|
| `true`, or `auto` on an attended run | either | drives that app and starts nothing, so no second instance runs; an `unattended` run labels its evidence "instance not started by this run" |
| `auto` on an `unattended` run | none | drives that app, evidence labeled "instance not started by this run" |
| `auto` on an `unattended` run, or `false` in either mode | declared | starts its own instance: runs `up`, then `info`, and drives the URL `info` reports, never the app that answered |
| `false` | none | stops with the gap report naming the collision (the running app, its URL or port, and the setting) |

An instance this run did not start is never driven on the own-instance row: when `info` reports the
address that answered before `up`, the run cannot tell its instance from the other, and it stops with
the gap report naming the collision. No usable target, or no response, means not running and the
step proceeds.

**Skip report.** When the step does not run, or runs and cannot be trusted, the state names why:
`did not resolve in this session`; `invocation refused (<reason>)`, never retried (not in the
session's skills allowlist, `disableBundledSkills`, `skillOverrides`, or a permission deny);
`identity mismatch`; `mutation detected after a scoped invocation`; or `resolved but degraded`
when `run` says it ran a weaker procedure, in which case the report relays its disclosure instead
of calling the launch complete. Each state names the axis line:
settings or environment, plan, platform or provider, host surface; and the enable path
(`disableBundledSkills`, `skillOverrides`). Every skip falls back to this skill's own launch playbook, the project's
documented start command per [e2e.md](e2e.md); mutation detected exits degraded
instead of launching a second time.

The `run` body enters context once and stays there.

**Result block.** The drive subagent's evidence output carries this block after the Route block,
whichever state the step ended in:

```text
Native step: run
State: ran | resolved but degraded (<disclosure>) | did not resolve in this session (<axis>) | invocation refused (<reason>) | identity mismatch | skipped (unattended | orchestrator governs the start | non-UI route | app already running) | mutation detected after a scoped invocation
Outside-scope changes: none | <paths>
```

**`--unattended`:** never invoke `run`; this skill's own launch playbook runs, and the result block
records `State: skipped (unattended)` without asking.

## Drive

The launch, on whichever path the one-launch-path rule in SKILL.md's Boundary section selects,
happens inside the drive subagent, and the evidence output it returns carries the Native step
result block.

Before dispatching the drive subagent, once the driver for the run is known: when it is `playwright`, whether
`e2e_driver` pins it or `auto` picks it, run SKILL.md's browser-driver check
as one Bash call. It exits non-zero when the resolved `browser_driver` command is not on PATH, and
its message names the setting, the value, where the value came from, and the two ways forward
(install that tool, or set `browser_driver` to a browser tool you have). On a non-zero exit, STOP
before driving anything and write the gap report from Prerequisites with that message. No other
browser tool is a silent substitute, and the run never switches tools partway through.

Pass the resolved config through to the executor:

- `browser_mode` → the `/playwright:playwright` session invocation. The executor owns the headed/headless flag spelling; `run-e2e` supplies the resolved value.
- `recording` → the capture path: `video` records via the playwright CLI, `gif` via `gif_creator`, `off` keeps the evidence-contract screenshots as the floor.
- `e2e_driver` → what drives the flows, picked per the Driver ranking in [e2e.md](e2e.md). A pinned value the target cannot use, and `chrome` on an `unattended` run, stop with the gap report instead of switching drivers. When the app has a control skill, the driving tool its hub names comes before `e2e_driver`; only a session instruction overrides it ([Control skill on this path](#control-skill-on-this-path)).

The workflow steps themselves live in [e2e.md](e2e.md). When the project has a committed E2E user-flow suite, the subagent runs it first and its pass or fail is the verdict; the ad-hoc drive and screenshots are evidence beside it, never the oracle. Each failed scenario returns a failure packet path with the evidence paths.

## Workspace environment

When origin's default branch declares a "Workspace environment" entry
(`docs/conventions/workspace-environment.md` in the consumer; contract:
`docs/contracts/workspace-environment/README.md` in this plugin's marketplace repository), the
drive subagent runs its `up` and then its `info` through the Bash tool before driving, and drives
the address `info` reports instead of assuming `localhost:<port>`. The entry is read from the
fetched default-branch commit, never the working tree. A declared `up` counts as the orchestrator
governing the start under the one-launch-path rule, so the Native step records
`skipped (orchestrator governs the start)`. When an app already answers before `up`, the Already
running table in the Native step decides whether the run reuses it or starts its own instance.
Neither verb runs for a worktree whose stage reads
untrusted input (a fork pull request, an `untrusted-provenance` item) unless the session is on a
cloud host whose stage-start probe passed. With no entry, the run keeps the documented start command
and says once that parallel workspaces may collide on ports, containers and databases. Procedure:
[e2e.md § Workspace environment](e2e.md#workspace-environment).

## Session names

The drive subagent makes one run id when the run starts: the UTC time as `YYYYMMDDHHMMSS`, a `-`,
and four random hex digits (`20261004153012-7f3a`). Every browser session the run opens is named
`[<workspace part>-]<run id>-<scenario part>`, built with this slug rule:

1. Lower-case the text.
2. Replace each run of characters outside `a-z0-9` with a single `-`.
3. Drop any `-` at the start or end; an empty result becomes `run`.
4. Cut the result to 64 characters.

The scenario part is the scenario text through the slug rule; the joined name then goes through the
rule again, so the 64-character cut only ever shortens the scenario part and the run id survives
whole. Every name matches `^[a-z0-9-]{1,64}$`. Scenario `Checkout: apply coupon & pay` becomes
`<run id>-checkout-apply-coupon-pay`. The subagent composes the name itself: the raw scenario text
never reaches a shell, and only the finished name is passed, quoted, as `-s='<name>'`.

When the run has a `WORKSPACE_ID` (a Workspace environment entry ran), the name starts with
a workspace part, so runs in different worktrees never share a session name. `WORKSPACE_ID` is
untrusted text: it goes through the slug rule and is then cut to 24 characters before it is joined,
and the joined name goes through the slug rule's 64-character cut as before, which still shortens
only the scenario part, so the run id survives whole. `WORKSPACE_ID` `Feature/ABC 12;x` gives the
workspace part `feature-abc-12-x`. Like the scenario text, the raw value never reaches a shell; only
the finished name is passed. With no `WORKSPACE_ID` the name has no workspace part.

## Control skill on this path

When the app has a control skill (SKILL.md, Feature map) and this path runs anyway, because the
person declined drive or app-control is not installed, the drive subagent reads its hub (from
`<dir>` alone when the run has `trusted-root=<dir>`, never from the checkout; SKILL.md, Feature
map) and:

1. Runs the hub's `## Ready` command before the first drive. A Ready that fails is an environment
   failure: report it with its output, and drive nothing.
2. Drives with the hub's driving tool unless the session prompt names another: as that `e2e_driver`
   value when the tool is one, otherwise through the tool or the hub's `cli/` commands. A hub marked
   `Attended runs only.`, or naming a driver that runs the person's own signed-in browser, stops an
   `unattended` run with the gap report.

## Teardown

Teardown closes each session this run opened, by its name (`playwright-cli -s='<name>' close`), and
stops only processes this run started. Never `close-all` or `kill-all`: another run, worktree or
person on the machine may own live sessions. A session that will not close is reported
by name; recovery is the playwright skill's "Recover from stale sessions" step, not part of the run.

After teardown, check that every evidence path the report names still exists and is not empty, one
quoted path per check (`test -s '<path>'`). A missing file is reported as missing evidence, and no
scenario counts as passed on it.
