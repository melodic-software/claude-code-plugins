# RESEARCH — Claude Code Workflow tool and workflows feature: context cost and disable mechanisms

## Task restatement

Research the Claude Code Workflow tool and the workflows feature — its context cost and every
supported way to disable it — for the author of a new marketplace skill that inventories and trims a
session's fixed startup context payload. Workflows ship a very large tool description and are a named
trim candidate. Six questions were posed: (1) what the feature is and what it adds to a session;
(2) whether the Workflow tool schema is always in the prefix or deferred behind ToolSearch; (3) every
supported disable mechanism and its exact spelling, with the prompt's proposed names treated as
unverified; (4) the scope and precedence of each; (5) whether disabling removes the schema from the
request payload or only refuses invocation; (6) whether `/context` attributes workflows to a row.
Output is for a Claude Code plugin maintainer. Budget: full depth, official-docs-first.

**All sources fetched 2026-08-17.** Tier 0 evidence is the locally installed
`@anthropic-ai/claude-code` **v2.1.232**; confirmed latest upstream is **2.1.233**.

## Headline answers

1. **Dynamic workflows** — Claude-authored JavaScript that orchestrates subagents in a background
   runtime. Adds 14 identifiable surfaces; only the `Workflow` tool and the bundled `/deep-research`
   command cost model-visible context.
2. **Not settled as "always prefix".** It is an ordinary gated built-in. Deferral eligibility is
   **server-controlled** (local default list is empty), and an empirical `claude -p` diff shows the
   schema **present in the initial request body**. Marked partly unverified — see Gaps.
3. **Both names in the prompt are correct and current**, verified verbatim: `disableWorkflows` and
   `CLAUDE_CODE_DISABLE_WORKFLOWS`. Five full-disable mechanisms plus plan gating, plus one
   **undocumented** key (`enableWorkflows`) that the `/config` toggle actually writes.
4. Standard settings ladder (managed > CLI > local > project > user); `disableWorkflows` is **not**
   a managed-precedence exception, so a managed value is absolute. The **env var is OR-ed ahead of
   settings**, so nothing can re-enable against it.
5. **It REMOVES the schema from the payload.** `isEnabled:()=>jD()` plus an `isEnabled()`-filtered
   tool array — confirmed on two code paths and by an independent request-body diff (~5,391 tokens).
   The docs alone do **not** settle this; that is stated explicitly in the sidecar.
6. **No.** `/context` has no workflows row; the cost is folded into generic **`System tools`**.

## Sidecar abstracts

- **feature-and-components** — Dynamic workflows are Claude-authored JS orchestration scripts; they add a Workflow tool, /workflows and /deep-research commands, an ultracode keyword and effort level, two save directories, a plugin workflows/ component, and five config keys.
- **tool-loading-and-context-cost** — The Workflow tool description measures 19,588 bytes in the v2.1.232 binary (~5,391 tokens by an independent request-body diff); it is an ordinary gated built-in, and whether it is deferred behind ToolSearch is server-controlled rather than a fixed property of the tool.
- **disable-mechanisms** — Five supported full-disable mechanisms exist — a /config toggle, disableWorkflows in settings, CLAUDE_CODE_DISABLE_WORKFLOWS, managed settings, and the admin page — plus plan gating; the env var uses truthiness not literal 1, and disableWorkflows is not a managed-precedence exception.
- **payload-removal** — Disabling removes the Workflow tool from the tool list before the request is built — its isEnabled() is the disable predicate and the tool array is filtered by isEnabled() — so the schema leaves the payload rather than the tool merely refusing invocation.
- **context-attribution** — /context has no workflows-specific row; the Workflow tool schema is folded into the generic "System tools" row (or "System tools (deferred)"), so the feature is not separately attributable from /context output alone.
- **evidence-and-gaps** — Fetch log, conflicts, recency verdict against Claude Code 2.1.233, and the explicit list of what could not be verified — chiefly runtime deferral of the Workflow tool and first-hand access to the token measurement.

## Section → file + anchor

| Question | Section | File | Anchor |
|---|---|---|---|
| Q1 feature + components | feature-and-components | `RESEARCH-feature-and-components.md` | `#components-the-feature-adds-to-a-session` |
| Q2 prefix vs deferred | tool-loading-and-context-cost | `RESEARCH-tool-loading-and-context-cost.md` | `#answer-stated-carefully` |
| context cost / size | tool-loading-and-context-cost | `RESEARCH-tool-loading-and-context-cost.md` | `#the-size-of-the-thing` |
| Q3 disable spellings | disable-mechanisms | `RESEARCH-disable-mechanisms.md` | `#full-mechanism-table-with-scope-and-precedence` |
| Q4 scope + precedence | disable-mechanisms | `RESEARCH-disable-mechanisms.md` | `#precedence-for-mechanisms-2-4-and-5` |
| undocumented key | disable-mechanisms | `RESEARCH-disable-mechanisms.md` | `#an-undocumented-sixth-key-enableworkflows` |
| Q5 payload vs refusal | payload-removal | `RESEARCH-payload-removal.md` | `#tier-0-the-mechanism-in-three-linked-facts` |
| Q6 /context row | context-attribution | `RESEARCH-context-attribution.md` | `#the-actual-row-set` |
| gaps / recency / fetch log | evidence-and-gaps | `RESEARCH-evidence-and-gaps.md` | `#gaps--what-i-could-not-verify` |
| coverage ledger | — | `research-checklist.md` | — |

## Next-stage handoff

### Settled — safe to build on

- `disableWorkflows` (settings, any scope) and `CLAUDE_CODE_DISABLE_WORKFLOWS` (env) are the two
  documented disable spellings; both verified verbatim in current docs and in the shipped binary.
- Disabling **removes** the `Workflow` tool from the tool array before request assembly. This is a
  real fixed-prefix trim, on every turn, not a runtime refusal.
- The tool description is **19,588 bytes** in v2.1.232 — plausibly the single largest built-in tool
  description Claude Code ships, and roughly a third of the ~16k-token built-in tool budget reported
  by the community.
- Managed settings make it absolute (`disableWorkflows` is not a precedence exception); the env var
  is OR-ed ahead of all settings and cannot be overridden downward.
- `/context` gives no workflows row — the trim is verifiable only by differencing `System tools`.
- Non-substitutes: `workflowKeywordTriggerEnabled`, `disableBundledSkills`, `workflowSizeGuideline`.

### Open decisions for the skill's author

- **Does the skill write `disableWorkflows` or recommend it?** Managed-settings semantics mean a
  project-scope write is silently inert in a managed org. Prefer detecting and reporting over writing.
- **Which measurement harness?** `claude -p` + `ANTHROPIC_BASE_URL` diff is the only method that
  attributes precisely, but it under-reports runtime-injected payloads (`disableArtifact`,
  `disableBundledSkills` measured zero there). `/context` differencing is cheaper and interactive but
  aggregates. Consider doing both and reconciling.
- **Baseline must record plan and opt-in state.** On Pro, workflows are off until opted in, so the
  saving is already banked and reporting it would be a phantom.
- **Avoid `enableWorkflows` in anything the skill writes** — real but undocumented.

### Carry these caveats into the skill's own docs

- Enumerate settings keys from **downloaded** doc pages, not from a summarizer: the settings and
  env-vars pages are 334 KB / 404 KB and summarization silently dropped both workflow keys during
  this research.
- `CLAUDE_CODE_DISABLE_WORKFLOWS` disables on **any non-empty value**, including `0` and `false`.
  Unset it to enable; never set it to a falsey-looking string.
