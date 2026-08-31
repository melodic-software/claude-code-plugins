# Source skill recommendation from the catalog, not the in-context listing

- Status: accepted
- Date: 2026-08-18

## Context

`session-flow:show-options` answers "what should I run next?" by presenting the installed skills that
fit the moment as a menu the operator chooses from. Its defining constraint is that it must not
withhold an option because it judges the step already done or unnecessary — the human decides.

The obvious implementation reads the in-context skill listing, which is already in every session's
context and needs no I/O. That implementation was specified, then measured, and it fails the
constraint it was built to serve. Two documented listing behaviors are the reason:

- A skill set to `disable-model-invocation: true` is **absent from the model's listing entirely**.
  In this marketplace that is **56 of 207 skills (27%)**, including `education:teach`, the skill most
  relevant to an operator trying to learn their own catalog.
- When the listing overflows its character budget, Claude Code **drops descriptions starting with the
  skills invoked least**. Measured here with the repo's own `check-listing-budget.sh`: **101,563
  characters against an 8,000-char budget — 12.7× over**, leaving roughly 82% of skills as bare names
  in a live session.

"Forgotten" correlates with "rarely invoked", which is precisely what the drop-order sheds first. A
recommender sourced from the listing is blindest where the operator most needs it, biased in exactly
the wrong direction, and — the part that makes it a correctness bug rather than a limitation — it
cannot tell that it is blind. The gatekeeping the contract bans would have been reinstated by the
harness, invisibly.

> **Revised 2026-08-31:** the drop-order mechanism above is stated wrongly. Claude Code does not drop
> descriptions "starting with the skills invoked least". It ranks by a decay-weighted score,
> `usageCount * max(0.5 ^ (daysSinceUse / 7), 0.1)`, sorts descending, and grants descriptions
> greedily until the budget runs out; what does not fit renders as a bare name. So a heavily used but
> stale skill can lose its description before a lightly used fresh one: 100 uses 60 days ago scores
> 10 and loses to 12 uses today. Recovered from the Claude Code 2.1.251 binary and stamped in
> [`docs/topics/usage-tracking-claude-json/EXPLORE.md`](../topics/usage-tracking-claude-json/EXPLORE.md)
> Part 2, which carries the basis and the recheck trigger.
>
> **The ADR's core decision is untouched, and this correction strengthens the case for it.** A
> never-invoked skill scores exactly zero and is still shed first, so the bias this paragraph
> identifies holds; the decay term adds a second bias the paragraph did not anticipate, against
> skills the operator used a while ago and has since forgotten, which is the same population
> `show-options` exists to surface. The budget arithmetic quoted above is unaffected: it measures
> demand against the budget, not the order of shedding.

Separately, the no-omission rule was measured against the real catalog at a real moment. Rendering
every candidate in full produced **139 options across 275 lines, ~7 screens, ~4,100 tokens** — 97.8%
of the catalog, i.e. the generated cheat sheet with an extra column, which an operator reads once and
never again. Two buckets were structurally broken: "Standing" held 60 options (43% of the catalog, so
it predicted nothing), and "Backfill" was definitionally every upstream stage.

## Decision

**Candidate names resolve from the installed catalog, never from the in-context listing alone.** The
ladder is `/claude-ops:inventory` (gated on that plugin being installed — it owns whole-fleet
enumeration and ships a bundled script), else a catalog file the consuming project declares, else the
listing **with its truncation disclosed in the output**. Walking `~/.claude/plugins/cache` directly is
rejected: only the cache's existence is documented, its `<marketplace>/<plugin>/<version>` nesting is
not, and the version directory changes on every update — `skill-quality:check` already refuses that
move on those grounds, and a second cache-walker would be the silent-second-way that
`discipline:reuse-or-replace` forbids.

