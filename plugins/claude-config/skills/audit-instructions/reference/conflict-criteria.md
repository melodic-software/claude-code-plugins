# Cross-Surface Conflict Criteria

Version: 1.5.0
Last updated: 2026-08-15

**The adjudication procedure for check I15.** [criteria.md](criteria.md)'s I15 entry owns the
definition — what a cross-surface conflict *is*, its comparison set, its import and symlink
resolution, its `AGENTS.md` exclusion, its remediation-by-scope rules, and its five must-not-flag
cases. None of that is restated here. This file owns the part a check entry has no room for: **how a
candidate pair is adjudicated** — whether the two surfaces can even co-load, what the official docs
settle about precedence and what they refuse to, and the further must-not-flag cases the pre-scan and
the lane each drop.

The three shared axes (evidence tier, authority, severity) are defined once in
[criteria.md](criteria.md) and are not restated here.

**Recheck triggers** — re-verify against live docs when any fires: a change to the memory page's
precedence or load-order text; a change to the skills page's statements about instruction authority;
any new instruction surface added to the product; a change to how permission rules or permission
modes remove a tool from Claude's pool; a change to **which hook events inject handler output into
the session's context**, to the events `additionalContext` is accepted on, or to the handler types
that can return it; the removal, renaming, or restructuring of the hooks page's **per-event exit-2
table** this file defers to for blockability, or a change to the set of locations a hook may be
declared in; a change to the table's `SubagentStop`, `PostToolUse`, or `PreToolUse` rows — the
three the worked examples below cite. A row added to the table, or a change to any row this file
does not cite, needs no recheck — the partition itself is never restated here.

## Sources

Every precedence claim below is quoted from a page fetched when this file was written. A claim these
pages do not make is recorded as unresolved and given no winner.

- Memory — CLAUDE.md, `.claude/rules/`, auto memory — <https://code.claude.com/docs/en/memory>
- Skills — <https://code.claude.com/docs/en/skills>
- Subagents — what loads into a subagent at startup — <https://code.claude.com/docs/en/sub-agents>
- Output styles — how a style reaches the system prompt — <https://code.claude.com/docs/en/output-styles>
- Permissions — how deny rules and permission modes remove a tool —
  <https://code.claude.com/docs/en/permissions>
- Hooks — handler types, which events inject handler output into context, `additionalContext`,
  exit-code semantics — <https://code.claude.com/docs/en/hooks>
- Context window — what survives compaction, and which hook output reaches Claude —
  <https://code.claude.com/docs/en/context-window>

## Boundary: what C6's population actually is

I15 routes a contradiction whose **both** anchors sit in `claude-memory:audit`'s C6 discovery
population to that check, and keeps every other pair here — including memory-layer pairs C6 still
does not enumerate, and every cross-layer pair. The predicate is the population, never the layer
name.

The `claude-memory:audit` skill's check **C6** asks its question "across CLAUDE.md, CLAUDE.local.md,
and rules files". Its live discovery is
`skills/audit/scripts/discover-instruction-surfaces.sh`, which emits **project and user** scope —
root-level project `CLAUDE.md` / `CLAUDE.local.md` / `.claude/rules/**`, plus
`${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md` and `…/rules/**` — each tagged so project-scoped criteria
can skip personal files. Step 3 of the audit workflow then compares user-scope surfaces against
project ones as live C6 conflicts. That widening closed the silent gap the previous edition of this
section documented: a user-global instruction contradicting a project one is no longer deferred by
I15 into a check that could not see it.

Route on that population:

| Pair | Owner |
|---|---|
| Both anchors in the **discover-instruction-surfaces** population (any mix of project / user / `both` scope among root-level `CLAUDE.md` / `CLAUDE.local.md` / rules) — **including user↔project** | `claude-memory`'s C6 |
| Anything else — **any nested `CLAUDE.md` / `CLAUDE.local.md` side**, any auto-memory side, settings, hooks, skills, agents, output styles, or any other surface outside that population | I15 |

**Nested memory files stay with I15**, for the same reason as before. Phase A inventories every nested
`CLAUDE.md` / `CLAUDE.local.md` in the project tree, while discover-instruction-surfaces is depth-1 by
design — so routing a nested pair to C6 hands it to a check that never reads the file.

**Auto-memory stays with I15** on the same evidence. `claude-memory` audits `MEMORY.md` for size and
index integrity via a separate resolver, but that path is not in the discover-instruction-surfaces
population C6 pairs over. Routing a `MEMORY.md`-versus-`CLAUDE.md` contradiction to C6 would leave it
audited by neither skill's conflict check.

**I15 still owns memory-layer precedence adjudication** — what the docs settle, what they leave
unresolved, and the co-residency / liveness gates in this file — for every pair it keeps. C6 owns
instruction-*content* consistency inside its discovery population; it does not absorb this file's
precedence tables or the surfaces outside that population.

