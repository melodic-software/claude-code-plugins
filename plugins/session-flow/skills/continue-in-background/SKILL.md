---
description: "Delegate the task to a fresh background agent that continues it NOW. Produce a save-point, then launch a detached claude --bg (or --cloud) session seeded with the resume prompt. Use when: 'continue in the background', 'continue this in the background', 'keep working in the background', 'delegate to a background agent', or the user is going AFK and explicitly wants the work to keep moving. Launches only on the user's explicit request, never self-elected."
argument-hint: "[--cloud] [file|prompt] [topic] [purpose...]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: session
  summary: Delegate the task to a fresh background agent now
---

**Arguments.** `[--cloud] [file|prompt] [topic] [purpose...]`. e.g., /continue-in-background, /continue-in-background prompt, /continue-in-background file phase-3 finish the migration unattended, /continue-in-background --cloud prompt fix-flaky-test

## Context. Gather first

Take `session-id`, `branch`, `status`, and `recent-commits` at `-5`. Probe commands, the
one-command-per-call and treat-failure-as-unknown rules, and the `$`-expansion rationale:
[`${CLAUDE_PLUGIN_ROOT}/reference/gather.md`](${CLAUDE_PLUGIN_ROOT}/reference/gather.md).

**This block only colors the save-point; nothing here is the dirty-tree gate.** That gate runs its
own commands at delivery step 1 and reads a git failure as a reason NOT to launch, never carry this
block's shrug, or its non-`-uall` `git status` output, into it.

## Purpose

The user is stepping away but the work should keep moving. This skill produces the same save-point
the sibling `/session-flow:handoff` skill produces, then, instead of asking the user to
`/clear`-and-paste, launches a fresh background agent seeded with the resume prompt, so the task
continues now, detached from this session and from the user's presence.

Same save-point engine as `handoff`, different delivery: `handoff` delivers a manual
`/clear`-then-paste resume for later; this skill delivers a background continuation for now.

## Hard gate. Launch only on explicit user intent

Launching a detached session is a side effect the user must have asked for. Launch ONLY when the
user explicitly requested background delegation: they invoked this skill by name, or asked in words
("continue this in the background", "keep it moving while I'm away"). NEVER self-elected: the user
merely going AFK, context being heavy, or this skill being model-invoked on a description match is
NOT authorization. When invoked without that explicit request, produce the save-point, emit the
rails resume prompt with the standard `/clear`-then-paste instruction, state that no agent was
launched because background delegation was not explicitly requested, and STOP. The user can ask
for the launch or run `/session-flow:continue-in-background` themselves.

## Arguments

