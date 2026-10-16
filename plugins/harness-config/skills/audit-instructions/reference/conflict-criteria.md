# Cross-Surface Conflict Criteria

## Contents

- [Sources](#sources)
- [Boundary: what C6's population actually is](#boundary-what-c6s-population-actually-is)
- [Prerequisite: co-residency](#prerequisite-co-residency)
- [Prerequisite: effective liveness, which the tree does not determine](#prerequisite-effective-liveness-which-the-tree-does-not-determine)
- [Known limit: the plugin-source tree and the installed cache](#known-limit-the-plugin-source-tree-and-the-installed-cache)
- [Scope filters findings, never reads](#scope-filters-findings-never-reads)
- [The five gates](#the-five-gates)
- [Precedence: what the docs settle, and what they do not](#precedence-what-the-docs-settle-and-what-they-do-not)
- [Running the pass](#running-the-pass)
- [Must-not-flag set](#must-not-flag-set)
- [Deterministic pre-scan](#deterministic-pre-scan)
- [Worked examples](#worked-examples)
- [Output format](#output-format)

Version: 1.7.0
Last updated: 2026-10-11

**The adjudication procedure for check I15.** [criteria.md](criteria.md)'s I15 entry owns the
definition: what a cross-surface conflict *is*, its comparison set, its import and symlink
resolution, its conditional `AGENTS.md` exclusion, its remediation-by-scope rules, and its five must-not-flag
cases. None of that is restated here. This file owns the part a check entry has no room for: **how a
candidate pair is adjudicated**. That covers whether the two surfaces can even co-load, what the
official docs settle about precedence and what they refuse to, and the further must-not-flag cases
the pre-scan and the lane each drop.

**Shared-surface ownership is out of scope for I15.** This pass detects conflicting instruction
*pairs*; it does not assign *ownership* when multiple contributors' preferences meet on one
surface. That governance question is recorded as rejected for this repository in
`docs/out-of-scope/shared-surface-instruction-governance.md`
(#3568). `instruction-exception-register` governs deletions only, not ownership.
**Claim:** I15 does not assign shared-surface ownership. **Basis:** this file's pair-detection
charter; the rejected-concept ledger entry for #3568. **As of:** 2026-09-28. **Recheck:** when
that ledger's recheck fires.

The three shared axes (evidence tier, authority, severity) are defined once in
[criteria.md](criteria.md) and are not restated here.

**Recheck triggers** (as of 2026-10-11). Re-verify against live docs when any fires: a change to the memory page's
precedence or load-order text; a change to the skills page's statements about instruction authority;
any new instruction surface added to the product; a change to how permission rules or permission
modes remove a tool from Claude's pool; a change to **which hook events inject handler output into
the session's context**, to the events `additionalContext` is accepted on, or to the handler types
that can return it; the removal, renaming, or restructuring of the hooks page's **per-event exit-2
table** this file defers to for blockability, or a change to the set of locations a hook may be
declared in; a change to the table's `SubagentStop`, `PostToolUse`, or `PreToolUse` rows, the
three the worked examples below cite. A row added to the table, or a change to any row this file
does not cite, needs no recheck, because the partition itself is never restated here.

## Sources

Every residency and precedence decision below points at the section it rests on, and the pass reads
that section live when it runs. A claim these pages do not make is recorded as unresolved and given
no winner. The pages, each entered through the section most of this file cites:

- Memory, covering CLAUDE.md, a natively read `AGENTS.md`, `.claude/rules/`, and auto memory:
  [how CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load)
- Skills: [frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference)
- Subagents, covering what loads into a subagent at startup:
  [what loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)
- Output styles, covering how a style reaches the system prompt:
  [how output styles work](https://code.claude.com/docs/en/output-styles#how-output-styles-work)
- Permissions, covering how deny rules and permission modes remove a tool:
  [manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions)
- Hooks, covering handler types, which events inject handler output into context, `additionalContext`,
  and exit-code semantics: [hook handler fields](https://code.claude.com/docs/en/hooks#hook-handler-fields)
- Context window, covering what survives compaction:
  [what survives compaction](https://code.claude.com/docs/en/context-window#what-survives-compaction)

## Boundary: what C6's population actually is

I15 routes a contradiction whose **both** anchors sit in `harness-memory:audit`'s C6 discovery
population to that check, and keeps every other pair here, including memory-layer pairs C6 still
does not enumerate, and every cross-layer pair. The predicate is the population, never the layer
name.

The `harness-memory:audit` skill's check **C6** asks its question across the memory files its own
discovery emits. That discovery is
`skills/audit/scripts/discover-instruction-surfaces.sh`, which emits **project and user** scope:
root-level project `CLAUDE.md` / `CLAUDE.local.md` / `AGENTS.md` and `.claude/AGENTS.md` where no
`CLAUDE.md` displaces them / `.claude/rules/**`, plus
`${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md` and `…/rules/**`, each tagged so project-scoped criteria
can skip personal files. Step 3 of the audit workflow then compares user-scope surfaces against
project ones as live C6 conflicts.

Route on that population:

| Pair | Owner |
|---|---|
| Both anchors in the **discover-instruction-surfaces** population (any mix of project / user / `both` scope among root-level `CLAUDE.md` / `CLAUDE.local.md` / a natively read `AGENTS.md` or `.claude/AGENTS.md` / rules), **including user↔project** | `harness-memory`'s C6 |
| Anything else: **any nested `CLAUDE.md` / `CLAUDE.local.md` side**, any auto-memory side, settings, hooks, skills, agents, output styles, or any other surface outside that population | I15 |

**Nested memory files stay with I15.** Phase A inventories every nested
`CLAUDE.md` / `CLAUDE.local.md` in the project tree, while discover-instruction-surfaces is depth-1 by
design, so routing a nested pair to C6 hands it to a check that never reads the file.

**Auto-memory stays with I15** on the same evidence. `harness-memory` audits `MEMORY.md` for size and
index integrity via a separate resolver, but that path is not in the discover-instruction-surfaces
population C6 pairs over. Routing a `MEMORY.md`-versus-`CLAUDE.md` contradiction to C6 would leave it
audited by neither skill's conflict check.

**I15 still owns memory-layer precedence adjudication** for every pair it keeps: what the docs
settle, what they leave unresolved, and the co-residency / liveness gates in this file. C6 owns
instruction-*content* consistency inside its discovery population; it does not absorb this file's
precedence tables or the surfaces outside that population.

When both anchors are in C6's population, report the pair as an observation and point the operator at
`/harness-memory:audit` rather than grading it here; when that plugin is not installed, keep it as a
finding so nothing is silently dropped. This mirrors the reciprocal routing `harness-memory` already
performs for content-fit findings.

The rule remains **route on the population a check actually enumerates, never on the name of the
layer**: a boundary drawn from a label rather than from the incumbent's discovery script leaves whole
pair classes audited by neither skill. When that script's population moves, this table moves with it.

**A standing instruction against plausible user requests is not a member.** I15 does not detect
conflict between a standing instruction and a hypothetical or plausible user request. Its population
is the set of surfaces the tree can enumerate, and such requests are not in it. The reason is the
[co-residency prerequisite](#prerequisite-co-residency): both directives must be in the same context
window, and a hypothetical request has no residency, no enumerability and no liveness the tree can
determine. Admitting the axis would either drop that gate and reintroduce the noise it suppresses, or
need a parallel liveness notion for imagined inputs. The population is also unbounded, so the
false-negative rate cannot be measured. The owner adjudicated this in #3565 and rejected the reopen. A
corpus of realistic prompts to test instruction surfaces against is a different artifact and would be
filed separately, not as an I15 extension.
**Claim:** I15 does not adjudicate standing instructions against plausible user requests.
**Basis:** this file's Prerequisite: co-residency section and the owner decision on #3565.
**As of:** 2026-09-29. **Recheck:** when the co-residency prerequisite changes or a bounded,
enumerable request corpus is filed as its own artifact.

## Prerequisite: co-residency

A conflict requires both directives to be in the same context window at the same time. Matching text
shapes without this gate produces noise, because most surface pairs never co-load.

| Surface | When resident | Where to read the residency live |
|---|---|---|
| User `CLAUDE.md` | Every session, unless the file is over the size limit the second pointer names, which skips it | [memory: how CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load); [memory: how it works](https://code.claude.com/docs/en/memory#how-it-works) |
| Project `CLAUDE.md` / `CLAUDE.local.md` | Every session in that tree, after user scope, under the same size limit | [memory: how CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load) |
| Project `AGENTS.md` / `.claude/AGENTS.md`, where no `CLAUDE.md` name displaces it, **and, under `claude-md-and-agents-md`, even where one does**, in both cases only where the session reads `AGENTS.md` natively at all | Every session in that tree | [memory: AGENTS.md](https://code.claude.com/docs/en/memory#agents-md); [memory: choose which instruction files load](https://code.claude.com/docs/en/memory#choose-which-instruction-files-load) |
| Nested `CLAUDE.md` in a subdirectory | On demand, when Claude works with a file there | [memory: how CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load) |
| `.claude/rules/*` without `paths` | Every session | [memory: set up rules](https://code.claude.com/docs/en/memory#set-up-rules) |
| `.claude/rules/*` with `paths` | Only when a matching file is read | [memory: path-specific rules](https://code.claude.com/docs/en/memory#path-specific-rules) |
| Skill body | Only once invoked, then for the rest of the session | [skills: skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle) |
| Auto memory `MEMORY.md` | Every **main** session, only its loaded portion, and **not** in a subagent, except a fork | [memory: how it works](https://code.claude.com/docs/en/memory#how-it-works) |
| A subagent's **own** auto memory `MEMORY.md` (its `memory` field) | Every dispatch of **that** subagent, only its loaded portion, never the main session, and never another agent's | [subagents: enable persistent memory](https://code.claude.com/docs/en/sub-agents#enable-persistent-memory) |
| Skill bundled `reference/`, `context/` file | Only when Claude reads it | [skills: add supporting files](https://code.claude.com/docs/en/skills#add-supporting-files) |
| Agent definition (its own subagent) | Always, as that subagent's system prompt, alongside whichever CLAUDE.md files its definition does not opt out of | [subagents: what loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup) |
| Skill named in an agent's `skills:` field | In that subagent, when the preload accepts the name; a name the preload skips or does not reach is not resident | [subagents: preload skills into subagents](https://code.claude.com/docs/en/sub-agents#preload-skills-into-subagents) |
| Prompt-type hook text | **Never**. See "A prompt hook's text is not an instruction" below | [hooks: prompt and agent hook fields](https://code.claude.com/docs/en/hooks#prompt-and-agent-hook-fields) |
| Handler **stdout** on an event the section names as adding stdout to context | From injection onward, as ordinary message history | [hooks: exit code 0](https://code.claude.com/docs/en/hooks#exit-code-0) |
| Handler `hookSpecificOutput.additionalContext` on a **main-session** event | From injection onward, at the position the event dictates | [hooks: add context for Claude](https://code.claude.com/docs/en/hooks#add-context-for-claude) |
| Handler `hookSpecificOutput.additionalContext` on `SubagentStart` / `SubagentStop` | In **that subagent's** context, never the main session's | [hooks: SubagentStart](https://code.claude.com/docs/en/hooks#subagentstart); [hooks: SubagentStop](https://code.claude.com/docs/en/hooks#subagentstop) |
| Handler **stdout** on any other event | **Never** | [hooks: exit code 0](https://code.claude.com/docs/en/hooks#exit-code-0) |
| Output style (the **active** one) | Every session in the main conversation, from the point it became active | [output styles: how output styles work](https://code.claude.com/docs/en/output-styles#how-output-styles-work) |

The pass reads the stdout event set, the size limit, the loaded portion of a `MEMORY.md` and the
preload limit from those sections when it runs. This table copies none of them, because each one has
moved without an edit here.

- **Pointer**: when deciding whether a surface is resident, fetch the section its row names live.
- **As of**: 2026-10-11
- **Recheck trigger**: a row's section is renamed or removed, or it adds or drops a condition on
  when that surface loads.

**The `AGENTS.md` row's residency is conditional on availability and the mode, not on displacement
alone.** Availability comes first: a session that reads no `AGENTS.md` at all, for any of the
documented reasons, does not load the file, so the row asserts no residency for it and gate 1 does
not pair it. The mode then decides whether a `CLAUDE.md` beside it displaces it, and some of its
values rule the file out whatever the displacement answer is. Treating displacement as the whole
question would report a conflict against a surface nothing loads. Resolve both, and where a
condition stays unresolved, **do not assert residency for it**: I15 is a finding lane, so an
unestablished residency is a leave-alone rather than a pair to judge, exactly as the record's
finding-lane rule says and as gate 1 already treats every other surface whose residency is not
established. Both carry their dated records, with the settings scopes and the key the
mode lives under, in [agents-md-liveness.md](../../../reference/agents-md-liveness.md).

**An agent definition co-resides with the CLAUDE.md files its subagent loads, and by default that
is a guaranteed pair.** A non-fork subagent loads the main conversation's CLAUDE.md hierarchy unless
it is a built-in agent that skips it or its own definition opts out of it. So an agent definition
that opts out of nothing, contradicting a `CLAUDE.md`, clears gate 1 outright, without the
conditional treatment a skill body gets. Resolve the opt-out per definition before pairing: read the
definition's frontmatter for the opt-out field the section names, and pair the definition only with
the files that section says still load under it. A pair whose memory-layer half the subagent does not
load fails gate 1.

**Auto memory is the exception inside that hierarchy.** The main conversation's auto memory does not
reach a non-fork subagent, while a subagent that enables its own `memory` field reads its own
directory. So an agent definition against the **main** `MEMORY.md` fails gate 1, because the two
never occupy one context, and pairing them reports a conflict between contexts that do not coexist.
Two pairs remain real and should not be swept away with it: a **fork** does inherit the parent, and a
subagent that enables its own `memory` can contradict the definition it runs under, but that is the
subagent's own memory directory, not the main conversation's.

**Built-in agents that skip CLAUDE.md, such as `Explore` and `Plan`, never pair with it.** A pair
whose only memory-layer half reaches such a delegation fails gate 1, and the remediation is to
restate the rule in the delegation prompt rather than to reconcile the two surfaces.

- **Pointer**: when deciding which CLAUDE.md files and which auto memory reach a subagent, fetch
  [subagents: what loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)
  and [memory: how it works](https://code.claude.com/docs/en/memory#how-it-works) live.
- **As of**: 2026-10-11
- **Recheck trigger**: the startup section adds or drops an agent that skips CLAUDE.md, changes what
  the opt-out field leaves loaded, or adds another per-agent control over it.

**Only the active output style is resident, and only in the main conversation.** A style becomes
active through the `outputStyle` setting or a plugin's `force-for-plugin`; every other style on disk
is inventoried but never loaded, so a pair reaching an inactive style fails gate 1 outright. Two
further bounds: a style shapes the main conversation and not a non-fork subagent, so an output style
never pairs with an agent definition except via a fork; and a style switched mid-session is resident
only from the point the change-style section says it takes effect, so pair against the style active
for the turn in question.

- **Pointer**: when deciding where a style applies and when a switch takes effect, fetch
  [output styles: how output styles work](https://code.claude.com/docs/en/output-styles#how-output-styles-work),
  [output styles: change your output style](https://code.claude.com/docs/en/output-styles#change-your-output-style)
  and [subagents: what loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: one of those sections changes whether a style reaches a subagent or when a
  switch takes effect.

**A prompt hook's text is not an instruction to the main session.** A `type: "prompt"` handler's
text goes to a separate evaluator model call that returns a decision, and is never injected into the
main conversation
([hooks: prompt and agent hook fields](https://code.claude.com/docs/en/hooks#prompt-and-agent-hook-fields),
as of 2026-10-11; recheck when that section lets a prompt handler's text reach the session's
context). Comparing that raw
prompt against a `CLAUDE.md`, a skill, or an output style manufactures conflicts between two models
that satisfy their own instructions independently: an evaluator told to *return JSON only* does not
contradict a main-session rule requiring Markdown output.

So a prompt hook enters the comparison set as the **constraint it imposes**, never as its prose:

- The **act** it gates, taken from the decision the evaluator can return, together with the hook's
  `matcher` and event. A `PreToolUse` hook matching `Bash` constrains Bash calls, and nothing else.
- Not the wording of the prompt, the output format it demands of its evaluator, the persona it sets,
  or any directive whose only audience is that evaluator.

A pair is then real when a resident instruction tells the main session to do something the hook's
gate would block under a matching input, such as "always run `git push --force` after a rebase"
against a `PreToolUse` hook that denies force-pushes. That is a genuine unsatisfiable pair; a formatting
directive addressed to the evaluator is not. An `agent` handler is treated the same way: it too
runs its own evaluation before returning a decision, so it enters as the act it gates.

**But the discriminator is whether the handler's output reaches this session's context, not whether
the handler is `type: "command"`.** The hooks page settles *which channel reaches context* per
**event**, not per handler type: plain stdout reaches context only on the events its exit-code-0
section names, and `hookSpecificOutput.additionalContext` on the events its add-context section
names. Neither list is copied here, because events join them. Nor is the JSON channel type-scoped:
read each handler type's own fields section for how its output is parsed, and treat any type whose
output the page parses like command-hook output as able to inject context.

**Type still decides one thing, and it is not the channel: registrability.** Not every event accepts
every handler type, so resolve the event×type pair against the event's own section before admitting a
surface: a handler of a type the event does not accept is not a surface with unreadable text, it is a
hook that cannot be registered there at all. Likewise, a handler type with no stdout cannot use the
stdout channel, while it may still use the `additionalContext` channel on an event that accepts it.

- **Pointer**: when resolving a hook surface's channel and registrability, fetch
  [hooks: hook handler fields](https://code.claude.com/docs/en/hooks#hook-handler-fields),
  [hooks: exit code 0](https://code.claude.com/docs/en/hooks#exit-code-0),
  [hooks: add context for Claude](https://code.claude.com/docs/en/hooks#add-context-for-claude) and
  the event's own section (for example
  [hooks: SessionStart](https://code.claude.com/docs/en/hooks#sessionstart)) live.
- **As of**: 2026-10-11
- **Recheck trigger**: the handler types change, an event is added to or dropped from either
  channel's event set, or an event changes which handler types it accepts.

So **a handler whose output is injected as context enters the comparison set as that text**, on the
same terms as any other instruction surface. A `SessionStart` command hook printing a standing
behavioral block ("respond tersely … applies to every response") is live directive text in this
session's context window, and pairing it against an output style's format contract or a `CLAUDE.md`
rule is exactly what gate 1 is for. Excluding it because the handler is `type: "command"` drops one
half of a pair that provably co-resides, and does so silently, since a per-surface lane never sees
the surface at all.

**A subagent-scoped injection is not resident here.** `SubagentStart` and `SubagentStop` add their
`additionalContext` to the subagent's context (the table's pointers above), so it fails gate 1
against any main-session surface exactly as the active output style does. It is a real surface in the subagent's own context, where it
can contradict the agent definition it runs under or a skill named in that agent's `skills:` field.
Pair it there, and never against the main conversation's `MEMORY.md` or active output style.

**What the compaction table decides, and what it does not.** The context-window page's compaction
table says what becomes of hook-added context and of compaction-matched hooks after a compaction. It
bounds *how long* injected text stays resident; it never removes a context-injecting hook from the
comparison set, so read its hook rows for the residency consequences below and nothing else.

- **Pointer**: when deciding what hook-injected text survives a compaction, fetch
  [context window: what survives compaction](https://code.claude.com/docs/en/context-window#what-survives-compaction)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: the table adds, drops or changes a row about hooks or hook-added context.

Three consequences for residency, and each one bounds a pair rather than admitting it wholesale:

- **Injected text is ordinary message history, not a re-injected surface.** It is resident from the
  moment it lands and, unlike root `CLAUDE.md`, nothing re-injects it from disk after compaction.
  A `SessionStart` hook registered for the `compact` matcher fires again after a compaction and
  re-injects; a hook registered only for `startup` does not. Treat a pair whose hook half is
  `startup`-only as conditional after a compaction, and say so rather than asserting permanent
  residency. Read the matcher values from
  [hooks: SessionStart](https://code.claude.com/docs/en/hooks#sessionstart) live (as of 2026-10-11;
  recheck when its matcher values change).
- **Exit-2 stderr is turn-scoped error feedback, not a standing directive, and only some events
  have an act to block.** Exit-2 stderr reaches Claude as an error message
  ([hooks: exit code 2](https://code.claude.com/docs/en/hooks#exit-code-2), as of 2026-10-11;
  recheck when that section stops feeding exit-2 stderr back to Claude), so it is not nothing;
  but it is a one-turn message, never a standing rule. Whether it also carries a *gate* is
  event-specific, and the sole authority on that is the hooks page's
  [Exit code 2 behavior per event](https://code.claude.com/docs/en/hooks#exit-code-2-behavior-per-event)
  table (as of 2026-10-11; recheck when the table is renamed, removed or restructured, or its
  `SubagentStop`, `PostToolUse` or `PreToolUse` row changes, the three cited below). Its rows are not
  reproduced here in either direction: the event set grows, so any list
  copied into this file becomes a closed partition that silently misgrades the next event added.
  Resolve the handler's event, read that event's row, and pair on the row's own `Can block?` cell:
  - **The cell says yes.** The conflict-bearing content is whatever that row states is prevented,
    quoted from the row rather than assumed. What a row prevents is not always a tool call or a
    prompt; the cell, never the gate abstraction, supplies the paired content. `SubagentStop`
    blocks but is subagent-scoped: its act pairs inside the subagent, under the subagent-scoping
    rule above, and never against a main-session surface.
  - **The cell says no.** Nothing is prevented, so there is no act and no gate to pair; treat the
    message as transient feedback and pair it as nothing. `PostToolUse` is the worked example: its
    row says it cannot block, because the tool has run. A per-edit linter there can only surface
    findings as advisory context, which is why the actionlint plugin's `actionlint-check.sh`
    belongs in a git `pre-commit` entry that blocks the commit rather than per edit
    ([check-placement](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/check-placement/README.md#the-rubric)).
    Reading any `PostToolUse` handler's exit-2 stderr as a prohibition on the tool it ran
    *after* would manufacture an unsatisfiable conflict against any instruction requiring that
    tool. The tool already ran, and the hook can neither block nor undo it. Registered instead on
    `PreToolUse`, whose row blocks the tool call, the same handler WOULD enter the comparison set
    as the act it blocks.
  - **The event has no row, or the table could not be reached.** Record the surface with its event
    as `blockability-unresolved` and report the pair as such, on the same terms the
    `text-unresolved` rule below gives. Never infer blockability from the event's name, its prefix,
    or from what a hook of that shape usually does.
- **A hook's own configuration is still not instruction text.** The command line, its arguments, and
  its `matcher` are the gate, not prose addressed to the model. Extract only what is injected, under
  the same no-secrets handling every settings-sourced surface gets.
- **Text the config does not contain is `text-unresolved`, and a pair touching it is reported rather
  than graded.** A handler that runs a script has its injected text determined at run time, so an
  inventory taken outside that run cannot read it. Phase A records the surface with the handler's
  event and `matcher` and marks it; the lane then treats it exactly as the liveness gate below treats
  a `liveness-unresolved` surface: report the pair as such, and never infer the text from the script
  name, the handler's arguments, or what a hook of that shape usually emits. Inventing the half you
  cannot read is a worse failure than excluding the surface, because it manufactures a
  quotation.

**Guaranteed pairs** are any two of {user `CLAUDE.md`, project `CLAUDE.md`, a natively read project
`AGENTS.md`, unscoped rules, `MEMORY.md`}, and any agent definition against any of them **except `MEMORY.md`**, except via
a built-in agent that skips CLAUDE.md (`Explore` / `Plan`), and except a file the definition's own
opt-out leaves unloaded (see "An agent definition co-resides" above).
**Conditional pairs** involve a skill body, a path-scoped rule, a nested `CLAUDE.md`, or
context-injected hook output. They are real, but they only bite once that surface loads. Hook output is
conditional on its own event and `matcher` firing, which for a `SessionStart` `startup` hook means
every new session but not necessarily after a compaction. Report the distinction; do not drop
conditional pairs, because the worked example below is one.

## Prerequisite: effective liveness, which the tree does not determine

Co-residency asks *when* a surface loads. This gate asks a prior question, **whether it loads at
all in this session**, and the answer is not a function of the file tree. Six session-level inputs
change it. The first five are memory controls, the last a hooks control, because a hook's
instruction text is only as live as the handler that carries it. Each names the section to read for
its current behavior:

- **Launch directory.** Which ancestor `CLAUDE.md` files are candidates at all follows from where the
  session started, not from the repo root
  ([memory: how CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load)).
- **`claudeMdExcludes`.** A file the tree contains may be excluded and therefore dead; resolve the
  patterns across every settings layer that sets them, and note which files exclusion cannot reach
  ([memory: exclude specific CLAUDE.md files](https://code.claude.com/docs/en/memory#exclude-specific-claude-md-files)).
- **`--setting-sources`.** Excluding a source can skip the rules files that source would contribute,
  so a `.claude/rules/` file on disk may contribute nothing
  ([memory: set up rules](https://code.claude.com/docs/en/memory#set-up-rules)).
- **`--add-dir` with its CLAUDE.md-loading variable.** An additional directory can contribute memory
  files a walk of the project tree never sees; read which ones from
  [memory: load from additional directories](https://code.claude.com/docs/en/memory#load-from-additional-directories).
  An `AGENTS.md` there is not one: it does not load, per the dated record in
  [agents-md-liveness.md](../../../reference/agents-md-liveness.md).
- **A declined external-import approval.** That state is persistent, machine-local, and invisible
  in the tree
  ([memory: import additional files](https://code.claude.com/docs/en/memory#import-additional-files)).
- **Effective hook enablement, which resolves per scope and not per file.** `disableAllHooks` turns
  hooks off while the configured entry survives, so the tree still shows a hook that cannot fire.
  It respects the managed hierarchy: a lower-scope disable leaves managed hook text **live**, and it
  must not be dropped with the rest. The mirror control, `allowManagedHooksOnly`, blocks non-managed
  hooks, with exemptions the settings reference names. Either one silences instruction text this
  session while leaving it on disk, and neither is readable from the tree
  ([hooks: disable or remove hooks](https://code.claude.com/docs/en/hooks#disable-or-remove-hooks);
  [settings reference: what runs under allowManagedHooksOnly](https://code.claude.com/docs/en/settings-reference#what-runs-under-allowmanagedhooksonly)).

- **Pointer**: when resolving a session's liveness controls, fetch the section each bullet names
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: one of those sections adds, removes or changes a control over which
  instruction files load or which hooks run.

A pass that skips this gate reports conflicts between instructions one side of which is dead, and
misses live counterparts that were never inventoried. Both failures are silent, and both are
reproducible only on the machine that produced them.

**So resolve effective liveness before pairing, and record what you resolved.** Take the session's
launch directory, the merged effective values of `claudeMdExcludes`, `--setting-sources`, and the
additional-directory inputs, and `disableAllHooks` **at each settings scope** together with
`allowManagedHooksOnly`; drop excluded and source-skipped surfaces from the comparison set, drop
every hook surface the resolved enablement silences, prompt-type and context-injecting alike, since
neither reaches this session when the handler never fires, while keeping managed hook text against a
user, project, or local `disableAllHooks`, and add the memory files the additional directories
contribute. Where a value cannot be resolved, as with an inventory taken outside the session it
describes or a declined import that leaves no trace in the tree, mark the affected surfaces
`liveness-unresolved` and report pairs touching them as such rather than grading them. **Name the resolved controls in the pass's tier-transparency line**: a
finding whose liveness depends on a machine-local setting is not reproducible elsewhere, and a reader
comparing two machines' reports needs to know which inputs differed.

## Known limit: the plugin-source tree and the installed cache

**Installed plugins are covered everywhere.** Phase A's read-only tier reads the *installed cache*
of every enabled plugin at its selected install record: skill bodies, agent definitions,
`type: "prompt"` handler text, and the active output style. So an agent definition shipped by an
enabled plugin does have its second side, and an agent-versus-memory pair is available rather than
missing.

**In a marketplace repository, the plugin source is the editable set.** When
`.claude-plugin/marketplace.json` is present at the project root, the repository publishes the
plugins under `plugins/**`, so their surfaces are locally owned: Phase A inventories them as
editable, lanes audit them, and a proposed diff lands on the source file, never on the cache. The
installed cache of those same plugins is read for **residency only**, to decide whether a surface
loads in this session and what text the session actually sees, and is never the target of a
proposal. Without a marketplace manifest the source tree is not special and the cache stays
upstream-owned, as the Scope boundary says.

**The limit is drift between the two.** The session loads the cache, not the source, so a finding on
a source surface describes the next published text, not necessarily what loads now. For every
marketplace plugin the session has installed, the report names the drift: the install record's
commit against `git rev-parse HEAD` when the record carries a commit, otherwise the installed
version against the manifest `version` at HEAD, stating which comparison was made. A plugin with no
drift says so in one line. Report the drift in the pass's tier-transparency line, since a reader who
sees a source finding the live session cannot reproduce needs to know the two trees differ.

## Scope filters findings, never reads

`audit-instructions` takes a scope argument that narrows Phase A's inventory. A pairwise observable
is undefined on one side, so under `skills` the `CLAUDE.md` half of every cross-layer pair would
simply be absent, and the pass would report clean while appearing to have run, which is worse than
declining to run.

**So this pass enumerates every surface `all` would collect, read-only, and applies the scope to the
finding instead: report a pair when at least one of its anchors is in scope.** That keeps a scoped
invocation honest without making the conflict check an `all`-only feature.

## The five gates

A pair is a conflict only when **all five** hold. Any gate failing removes it from the finding set.

1. **Co-residency.** The two surfaces can be resident simultaneously, per the table above.
2. **Same observable.** Both constrain the same decidable act, identified as a (verb, object,
   trigger) triple rather than by topic similarity. "Emoji in a GitHub reaction" and "emoji in
   assistant prose" are two observables, not one.
3. **Opposed polarity.** For at least one input satisfying both triggers, the two prescribed actions
   cannot both be taken.
4. **No arbitration.** Neither directive, nor any third resident text, says which wins. An explicit
   precedence sentence, a deference clause, or a config opt-in gate resolves the pair.
5. **Non-vacuous trigger overlap.** A realistic prompt fires both. Directives scoped to disjoint
   conditions (interactive versus autonomous, code versus prose) do not overlap.

### Conflict types, by remediation route

- **Type A, direct contradiction.** Both absolute, opposite polarity. Route: arbitrate, or drop one.
- **Type B, modality collision.** One absolute ("never"), one conditional ("when warranted"), same
  act. The absolute reads as a hard rule and the conditional reads as license, and neither author
  sees the other.
- **Type C, unarbitrated co-authority.** Two surfaces each assert ownership of one decision with no
  precedence statement. Route: one precedence sentence at the higher surface.

**Split-brain is a precursor, not a fourth type.** Two files governing one behavior where only one is
ever loaded fails gate 1 by construction, so it can never be a conflict finding. Listing it as a
conflict type would either make it unreachable or force the lane to flag non-co-resident files. Report
it separately as **orphaned instruction drift**: not a contradiction today, but the state a
contradiction grows out of once the two copies diverge. Route: import or symlink so both load, or
delete the orphan.

## Precedence: what the docs settle, and what they do not

**Report the conflicting pair. Do not adjudicate it.** Where the official docs define an order, cite
it and name the winner. Where they do not, report the conflict as unresolved and invent no winner.

### Settled: cite and name the winner

| Claim | Where the docs settle it |
|---|---|
| An unscoped rule ranks equal to `.claude/CLAUDE.md` | [memory: set up rules](https://code.claude.com/docs/en/memory#set-up-rules) |
| A mechanism beats instruction text | [memory: deploy organization-wide CLAUDE.md](https://code.claude.com/docs/en/memory#deploy-organization-wide-claude-md) |
| Managed policy cannot be excluded | [memory: exclude specific CLAUDE.md files](https://code.claude.com/docs/en/memory#exclude-specific-claude-md-files) |

### Unresolved: report, and name no winner

| Pair | Why |
|---|---|
| User `CLAUDE.md` vs project `CLAUDE.md` | The memory page concatenates them and states no override between them ([memory: how CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load)). |
| User rule vs project rule | The memory page orders them but says neither overrides the other ([memory: user-level rules](https://code.claude.com/docs/en/memory#user-level-rules)). |
| Skill body vs any `CLAUDE.md` | The skills page states no authority relation between a skill body and a memory surface. Silence is not a winner. |
| Managed policy vs lower scopes | Loading first and being non-excludable are load ordering and non-excludability. The docs never say it overrides. |

**Do not infer a winner from load order.** The memory page orders files by directory and by scope,
beside an explicit denial of override semantics. Reading the order as "later wins" invents
precedence the docs decline to state.

- **Pointer**: when grading a pair's precedence, fetch the section its row names live; a row whose
  section now states a winner, or no longer states one, moves between the two tables.
- **As of**: 2026-10-11
- **Recheck trigger**: one of those sections adds, removes or changes a statement of which
  instruction surface wins.

**The escape hatch worth naming.** Because a mechanism outranks instruction text, an instruction-level
conflict that keeps recurring is often best resolved by moving one side to a mechanism rather than by
rewriting prose: a `PreToolUse` hook, a `permissions.deny` rule, or, for a tool a specific skill must
never call, the skill's own `disallowed-tools` frontmatter (what it removes and for how long:
[skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference), as of
2026-10-11; recheck when that field's row changes). Offer this as an option; the choice is the
operator's.

**Check first that the mechanism resolves the pair rather than breaking one side.** Both tool-removal
forms, a bare-name `permissions.deny` rule and `disallowed-tools`, work by taking the tool out of
Claude's pool, so a skill whose text *requires* that tool is left naming something absent: the
mandate becomes unsatisfiable, not stricter, and the model must improvise. When the mandating side is
a gate, the mechanism has to land together with a rewrite of that side stating what must be true
rather than which tool to call. Recommend the pair, never the rule alone.

**Availability-conditioning does not fail gate 5.** A mandate rephrased as "`X` when it is in the
pool, otherwise ask inline" narrows *how* the act is performed, not *whether* it is. That is a
**subset** of an always-resident prohibition's scope, not a disjoint condition, so a realistic prompt
still fires both wherever the tool is present: gate 5 holds and must-not-flag case 12 does not apply.
Gate 3 then decides the pair on the rewritten text, and the branch to test is the one where the tool
*is* present. A line directing its use there still prescribes an act the prohibition forbids, however
the fallback branch is worded. Do not wave a pair through because one side acquired a condition, and
do not treat a softened verb as self-evidently permissive; that is a gate-3 judgment on specific text,
made by the lane, not a class of drop.

## Running the pass

Two departures from the skill's per-surface lanes, both forced by the pairwise unit:

- **One lane over the pair set, not one lane per surface.** A per-surface lane cannot see the second
  half of a pair. That blindness is the reason this pass exists. Bound it under the skill's own
  dispatch gate.
- **Read beyond the editable set.** A surface the inventory recorded as *skipped*, whether installed
  plugin-cache content, a managed materialization, or org-managed policy CLAUDE.md, is still a valid
  conflict participant, because a contradiction is real whether or not this repo may edit either
  side. Include skipped surfaces as read-only participants. When remediation lands on one, it routes
  to the owning repository per the skill's Scope boundary instead of becoming a proposed diff.

## Must-not-flag set

False positives are the failure mode. Each case below is either suppressed by the pre-scan (pinned in
`scripts/conflict-scan.test.sh`) or dropped by the lane at the named gate.

| # | Case | Dropped by | Gate |
|---|---|---|---|
| 1 | Two directives in the **same file** | pre-scan | not cross-surface by construction |
| 2 | A mandate conditioned on an explicit **user-config opt-in** | pre-scan | 4, since the opt-in is arbitration |
| 3 | A prohibition trailing the entity **past a sentence break**, governing a different object | pre-scan | 2 |
| 4 | A prohibition **distant** from the entity on a long line | pre-scan | 2 |
| 5 | Two surfaces that both **mandate** the same entity | pre-scan | 3 |
| 6 | Disagreement about **different entities** | pre-scan | 2 |
| 7 | **Permissive** language ("may override") read as a mandate | pre-scan | 3 |
| 8 | A surface carrying an explicit **deference clause** | lane | 4 |
| 9 | A **general rule plus a narrower exception** | lane | 3 |
| 10 | Two directives about **different scopes** of one topic | lane | 2 |
| 11 | A **scope declaration**, an artifact listing the surfaces it operates on | lane | 2, since it is not a behavioral claim |
| 12 | Directives scoped to **disjoint conditions** (interactive vs autonomous) | lane | 5 |
| n/a | *Not a case:* one side conditioned on the entity's **availability**, which is a subset, not disjoint. See "Availability-conditioning does not fail gate 5" above | n/a | n/a |
| 13 | The **same word with two referents** across surfaces | lane | 2 |

Case 13 is the sharpest in practice, because keyword overlap is exactly what a text scan sees. Two
live instances: a hook blocking shell-redirection file writes reads as contradicting guidance to use a
heredoc for multi-line strings, but one observable is *writing a file by redirection* and the other is
*passing a string to a command's stdin*; and "never skip emoji reactions" against a no-emoji output
rule is a GitHub reaction API call versus assistant prose. Both are correctly-scoped alignments.

Case 8 is the posture the repo already models: a surface that says the project's documented
conventions override its own baseline wherever they conflict has *resolved* the conflict, not created
one. Treat such a clause as the remediation template for Type C, never as a finding.

Case 9 matters most for an absolute that carries its own exception clause sitting beside a directive
presupposing exactly that exception. The pre-scan marks the exception rather than dropping the pair,
because whether the exception is *reachable from the other surface* is gate 4 and needs judgment: an
exception only a human can trigger is not reachable by an invoked skill, so the pair survives.

## Deterministic pre-scan

`scripts/conflict-scan.sh` narrows the quadratic search space to a review queue. It decides only the
four gates a text scan can decide: distinct files, same entity, opposed polarity, and the opt-in
filter. It emits `fileA:lineA|fileB:lineB|entity|flags`, always exiting 0.

An entity is a CamelCase identifier anywhere, or a single capitalized word **inside backticks**. The
second form is what reaches single-word tools (`Bash`, `Read`, `Edit`); requiring the backticks is what
keeps every sentence-initial capitalized word out. Neither form is a hardcoded tool list, so a tool the
scan has never heard of is still covered, at the cost of precision, since CamelCase proper nouns match
the first form.

Polarity is read from a window around the mention, and **both halves of that window stop at a sentence
boundary**, so only a polarity token in the entity's own sentence classifies it. A prohibition counts
when it precedes the entity within that sentence, or follows it within it. "`WebFetch` must not be
used" is a prohibition, while "…via `X` once. Do not gate per repo" is a trailing clause about a
different object, and "Never delete branches. Always use `X` first" is a mandate rather than a
prohibition inherited from the sentence before it. A boundary is a sentence-ending mark **followed by
a space**, because a bare mark also occurs inside a dotted config path or a version number, **or a
contrastive conjunction** (`but`, `whereas`, `though`, `although`, `yet`), with or without a
preceding comma, since English does not require one. `while` is the exception and still needs its
comma: unpunctuated, it is temporal at least as often as contrastive ("use `X` while the flag is
set" is one clause).
The second form is what keeps one sentence carrying two entities at opposite polarity honest:
"Always use `Read`, but never use `Bash`" must classify `Read` as a mandate and `Bash` as a
prohibition. It is deliberately not *any* comma. Ordinary comma-separated prose keeps its polarity
throughout, and cutting on every comma would drop the token that does govern the entity.

It is advisory. A row is a candidate, never a finding: gates 2 and 5 are not greppable, and the lane
refines every row against the must-not-flag set above.

**It is also a seed, not the population. That limit decides how the lane works, and it is not a caveat.** The scan
only reaches directives that name a *tool-shaped* entity, so an ordinary behavioral pair like
"Always run tests before committing" against "Never run tests before committing" yields **zero**
rows: no CamelCase identifier, no backticked capitalized word, nothing to bucket on. That is a common
and perfectly real Type A conflict.

Widening the entity pattern is not the fix. Only a minority of rows survive entity triage
(measured below); admitting arbitrary verb phrases would bury the queue rather than extend it. **The
lane therefore reads the surfaces in scope, and treats the scan output as a priority ordering rather
than as its work list.** Concretely: work the emitted rows first because they are cheap and
pre-bucketed, then read the in-scope surfaces for directive pairs the scan cannot shape-match, such
as a mandate and a prohibition over the same act stated in ordinary prose. **A pass that reports only what
the scanner emitted has not run this check**, and the report says which of the two it did.

**Why it stays advisory rather than becoming a CI gate.** Measured over this repository's own skill
markdown plus its root `CLAUDE.md` on 2026-09-06, the scan returns 170 candidate rows in a few
seconds. Most of them name a CamelCase *proper noun*, `GitHub`, `PowerShell`, `EventStorming` and
the like, not a directive about a tool: `GitHub` alone accounts for 100 rows and `PowerShell` for
38. A precision rate in that range is a good review queue and a bad gate, so no conflict class in
this pass is currently gate-grade: gates 2 and 5
carry the discrimination, and both need a model. Should a class ever reach gate-grade precision, its
home is a repo-level `scripts/check-*.sh` + `.test.sh` + `ci.yml` lane following the silent-skip
gate's documented lane shape, not this skill.

## Worked examples

Two instances from this repository, both illustrating a different half of the pass. The first is
shown at the state that produced it, with its remediation, because how a Type A pair stops being one
is as instructive as how it is found.

**1. A skill body against the user's global CLAUDE.md: cross-layer, conditional, safety-bearing.**
`~/.claude/CLAUDE.md` carries "Ask questions inline; never use the `AskUserQuestion` tool unless
explicitly asked to use it", resident in every session. Against it,
`plugins/repo-hygiene/skills/clean/SKILL.md` stated "**Mandatory gate:** show dry-run output →
`AskUserQuestion` → only then `--apply`". Measure the corpus at any commit rather than quoting a
figure that drifts:

```bash
git grep -c "AskUserQuestion" -- 'plugins/**/*.md' ':!**/CHANGELOG.md' ':!**/conflict-criteria.md' \
  | awk -F: '{s+=$2} END {print s}'
git grep -n "AskUserQuestion" -- 'plugins/**/*.md' ':!**/CHANGELOG.md' ':!**/conflict-criteria.md' \
  | grep -c use_ask_user_question
```

The second figure is the subset carrying a `use_ask_user_question` opt-in gate on the same line
(must-not-flag case 2); the difference is the ungated remainder. **This file is excluded on purpose.**
It names both tokens, including on the command lines above, so without the exclusion the measurement
counts itself and drifts every time this example is edited.

All five gates held. Gate 4 turns on the prohibition's exception being unreachable: "unless explicitly
asked" is satisfiable by the user, never by an invoked skill. Type A, conditional co-residency,
verdict **unresolved**, because the skills page states no authority relation between a skill body and
a memory surface. It was not a style nit: in `repo-hygiene:clean` and `disk-hygiene:clean` that call
*was* the destructive-action confirmation gate, so resolving toward the CLAUDE.md degraded a safety
mechanism while resolving toward the skill disobeyed a standing instruction. Both anchors were
reported and the choice left to the operator.

Both skills state the gate as invariant-plus-surface: the confirmation bar is unconditional, while the
surface prefers `AskUserQuestion` and falls back to an inline question when it is absent. That wording
exists on its own grounds, because a mandate naming a tool that can be absent (permission mode
`dontAsk`, a **bare-name** `permissions.deny` rule, and a `disallowed-tools` entry can each take it
away; see
[permission modes: dontAsk](https://code.claude.com/docs/en/permission-modes#allow-only-pre-approved-tools-with-dontask-mode),
[permissions: manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions) and
[skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference), as of
2026-10-11; recheck when one of them stops removing or denying the tool) is unsatisfiable in exactly
the sessions that most need a gate. It is not a verdict on the pair. Run the gates against the current text as you would for any
pair, and do not assume that the pair dissolved because one side acquired a condition (gate 5 is
unaffected; see above) or that a softened verb settles gate 3, whose deciding branch is the one where
the tool *is* present. No winner is available to name: the authority relation the Unresolved table
denies still does not exist, and a rewrite on one side is not the operator's decision.

**2. A near-miss the gates correctly reject: description-versus-body divergence.**
`harness-memory:audit`'s `description` (in `SKILL.md`) sells "memory health" and greps zero for
conflict, contradict, or consistency, while that skill's own `reference/criteria.md` ships C6, an explicit
contradiction check. Two different files, both readable, genuinely out of step, and the divergence
has real cost: a search over skill descriptions alone would conclude no conflict detector exists.

**It is still not a conflict, and the pass must not report it as one.** Gate 3 fails: a description
that omits a capability does not prescribe an action incompatible with performing it. Nothing about
"memory health" forbids checking consistency. This is *incompleteness*, which routes to a listing or
discoverability check, not opposed polarity.

Keep it as the calibration case. An auditor that grades summary omissions as contradictions will bury
its real findings, and this is the most persuasive-looking instance in the repository.

## Output format

A conflict finding is a **pair**, so it is reported as one. For each finding give:

- both anchors as `path:line`, mandate side first. **A hook-injected surface has no file of its
  own**, so its anchor is the settings file, plugin `hooks/hooks.json`, or component frontmatter
  where the emitting handler is *configured*, at that handler's line, qualified by its event and
  `matcher`, since that is what makes the text resident. Name it that way rather than dropping the
  anchor: an admitted surface a lane cannot cite is a fix present in name only
- the behavior at issue, stated as the (verb, object, trigger) triple
- the two contradictory claims **quoted verbatim**
- the conflict type (A–C), and which surfaces are guaranteed versus conditional co-residents.
  Orphaned instruction drift is reported separately and is not one of these types
- the precedence verdict: the winner **with its doc citation**, or `unresolved` with the reason

A clean pass ("No cross-surface conflicts found.") is a valid outcome. This pass never edits a file
and never picks a winner the docs do not state.