When both anchors are in C6's population, report the pair as an observation and point the operator at
`/claude-memory:audit` rather than grading it here; when that plugin is not installed, keep it as a
finding so nothing is silently dropped. This mirrors the reciprocal routing `claude-memory` already
performs for content-fit findings.

The rule remains **route on the population a check actually enumerates, never on the name of the
layer** — a boundary drawn from a label rather than from the incumbent's discovery script is how a
gap the size of the pre-widening user↔project hole stays invisible. When that script's population
moves again, this table moves with it.

## Prerequisite: co-residency

A conflict requires both directives to be in the same context window at the same time. Matching text
shapes without this gate produces noise, because most surface pairs never co-load.

| Surface | When resident | Source |
|---|---|---|
| User `CLAUDE.md` | Every session, in full | memory: "CLAUDE.md files are loaded in full regardless of length" |
| Project `CLAUDE.md` / `CLAUDE.local.md` | Every session in that tree, concatenated after user scope | memory: "All discovered files are concatenated into context rather than overriding each other" |
| Nested `CLAUDE.md` in a subdirectory | On demand, when Claude reads a file there | memory: "they are included when Claude reads files in those subdirectories" |
| `.claude/rules/*` without `paths` | Every session | memory: "loaded at launch with the same priority as `.claude/CLAUDE.md`" |
| `.claude/rules/*` with `paths` | Only when a matching file is read | memory: "only apply when Claude is working with files matching the specified patterns" |
| Skill body | Only once invoked, then for the rest of the session | skills: "a skill's body loads only when it's used" |
| Auto memory `MEMORY.md` | Every **main** session, first 200 lines or 25KB — **not** in a subagent, except a fork | memory: "The main conversation's auto memory isn't loaded into subagents; the exception is a fork" |
| A subagent's **own** auto memory `MEMORY.md` (its `memory` field) | Every dispatch of **that** subagent, first 200 lines or 25KB — never the main session, and never another agent's | subagents: the field "gives the subagent a persistent directory"; its system prompt "includes the first 200 lines or 25KB of `MEMORY.md` in the memory directory"; memory: "A subagent's own auto memory, enabled with the subagent `memory` field, is a separate directory" |
| Skill bundled `reference/`, `context/` file | Only when Claude reads it | skills: "letting Claude access detailed reference material only when needed" |
| Agent definition (its own subagent) | Always, as that subagent's system prompt — **alongside the full CLAUDE.md hierarchy** | subagents, "What loads at startup" |
| Skill named in an agent's `skills:` field | Always, in that subagent | subagents: "The full content of each listed skill is injected into the subagent's context at startup" |
| Prompt-type hook text | **Never** — see "A prompt hook's text is not an instruction" below | hooks: a `prompt` hook "send[s] a prompt to a Claude model for single-turn evaluation" |
| Handler **stdout** on `SessionStart`, `UserPromptSubmit`, `UserPromptExpansion` | From injection onward, as ordinary message history | hooks: "The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, and `SessionStart`, where stdout is added as context that Claude can see and act on" |
| Handler `hookSpecificOutput.additionalContext` on a **main-session** event | From injection onward, at the position the event dictates | hooks: "Where the reminder appears depends on the event" — session start, alongside the prompt, next to the tool result, or at the end of the turn |
| Handler `hookSpecificOutput.additionalContext` on `SubagentStart` / `SubagentStop` | In **that subagent's** context, never the main session's | hooks, `SubagentStart`: "Context added to **the subagent's** context for the duration of the subagent session"; `SubagentStop`: "Context added to **the subagent's** context" |
| Handler **stdout** on any other event | **Never** | hooks: "For most events, stdout is written to the debug log but not shown in the transcript" |
| Output style (the **active** one) | Every session in the main conversation, appended to the system prompt | output-styles: "Output styles directly modify Claude Code's system prompt"; "read once at session start" |

**An agent definition co-resides with the whole CLAUDE.md hierarchy, and that is a guaranteed pair.**
A non-fork subagent's initial context contains "every level of the CLAUDE.md hierarchy the main
conversation loads, including `~/.claude/CLAUDE.md`, project rules, `CLAUDE.local.md`, and managed
policy files". So an agent definition contradicting a `CLAUDE.md` clears gate 1 outright — it does not
need the conditional treatment a skill body gets.

**Auto memory is the exception inside that hierarchy.** "The main conversation's auto memory isn't
loaded into subagents; the exception is a fork, which inherits the parent conversation and system
prompt. A subagent's own auto memory, enabled with the subagent `memory` field, is a separate
directory" (memory). So an agent definition against the **main** `MEMORY.md` fails gate 1 — the two
never occupy one context — and pairing them reports a conflict between contexts that do not coexist.
Two pairs remain real and should not be swept away with it: a **fork** does inherit the parent, and a
subagent that enables its own `memory` can contradict the definition it runs under, but that is the
subagent's own memory directory, not the main conversation's.