`$ARGUMENTS` carries `[--cloud] [file|prompt] [topic] [purpose...]`, all optional and positional.
A leading `--cloud` selects the cloud delivery below and is consumed before the rest parses. The
rest has the same semantics as `handoff`: method (`file` | `prompt`) recognized only as the first token,
otherwise auto-detect; topic is the kebab slug for the save-point filename, inferred when omitted;
everything after the topic token is optional natural-language purpose text ("what will the next
session be used for?"), no quoting, no new syntax, invocations without it parse exactly as
before, and its emphasis-only tailoring rules are owned by the engine doc ("The purpose argument
tailors emphasis only"). Parse purpose from `$ARGUMENTS` in place, never pre-compute. Before the
resolved topic is embedded anywhere (filename, `--name` flag), sanitize it to `[a-z0-9-]` only,
strip or replace every other character, so a crafted slug cannot smuggle quotes or extra flags
into the launch command. Purpose text is never embedded in the launch command at all. It shapes
the save-point's content, and the agent receives only the `/goal` payload.

## Produce the save-point

The save-point machinery, destination resolution, locating the position, full-vs-prompt-only
choice, the mandatory redaction pass, the handoff-file write, and the rails resume prompt, lives
in the shared engine doc
[`${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`](${CLAUDE_PLUGIN_ROOT}/reference/save-point.md).
Walk it top to bottom; do not restate or improvise any of its steps. On the full path the file is
shape 2: `save_point.py validate <file>` must exit 0 before anything launches (an unfinished
skeleton, one still carrying `<!-- FILL` slots, fails there and cannot be launched from).

## Completion condition gate

No one is present to say the work is done, so the launched session starts only with a checkable
completion condition, armed as its `/goal`. Settle it while producing the save-point:

1. **A goal applies** under the engine doc's goal-region rule (the user asked for a fresh goal, or
   a `/goal` is active in this session) → the save-point's goal region holds the condition the
   launch arms. A checkable done condition the user states in this invocation ("done when …")
   is a fresh-goal request: it lands here, with no draft and no confirmation round. When the goal is active here, the report tells the user to run `/goal clear` in
   this session, which otherwise keeps starting turns after the STOP.
2. **No goal applies** → draft one from the remaining work with `/planning:draft-goal-condition`
   and write the save-point with it as a fresh goal; its on-screen goal region is the display.
   Then ask the user to confirm the launch, and launch only on a yes: the request made over that
   condition is their approval to arm it. No answer this turn → no launch.
3. **No checkable condition** (the lever check routes away from `/goal`, or the draft cannot pass
   its counter) → write the save-point without a goal region and do not launch. Say that a
   background run needs a completion condition and that the user can rerun
   `/session-flow:continue-in-background` with the done condition named in the request. Fall
   back to the `/clear`-then-paste instruction.

The launch payload is `/goal`, a space, then text taken from the emitted prompt, never retyped:

- **Full path**: the between-rails text of the goal region (headed by the `Type /goal`
  instruction) of `save_point.py emit <file>`. It ends with the resume region's `Read @`
  directive, so the agent reads the handoff file in the turn the goal arms.
- **Prompt-only**: the goal region's between-rails text, a blank line, then the resume region's,
  so the remaining-work bullets travel too. The payload after `/goal` and its space stays within
  the goal-region limit the engine doc states, counted with `wc -m <prompt-file>` less those 6
  characters, never estimated; over it, do not launch, and fall back with the full path (`file`)
  named as the fix.

We rely on a background launch arming the whole multi-line payload as its goal, which our probe
observed.

- **Pointer**: the `--bg` probe in the Verification section of
  [#8742](https://github.com/melodic-software/claude-code-plugins/pull/8742); the docs section for
  non-interactive goals, <https://code.claude.com/docs/en/goal#run-non-interactively>.
- **As of**: 2026-10-20
- **Recheck trigger**: a Claude Code release note changes how a background session's first prompt
  runs a slash command, or that section starts or stops naming background sessions.

## Delivery: background-agent launch

**Output order: position panel, then the rails prompt, then the launch report.** The panel (engine
doc, "Emit the position panel") leads; the operator is walking away while an agent keeps working,
so the one thing they should not have to reconstruct is where the work stood when they left. It is
screen output only: **the launched agent receives exactly the `/goal` payload and never a line of
the panel**, which keeps it identical to the goal-region paste a person would make.

The rails prompt from the engine doc is still emitted before the launch (transparency + manual
fallback), then:

1. **Dirty-tree gate.** First establish there is a tree to inspect, with
   `git rev-parse --is-inside-work-tree` in the consuming project. Exactly two results are
   specified, and everything else falls through to a deliberate default:

   - Prints `true` → there is a work tree; inspect it with the gate below.
   - Fails *specifically* because this is not a git repository, AND no `WorktreeCreate` hook is
     configured (<https://code.claude.com/docs/en/hooks#worktreecreate>; as of 2026-10-11;
     recheck trigger: that section changes what the hook replaces or when it fires) → there is
     no uncommitted work to protect and no worktree isolation to lose, since we treat
     background sessions there as editing the working directory in place
     (<https://code.claude.com/docs/en/agent-view#how-file-edits-are-isolated>; as of
     2026-10-11; recheck trigger: that section changes when a session edits in place) →
     launch, and state both in the launch report. That hook is the isolation path for non-Git source control, so a configured one,
     or an absence you cannot establish, puts the launched session in a workspace this
     checkout's local changes never reach: that is the default branch below, not this one.
   - **Anything else** → the tree's state is UNKNOWN, which is not the same as clean → do NOT
     launch; fall back exactly as the dirty case does below, reporting what the command said.
     "Anything else" is the default on purpose, and it is wide: a failure for some other reason
     (dubious ownership, a damaged repository, git missing from `PATH`), and also a *successful*
     `false`. Inside a bare repository or inside a `.git` directory, where the command exits 0
     and there is no work tree to inspect.

   Never route by exit status alone. A non-zero exit is not evidence of "no repository", and a
   zero exit is not evidence of a clean tree; both readings put dirty trees on the launch path,
   which is how a gate that exists to protect uncommitted work ends up failing open. Only the
   two identifications above may leave the default branch.

   Inspect the tree with `git status --porcelain -uall` in the consuming project (`-uall`
   lists files inside untracked directories individually; the default collapses a brand-new
   handoff directory into one directory entry, which both defeats the exemption below and can
   hide other dirt behind it) and IGNORE save-point files under the handoff location, the
   just-written one AND any prior sessions' (this skill never commits them; they are
   session-chain artifacts, part of the launch rather than disqualifying dirty state; the
   background session starts in this working directory, so it reads the handoff file before any
   edit moves it into a worktree). Before judging other changes, read the effective
   `worktree.bgIsolation` (below). Unless it is `none`, we treat a background session as editing
   in an isolated worktree, a fresh checkout, so OTHER uncommitted changes in this checkout would
   NOT carry into the launched agent's edits (pointer, for when isolation applies and when it is
   skipped: <https://code.claude.com/docs/en/agent-view#how-file-edits-are-isolated>; as of
   2026-10-18; recheck trigger: that section changes when a session is isolated). Any
   such changes → do NOT launch: report why and fall back to the standard `/clear`-then-paste
   instruction (same checkout, dirty state intact), noting the user can commit or stash and
   re-run `/session-flow:continue-in-background`. Exception: launch anyway when the current session already
   runs inside a linked git worktree, where isolation is skipped per the same page.

   **`worktree.bgIsolation`.** Read it with `jq` from the settings files, first file that sets
   it wins across tiers: managed settings (the managed settings file and its `managed-settings.d`
   drop-in directory, where they exist on this machine), then the project's
   `.claude/settings.local.json` and `.claude/settings.json`, then `~/.claude/settings.json`.
   Within the managed tier, do not assume first match: read the file-versus-drop-in and
   drop-in-versus-drop-in order, and where each lives, from the managed settings pointers
   below, and apply it. Managed settings delivered another way, or from a location this
   read cannot find, are not covered: say so in the launch report. A `--settings` value cannot be
   read from files either, so whenever a launch report is written, say the read covered the files
   only. `none` is the value that turns isolation off; the pointer says what it does. When the value is `none`,
   the "would NOT carry" refusal does not apply, since the launched session sees the uncommitted
   changes: launch, and state in the launch report that the background session edits this
   checkout in place, alongside the user, so both may touch the same files at once; this holds
   inside a linked worktree too. Any other
   result, including a file that does not parse, leaves the gate above unchanged. The `--cloud`
   variant below ignores this setting. Pointers:
   <https://code.claude.com/docs/en/agent-view#how-file-edits-are-isolated>; as of 2026-10-18;
   recheck trigger: that section changes what `worktree.bgIsolation` does or its accepted values.
   Settings precedence (tier order): <https://code.claude.com/docs/en/settings#settings-precedence>;
   as of 2026-10-18; recheck trigger: that section changes the tier order. Managed file locations:
   <https://code.claude.com/docs/en/managed-settings#where-each-mechanism-stores-the-policy>; as of
   2026-10-18; recheck trigger: that section changes where the managed file or drop-in directory
   lives. Managed file and drop-in merging:
   <https://code.claude.com/docs/en/managed-settings#how-claude-code-combines-managed-sources>
   and <https://code.claude.com/docs/en/managed-settings#split-a-file-based-policy-across-teams>;
   as of 2026-10-18; recheck trigger: either section changes how the file and its drop-ins merge
   or their order.
