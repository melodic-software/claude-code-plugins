# The batched pass

The five steps full-batch mode runs once the inheritance preflight in
[`inheritance-preflight.md`](inheritance-preflight.md) has proved the fan-out inherits. Recorded as
a declared delta from the shared correction loop, per [`../SKILL.md`](../SKILL.md). Session-start
digest mode never runs any of it.

Recorded here as a **declared delta** per the shared method doc's
declared-delta rule (this runbook is not a corrector, but it orchestrates the
shared loop across members and diverges from its per-corrector
"correct forward now" step, so the divergence is part of this skill's
contract, not silent drift). Two divergences are declared: the **inserted
preflight** above, which sits before this list's step 1 and gates the whole
pass, and the split below. The shared loop has each corrector run steps 1–3
itself, in its own context. This runbook **splits** them: the audit
(steps 1–2) runs in per-corrector subagents; the correction (step 3) is
collected and applied ONCE on the main thread, serialized in rank order.
Rationale: a dozen disciplines each correcting forward independently in one
context recreates the salience dilution this plugin exists to fix, and a
merged pass lets order matter. The shared method's Non-negotiables are
unchanged and bind every member.

1. **Fan out, audit-only**, after the preflight above has proved inheritance.
   For each in-scope corrector, dispatch a
   conversation-inheriting **fork** subagent, the Agent tool's
   `subagent_type: "fork"`, which inherits the full conversation history the
   audit must read. A fresh/typed subagent receives no history, and a
   skill-level `context: fork` also discards it. Neither can audit this
   conversation. The forks read the live working tree. Do NOT isolate them
   (see Gotchas: isolation would hide the uncommitted work in flight, which is
   usually the thing under audit). Their no-writes rule is trusted, not
   enforced. See Gotchas, and treat a fork that wrote as untrusted output:
   stop rather than correct on top of it. Instruct
   each fork: answer the preflight's inheritance-proof question first, then
   load exactly this ONE corrector's
   `SKILL.md`, run shared-loop steps 1–2 only (re-anchor + self-audit), make
   NO writes, and return a findings ledger. Each ledger entry carries the
   concrete located finding AND the remedy this corrector would apply for it
   (the shared loop's step-3 corrective action, *described* not performed. The
   fork still writes nothing), or an honest "clean". Capturing the proposed
   remedy in the audit is what gives step 3 the reporter→remedy data to key on;
   a ledger of bare violations would leave the dedup with nothing to preserve.

   **Wave sizing, budget, and what counts as a failure.** Prefer ONE wave:
   dispatch every in-scope member together, so no member's ledger is in the
   transcript when another member spawns. That independence is load-bearing,
   not decoration. Step 3's dedup and step 4's ordering both assume the
   ledgers were formed without seeing each other, and a fork inherits
   everything the session holds at the moment it spawns. Splitting the fan-out
   is what breaks it, so do not import the `-deep` siblings' "roughly a dozen"
   wave: it is calibrated for cheap fresh-context subagents that carry no such
   invariant.

   One wave is usually possible, and the two documented limits are not the
   same kind of limit. `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` ("Maximum number
   of read-only tools and subagents that can execute in parallel", documented
   default 10) caps how many run at once. It does not cap how many you
   dispatch. The hard one is `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (documented
   default 20): past it, "spawning another with the Agent tool fails with
   `Concurrent subagent limit reached`, and the error tells Claude not to
   retry." Every Agent-tool subagent counts against it, forks included, shared
   with everything else the session is running. There is no longer a per-session
   total to count against: the 200-subagent-per-session cap and its
   `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` variable were removed in
   v2.1.220–v2.1.224, leaving the concurrency and depth limits
   (<https://code.claude.com/docs/en/sub-agents>,
   <https://code.claude.com/docs/en/env-vars>,
   <https://code.claude.com/docs/en/whats-new/2026-w32>; cap removal verified
   2026-08-10. `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` above **re-verified
   2026-08-10 against the primary page**, read verbatim end to end through the
   `.md` fetch route
   ([upstream-drift](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route)),
   which reached the `CLAUDE_CODE_MAX_*` range the three earlier fetches had
   truncated before. The row reads "Maximum number of read-only tools and
   subagents that can execute in parallel (default: 10)". Unchanged from the
   2026-07-29 read, and the same-day mirror basis that stood in for it (#2176)
   is **retired**, exactly as that record's own trigger said it would be on a
   primary read of this range. The env-vars rows for
   `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` ("Removed in v2.1.224 and now a
   no-op … Previously capped … (default: 200)"),
   `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` ("default: 20"),
   `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` ("the `run_in_background` parameter on
   Bash and subagent tools"), and `CLAUDE_CODE_FORK_SUBAGENT` ("overriding any
   server-side rollout") were read in the same fetch and each matches the way
   this skill cites it. Upstream publishes no per-page content date, so the
   fetch date is the whole of the currency claim. Recheck trigger: a Claude Code
   release note naming tool-use concurrency, parallel tool execution, or any of
   these variables, or a re-fetch of env-vars diverging from a quoted row).
   So even a fully-admitted set, every core plus every situational corrector, dispatches in one wave in an
   otherwise-quiet session.

   **Never drop a relevant corrector to fit a budget.** Membership resolution
   decides what is in scope; concurrency decides only when it runs. If the
   session already holds enough subagents that the full set cannot be
   dispatched, wait for capacity and then dispatch it whole. Split only if that
   is not possible, and then **say so in the report**: every member in a later
   wave inherits the earlier waves' ledgers and can be anchored by them. That
   is a real weakening of the independence the dedup relies on, disclosed, not
   hidden. Only a split fan-out needs the `-deep` siblings' per-wave
   checkpointing of the collected ledgers; a single wave has no partial state
   to lose.

   **Retry, and what counts as a failure.** Retry only a failed subset, once, and **failure includes a ledger returned without verified inheritance
   proof**, not only an errored dispatch: a fabricated ledger is the exposure
   the retry rule exists for. One dispatch error is explicitly NOT a retryable
   failure: `Concurrent subagent limit reached`, which the harness tells Claude
   not to retry. That is a capacity race, not a failed audit. Wait for
   capacity and dispatch, rather than retrying into the same wall. A retry is anchored by construction, one wave or
   many: it spawns after other members' ledgers have landed, so it inherits
   them. There is no un-anchored rerun available inside this conversation; re-running the whole pass would inherit MORE, not less, since every ledger
   is already in the transcript any new fork copies. So do not offer a clean
   rerun; report each retried member's ledger as anchored and weigh it as such.
   A member still unproven after its one retry is reported
   open, and the verified ledgers are kept and corrected. See the preflight's
   mid-fan-out rule; only a failed canary collapses the pass to the digest.
2. **Collect** every ledger.
3. **Dedup by root cause.** Before correcting, group ledger entries across
   correctors that name the SAME underlying finding. Distinct disciplines
   routinely surface one root cause as separate entries (e.g. a recall-based
   claim flagged independently by `do-your-research`, `recheck-against-upstream`,
   and `mind-your-maxims`). Group them into one finding carrying the union of
   their located evidence and, keyed BY reporting corrector, the remedy that
   corrector asks for, a reporter→remedy mapping, not a flat remedy list beside
   a separate reporter list, so step 4 knows which remedy belongs to which rank.
   What dedup collapses is the
   re-analysis and the re-reporting of one root cause, NOT the corrective work:
   a shared root cause can demand more than one remedy that are not
   interchangeable (verifying or retracting the unsupported claim satisfies the
   research reporters, but `mind-your-maxims` may still require a reader-facing
   uncertainty disclosure), and every reporter's remedy is still applied. This
   grouping is the ONLY place ledgers combine: the forks stay independent by
   design (no shared ledger across forks. That independence is what keeps each
   audit's perspective un-anchored), and grouping is by root cause, not by
   corrector. A finding only one corrector raised passes through unchanged.
4. **Correct once, in rank order.** Walk the in-scope members, the core and
   situational correctors that ran (never-tier carries no rank and was already
   excluded at membership resolution). By ascending `discipline-batch-rank`,
   and correct forward each finding on the main thread now, the shared loop's
   step 3, batched. For a grouped finding, "once" means the root cause is
   analyzed and corrected in a single pass, not that its remedies collapse to
   one: apply every reporter's distinct remedy, each at its own reporting
   corrector's rank (so the research retraction and the `mind-your-maxims`
   disclosure both happen, in rank order), rather than dropping the
   lower-priority reporters' corrective work. The order:
   `use-your-skills` first (fix which skills govern the work) → evidence
   correctors (get the facts right) → structural correctors → `mind-your-maxims`
   (communication) → `tighten-your-output` dead last, so it never tightens
   text a later corrector rewrites. Correcting on the main thread does not
   suppress the shared method's fresh-context escalation: where a finding's
   suspected drift source is this context's own judgement, re-derive it in a
   fresh-context (non-fork) subagent blind to that reasoning, per the method
   doc's Non-negotiable, the batch orchestrates the correction here, it does
   not waive that escalation. (The fork *audit* inherits context on purpose:
   step 2 is a same-context self-audit; this carve-out is about step 4.)
5. **Report** one consolidated ledger: per corrector. Corrected / clean /
   open; a root-cause finding merged in step 3 is listed once, attributed to
   every corrector that reported it; plus which situational members ran versus
   were skipped, and which never-members exist for direct use.