**The two exceptions are `Explore` and `Plan`**, which "skip your CLAUDE.md files and the parent
session's git status", and "there is no frontmatter field or per-agent setting to change which agents
skip them." A pair whose only memory-layer half reaches an `Explore` or `Plan` delegation therefore
fails gate 1 — and the docs name the correct remediation, which is to restate the rule in the
delegation prompt rather than to reconcile the two surfaces.

**Only the active output style is resident, and only in the main conversation.** A style becomes
active through the `outputStyle` setting or a plugin's `force-for-plugin`; every other style on disk
is inventoried but never loaded, so a pair reaching an inactive style fails gate 1 outright. Two
further bounds from the same page: a style applies "to the main conversation only: a subagent runs its
own system prompt", with a fork the exception — so an output style never pairs with an agent
definition except via a fork — and it is read "once at session start", so a mid-session edit is not
resident until the next session.

**A prompt hook's text is not an instruction to the main session.** Per
[hooks](https://code.claude.com/docs/en/hooks), a `type: "prompt"` handler "send[s] a prompt to a
Claude model for single-turn evaluation. The model returns a yes/no decision as JSON" — a separate
model call, evaluated in isolation, never injected into the main conversation. Comparing that raw
prompt against a `CLAUDE.md`, a skill, or an output style manufactures conflicts between two models
that satisfy their own instructions independently: an evaluator told to *return JSON only* does not
contradict a main-session rule requiring Markdown output.

So a prompt hook enters the comparison set as the **constraint it imposes**, never as its prose:

- The **act** it gates, taken from the decision the evaluator can return, together with the hook's
  `matcher` and event — a `PreToolUse` hook matching `Bash` constrains Bash calls, and nothing else.
- Not the wording of the prompt, the output format it demands of its evaluator, the persona it sets,
  or any directive whose only audience is that evaluator.

A pair is then real when a resident instruction tells the main session to do something the hook's
gate would block under a matching input — "always run `git push --force` after a rebase" against a
`PreToolUse` hook that denies force-pushes. That is a genuine unsatisfiable pair; a formatting
directive addressed to the evaluator is not. An `agent` handler is treated the same way: it too
"spawn[s] a subagent … before returning a decision", so it enters as the act it gates.

**But the discriminator is whether the handler's output reaches this session's context, not whether
the handler is `type: "command"`.** [hooks](https://code.claude.com/docs/en/hooks) lists five
handler types — `command`, `http`, `mcp_tool`, `prompt`, `agent` — and settles *which channel
reaches context* per **event**, not per type: for most events "stdout is written to the debug log
but not shown in the transcript. The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, and
`SessionStart`, where stdout is added as context that Claude can see and act on", and
`hookSpecificOutput.additionalContext` is accepted on a wider event set still. Nor is the JSON
channel type-scoped: an `http` handler's "response body uses the same JSON output format as command
hooks", and an `mcp_tool` handler's "tool's text content is treated like command-hook stdout".

**Type still decides one thing, and it is not the channel: registrability.** "Not all events support
every hook type" — `SessionStart`, for one, states "Only `type: "command"` and `type: "mcp_tool"`
hooks are supported". So resolve the event×type pair against the docs before admitting a surface:
an `http` handler on `SessionStart` is not a surface with unreadable text, it is a hook that cannot
be registered there at all. An `http` handler also has no stdout — it returns a response body — so
the stdout channel above is `command` and `mcp_tool` only, while the `additionalContext` channel is
open to `http` on the events that accept both.

So **a handler whose output is injected as context enters the comparison set as that text**, on the
same terms as any other instruction surface. A `SessionStart` command hook printing a standing
behavioral block ("respond tersely … applies to every response") is live directive text in this
session's context window, and pairing it against an output style's format contract or a `CLAUDE.md`
rule is exactly what gate 1 is for. Excluding it because the handler is `type: "command"` drops one
half of a pair that provably co-resides — and does so silently, since a per-surface lane never sees
the surface at all.

**A subagent-scoped injection is not resident here.** `SubagentStart` and `SubagentStop` add
"Context added to **the subagent's** context", so their `additionalContext` fails gate 1 against any
main-session surface exactly as the active output style does ("to the main conversation only: a
subagent runs its own system prompt"). It is a real surface in the subagent's own context, where it
can contradict the agent definition it runs under or a skill named in that agent's `skills:` field —
pair it there, and never against the main conversation's `MEMORY.md` or active output style.

**What the compaction table does and does not say.** The context-window page's "What survives
compaction" table gives hooks one row, whose cell reads "Not applicable; hooks run as code, not
context". That is a statement about the hook *mechanism*: a hook definition is not a context block
to be re-injected, the way root `CLAUDE.md` is. It says nothing about the handler's output, and the
same page says the opposite about that output — in the `desc` text of its embedded context-window
simulation, a `PostToolUse` hook "reports back via `hookSpecificOutput.additionalContext`. That
field enters Claude's context." Reading the compaction row as an exclusion rule is what produced
this gap.

Three consequences for residency, and each one bounds a pair rather than admitting it wholesale:

- **Injected text is ordinary message history, not a re-injected surface.** It is resident from the
  moment it lands and, unlike root `CLAUDE.md`, nothing re-injects it from disk after compaction.
  Composing two doc facts: a `SessionStart` hook does re-fire on the `compact` matcher ("Auto or
  manual compaction"), so a hook registered for it re-injects and a hook registered only for
  `startup` does not. Treat a pair whose hook half is `startup`-only as conditional after a
  compaction, and say so rather than asserting permanent residency.
- **Exit-2 stderr is turn-scoped error feedback, not a standing directive — and only some events
  have an act to block.** "Exit 2 means a blocking error … stderr text is fed back to Claude as an
  error message." It reaches Claude, so it is not nothing; but it is a one-turn message, never a
  standing rule. Whether it also carries a *gate* is event-specific, and the sole authority on that
  is the hooks page's
  [Exit code 2 behavior per event](https://code.claude.com/docs/en/hooks#exit-code-2-behavior-per-event)
  table. Its rows are not reproduced here in either direction: the event set grows, so any list
  copied into this file becomes a closed partition that silently misgrades the next event added.
  Resolve the handler's event, read that event's row, and pair on the row's own `Can block?` cell:
  - **The cell says yes** — the conflict-bearing content is whatever that row states is prevented,
    quoted from the row rather than assumed. What a row prevents is not always a tool call or a
    prompt; the cell, never the gate abstraction, supplies the paired content. `SubagentStop`
    blocks but is subagent-scoped: its act pairs inside the subagent, under the subagent-scoping
    rule above, and never against a main-session surface.
  - **The cell says no** — nothing is prevented, so there is no act and no gate to pair; treat the
    message as transient feedback and pair it as nothing. `PostToolUse` is the worked example: its
    row says so outright ("the tool already ran"), and this repository's own `PostToolUse` linter
    is built on that row — `plugins/actionlint/hooks/actionlint-check.sh` deliberately always
    exits 0 and surfaces findings as advisory context, because an exit 2 there could block
    nothing. Reading any `PostToolUse` handler's exit-2 stderr as a prohibition on the tool it ran
    *after* would manufacture an unsatisfiable conflict against any instruction requiring that
    tool — the tool already ran, and the hook can neither block nor undo it. Registered instead on
    `PreToolUse`, whose row blocks the tool call, the same handler WOULD enter the comparison set
    as the act it blocks.
  - **The event has no row, or the table could not be reached** — record the surface with its event
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
  a `liveness-unresolved` surface — report the pair as such, and never infer the text from the script
  name, the handler's arguments, or what a hook of that shape usually emits. Inventing the half you
  cannot read is a worse failure than the exclusion this section replaces, because it manufactures a
  quotation.

**Guaranteed pairs** are any two of {user `CLAUDE.md`, project `CLAUDE.md`, unscoped rules,
`MEMORY.md`}, and any agent definition against any of them **except `MEMORY.md`**, and except via
`Explore` / `Plan`.
**Conditional pairs** involve a skill body, a path-scoped rule, a nested `CLAUDE.md`, or
context-injected hook output — real, but they only bite once that surface loads. Hook output is
conditional on its own event and `matcher` firing, which for a `SessionStart` `startup` hook means
every new session but not necessarily after a compaction. Report the distinction; do not drop
conditional pairs, because the worked example below is one.

## Prerequisite: effective liveness, which the tree does not determine

Co-residency asks *when* a surface loads. This gate asks a prior question — **whether it loads at
all in this session** — and the answer is not a function of the file tree. Six session-level inputs
change it — the first five from [memory](https://code.claude.com/docs/en/memory), the last from
[hooks](https://code.claude.com/docs/en/hooks), because a hook's instruction text is only as live as
the handler that carries it:

- **Launch directory.** "if you run Claude Code in `foo/bar/`, it loads instructions from
  `foo/bar/CLAUDE.md`, `foo/CLAUDE.md`, and any `CLAUDE.local.md` files alongside them" — which
  ancestors are candidates at all follows from where the session started, not from the repo root.
- **`claudeMdExcludes`.** "Patterns are matched against absolute file paths using glob syntax. You
  can configure `claudeMdExcludes` at any settings layer: user, project, local, or managed policy.
  Arrays merge across layers." A file the tree contains may therefore be dead. (Managed policy
  CLAUDE.md is the one thing exclusion cannot reach.)
- **`--setting-sources`.** "Project rules are skipped if you exclude `project` from
  `--setting-sources`" — a `.claude/rules/` file on disk then contributes nothing.
- **`--add-dir` with `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`.** Setting it "loads
  `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`, and `CLAUDE.local.md` from the additional
  directory" — live surfaces a walk of the project tree never sees.
- **A declined external-import approval.** "If you decline, the imports stay disabled and the dialog
  doesn't appear again" — persistent, machine-local, and invisible in the tree.
- **Effective hook enablement, which resolves per scope and not per file.** "To temporarily disable
  all hooks without removing them, set `"disableAllHooks": true` in your settings file" — the
  configured entry survives, so the tree still shows a hook that cannot fire. It "respects the
  managed settings hierarchy": `disableAllHooks` "set in user, project, or local settings can't
  disable those managed hooks. Only `disableAllHooks` set at the managed settings level can disable
  managed hooks", so a lower-scope disable leaves managed hook text **live** and it must not be
  dropped with the rest. The mirror control cuts the other way: "Enterprise administrators can use
  `allowManagedHooksOnly` to block user, project, and plugin hooks. Hooks from plugins force-enabled
  in managed settings `enabledPlugins` are exempt." Either one silences instruction text this
  session while leaving it on disk, and neither is readable from the tree.

A pass that skips this gate reports conflicts between instructions one side of which is dead, and
misses live counterparts that were never inventoried. Both failures are silent, and both are
reproducible only on the machine that produced them.

**So resolve effective liveness before pairing, and record what you resolved.** Take the session's
launch directory, the merged effective values of `claudeMdExcludes`, `--setting-sources`, and the
additional-directory inputs, and `disableAllHooks` **at each settings scope** together with
`allowManagedHooksOnly`; drop excluded and source-skipped surfaces from the comparison set, drop
every hook surface the resolved enablement silences — prompt-type and context-injecting alike, since
neither reaches this session when the handler never fires — while keeping managed hook text against a
user, project, or local `disableAllHooks`, and add the memory files the additional directories
contribute. Where a value cannot be resolved — an
inventory taken outside the session it describes, a declined import that leaves no trace in the tree
— mark the affected surfaces `liveness-unresolved` and report pairs touching them as such rather
than grading them. **Name the resolved controls in the pass's tier-transparency line**: a
finding whose liveness depends on a machine-local setting is not reproducible elsewhere, and a reader
comparing two machines' reports needs to know which inputs differed.

## Known limit: Phase A does not reach the plugin-source tree

**Installed plugins are covered; a marketplace repository's own `plugins/` source tree is not.**
These are different surfaces and only one of them is a limit. Phase A's read-only tier reads the
*installed cache* of every enabled plugin at its selected install record — skill bodies, agent
definitions, `type: "prompt"` handler text, and the active output style — so an agent definition
shipped by an enabled plugin does have its second side, and an agent-versus-memory pair is
available rather than missing.

What Phase A still does not enumerate is the **authoring** tree: `plugins/**` in a marketplace
repository is plugin *source*, not an installed plugin, and nothing there is loaded into the session
being audited. Pairs drawn wholly from it — a skill's stated default against its own plugin README —
therefore have no second side. ADR 0005 makes extending Phase A a precondition of that placement,
and it is tracked as
[#1421](https://github.com/melodic-software/claude-code-plugins/issues/1421) rather than folded in
here, since it widens what *every* phase reads. **Report that narrower limit in the pass's
tier-transparency line** — and only that one: reporting installed-plugin surfaces as uncovered would
understate coverage the pass now has.

## Scope filters findings, never reads

`audit-instructions` takes a scope argument that narrows Phase A's inventory. A pairwise observable
is undefined on one side, so under `skills` the `CLAUDE.md` half of every cross-layer pair would
simply be absent — and the pass would report clean while appearing to have run, which is worse than
declining to run.

**So this pass enumerates every surface `all` would collect, read-only, and applies the scope to the
finding instead: report a pair when at least one of its anchors is in scope.** That keeps a scoped
invocation honest without making the conflict check an `all`-only feature.

## The five gates

A pair is a conflict only when **all five** hold. Any gate failing removes it from the finding set.

1. **Co-residency** — the two surfaces can be resident simultaneously, per the table above.
2. **Same observable** — both constrain the same decidable act, identified as a (verb, object,
   trigger) triple rather than by topic similarity. "Emoji in a GitHub reaction" and "emoji in
   assistant prose" are two observables, not one.
3. **Opposed polarity** — for at least one input satisfying both triggers, the two prescribed actions
   cannot both be taken.
4. **No arbitration** — neither directive, nor any third resident text, says which wins. An explicit
   precedence sentence, a deference clause, or a config opt-in gate resolves the pair.
5. **Non-vacuous trigger overlap** — a realistic prompt fires both. Directives scoped to disjoint
   conditions (interactive versus autonomous, code versus prose) do not overlap.

### Conflict types, by remediation route

- **Type A — direct contradiction.** Both absolute, opposite polarity. Route: arbitrate, or drop one.
- **Type B — modality collision.** One absolute ("never"), one conditional ("when warranted"), same
  act. The absolute reads as a hard rule and the conditional reads as license, and neither author
  sees the other.
- **Type C — unarbitrated co-authority.** Two surfaces each assert ownership of one decision with no
  precedence statement. Route: one precedence sentence at the higher surface.

**Split-brain is a precursor, not a fourth type.** Two files governing one behavior where only one is
ever loaded fails gate 1 by construction, so it can never be a conflict finding — listing it as a
conflict type would either make it unreachable or force the lane to flag non-co-resident files. Report
it separately as **orphaned instruction drift**: not a contradiction today, but the state a
contradiction grows out of once the two copies diverge. Route: import or symlink so both load, or
delete the orphan.

## Precedence: what the docs settle, and what they do not

**Report the conflicting pair. Do not adjudicate it.** Where the official docs define an order, cite
it and name the winner. Where they do not, report the conflict as unresolved and invent no winner.

### Settled — cite and name the winner

| Claim | Verbatim source |
|---|---|
| Project rules beat user rules | memory: "User-level rules are loaded before project rules, **giving project rules higher priority**." |
| An unscoped rule ranks equal to `.claude/CLAUDE.md` | memory: "Rules without `paths` frontmatter are loaded at launch with the **same priority** as `.claude/CLAUDE.md`." |
| A mechanism beats instruction text | memory: "Settings rules are enforced by the client regardless of what Claude decides to do. CLAUDE.md instructions shape Claude's behavior but are **not a hard enforcement layer**." |
| Managed policy cannot be excluded | memory: "Managed policy CLAUDE.md files cannot be excluded." |

### Unresolved — report, and name no winner

| Pair | Why |
|---|---|
| User `CLAUDE.md` vs project `CLAUDE.md` | memory: "All discovered files are **concatenated into context rather than overriding each other**", and "Claude may pick one arbitrarily." |
| Skill body vs any `CLAUDE.md` | The skills page states no authority relation between a skill body and a memory surface. Silence is not a winner. |
| Managed policy vs lower scopes | "Loads before" and "cannot be excluded" are load ordering and non-excludability. The docs never say it overrides. |

**Do not infer a winner from load order.** The memory page's "instructions closer to where you
launched Claude are read last" is ordering prose that sits beside an explicit denial of override
semantics. Reading it as "later wins" invents precedence the docs decline to state.

**The escape hatch worth naming.** Because a mechanism outranks instruction text, an instruction-level
conflict that keeps recurring is often best resolved by moving one side to a mechanism rather than by
rewriting prose — a `PreToolUse` hook, a `permissions.deny` rule, or, for a tool a specific skill must
never call, the skill's own `disallowed-tools` frontmatter (skills: "Tools removed from Claude's
available pool while this skill is active. Use for autonomous skills that should never call certain
tools, such as `AskUserQuestion` for a background loop"). Offer this as an option; the choice is the
operator's.

**Check first that the mechanism resolves the pair rather than breaking one side.** Both tool-removal
forms — a bare-name `permissions.deny` rule and `disallowed-tools` — work by taking the tool out of
Claude's pool, so a skill whose text *requires* that tool is left naming something absent: the
mandate becomes unsatisfiable, not stricter, and the model must improvise. When the mandating side is
a gate, the mechanism has to land together with a rewrite of that side stating what must be true
rather than which tool to call. Recommend the pair, never the rule alone.

**Availability-conditioning does not fail gate 5.** A mandate rephrased as "`X` when it is in the
pool, otherwise ask inline" narrows *how* the act is performed, not *whether* it is. That is a
**subset** of an always-resident prohibition's scope, not a disjoint condition, so a realistic prompt
still fires both wherever the tool is present: gate 5 holds and must-not-flag case 12 does not apply.
Gate 3 then decides the pair on the rewritten text, and the branch to test is the one where the tool
*is* present — a line directing its use there still prescribes an act the prohibition forbids, however
the fallback branch is worded. Do not wave a pair through because one side acquired a condition, and
do not treat a softened verb as self-evidently permissive; that is a gate-3 judgment on specific text,
made by the lane, not a class of drop.

## Running the pass

Two departures from the skill's per-surface lanes, both forced by the pairwise unit:

- **One lane over the pair set, not one lane per surface.** A per-surface lane cannot see the second
  half of a pair — that blindness is the reason this pass exists. Bound it under the skill's own
  dispatch gate.
- **Read beyond the editable set.** A surface the inventory recorded as *skipped* — installed
  plugin-cache content, a managed materialization, org-managed policy CLAUDE.md — is still a valid
  conflict participant, because a contradiction is real whether or not this repo may edit either
  side. Include skipped surfaces as read-only participants. When remediation lands on one, it routes
  to the owning repository per the skill's Scope boundary instead of becoming a proposed diff.

## Must-not-flag set

False positives are the failure mode. Each case below is either suppressed by the pre-scan (pinned in
`scripts/conflict-scan.test.sh`) or dropped by the lane at the named gate.

| # | Case | Dropped by | Gate |
|---|---|---|---|
| 1 | Two directives in the **same file** | pre-scan | not cross-surface by construction |
| 2 | A mandate conditioned on an explicit **user-config opt-in** | pre-scan | 4 — the opt-in is arbitration |
| 3 | A prohibition trailing the entity **past a sentence break**, governing a different object | pre-scan | 2 |
| 4 | A prohibition **distant** from the entity on a long line | pre-scan | 2 |
| 5 | Two surfaces that both **mandate** the same entity | pre-scan | 3 |
| 6 | Disagreement about **different entities** | pre-scan | 2 |
| 7 | **Permissive** language ("may override") read as a mandate | pre-scan | 3 |
| 8 | A surface carrying an explicit **deference clause** | lane | 4 |
| 9 | A **general rule plus a narrower exception** | lane | 3 |
| 10 | Two directives about **different scopes** of one topic | lane | 2 |
| 11 | A **scope declaration** — an artifact listing the surfaces it operates on | lane | 2 — not a behavioral claim |
| 12 | Directives scoped to **disjoint conditions** (interactive vs autonomous) | lane | 5 |
| — | *Not a case:* one side conditioned on the entity's **availability** — a subset, not disjoint. See "Availability-conditioning does not fail gate 5" above | — | — |
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
four gates a text scan can decide — distinct files, same entity, opposed polarity, and the opt-in
filter — and emits `fileA:lineA|fileB:lineB|entity|flags`, always exiting 0.

An entity is a CamelCase identifier anywhere, or a single capitalized word **inside backticks**. The
second form is what reaches single-word tools (`Bash`, `Read`, `Edit`); requiring the backticks is what
keeps every sentence-initial capitalized word out. Neither form is a hardcoded tool list, so a tool the
scan has never heard of is still covered — at the cost of precision, since CamelCase proper nouns match
the first form.

Polarity is read from a window around the mention, and **both halves of that window stop at a sentence
boundary**, so only a polarity token in the entity's own sentence classifies it. A prohibition counts
when it precedes the entity within that sentence, or follows it within it — "`WebFetch` must not be
used" is a prohibition, while "…via `X` once. Do not gate per repo" is a trailing clause about a
different object, and "Never delete branches. Always use `X` first" is a mandate rather than a
prohibition inherited from the sentence before it. A boundary is a sentence-ending mark **followed by
a space** — a bare mark also occurs inside a dotted config path or a version number — **or a
contrastive conjunction** (`but`, `whereas`, `though`, `although`, `yet`), with or without a
preceding comma, since English does not require one. `while` is the exception and still needs its
comma: unpunctuated, it is temporal at least as often as contrastive ("use `X` while the flag is
set" is one clause).
The second form is what keeps one sentence carrying two entities at opposite polarity honest:
"Always use `Read`, but never use `Bash`" must classify `Read` as a mandate and `Bash` as a
prohibition. It is deliberately not *any* comma — ordinary comma-separated prose keeps its polarity
throughout, and cutting on every comma would drop the token that does govern the entity.

It is advisory. A row is a candidate, never a finding: gates 2 and 5 are not greppable, and the lane
refines every row against the must-not-flag set above.

**It is also a seed, not the population — and this is a load-bearing limit, not a caveat.** The scan
only reaches directives that name a *tool-shaped* entity, so an ordinary behavioral pair like
"Always run tests before committing" against "Never run tests before committing" yields **zero**
rows: no CamelCase identifier, no backticked capitalized word, nothing to bucket on. That is a common
and perfectly real Type A conflict.

Widening the entity pattern is not the fix. Precision is already 28% on the tool-shaped rows
(measured below); admitting arbitrary verb phrases would bury the queue rather than extend it. **The
lane therefore reads the surfaces in scope, and treats the scan output as a priority ordering rather
than as its work list.** Concretely: work the emitted rows first because they are cheap and
pre-bucketed, then read the in-scope surfaces for directive pairs the scan cannot shape-match — a
mandate and a prohibition over the same act stated in ordinary prose. **A pass that reports only what
the scanner emitted has not run this check**, and the report says which of the two it did.

**Why it stays advisory rather than becoming a CI gate.** Measured over this repository's own skill
bodies plus its root `CLAUDE.md`, the scan returns 169 candidate rows in about 2 seconds. 121 of them
name a CamelCase *proper noun* — `GitHub`, `PowerShell`, `EventStorming`, `GraphQL` — not a directive
about a tool. Only the `AskUserQuestion` rows survive entity triage. A 28% precision rate is a good
review queue and a bad gate, so no conflict class in this pass is currently gate-grade: gates 2 and 5
carry the discrimination, and both need a model. Should a class ever reach gate-grade precision, its
home is a repo-level `scripts/check-*.sh` + `.test.sh` + `ci.yml` lane following the silent-skip
gate's documented lane shape — not this skill.

## Worked examples

Two instances from this repository, both illustrating a different half of the pass. The first is
shown at the state that produced it, with its remediation, because how a Type A pair stops being one
is as instructive as how it is found.

**1. A skill body against the user's global CLAUDE.md — cross-layer, conditional, safety-bearing.**
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
(must-not-flag case 2); the difference is the ungated remainder. **This file is excluded on purpose**
— it names both tokens, including on the command lines above, so without the exclusion the measurement
counts itself and drifts every time this example is edited.

All five gates held. Gate 4 turns on the prohibition's exception being unreachable: "unless explicitly
asked" is satisfiable by the user, never by an invoked skill. Type A, conditional co-residency,
verdict **unresolved** — the skills page states no authority relation between a skill body and a
memory surface. It was not a style nit: in `repo-hygiene:clean` and `disk-hygiene:clean` that call
*was* the destructive-action confirmation gate, so resolving toward the CLAUDE.md degraded a safety
mechanism while resolving toward the skill disobeyed a standing instruction. Both anchors were
reported and the choice left to the operator.

**What changed on the mandate side — and why that is not a verdict.** Both skills now state the gate
as invariant-plus-surface: the confirmation bar is unconditional, while the surface prefers
`AskUserQuestion` and falls back to an inline question when it is absent. That rewrite was made on its
own grounds, not to win this pair: the old wording named a tool that can be absent — permission mode
`dontAsk` denies it *"even if you've allowed"* it, a **bare-name** `permissions.deny` rule *"removes
the tool from Claude's context entirely"*, and a `disallowed-tools` entry removes it *"from Claude's
available pool while this skill is active"* — so the mandate was unsatisfiable in exactly the sessions
that most needed a gate.

**This file deliberately does not adjudicate the resulting pair.** The rewrite was authored in the
same repository as this criteria doc, so a verdict recorded here would be the author grading their own
text — and the pair's operator-level half is an open, undecided question
([#1722](https://github.com/melodic-software/claude-code-plugins/issues/1722)). Run the gates against
the current text as you would for any pair. Two things not to assume while doing it: that the pair
dissolved because one side acquired a condition (gate 5 is unaffected — see above), and that a
softened verb settles gate 3 — the branch that decides it is the one where the tool *is* present.

What the closed history does establish: **no winner was named**, and none was available to name. The
authority relation the Unresolved table denies still does not exist, and a rewrite on one side is not
the operator's decision — it must never be recorded as one.

**2. A near-miss the gates correctly reject — description-versus-body divergence.**
`claude-memory:audit`'s `description` (in `SKILL.md`) sells "memory health" and greps zero for
conflict, contradict, or consistency, while `reference/criteria.md` ships C6, an explicit
contradiction check. Two different files, both readable, genuinely out of step — and the divergence
has real cost: it is why repeated incumbent searches over skill descriptions concluded no conflict
detector existed in this repository.

**It is still not a conflict, and the pass must not report it as one.** Gate 3 fails: a description
that omits a capability does not prescribe an action incompatible with performing it. Nothing about
"memory health" forbids checking consistency. This is *incompleteness*, which routes to a listing or
discoverability check — not opposed polarity.

Keep it as the calibration case. An auditor that grades summary omissions as contradictions will bury
its real findings, and this is the most persuasive-looking instance in the repository.

## Output format

A conflict finding is a **pair**, so it is reported as one. For each finding give:

- both anchors as `path:line`, mandate side first. **A hook-injected surface has no file of its
  own**, so its anchor is the settings file, plugin `hooks/hooks.json`, or component frontmatter
  where the emitting handler is *configured*, at that handler's line — qualified by its event and
  `matcher`, since that is what makes the text resident. Name it that way rather than dropping the
  anchor: an admitted surface a lane cannot cite is a fix present in name only
- the behavior at issue, stated as the (verb, object, trigger) triple
- the two contradictory claims **quoted verbatim**
- the conflict type (A–C), and which surfaces are guaranteed versus conditional co-residents —
  orphaned instruction drift is reported separately and is not one of these types
- the precedence verdict: the winner **with its doc citation**, or `unresolved` with the reason

A clean pass ("No cross-surface conflicts found.") is a valid outcome. This pass never edits a file
and never picks a winner the docs do not state.
