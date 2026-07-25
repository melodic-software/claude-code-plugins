# C — adversarial audit of the Brief and the coverage ledger

Scope: `docs/topics/discovery-subagent-dispatch/PLAN.md`,
`LEDGER.md`, and
`.work/discovery-subagent-dispatch/audit/B01.md`–`B11.md`.

Harness claims were re-verified this session against
<https://code.claude.com/docs/en/sub-agents>, <https://code.claude.com/docs/en/skills>, and
<https://code.claude.com/docs/en/hooks> (fetched 2026-07-24), and against the installed harness:
`claude --version` → **2.1.219**.

**Findings: 2 CRITICAL · 8 IMPORTANT · 4 SUGGESTION.**

---

## CRITICAL

### C1 — "Result: zero flips" rests on a re-test that covered 13 of 36 candidate rows

- **Where:** `LEDGER.md:108-117`.
- **What is claimed:** the mid-flow / irreversible-action rule "was added after B01–B08 returned.
  B02, B07, B10, and B11 applied it natively … B01, B04, B05, and B06 predated it, so their 21
  INLINE-ONLY rows were re-tested against it here. **Result: zero flips.**"
- **What is actually true.** Of B01–B08, the batches said to have applied the rule natively are B02
  and B07; the batches re-tested are B01, B04, B05, B06. **B03 and B08 appear in neither set.**
  Scripted INLINE-ONLY counts from the batch artifacts: B01 4, B02 4, B03 6, B04 5, B05 4, B06 8,
  B07 1, B08 9, B09 10, B10 2, B11 4 (total 57, matching the ledger). So:
  - 13 rows re-tested row by row (B01 4 + B04 5 + B05 4),
  - 8 rows tested only "at its summary's argument level rather than row by row" — the ledger's own
    admission at line 117 (B06),
  - **15 rows never tested at all** (B03 6 + B08 9).

  "Result: zero flips" is presented as a result over 21 rows; it is a result over 13.
- **The exposure is demonstrated, not hypothetical.** Criteria line 54 requires: "name the blocker
  as the absence of a USER, never as the absence of `AskUserQuestion`". `B03:22` justifies
  `/discovery:blindspot` = INLINE-ONLY with "an interactive user turn a subagent cannot take
  (`AskUserQuestion` is filter-1 blocked)" — the exact tool-shaped form the criteria call
  defeasible. `B03:33` (`/docs-hygiene:rename-references`) and `B03:27` (`/disk-hygiene:clean`)
  lead with the same shape, though both name a substantive gate as well.
- **Fix:** re-test B03's and B08's 15 INLINE-ONLY rows, and downgrade the B06 claim to what line 117
  already concedes.

### C2 — The filter-1 quantifiers ("everywhere", "every subagent") are contradicted by the fork exemption the same work relies on

