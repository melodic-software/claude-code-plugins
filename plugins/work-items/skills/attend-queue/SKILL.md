---
name: attend-queue
description: "Attend the human-in-the-loop queue for loop-lane operation: ONE attention view merging worker-escalated items (human-gated role label + machine-marked escalation comment) with untriaged raw intake, then drive each row to resolution — answer escalated questions via interview, write answers back as issue comments, ratify first-drain C3 admissions, and flip unblocked items to the autonomous-eligible role label. Use when: 'attend the queue', 'attend queue', 'answer escalations', 'work the escalation queue', 'what needs my attention across the lanes', 'HITL queue', 'ratify admissions', 'clear the human queue'. Attended lane of the loop-lane three-session topology — judgment only; never executes work items, never merges. Composes /work-items:triage (attention view + machinery) and /planning:interview. Sibling skills: /work-items:work-loop (autonomous drain), /work-items:triage (raw intake), /work-items:track (backlog CRUD)."
argument-hint: "(no arguments — polls escalations and untriaged intake for the bound repository)"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Label edits, comments, and
closes route through the bound adapter's write mechanics; the core inlines no provider commands —
with one deliberate exception below: the `#502` telemetry upsert is an inlined `gh api` call,
mandated by the loop-lane convention because an installed plugin cannot invoke a sibling plugin's
script.

## Purpose

The **attended queue** of the loop-lane three-session topology: a human-present poll of everything
the autonomous lanes escalated plus everything raw intake produced, in one attention view. This
lane owns judgment — it answers, ratifies, and routes; it never executes work items and never
merges. It runs attended by definition; the worker loop (`/work-items:work-loop`) is the
unattended surface.

## Loop-lane contract (cited, never restated)