2. Launch from the consuming project's root, passing the `/goal` payload verbatim as one argument.
   First write it, as the completion condition gate defines it, to a temporary file with the
   Write tool (never inline it in the command: prompt content is
   untrusted session text, and any inline embedding, a heredoc, an escaped string, hands crafted
   content a path out of the quoting and into the shell). `<topic>` = the resolved, sanitized
   topic slug (argument or inferred); when none resolves, use `resume`:

   ```bash
   cd "${CLAUDE_PROJECT_DIR}" && CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1 claude --bg --name "continue-<topic>" --permission-mode auto "$(cat "<prompt-file>")" && rm -f "<prompt-file>"
   ```

   Insert `--effort "<level>"` before the prompt argument when "What the launched session
   inherits" below calls for it.

   `--permission-mode auto` is always passed, following the repository's rule to launch
   unattended local lanes with `--permission-mode auto` (AGENTS.md). Whether a detached session
   can still stop on a prompt after auto mode falls back is unverified: no probe has been run.
   Pointer: [Permission modes § When auto mode falls back](https://code.claude.com/docs/en/permission-modes#when-auto-mode-falls-back)
   and [agent view § Permission mode, model, and effort](https://code.claude.com/docs/en/agent-view#permission-mode-model-and-effort);
   as of 2026-10-19; recheck trigger: either section changes what a background session does when
   an action is denied or auto mode falls back. The launch report says auto mode may deny an
   action and that where a denied action is reported is unverified; it never promises the final
   hand-off.

   `claude --bg` starts the session as a background agent and returns immediately; the user
   manages it with `claude agents`. `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` is required
   because this launch runs from a Bash-tool subprocess, a nested session the `claude agents`
   list would otherwise leave out (pointer: the `CLAUDE_CODE_CHILD_SESSION` and
   `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE` rows of
   <https://code.claude.com/docs/en/env-vars#variables>; as of 2026-10-11; recheck trigger:
   either row changes how nested sessions are listed). Awareness note: the prompt
   travels in the process argument list, so it is briefly visible to other local processes
   (`ps`), inherent to `claude --bg "<prompt>"`. The mandatory redaction pass has already
   scrubbed the prompt by this point; this exposure is one more reason secrets never belong in
   save-point output on ANY path.
3. Report the launch result: the command's output, the agent name, the `claude agents`
   management hint, any launched-session behavior the resumed work depends on (next
   section), and that auto mode may deny an action and where a denied action is reported is
   unverified, never a promise of the final hand-off. Verify the agent actually appeared. A zero-exit launch can still be invisible if
   the persistence override is ever unrecognized. Confirm by listing sessions non-interactively this
   turn when the CLI offers a way, and otherwise telling the user explicitly: "confirm it
   appears in `claude agents`". The `/clear`-then-paste instruction is replaced by this report.
   The user no longer needs to paste anything.
4. **Launch failure → fall back, never block.** Non-zero exit (e.g. the installed Claude Code
   predates `--bg`) → report the error and fall back to the standard `/clear`-then-paste
   instruction. The save-point already exists; nothing is lost.
5. **STOP.** The background agent is the continuation; this session terminates the task. Do not
   monitor, poll, or babysit the launched agent, and do not start new work items.

## Delivery variant: `--cloud`

Same hard gate, completion condition gate, save-point, `/goal` payload, prompt file, failure
fallback and STOP, plus one more condition: the user's own words asked for a cloud session.
Whether a cloud session arms a `/goal` from its first prompt has not been probed, so the report
says so and tells the user to confirm `◎ /goal active` when they open the session. A request for background work alone
does not cover it; without that, drop `--cloud` and take the local delivery. Steps 1 to 3
change, because this skill launches a cloud session only from a clean checkout whose branch
matches its remote:

1. **Only pushed work reaches it.** Launch only when `git status --porcelain -uall` lists nothing
   but save-point files (neither the linked-worktree exception nor `worktree.bgIsolation: none` applies), `git fetch --quiet` then
   succeeds, and `git rev-parse HEAD` equals `git rev-parse @{upstream}`; the fetch keeps a stale
   tracking ref from passing the check. No upstream, a failed command, or any other result → no
   launch; fall back as the dirty case does and name commit-and-push as the fix. Upstream can
   also bundle a repo in some cases (Pointer below). This skill does not take that path, so the
   cloud session starts from pushed state; a user who wants a bundle starts `claude --cloud`
   themselves. A
   handoff file in the memory tier never reaches the VM, and the full path's `Read @` names a
   local path, so launch only on the prompt-only path. When the save-point takes the full path,
   forced or by default, do not launch: tell the user to commit and push the handoff or plan,
   then rerun as `--cloud prompt <topic> <purpose naming its repo-relative path>`. This skill
   commits nothing.
2. **Launch** from the project root with the prompt file:
   `claude --cloud "$(cat "<prompt-file>")" && rm -f "<prompt-file>"`, with `--effort "<level>"`
   before the prompt argument when "What the launched session inherits" calls for one. If the CLI
   rejects `--effort` with `--cloud`, relaunch without it and have the report name the level and
   tell the user to send `/effort <level>` in the session.
3. **Report** the session id and link it prints, plus the return paths: `claude --teleport <id>`
   or `/teleport` to continue it in a terminal (its requirements: Pointer below), which needs the
   same account; `claude -p "<message>" --cloud <id>` to queue a follow-up. Name
   the account the CLI is signed in to now: the session draws that account's limits, teleport and
   follow-ups fail after the CLI switches accounts, and the repo's plugins load only when that
   account's cloud environment runs the repo's setup script.

- **Pointer**: <https://code.claude.com/docs/en/claude-code-on-the-web#start-a-cloud-session-from-your-terminal>,
  <https://code.claude.com/docs/en/claude-code-on-the-web#send-local-repositories-without-github>,
  <https://code.claude.com/docs/en/claude-code-on-the-web#manage-context> (`/effort` in a session),
  <https://code.claude.com/docs/en/claude-code-on-the-web#continue-a-cloud-session-in-your-terminal>,
  <https://code.claude.com/docs/en/claude-code-on-the-web#send-follow-ups-from-the-cli>; what the
  session lacks: <https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup>.
- **As of**: 2026-10-11
- **Recheck trigger**: any of those sections changes what the VM clones or bundles, the `--cloud`,
  `--teleport` or follow-up syntax, or teleport's requirements.

## What the launched session inherits (and what it does not)

The launched agent is a NEW session, not a fork of this one. What it inherits is upstream
behavior; the rules below are ours, built on it.

- **Pointer**: [Manage multiple agents with agent view § Settings and provider](https://code.claude.com/docs/en/agent-view#settings-and-provider)
  and [§ Permission mode, model, and effort](https://code.claude.com/docs/en/agent-view#permission-mode-model-and-effort)
- **As of**: 2026-10-11
- **Recheck trigger**: either section changes what a new background session inherits.

Our rules:

- **CLI configuration is NOT inherited.** It carries none of the current session's CLI flags
  (e.g. `--mcp-config`, `--settings`, `--add-dir`, `--plugin-dir`). Mirror onto the launch
  command any such flags the resumed work depends on, and say so in the launch report.
- **Model and effort are NOT inherited** from the current session's in-conversation choices.
  They resolve from the launch command's own `--model` / `--effort` flags and, absent those,
  from the settings of the directory it starts in (project/user settings, including `env`
  values such as `ANTHROPIC_MODEL`). When the resumed work depends on a specific model or
  effort, pass the flags explicitly and note them in the launch report.

  For resumed verify work, and for any task the launched session runs unattended, pass an
  explicit `--effort` so the work does not silently run at the default. At launch, read
  model-config's
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level)
  table, pick the level whose described use fits the resumed task, and pass that level as
  `--effort "<level>"` in step 2's command, before the prompt argument. A task that changes code
  or verifies it is never given a level below medium; skip any row the table says is not an
  effort level. The value is one level name of lowercase letters only, never free text, for the
  same reason the topic slug is sanitized. The launch report names the level and quotes the
  matched use. When the page cannot be read, say so, pass no `--effort`, and state that the
  session will start at its default level.

  - **Pointer**: for choosing a level, see the table linked above; for the `--effort` flag, see
    [Set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level).
  - **As of**: 2026-10-02
  - **Recheck trigger**: either section is renamed or moved, the table's columns change, or the
    `--effort` flag changes.
- **Permission mode is set at launch, not inherited.** Step 2's command always passes
  `--permission-mode auto`, so a directory setting with another default mode does not set the
  launched session's mode.
- **Directory settings ARE read normally.** The session reads its settings from the directory
  it runs in, the same as a fresh `claude` started there.

## Post-launch enforcement checklist

Tick each item in the response so the user can verify the exit shape (in addition to the engine
doc's save-point items, which the sibling `handoff` skill's checklists mirror):

- [ ] Explicit user intent for background delegation verified (hard gate). Absent intent →
  save-point + `/clear`-then-paste exit, no launch, reason stated
- [ ] Position panel emitted per the engine doc ("Emit the position panel"), ahead of the rails
  prompt, OR an explicit line saying the units would not resolve, and none of its text included in
  the prompt handed to the launched agent
- [ ] Purpose text (when the invocation carried any) applied per the engine doc's tailoring rules
  full path: brief lead, Suggested-skills selection, Remaining-actions order; prompt-only: the
  inline `Purpose:` line between the rails, never discarded (the launched agent receives exactly
  the rails prompt); a goal-conflicting purpose flagged rather than obeyed; never embedded in the
  launch command. No purpose given → nothing to tick
- [ ] Dirty-tree gate evaluated this turn: `git rev-parse --is-inside-work-tree` first, then
  `git status --porcelain -uall` when it says `true`, ignoring save-point files under the handoff
  location; effective `worktree.bgIsolation` read before judging other changes, and `none` → launch with the
  edits-this-checkout-in-place warning in the report (`--settings` tier named as not covered);
  otherwise other uncommitted changes without the linked-worktree exception → no launch, reason
  reported, fallback to `/clear`-then-paste. Positively identified as not a git repository AND no
  `WorktreeCreate` hook configured → launch, that reading stated in the report; any other
  `rev-parse` result, failing or `false`, and any hook whose absence is not established → state
  unknown, no launch, same fallback
- [ ] Completion condition settled: an applying goal used (an active one → `/goal clear` advised
  in the report), or one drafted with `/planning:draft-goal-condition`, shown as the goal region,
  and launched only on the user's yes to it; none → no launch, the message saying how to supply
  one, fallback to `/clear`-then-paste
- [ ] Background agent launched (`claude --bg --name … --permission-mode auto`), the payload being
  `/goal`, a space and the goal region's between-rails text from `save_point.py emit <file>` on
  the full path (validated first, exit 0 quoted), or on prompt-only the goal region then the
  resume region, counted within the limit; and the launch result reported (including any non-inherited flags mirrored or worth
  flagging, and that auto mode may deny an action and where a denied action is reported is
  unverified), OR the non-zero exit reported with fallback to
  `/clear`-then-paste
- [ ] For resumed verify or unattended work, `--effort` passed with the model-config table's level
  whose described use fits the task, the report naming the level and quoting that use; page unreadable → said so, no `--effort`, and the report states the session starts
  at its default level
- [ ] `--cloud` only: clean tree, fetched branch matching its upstream, prompt-only payload,
  `--effort` passed as for `--bg` (CLI rejects it → relaunched without, `/effort` advised); the
  report names the session id, the teleport and follow-up commands, and the signed-in account,
  and says goal arming there is unprobed
- [ ] **EXECUTION STOPS HERE**, no monitoring, no babysitting, no new work items

## Boundary, native Claude Code surfaces

Three built-in commands also keep work moving off this terminal, so "continue in the background"
can mean any of them.

- **`/subtask`, `/fork`, `/background` (built-in commands)**: `/subtask` hands a side task to a
  subagent that reports back here, `/fork` copies the conversation into a background session,
  and `/background` moves this session itself off the terminal. None writes a save-point. All
  three are reserved for the person to run; the model does not invoke them. What each launches,
  its alias and its gate: the records table in
  [native-surfaces § verification record](reference/native-surfaces.md#native-background-surfaces-verification-record)
  (as of 2026-10-11; recheck trigger: that table's rows or their recheck events change).
- **This skill (marketplace plugin).** Writes a durable, redacted save-point, gates on a dirty
  tree, and launches a fresh `claude --bg` session seeded only with the save-point's `/goal`
  payload, so the continuation carries no conversation history, survives on disk, and ends on a
  checked condition.

**Routing.** At the start of the run, offer them to the person: you can run `/background` to
detach this session as it is, `/fork` to copy it into a background session, or `/subtask` for a
side task whose result should come back here, instead of or alongside this skill. Prefer this
skill when the continuation should start clean from a durable save-point. An unattended run
records the offer in its output instead of asking.

**Mutation gate.** This skill writes the save-point and launches one session, only on explicit
request. It never runs a native command on the person's behalf.

**Availability is never assumed.** All three are gated, and their behavior depends on the
session's setup; read the gates live from the records table in
[native-surfaces § verification record](reference/native-surfaces.md#native-background-surfaces-verification-record)
(as of 2026-10-11; recheck trigger: that table's rows or their recheck events change). This
section states what to do when they resolve, never that they are present.

## Gotchas

Failure patterns are documented inline at the step that owns them: the `-uall` untracked-directory
collapse, the non-repo-plus-no-`WorktreeCreate`-hook vs. unknown split with its deliberately wide
unknown default, and the ban on reusing the context block's git output (dirty-tree gate, step 1;
context block), the no-inline-prompt rule and the session-persistence env requirement (launch
command, step 2), slug sanitization ("Arguments"), and non-inheritance surprises. Model, effort,
CLI flags ("What the launched session inherits").

## What this skill does NOT do

- **Does not launch without explicit user intent**. The hard gate above; the fallback exit is
  the sibling `handoff` skill's `/clear`-then-paste shape
- **Does not launch without a completion condition**. The completion condition gate above
- **Does not commit**. Save-points are durable task state, not source code; the dirty-tree gate
  reports other uncommitted work rather than committing or stashing it
- **Does not monitor the launched agent**. The user manages it with `claude agents`
- **Does not continue executing the underlying task in this session**. The background agent is
  the continuation
- **Does not restate the save-point engine**. Production lives in the shared engine doc