- **Where:** `PLAN.md:34` ("Filter 1 (everywhere)"), `PLAN.md:40` ("`Workflow` is unavailable in
  **every subagent**"), `PLAN.md:43` ("`AskUserQuestion` is unavailable in **every subagent**").
- **What the doc says**, in the sentence that introduces both filters:

  > "Subagents inherit the built-in tools and MCP tools available in the main conversation, narrowed
  > by two filters … **Forks skip both filters and receive the
  > main conversation's exact tool pool.**"

  and, in the fork section:

  > "A fork is a subagent that inherits the entire conversation so far instead of starting fresh …
  > a fork sees the same system prompt, tools, model, and message history as the main session"

  A fork is explicitly a subagent. The only documented carve-out inside the exemption is `Agent`:
  "in a fork the tool stays listed but returns an error instead of spawning."
- **Precise scope of the defect.** I am not claiming a fork can prompt the user; whether
  `AskUserQuestion` *functions* from a background fork is undocumented in either direction. The
  defect is that the Brief states an unconditional quantifier the doc conditions, and the condition
  is not academic here: `history-fork` is one of the four mechanisms in the ledger's own vocabulary
  (`LEDGER.md:34-36`), amendment 3 (`PLAN.md:90-94`) elevates it to a live
  fourth mechanism, and `/session-flow:orient` is verdicted on it (`B09`). The Constraints block and
  the mechanism vocabulary therefore describe incompatible tool pools for the same mechanism.
- **Downstream:** `PLAN.md:41-42` treats `research-deep`'s inline-dispatcher requirement as proven
  by "Workflow is unavailable in every subagent". The requirement is still correct — `B03:26` shows
  `research-deep/SKILL.md:18` states it independently, and the multi-topic path needs `Agent` — but
  the proof offered does not cover a fork.

---

## IMPORTANT

### I1 — "`TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate` do not survive the background filter" is unqualified, and the qualification is load-bearing

Ranked IMPORTANT rather than CRITICAL because no verdict flips on it — what is holed is a
decision's stated rationale and a blocker rule's phrasing.

- **Where:** `PLAN.md:45-46`; propagated to `LEDGER.md:50` as a fleet-wide
  hard blocker, and to `PLAN.md:75` (Decision 5) as the *stated reason* the coverage ledger must be
  a file: "The file is mandatory because dispatched agents have no Task tools."
- **What the doc says.** The background-filter paragraph is immediately followed by:

  > "Teammates in [agent teams](/docs/en/agent-teams) additionally keep the task tools and cron
  > tools: `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`, `CronCreate`, `CronDelete`, and
  > `CronList`."

  The claim is true for a subagent spawned through the Agent tool and false for a teammate. The
  Brief states it as a property of dispatch as such.
- **Blast radius, per row.** I checked the rows that lean on it rather than asserting a sweep:
  - **Decision 5's rationale is holed, its conclusion is not.** A file on disk is still the right
    artifact — it survives the agent, is readable by the parent, and is diffable. But the *reason*
    given is the only reason given, and it is conditional on the dispatch mechanism. Decision 5
    needs a reason that does not depend on the tool filter (durability and parent-readability
    both work).
  - `/implementation:implement` (`B05`, INLINE-ONLY) — verdict survives. `TaskCreate` is cited
    alongside plan mode, and `EnterPlanMode` is filter-1 dropped everywhere. Note the escape hatch
    is closed twice over: a plugin agent cannot set `permissionMode: plan` to retain
    `ExitPlanMode`, because `permissionMode` is ignored for plugin subagents.
  - `/session-flow:reconcile` (`B09:25`, INLINE-ONLY) — verdict survives on the independent
    ground the row itself names ("harness control reaches only this session's own work").
  - `LEDGER.md:50` — the blocker rule needs the teammate carve-out stated,
    or it will over-block any future row whose only blocker is a task tool.

### I2 — "The single real loss is … a private inline MCP server" understates what plugin agents give up

- **Where:** `PLAN.md:51-56`.
- The doc confirms the three fields are ignored: "For security reasons, plugin subagents don't
  support the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields."
- **`permissionMode` is a second real loss.** The doc makes parent precedence conditional, not
  total: "If the parent uses `bypassPermissions` or `acceptEdits`, this takes precedence and can't
  be overridden. If the parent uses auto mode, the subagent inherits auto mode and any
  `permissionMode` in its frontmatter is ignored." Under a parent in **`default`** — the shipped
  default — a project or user agent *can* override (`plan`, `acceptEdits`, `dontAsk`,
  `bypassPermissions`); a plugin agent cannot. The Brief's "permission mode is inherited from the
  parent — a parent in `auto` mode yields a subagent in `auto` mode" picks the one parent mode
  where the loss happens to be nil and generalizes from it.
- **`hooks` is a third, partially compensated loss.** The compensation claim is accurate as far as
  it goes: hook input gains `agent_id` ("Present only when the hook fires inside a subagent call.
  Use this to distinguish subagent hook calls from main-thread calls") and `agent_type`. But that
  is *observability* inside a session-wide hook, not *scoping*: `SubagentStart`/`SubagentStop`
  matchers filter on agent type, while `PreToolUse` matchers filter on tool name, so per-agent
  `PreToolUse` behavior has to be branched inside the hook script. The frontmatter form also has a
  lifecycle the settings form does not — frontmatter hooks are "cleaned up when the component
  finishes."

### I3 — The `CLAUDE_CODE_FORK_SUBAGENT` gating claim is stale, and it over-caveats a verdict

- **Where:** `PLAN.md:49`, `PLAN.md:92` ("It is rollout-gated by `CLAUDE_CODE_FORK_SUBAGENT`"),
  `LEDGER.md:35-36` ("Rollout-gated by `CLAUDE_CODE_FORK_SUBAGENT` and
  degrades to *stop*, not to *inline*").
- **What the doc says:** "Run a forked subagent with `/subtask`, which
  requires Claude Code v2.1.212 or later. … Before v2.1.212, the forked-subagent command was
  `/fork`. **It was enabled by default on v2.1.161 or later**; on v2.1.117 through v2.1.160 it
  required setting the `CLAUDE_CODE_FORK_SUBAGENT` environment variable to `1`, unless a server-side
  rollout enabled it." The variable is now a control ("set to `1` to enable it explicitly or to `0`
  to disable it"), not a gate. On the installed 2.1.219 forks are on by default and the command is
  `/subtask`.
- **Consequence:** `/session-flow:orient`'s `history-fork` mechanism (`B09`) is *less* caveated than
  the ledger records, not more. The residual caveat the ledger states is real and should stay:
  "Letting Claude itself spawn forks is experimental and may change in future releases."
- The same stale gating is reproduced in shipped skill text — `plugins/discovery/skills/explore-deep/SKILL.md:3`
  ("requires CLAUDE_CODE_FORK_SUBAGENT=1 — when unset, fall back to inline /explore"). `B03`'s
  Notable §2 catches that this is attached to the wrong mechanism; it is *also* attached to a
  requirement that no longer exists.

### I4 — No Claude Code version floor is recorded anywhere, despite six version-gated claims

Every load-bearing Constraints claim carries a `min-version` in the source docs, and none is
recorded in `PLAN.md` or the ledger:

- background is the default execution mode — "as of v2.1.198 it runs subagents in the background by
  default". Before that, the Brief's whole "background filter is the default filter" premise fails.
- `background: false` on a `context: fork` skill — "Requires Claude Code v2.1.218 or later";
  "Before v2.1.218, forked skills always blocked the turn until they finished." `PLAN.md:47-50`'s
  escape hatch does not exist below 2.1.218.
- The narrow tool set applying to a backgrounded `context: fork` skill is itself
  `{/* min-version: 2.1.218 */}`.
- `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` — "From Claude Code v2.1.172 through v2.1.216, subagents
  could nest by default, up to five layers deep, and the limit couldn't be changed." On that range
  the environment change recorded at `PLAN.md:63-65` is inert *and unnecessary*. It is correct on
  the installed 2.1.219.
- `/subtask` — v2.1.212 or later.
- The `skills:` preload exclusion for the bundled `/verify` and `/code-review` skills is
  `{/* min-version: 2.1.215 */}`.

This is the single highest-leverage omission for a *contract* document: every claim in the block is
true on 2.1.219 and several are false on versions still in the field.

### I5 — Amendment 1's evidence base is 6 of 7, and the two-path vocabulary is a false dichotomy

- **Where:** `PLAN.md:82-83`, `LEDGER.md:38-45` ("a `plugin-agent` can
  receive its discipline **two ways** … Every agent this marketplace ships today (`review/` ×6,
  `plugin-quality/` ×1) uses runtime invocation, none uses `skills:`").
- **Verified:** 7 agent files exist (`plugins/review/agents/` ×6, `plugins/plugin-quality/agents/auditor.md`),
  and none declares `skills:`. That half holds.
- **But `plugin-quality:auditor` does not use runtime invocation either.** Its frontmatter is
  `tools: "Read, Grep, Glob, WebFetch, Bash, Write"` — no `Skill`. It carries **no skill-invocation
  path at all**: neither `skills:` preload nor the `Skill` tool. Its discipline arrives two other
  ways — 59 lines of method in the agent body, plus files it Reads from paths handed to it in the
  dispatch prompt ("the component-type lens file path(s) to apply", `auditor.md:10`; "Walk the
  component-type lens file(s) named in your dispatch prompt", `auditor.md:42`). Both are immune to
  the preload uncertainty and to the `disable-model-invocation` block, and the ledger's binary
  vocabulary has no cell for either. The ledger elsewhere holds up this same agent as prior art to
  copy (`LEDGER.md:361-362`) without noticing it uses neither of the two
  paths the vocabulary admits.
- The six `review/` agents do grant `Skill`, so "runtime invocation is the marketplace's proven
  default" survives; "all seven" does not.

### I6 — The `disable-model-invocation: true` list is incomplete, and presented as resolved

- **Where:** `LEDGER.md:355-357` lists eight skills;
  `PLAN.md:88-89` lists four and honestly marks "(sweep incomplete)".
- **Scripted over the corpus, the true set is nine.** The ledger omits
  **`/re-anchor:use-your-skills`** (`plugins/re-anchor/skills/use-your-skills/SKILL.md:5`).
- Material impact is small — that row is INLINE-ONLY in `B08` on a transcript blocker — but the
  ledger presents its list as the closed set that resolves `PLAN.md`'s admittedly incomplete one,
  and it is not closed. The corpus is 138 files; this is a one-command check.

### I7 — The `-deep` retirement proposal pre-empts a USER-RESERVED question and does not engage the governing convention

- **Where:** `LEDGER.md:182-185` — "The live proposal is to retire both —
  relocating `explore-deep`'s body into `plugins/discovery/agents/explorer.md` and `research-deep`'s
  tier ladder plus multi-topic decomposition check into `/research`".
- `PLAN.md:147-149` marks that exact question **"arbiter: USER-RESERVED"** and notes its resolution
  "changes the acceptance criteria and the public skill surface." A ledger the plan step will read
  should not carry a "live proposal" on a user-reserved decision without labelling it as unratified.
- **The defect is absence of argument, not a bad argument.** `docs/MIGRATION-PLAYBOOK.md:130-136` is
  the governing convention and it names these two skills explicitly as the sibling-earning case:

  > "**Execution tier counts as structural:** a variant that changes execution *topology* — an
  > isolated forked subagent (`context: fork`) or a heavier dispatch tier (workflow engine, forked
  > subagent, or inline fallback) — **is fixed in frontmatter and cannot be a runtime argument**, so
  > it earns a sibling. `discovery`'s `explore-deep` (a `context: fork` variant of `explore`) and
  > `research-deep` (a dispatch variant of `research`) are siblings on this axis"

  Nothing in `PLAN.md`, the ledger, or any batch artifact cites this passage or argues against it.
- **The reinterpretation is available but asymmetric, and the asymmetry is the discriminator.** The
  convention states its own *reason*: tier is structural because it is frontmatter-fixed and cannot
  be a runtime argument. Under Decision 2 dispatch becomes a runtime `Agent` call made by the parent
  skill, so for **`research` / `research-deep`** that reason genuinely weakens — `research-deep`
  carries no execution frontmatter (`plugins/discovery/skills/research-deep/SKILL.md` is an inline
  dispatcher by body text, per its line 18). For **`explore-deep`** it does not weaken at all: that
  skill literally carries `context: fork` and `agent: general-purpose` in frontmatter
  (`plugins/discovery/skills/explore-deep/SKILL.md:7-8`) — the convention's named case, unchanged by
  Decision 2. Retiring both on one argument does not hold; retiring `research-deep` might.
- **Required:** either amend `MIGRATION-PLAYBOOK.md:130-136` with the re-derivation, or drop the
  "live proposal" wording until the user rules. Silently reinterpreting a convention in a work
  artifact is the drift the playbook exists to prevent.

### I8 — One row does not survive the "own `Agent` fan-out" blocker as the criteria state it

- `LEDGER.md:66-69` makes a skill's mandated `Agent` fan-out a **hard
  blocker forcing INLINE-ONLY** — scoped to "when the skill mandates fresh-context subagents **as a
  correctness control**" — "unless `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is set — which Decision 3
  keeps optional."
- **The row that does not fit:** `B08:19` verdicts `/re-anchor:recheck-against-upstream-deep` =
  **DISPATCH-OPTIONAL**, "gated on spawn depth", for a skill whose fan-out *is* its method — step 1
  enumerates every upstream-dependent surface and the waves are how the work gets done. That is the
  strongest form of the blocker, and it draws the weakest verdict of the three fan-out rows.
- **Two rows that look inconsistent and are not.** I tested the obvious pairing and it holds up:
  `/docs-hygiene:compress` (`B03:31`, INLINE-ONLY) mandates semantic-diff dispatch "for default
  action" — the fan-out is the primary path — while `/docs-hygiene:audit-derivability` (`B03:28`,
  DISPATCH-DEFAULT) needs a nested spawn only for a deletion *spot-test* inside a skill whose main
  per-doc sweep dispatches cleanly. Different structural positions; the criteria's
  "correctness control" wording separates them. No finding here.
- **Fix:** re-derive the `recheck-against-upstream-deep` verdict, or state why a whole-method
  fan-out is not a correctness control. Note the ledger's own open item
  (`LEDGER.md:343-347`) already records this subset as one where "the env
  var is a hard prerequisite", and amendment 4 (`PLAN.md:96-99`) proposes codifying that — so the
  criteria and the rows are closer to agreement than the row count suggests; this is one unreconciled
  verdict, not a pattern.

---

## SUGGESTION

### S1 — Two exclusion counts in the ledger preamble are wrong

`LEDGER.md:8-10`:

- "`*/skills/setup/` (**39** skills)" — the filesystem has **43** (`plugins/*/skills/setup/SKILL.md`).
- "`*/skills/*/vendor/SKILL.md` and other nested `SKILL.md` (**7** files)" — there are **6**
  (`context7/lookup/vendor/cli`, `context7/lookup/vendor/find-docs`, `dometrain/sync/vendor`,
  `playbooks/boris/vendor`, `playbooks/skill-authoring/vendor`, `playwright/playwright/vendor`).
  187 `SKILL.md` under `plugins/` total, 181 at the top skill level.

Neither affects the corpus — 43 + 138 = 181 reconciles exactly, so the 138 was enumerated against
the live tree while the exclusion counts were not. They read as stale carry-overs rather than
transcription slips, in a document whose value proposition is "enumerated by script, not by hand."

### S2 — `PLAN.md:63-65`'s "env vars are read at session start" is uncited

Plausible and consistent with the observed behavior, but it is a harness claim in a block whose
header asserts everything below it was "verified against official docs this session." I did not find
it stated in `sub-agents`, `skills`, or `hooks`. Either cite `env-vars`/`settings` or move it out of
the verified block.

### S3 — `PLAN.md:34`'s `ExitPlanMode` entry drops its condition

The doc reads "`ExitPlanMode`, **unless the subagent's `permissionMode` is `plan`**". The Brief
lists it unconditionally. Low impact for plugin agents specifically — they cannot set
`permissionMode` at all (see I2) — but the Constraints block is written as a general harness
reference, and `LEDGER.md:51` inherits the same unconditional form.

### S4 — Observed outside the assigned scope: `verify/A.md` proposes a re-verdict, not a correction

`A.md:55` records `/bug-report:write` as DISPATCH-OPTIONAL where the ledger has INLINE-ONLY. My
transcription check confirms the ledger matches `B01`, so this is A.md disagreeing with the batch,
not catching a copy error. Flagging only; `A.md` was not in my review set and I did not audit it.

---

## Sound — no defect found

- **Subagent frontmatter field list** (`PLAN.md:27-29`). All 16 fields match the doc's "Supported
  frontmatter fields" table exactly, in kind and spelling. `prompt` is correctly *excluded* — it is
  an `--agents` JSON field, not file frontmatter.
- **`skills:` preload semantics** (`PLAN.md:30-32`). Verbatim support: "The full skill content is
  injected, not only the description. Subagents can still invoke unlisted project, user, and plugin
  skills through the Skill tool," and "You can't preload skills that set
  `disable-model-invocation: true`." The "all discovery skills qualify today" sub-claim checks out:
  all five non-setup `discovery` skills are `disable-model-invocation: false`.
- **Filter-2 membership** (`PLAN.md:36-39`). The 19 built-ins plus "every MCP tool" match the doc's
  list exactly, in order.
- **`context: fork` is a regular agent type on the narrow set** (`PLAN.md:47-50`). Near-verbatim:
  "the skill's subagent is a regular agent type, so the exemption for subagents that fork the
  conversation doesn't cover it. If your skill's steps depend on a tool outside that set, set
  `background: false`."
- **Plugin agents ignore `hooks`/`mcpServers`/`permissionMode`** (`PLAN.md:51`). Verbatim. Only the
  cost assessment is wrong (I1), not the fact.
- **Corpus enumeration.** Scripted set comparison: the 138 ledger rows are **set-equal** to the 138
  `plugins/*/skills/*/SKILL.md` excluding `setup/`. Zero missing, zero extra, zero duplicates.
- **Verdict tallies** (`LEDGER.md:90-96`). 20 / 29 / 57 / 32 = 138,
  reproduced by script from the row table.
- **Transcription batch → ledger.** 138/138 verdicts agree. (My extraction regex initially matched
  137; the miss was `/planning:devils-advocate`, whose verdict is bolded in `B06:16` — checked by
  hand, it agrees.) Note the ledger's stronger claim at lines 98-101 — that the script "caught one
  stale value … No other divergence" — is a claim about a historical correction. My check
  corroborates that the *current* state is consistent; it cannot verify what was corrected.
- **`B03`'s `explore-deep` line-24 finding.** Confirmed against the file:
  `plugins/discovery/skills/explore-deep/SKILL.md:24` does say "You inherit the parent's full
  toolset", the frontmatter sets `context: fork` with no `background:` key, and the doc's
  `{/* min-version: 2.1.218 */}` paragraph makes that false. `B03`'s reading is correct. (See I3 for
  a second, separate error in the same skill's frontmatter.)
- **`B08`'s re-anchor `-deep` contrast** (`B08:115-123`). Sound and not motivated: nine of eleven
  base correctors are INLINE-ONLY on a transcript blocker, so the parent cannot absorb the `-deep`
  sibling's fan-out and the pair remains two genuine tiers. The batch also states its own scope
  limit — it declines to generalize to `discovery`.
- **Quoted skill lines spot-checked.** `research/SKILL.md:126` and `:148`, and
  `research-deep/SKILL.md:18`, are quoted accurately in `PLAN.md` and the batch artifacts.