Shared cross-lane concerns — topology, the escalation contract, capability tiers, stop shapes,
telemetry, the guard binding — are owned by the loop-lane convention
(`docs/conventions/loop-lane/README.md` in this plugin's marketplace repository) and held here by
citation. This skill restates none of them; it adds only the attended-lane mechanics below.

## Attention view (one view, two sources)

Build a single merged view, oldest first, each row tagged by kind:

1. **`[escalated]`** — open items carrying the human-gated role label (**resolved from the
   binding's `config.role_labels`, never compared as a literal**; warn loudly on a defaulted
   resolution) that also carry a machine-marked escalation comment whose first line starts with
   `<!-- work-items:escalation` — the marker is what discriminates a worker-**escalated** item
   from an operator-**parked** one; both wear the same role label, so the label alone never
   qualifies a row. Marker kinds `escalated` (a worker question) and `routed-advisory` (a
   workflow-bot advisory routed by the worker loop's intake sweep) both list here;
   `kind=ratify-c3` rows list as `[ratify]` instead.
2. **`[ratify]`** — the subset of escalated items whose marker carries `kind=ratify-c3`: C3
   bug-fix-shaped admissions the worker loop queued for first-drain ratification (earn-trust
   posture; see `/work-items:work-loop`'s admission gate).
3. **`[intake]`** — untriaged raw intake, exactly the buckets `/work-items:triage`'s attention
   view defines. Compose that view; do not re-derive its buckets here.

Lane-infrastructure items never enter the view: the per-lane telemetry tracking issues (the
`Lane telemetry: <lane>` title contract, holding the loop-lane convention's sentinel-marked
status comment) are excluded from the intake source — the same exclusion the worker loop applies
to its drain snapshot. An open telemetry issue is a lane operating, not intake.

Present the merged table with one-line summaries, then work rows in the operator's chosen order
(default: oldest first, `[ratify]` rows before `[escalated]` before `[intake]` at equal age —
ratifications unblock the waiting worker loop).

## Working the queue

**Brief before asking.** This lane works rows across many items in one pass, so the operator's
context from the previous row never carries over. Before any operator-facing decision question in
this loop — an `[intake]` recommendation, an `[escalated]` question, or a `[ratify]` prompt —
restate (1) which item (number + one-line title), (2) the decision being asked, and (3) the
consequence of each option **you present**, then ask. An open-ended question presents no option set
to enumerate consequences for — state instead what the answer will determine, and never narrow a
genuinely open question into a closed list just to satisfy the restatement. A terse output style
must never compress this restatement away; the row's context is precisely what the operator needs to
answer without stopping the pass to ask which item is in front of them.

- **`[intake]` rows** — run `/work-items:triage <number>`. The operator is present, so triage's
  **interactive** direction gate applies: brief before asking, recommend, wait for direction, then
  mutate. All triage machinery (states, outcomes, briefs, closing invariant) is owned there.
- **`[escalated]` rows** — read the machine-marked comment for the escalated question, restate the
  brief above, then drive it to a decision with `/planning:interview` (when the `planning` plugin is
  installed; otherwise ask the focused questions inline, one at a time, most load-bearing first — the
  same fallback shape triage's interview step uses). **Write the answer back as an issue comment** on
  the item — the decision lives on the tracker, never only in the session — replying in the thread of
  the escalation comment where the provider supports it.
- **`[ratify]` rows** — restate the brief above, then present the classification and the intended
  dispatch from the marker comment and the consequence of ratifying versus declining. On operator
  ratification, record it as a reply comment and flip the item per the rule below; on decline, leave
  it human-gated and record the rationale as a comment.
- **Flip to agent-ready.** When an answer or ratification removes the human blocker, apply the
  autonomous-eligible role label and remove the human-gated role label **in the same edit** (both
  resolved from `config.role_labels`, never literals) — an item wearing both roles is a
  contradiction. The item re-enters the worker loop's frontier on its next cycle; do not dispatch
  it from this lane.

Answers and dispositions written by the agent on the operator's behalf carry triage's AI
disclaimer; the operator's own words need none.

## Telemetry

Per the convention, this lane too maintains exactly ONE sentinel-identified status comment on its
per-lane tracking issue in the target repository (default title `Lane telemetry: attend-queue`,
created through the seam `create-item` verb when absent), edited in place each pass with the rows
handled, the answers written, and the guard mode. Same inlined upsert as the worker loop with
`MARKER="work-items:attend-queue"`:

```bash
MARKER="work-items:attend-queue"
SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"   # first line of $BODY_FILE
LOOKUP() { gh api --paginate "repos/$REPO/issues/$ISSUE/comments" \
  --jq ".[] | select(.body | startswith(\"$SENT\")) | .id"; }
if ! LIST=$(LOOKUP); then
  echo "telemetry: comment lookup failed; skipping upsert this cycle (fail closed)" >&2
else
  if [ -z "$LIST" ]; then
    gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" >/dev/null
    LIST=$(LOOKUP) || LIST=""   # re-list; a failure here converges next cycle
  fi
  CANON=$(printf '%s\n' "$LIST" | sort -n | head -n1)
  if [ -n "$CANON" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE"
    for DUP in $(printf '%s\n' "$LIST" | sort -n | tail -n +2); do
      gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
        -f body="Superseded duplicate - canonical telemetry comment: $CANON" || true
    done
  fi
fi
```

**Creation race reconcile (encoded above).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges every cycle
duplicates are visible: the LOWEST comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone so it never matches a lookup again — this
covers a racer that died between its POST and its own re-list, because the NEXT session's
ordinary upsert performs the same reconcile. A crashed racer's unmerged counters are an
accepted loss (durable state re-derives over a cycle); nothing is deleted.

When the bound provider is not `github`, this upsert is unavailable: carry the same telemetry
content in the lane's pass report/log instead, with a notice that the comment surface is absent.

## Rate-limit guard floor (inlined)

This lane consumes the shared subscription rate-limit windows. The operable floor below is inlined
**verbatim** per the convention's inline-floor rule (byte-identical across lanes and to the reader
contract's floor); provenance is the `rate-limit-guard` plugin's reader contract
(`plugins/rate-limit-guard/reference/reader-contract.md` in the marketplace repository) — cited for
provenance only, since an installed plugin cannot read a sibling plugin's files at runtime.

- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 90`
- **Pause end:** the **tripped** window's `resets_at`; when **both** windows trip, the **later**
  `resets_at`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale — treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from a
  fresh snapshot stays valid through the pause (no refresh happens while paused). While paused, a
  consumer **must** arm a session Monitor on the tee file and re-evaluate on every write — the file
  carries **no account-identifier field**, so a write is the only signal that the windows changed
  under you (account switch, another session's refresh).
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.

Two further reader-contract rules apply alongside the floor (outside the byte-audited block):

- **Fail-open capability detection, per window** (reader contract, "Capability detection"): tee file
  absent, stale, or missing `rate_limits` → whole guard **unknown → reactive-only**. An absurd
  `used_percentage` or `resets_at` makes only **that window** unknown: keep applying the floor to
  every still-plausible window, and drop to reactive-only only when no window is plausible. Never
  throttle proactively on untrusted data and never fabricate a pause.
- **Untrusted fields** (reader contract, "Tee file shape"): session-distinguishing fields (`session_id`,
  `session_name`, any future account field) are user/AI-influenced — parse them only with a JSON
  parser; never string-interpolate them into a shell command, another interpreter, or a prompt.

For this attended lane, "stop claiming new work" means: finish the row in hand, then stop pulling
further rows and report the pause to the operator — who may explicitly choose to continue (the
operator's presence is the "explicit user request" the hard-stop rule anticipates).

## Gotchas

- **The label alone is not an escalation.** `needs-human` (or its remap) marks parked items too;
  only the machine-marked escalation comment qualifies a row as `[escalated]`. Listing every
  human-gated item as if the worker escalated it buries real questions under parked ones.
- **Never flip without clearing.** Applying the autonomous-eligible role while the human-gated
  role remains would leave the item excluded from `list-frontier --autonomous` anyway — the flip
  is one edit that applies one role and removes the other.
- **Judgment lane only.** Resolving an escalation never turns into executing the item here; the
  worker loop picks it up through the frontier. Executing from this lane would bypass the seam
  claim and the topology's single-authority rule.
- **Do not re-triage routed items.** The `[intake]` source is `/work-items:triage`'s attention
  view by composition; items already carrying a routing outcome are out of scope by construction,
  and naming one explicitly gets triage's "already triaged" stop.
