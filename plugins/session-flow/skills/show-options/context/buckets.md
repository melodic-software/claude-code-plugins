# Buckets and rendering

How `show-options` sorts the resolved catalog into five buckets and renders them in two tiers. The
two rules in `SKILL.md` govern *presence*; everything here governs *order*, *grouping*, and *shape*.

## Why five, and why not the obvious four

An earlier cut of this design used **Backfill / Now / Next / Standing**. Built out against a real
~140-skill catalog at a real moment (a pre-PR session), it measured:

| Bucket | Options |
|---|---|
| Backfill | 27 |
| Now | 28 |
| Next | 25 |
| Standing | 60 |
| **Total** | **139** — 275 lines, ~7 screens, 97.8% of the catalog |

That is not a recommender; it is the generated cheat sheet with an extra column. Two of the four
buckets were structurally broken rather than merely large:

- **"Standing" (anytime hygiene) held 60 options — 43% of the catalog.** A bucket holding nearly half
  the population predicts nothing about its members. It was a dumping ground.
- **"Backfill" was definitionally every upstream stage.** At any given moment, every decision already
  made is upstream by construction, so "could still be run for a decision already made" selected the
  entire early catalog — 27 items, of which about two were genuinely useful.

The current five keep the two that earned their place, replace the two that did not, and add
`Later` — the catch-all whose absence would have made the never-omit rule unsatisfiable.

## The five

### Now

Fits the current moment. Ranked by fit to what the session is actually doing.

### Next

Two or three steps ahead on the trajectory. Answers "what is coming" so the operator can prepare or
reorder, not just react.

### Skipped upstream — artifact-grounded, never inferred

Only stages **upstream of the detected position whose output artifact is absent on disk**. The
artifact is the evidence: a plan file, a research index, cited sources, green test output. This is
`workflow`'s existing rule applied here — verify a stage from its artifact or output, not from
conversation vibes.

Grounding it this way collapsed the measured 27 to 2 in the scenario above, and both survivors were
real. Grounding it in conversation instead reinflates it toward the whole upstream catalog.

**When the memory root is unreadable or empty, this bucket does not fall back to inference.** In a
worktree, a sibling lane, or a fresh clone the memory slice is invisible, so every artifact reads
"absent" and inference would announce that the operator skipped everything — maximally wrong, and
wrong in the confident direction. Render the bucket empty with the reason:

```text
Skipped upstream: cannot ground upstream stages here — the memory slice is not readable from this
checkout, so artifact absence is not evidence of a skipped stage.
```

### Later — the in-domain remainder, tier 2 only

Everything relevant to this project that sits beyond the Next horizon: testing, review, and
verification skills early in a session; migration and release skills mid-build. Under the earlier
four-bucket cut these fit nowhere — not Now, not the two-to-three-step Next, not upstream, and not a
three-entry Spotlight — so the never-omit rule could only be honoured by stretching another bucket's
definition or by dropping them. Both are failures; this bucket is the fix.

**It renders tier 2 only** — bare invocation names with a count, roughly one wrapped line — and that
constraint is what keeps it from becoming the 60-row dumping ground "Standing" was. A catch-all is
safe precisely because it costs a line; a catch-all with full treatment is the failure mode measured
above.

It holds relevance, not everything. An out-of-domain skill (songwriting in a code session) is still
omitted under the irrelevant test in `SKILL.md`. If `Later` starts approaching the whole catalog,
the irrelevant test is being applied too timidly — that is the signal to tighten it, not to cap
`Later`.

### Spotlight — exactly three, least-recently-surfaced

Ranking alone re-shows the same handful of skills forever. That serves the immediate decision and
teaches the operator nothing about the rest of their catalog — repeated exposure to the same five
entries is restudy, not learning. Rotation forces encounters with different corners of the fleet
across invocations.

**Ledger — path and record shape are fixed here, not left to the invocation.** Two sessions choosing
different filenames or formats would each fail to recover what the other surfaced, and the
least-recently-surfaced ordering would never advance. So:

- **Path:** `<memory_dir>/show-options/spotlight-ledger.json`, with `<memory_dir>` resolved through
  the plugin's topic-docs binding (default `.work/`). Not under a topic slug — rotation is a
  property of the operator's catalog, not of any one topic, and a per-slug ledger would restart the
  rotation on every new piece of work.
- **Record shape:** a JSON object mapping a fully-qualified invocation name to the ISO-8601 UTC
  timestamp it was last surfaced in Spotlight. Nothing else — no ranks, no counts, no history.

  ```json
  {"/discipline:point-dont-copy": "2026-08-19T00:41:12Z", "/education:teach": "2026-08-18T22:03:57Z"}
  ```

- **Ordering:** a skill absent from the ledger has never been surfaced and sorts before every
  present entry; among present entries, oldest timestamp first. Write back only the three surfaced
  this invocation.
- **A missing or unparsable ledger is not an error.** Treat it as empty — every candidate is
  then never-surfaced — and write a fresh one. Rotation degrades to arbitrary-but-fair on first
  run, which is correct.

Two consequences, both accepted and both stated rather than hidden:

- It **resets per worktree and per clone**, because the memory tier is not shared across checkouts.
  A fresh checkout starts the rotation over. That is a mild loss, not a correctness problem.
- Concurrent sessions are **last-write-wins**. There is no lease, and two sessions firing at once may
  each advance the rotation independently.

**Not `${CLAUDE_PLUGIN_DATA}`.** That path is keyed to the plugin identifier and *nothing else* — no
project, no checkout, no session — so a fixed filename there is one file per *machine*, shared by
every repository the operator works in. A spotlight surfaced in repo A would then suppress it in
repo B, which is a worse failure than losing rotation on a fresh clone.

## Two-tier rendering

Per bucket, in this order:

**Tier 1 — at most five, ranked.** Each option carries exactly three things:

1. the invocation name;
2. one line of what it would add **to this conversation** — grounded in what the session is doing,
   never a paste of the skill's generic description;
3. when you would skip it, stated as fact.

Annotations ride in tier 1: `(ran this session)`, `(heuristic bucket — no stage metadata)`,
`(disabled via skillOverrides)`, `(nameable, not invocable — built-in)`.

**Tier 2 — the entire remainder of that bucket**, as bare invocation names with an explicit count:

```text
Also live now (23): /testing:plan, /review:code-review, /docs-hygiene:compress, …
```

The count is not decoration. It is what makes the omission-free claim checkable by the reader: they
can see that 23 more exist and that none was silently dropped.

## The budget

**The whole output stays around 60 lines.** Five per bucket at three lines each is ~60 lines of tier
1 before headings; tier 2 adds roughly one wrapped line per bucket. The measured alternative was 275
lines.

The cap is on **presentation volume**, never on the candidate set. Ranking and tiering are permitted;
suppression is not. If a bucket has 60 members, all 60 names appear — five in full, 55 counted.

## Expansion

One word promotes any tier-2 roster to full tier-1 treatment: `expand now`, `expand next`,
`spotlight all`, `expand skipped`. This is progressive disclosure — the order facts are met in, not
whether they survive. Nothing was withheld; it was deferred by one keystroke, and its existence and
count were both already on screen.

## Ranking inputs

Rank within a bucket by fit to the current moment: what the durable state says just happened, what
the trajectory implies next, and how directly the skill's stated purpose addresses it. **"Already
done" may lower a rank. It may never remove an entry.** That distinction is the whole contract — a
design that ranks and then truncates has reintroduced merit-based omission through the cutoff.
