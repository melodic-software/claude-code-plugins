# Run-everything mode: full-breadth review

The heavy, exhaustive sweep: run the main-thread orchestrator plugins AND fan out the full leaf roster (`leaf-roster.md`: its finding-producing agents + every discovered ownerless slice), then normalize everything into one severity-ranked report. The leaf fan-out runs as the saved `review:fanout-sweep` workflow when available; a main-thread fallback preserves coverage when it is not.

Trigger: `$ARGUMENTS` is `run-everything` / `everything` / `all`. Distinct from default mode (which auto-scales surfaces to diff size).

## Flow

1. **Pre-launch availability gate** (below). Run BEFORE any launch.
2. **Resolve the review diff base** (SKILL.md "Shared inputs"). Resolve it up front, because the orchestrator step passes it to Codex via `--base` and the leaf fan-out passes it as `args.diffBase`; every surface must diff the same base.
3. **Main-thread orchestrators.** Sequentially invoke the optional orchestrator plugins per SKILL.md "Orchestrator plugins". They fan out their OWN agents and stay on the main thread, never inside the Workflow (rationale: SKILL.md "Orchestrator plugins"). This exhaustive sweep is where the cross-vendor `codex` surface earns its cost most. When the plugin is present, invoke `/codex:review --wait --base <review-base>` (and `/codex:adversarial-review --wait --base <review-base>` for red-team breadth), since a different model is the one source of uncorrelated blind spots the Claude leaves and orchestrators structurally share. Two flags are required: `--wait` keeps the review in the foreground (without a flag the command prompts or backgrounds, returning only a status handle, so the step-6 synchronous normalization would see an empty surface and silently drop Codex), and `--base` carries the step-2 review diff base so Codex diffs the SAME change set as every other surface. Without it Codex auto-picks the working tree or default branch and reviews a different diff on any PR whose base is not the default branch. Coverage boundary: `--base` runs Codex in branch mode (`git diff <base>..HEAD`, committed only), which coincides with the leaves' `git diff <base>` on a clean branch (the review case) but NOT when the branch also carries uncommitted tracked edits. There Codex covers the committed diff while the leaves additionally cover the dirty tree. Name that gap in `## Surfaces` for a mixed branch+dirty run rather than assuming identical change sets.
4. **Resolve the roster.** Run the discovery recipe in `leaf-roster.md` to get the slice list.
5. **Leaf fan-out.** If the gate failed, take the coverage-parity fallback. Otherwise:
   - **Roles.** When `/multi-agent:route` resolves in this session, invoke it as `/multi-agent:route all session=<this session's model alias>` and keep the `roles` object of the JSON it prints. When it does not resolve, omit `args.roles`, and say once in the report that enabling the multi-agent plugin makes this routing configurable; the workflow's built-in fallbacks then apply.
   - **Launch** `Workflow({ name: "review:fanout-sweep", args: { diffBase, slices, roles, maxConcurrent } })`: `diffBase` is the step-2 base, `slices` the step-4 slice names, `roles` the map above, and `maxConcurrent` is optional (the workflow's default applies when omitted).
   - The workflow returns `records`, `raw`, `nulls` and `ran`. A returned `error` (missing or bad `diffBase`) means nothing was dispatched: fix the input and launch again.
6. **Normalize main-thread.** Gather the Workflow's extracted leaf records + the raw orchestrator outputs; run Stage 0 on the orchestrator outputs (the Workflow only extracted the leaf branch), then Stages 1–4 of `findings-normalization.md` over the combined record set. Reconcile per surface against the Workflow's `raw` array: any surface whose raw output is non-empty but yielded zero extracted records gets Stage 0 re-run main-thread on that raw text; whatever still fails to parse goes verbatim into `## Unparsed`. Partial extraction never silently drops a surface.
7. **Persist** per `findings-file-shape.md` "Findings-writer contract"; prepend the DEGRADED block when the fallback was taken.

**Pre-flight gate first:** SKILL.md's pre-flight gate applies to this mode too. The ask-shape check routes a whole-repo security-audit ask to the `leaf-roster.md` "Deep-scan escalation" before any diff resolution, and an unresolvable base ref or an empty change set (including untracked-only) reports and stops before step 1; with nothing diffable, every leaf would diff an empty tree and return nothing. Do NOT stage files.

## Pre-launch availability gate

The Workflow tool is not present in every session: a user or organization can turn workflows off, and on some plans they stay off until the user turns them on. Decide availability BEFORE attempting a launch. The check is whether the Workflow tool is in this session's toolset (listed or loadable); when it is absent → main-thread fallback. For the switches that turn workflows off, see [Turn workflows off](https://code.claude.com/docs/en/workflows#turn-workflows-off) (as of 2026-10-02; recheck when those switches are renamed).

If availability cannot be positively confirmed, fall back (fail-safe, not fail-open).

**Null reconciliation:** the workflow returns `nulls` (every leaf that produced no record, regardless of cause) and `ran` (the full expected roster). Render a `## Surfaces` line in the form `Ran: [...]. Returned no result: [...]`, with NO silent caps. Every null is named.

## Coverage-parity fallback (Workflows unavailable)

Spawn the SAME roster on the main thread via parallel Agent-tool calls (the main thread CAN spawn agents), using the same resolved review diff base, then run Stages 0–4 main-thread. Coverage and the findings contract are identical; what is lost: background execution, out-of-context intermediates, and resume caching. If the caller depends on a dropped property, STOP and surface it rather than silently downgrading.

## Degraded notice

When the fallback is taken, prepend a structurally distinct block at the TOP of the chat output AND the persisted file body (a blockquote above `## Findings`):

```text
> DEGRADED: Workflows unavailable (<signal>); ran N leaves on the main thread; dropped:
> background-exec / out-of-context-intermediates / resume-caching.
> Findings coverage is full; only the execution properties above are lost.
```

## Interrupted-run handling

If the Workflow is interrupted, ask for a relaunch of `review:fanout-sweep` with the same `args`. For which agents return saved results, which run again, and when a run can be relaunched from another session, see [Resume after a pause](https://code.claude.com/docs/en/workflows#resume-after-a-pause) (as of 2026-10-02; recheck when the resume or cross-session rules change). The report is written ONCE, main-thread, after the reduce returns, never partially from inside concurrent leaves.