**Name completeness and per-skill enrichment are separate ladders.** A probe established that
inventory supplies complete names — `education:teach` verified present — but no descriptions and no
`metadata.workflow-stage`. Enrichment therefore resolves independently (frontmatter read where files
are reachable, else the listing's survivors, else absent).

**Absent enrichment lands a skill in tier 2, never in omission.** Output renders two tiers per bucket:
at most five ranked options in full treatment, then the entire remainder as bare invocation names with
an explicit count. Tier 1 requires a description; tier 2 does not. This is what lets a thin catalog
degrade without breaking the no-omission rule, and the explicit count is what makes the
omission-free claim checkable by the reader.

**The no-gatekeeping rule is two rules, because one is insufficient.** (1) Never omit a candidate's
name. (2) Never invent one. Rule 1 alone creates pressure to fill buckets from a thin source, and a
menu that confidently routes to a nonexistent skill is worse than a short menu. Model judgment
reaches **rank and annotations**; it never reaches **presence**. A skill believed to have run is
ranked normally and annotated.

**A truncated pool must be disclosed**, per `docs/conventions/liveness-assertion/`: a status or
advisory surface fails loud or routes its findings into a visible channel, never both green and
silent. A menu that looks complete while missing a quarter of the catalog is that violation exactly.

**V1 ships manual-only** (`disable-model-invocation: true`). This costs no listing-budget description
— confirmed empirically: the aggregate stayed at 101,563 characters after the skill was added — and
avoids a verbatim trigger collision with `session-flow:workflow`, which already claims "what comes
next" and carries the inverse mandate ("route to exactly ONE owner… never present both"). That
mandate is amended reciprocally to govern **stage** routing and cede option surfacing, because two
contradictory routing doctrines in one plugin is a defect regardless of which skill wins at runtime.

> **Revised 2026-08-21 ([#3024](https://github.com/melodic-software/claude-code-plugins/issues/3024)):**
> the skill now ships `disable-model-invocation: false`. Graded against
> [`docs/conventions/invocation-mode/`](../conventions/invocation-mode/README.md) — the owner doc
> for this choice — no exception class fits it, and neither of the two reasons above survives that
> rubric: the listing-budget saving is the move the rubric names as *not* a sufficient reason to
> hide a skill, and the `workflow` trigger collision is already fixed by the reciprocal amendment
> in this very paragraph, which makes hiding redundant over a solved problem. This paragraph's
> reasoning stands as what was weighed at V1; the decision is in the rubric's fleet-grade table.
> **The ADR's core decision is untouched** — candidate names still resolve from the installed
> catalog, never the listing, which is what makes the skill worth reaching in the first place.

## Consequences

The skill pays one bounded enumeration cost per invocation instead of zero, in exchange for a
candidate set that is actually complete. In a consuming repo without `claude-ops` and without a
declared catalog it degrades to the listing — and says so, which is the whole point.

Being manual-only means the operator must remember to invoke the skill about forgetting skills. That
recursion is accepted for V1 rather than solved: graduating to model-invocable is an evidence-gated
decision, not a default, and `discipline:use-your-skills` already records the deferral of a
deterministic per-prompt routing hook. `Stop` and `TaskCompleted` are the deterministic
boundary events if that graduation is ever taken — never `UserPromptSubmit`, which is per-prompt.

> **Revised 2026-08-21 (#3024):** the recursion is what settled it. The graduation was gated on
> usage evidence that could not accrue while the recursion held, and the success criterion named
> below measures the *bucket cut* rather than the mode — the ADR's own instruction is to revisit
> the buckets first and the posture second. Graduating removes the recursion instead of waiting
> it out: a human who says "what are my options" now reaches the skill by saying it. The
> deterministic-hook note above is unaffected and stays deferred — model invocation is
> description-matched, not hook-driven, so no `Stop`/`TaskCompleted` hook is implied by this
> revision.

**Placement.** `docs/CATALOG-TAXONOMY.md`'s assignment principle says subject wins when the subject
is the salient reason a plugin exists, which argues for filing this under `claude-code`/`claude-ops`
beside `inventory`. It lands in `session-flow` instead: the skill's subject is the **session** — what
to do next given where this session stands — and its inputs are session state (durable artifacts,
trajectory, position). `inventory` answers "what exists on this machine", a machine-scope question
with no session in it. This skill consumes that answer; it is not a variant of it.

**Success criterion and recheck trigger.** The design is falsifiable, and this is its only durable
record: the operator invokes at least one presented option in a majority of firings, and a
never-before-run skill gets invoked at least once a week. If either fails in use, **revisit the bucket
cut first** — Skipped-upstream persistently empty or Spotlight persistently ignored are the specific
signals — and revisit the manual-only posture second. Usage-metrics-driven surfacing
(`~/.claude.json` `skillUsage`, undocumented internal state) stays deferred; rotation runs off a
ledger the skill writes itself, which is what keeps that deferral honest rather than load-bearing.

> **Revised 2026-08-31:** the deferral stands, but "undocumented internal state" is no longer the
> reason and should not be read as one. That substrate is now characterized and dated in
> [`docs/topics/usage-tracking-claude-json/EXPLORE.md`](../topics/usage-tracking-claude-json/EXPLORE.md),
> which invites the false inference that the deferral lifts once the state is known. It does not,
> because three grounds documentation cannot cure survive:
>
> - The scorer is **wrong-signed** for the question this skill asks. `zPe` scores high for skills
>   used recently and often, which are exactly the skills the operator has not forgotten. Inverting
>   it collapses to a decay-weighted least-recently-used ordering, which the self-written ledger
>   already supplies without a build-pinned dependency.
> - `skillUsage` holds only skills that have fired at least once. It structurally cannot name the
>   never-invoked population the no-omission rule above exists to protect.
> - It carries no causal-trigger field, so it cannot answer take-up: whether a skill was invoked
>   *because* it was surfaced. The ledger can. That is not a stopgap for missing documentation; it
>   measures something these counters never will.
>
> A binary-derived stamp is also not what "documented" meant here. Its own fallback rule, treat a
> version mismatch as scorer-unknown, is what ships alongside ground that can shift without notice,
> and its recheck trigger fires only when a human reads a release note.
>
> **Conditions for a future revisit,** so the next reader does not have to re-derive them: a
> published, versioned surface for skill-usage data rather than a reverse-engineered internal; a
> rotation signal not decay-weighted toward recent use; and take-up attribution. The third is
> unreachable from `skillUsage` by construction, so the ledger survives whatever happens to the
> first two. **The ADR's core decision is untouched.**

**The probe seam, and why the two-consumer version was withdrawn.** `show-options` adds no probe of
its own — it routes to `orient` — and the duplication that decision sidestepped is resolved in the
same change: `plugins/session-flow/reference/gather.md` now owns the block for all seven consumers
(`continue-in-background`, `find-handoff`, `handoff`, `orient`, `retro`, `running-retro`,
`workflow`).

The route worth recording is the one not taken. The first plan extracted the seam for **two**
consumers, on the stated basis that `orient` and `workflow` were the only ones carrying the block.
That was false — seven carry it — and extracting for two would have left five divergent copies
beside a new seam: two sources of truth for one probe, worse than the duplication it set out to fix.
The extraction was withdrawn on that finding and only re-taken once it covered every consumer.

The per-consumer differences are preserved rather than normalised, because a uniform block would
have silently changed behavior: `orient` reads `git log -8` where the save-point skills read `-5`,
`retro` alone takes `git diff --name-only HEAD`, `find-handoff` takes no git state beyond the
branch, and `workflow` takes no session id. The seam documents each divergence as deliberate so a
later tidying pass does not "fix" them.
