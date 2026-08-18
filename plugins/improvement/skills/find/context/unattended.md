# unattended — caller declaration, report shape, filing flow, data home

The mechanics of unattended mode (contract summary: SKILL.md § Unattended mode — read-only
apart from the persisted report and presence-gated filing; no questions; prioritization stays
human-gated per the tech-debt-sweep C1 contract).

## Caller-declaration contract

Unattended mode is entered only when the **invocation prompt declares it** — a routine wrapper,
a scheduled job, an orchestrating skill. It is never sniffed from the environment: there is no
supported way to observe non-interactivity, and guessing converts an interactive user's session
into a silent filing run. The declaration carries:

- **The declaration itself** — e.g. "This runs unattended — there is no interactive user to
  answer any question."
- **Any overrides of the soft defaults** — filing cap ("file at most 5" / "report only, file
  nothing"), size band, scan scope, dismissed-memory override ("include previously dismissed
  candidates").

The routine prompt wrapping this skill is the tuning surface; the operator iterates on it after
observing real runs. Absent an override, the defaults below apply. A general standing mandate
("keep the repo healthy") is not a filing authorization by itself — the unattended declaration
is what authorizes report persistence and filing, and only that.

## Data home — `${CLAUDE_PLUGIN_DATA}`, keyed per project

All persisted state lives under `${CLAUDE_PLUGIN_DATA}` per the marketplace's
plugin-data-report-keying convention. That directory is keyed to the **plugin identifier and
nothing else** — machine-global, shared by every repository the operator works in — so every
write goes under a project **state key**:

```text
${CLAUDE_PLUGIN_DATA}/find/<state-key>/reports/improvement-<UTC-timestamp>.md
${CLAUDE_PLUGIN_DATA}/find/<state-key>/dismissed.jsonl
```

This is consumer-repo-agnostic by design: the report never goes into the target repository, and
the recipe NEVER assumes any particular docs layout in the consuming repo (no topic-docs tree,
no `docs/` conventions — a consumer repo has none of that).

**`${CLAUDE_PLUGIN_DATA}` unset:** some environments do not provide the variable. Do not invent
a substitute directory and do not write into the target repo: emit the complete report as the
run's final output instead, add a `gap: persistence — CLAUDE_PLUGIN_DATA unset; report emitted
inline, dismissed-candidate memory unavailable this run` line, and skip the dismissed-memory
read/write (nothing is suppressed, nothing is recorded).

`<state-key>` is produced by the plugin's shipped helper — run it, never re-derive the key from
the description below (the helper is byte-identical across plugins per
`docs/conventions/plugin-data-report-keying/README.md`, and a hand-derived variation makes the
skill miss its own prior reports and dismissed-memory):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"
```

For reference, the key's shape is `<repo-identity>/<worktree-discriminator>`:

- **repo-identity** — the first configured remote URL (`git remote` then `git remote get-url`),
  normalized to `host/owner/repo`: lowercased, scheme/credentials/`.git` suffix stripped. No
  remote → `local/<first 12 hex of sha256 of the canonicalized repo root>`. Not a repository →
  `nonrepo/<first 12 hex of sha256 of the working directory>`.
- **worktree-discriminator** — first 8 hex of sha256 of the canonicalized worktree root
  (`git rev-parse --show-toplevel`, resolved with `pwd -P`). Two worktrees of one repo hold
  different content and must not share an artifact.
- Validate every derived segment as a path segment (`[a-z0-9._-]`, starting alphanumeric);
  hash anything that does not fit, so a hostile remote URL cannot walk the write out of the
  plugin's namespace. (`sha256sum`, or `shasum -a 256` where it is absent.)

Retention: **one report file per run** (UTC-timestamped filename — a same-day rerun must not
erase the earlier report; the sequence is the trend source), and the dismissed memory is a
single appended JSONL file. Reads follow the same key: serving another project's report is the
exact failure keying exists to prevent — if nothing exists at the derived key, say "no prior
report for this project"; never fall back to an unkeyed or differently-keyed path. Note once,
for operators: uninstalling the plugin from its last scope deletes this whole tree unless
`--keep-data` is passed — these reports have no other copy.

## Persisted report shape

```markdown
# Improvement report — <repo-identity> — <UTC timestamp>

## Run metadata

- Target / scope narrowing: <bare | "improve <X>" | size band>
- Mode: unattended (declared by: <caller, e.g. routine name or prompt excerpt>)
- Evidence sources probed: Tier 0 <which ran>; Tier 1 <present/absent>; Tier 2 <configured/none>
- GitHub access path: <mcp | gh | none>
- Windows used: <churn window; CI windows>
- Filing: tracker <present/absent>; filed <n> (ids); cap in effect <n>; dedupe skips <n>;
  dismissed suppressed <n>

## Ranked candidates

<the full ranked table — the row shape from SKILL.md § Candidate output shape: rank, candidate,
dimension, size, evidence citation + rung, confidence, value-to-effort rationale>

## Evidence gaps

- gap: <source> — <why unavailable> — <what would close it>
```

Every unavailable evidence source produces one `gap:` line — absence is reported, never
papered over. The report is complete without a tracker: filing is additive to it.

## Filing flow (presence-gated, deduped, capped)

1. **Tracker present?** `work-items:track` installed and bound → file; absent → report only,
   noted in the report's Filing line. Never file by improvising a `gh issue create` outside the
   tracker seam.
2. **Consult dismissed memory first** (already done during candidate assembly — order and
   rationale: ranking.md).
3. **Top candidates, in rank order, up to the adaptive cap.** For each: search-before-create
   per the tracker convention — `work-items:track`'s add action carries the pre-flight
   (adapter "Search items", `--state all`); run it before spending a cap slot. Duplicate found
   → skip, count it in the report, move to the next candidate.
4. **Each filed item carries its evidence** — the citation, rung, size, and value-to-effort
   rationale travel into the item body, so triage ranks over evidence, not anecdote.
5. **Nothing else.** No prioritizing the queue, no assigning, no starting work, no closing or
   demoting existing items — the run never self-disposes.

### Adaptive filing cap (soft default, prompt-overridable)

Following `work-items:work-loop`'s adaptive-item-cap precedent — a default with floor and
ceiling, adapted by observed outcomes, never a hard limit:

- **Default: 3 items per run** (floor 1, ceiling 5).
- **Ramp down** toward the floor when the previous run's filings are still sitting untriaged,
  or when operator dismissals of this skill's filings are accumulating — a queue that is not
  draining does not need more volume.
- **Ramp up** (by 1, toward the ceiling) only after a run whose filings were all triaged.
- Read the previous run's report (same `<state-key>`, latest timestamp) for what was filed;
  check the tracker for its current state.
- **The invocation prompt overrides all of it** — a cap, "report only", or "file everything
  above medium-high confidence" in the routine prompt wins over the default.

### Dismissed-candidate memory

`dismissed.jsonl`, keyed alongside the reports (path above). One JSON object per line:

```json
{"candidate":"<one-line candidate statement>","dimension":"<dimension>","dismissed_at":"<UTC>","source":"<operator|triage>","note":"<optional reason>"}
```

Append when an operator dismisses a candidate interactively, or when a filed item is closed as
won't-fix/not-planned. Consulted at candidate assembly (ranking.md); suppression is a soft
default the invocation prompt can override. Match on the candidate statement's substance (same
surface + same improvement), not string equality — re-worded duplicates of a dismissed
candidate are still dismissed.
