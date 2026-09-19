# The listing scorer, mirrored

Read this when the starvation band's ordering is in question: why it is not a
count, why a bare usage key does not move it, and when it means nothing at all.
The engine's own stamp lives beside `listing_score` in
`scripts/audit_skill_visibility.py`; this file is the reasoning, not a second
copy of the claim.

## What the product actually does

Claude Code ranks skills for description truncation by

```text
usageCount * max(0.5 ** (daysSinceUse / 7), 0.1)
```

then sorts that score descending and walks **every** competing entry with a
running description budget, granting whatever still fits and rendering the rest
name-only.

**It is a greedy first-fit walk, not a score-ordered prefix.** The grant loop has
no early exit, so a cheap low-scored description can still be granted after an
expensive higher-scored one was refused. Description LENGTH is therefore a second
ranking input, which no prose account of this mechanism mentions:

```js
for (let me of W) {
  let ge = me.entryLen - (me.cmd.name.length + 2);
  if (ge <= pe) pe -= ge; else fe.push(me);   // no break
}
```

This matters for the report's two fields. The `verdict` mirrors the walk. The
`band` ranks exposure, lowest score first, and the two are allowed to disagree:
a band-1 row with a very short description can survive a pass that sheds a
better-scored row with a long one.

Recovered from `claude.exe` at Claude Code 2.1.251 (`zPe` the scorer, `Ymt` the
truncator), re-verified unchanged at 2.1.252, and re-verified at 2.1.263 (`t$e`
the scorer). The scorer has two further call sites, the slash-menu top-five pin
and the command-search score boost, which is corroboration that it is the
product's general usage-priority function rather than a listing-local helper.
What the counts it reads actually mean, including the seeding and throttle
traps, is [usage-counters.md](usage-counters.md).

**The truncation runs in two places with identical semantics.** One builds the
system-prompt listing and collects the entries it grants; the other computes
`budgetTruncatedSkills` and collects the entries it refuses, which is what the
overflow warning reports. Both sort descending by the same score, compute the
same name-only floor forward, and walk the same first-fit loop with no break, so
a mirror of one predicts the other. Bundled skills never shed in either. The
overflow warning names `skillListingBudgetFraction` as the knob.

## The budget the walk spends

```text
budget_chars = max(1, floor((window ?? 200000) * bytesPerToken * fraction))
```

`SLASH_COMMAND_TOOL_CHAR_BUDGET` returns before the fraction is consulted, so it
is an unconditional override. Otherwise three inputs decide the number, and only
one of them is a setting:

- `fraction` is `skillListingBudgetFraction` from the merged settings, default
  0.01. `skillListingMaxDescChars` (default 1536) caps each entry's description
  before it is summed.
- `window` is the ACTIVE model's context window. The 200,000 in the formula is
  only the fallback when no window is passed to the arithmetic; the live caller
  passes the model's window, which is 1M for current models on the Anthropic API
  unless `CLAUDE_CODE_DISABLE_1M_CONTEXT` forces 200k or
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS` (honoured only when `DISABLE_COMPACT` is
  also set) names another value.
- `bytesPerToken` is 4 or 3 BY MODEL, resolved from the model id. A 3-byte
  model gets a budget a quarter smaller than a 4-byte model at the same fraction
  and window.

So the familiar 8,000 is one point on a surface: 200k window, 4 bytes, 1%. At
1M and 4 bytes the same fraction budgets 40,000, and at 1M with a 5% fraction
200,000. The engine never resolves the model from disk, so unpinned it reports
the budget as a band over both windows and both byte estimates, each row
labelled, and names no row as the session's; `--context-window` and
`--bytes-per-token` collapse the axes when the operator knows them.

## Why "least invoked" was the wrong description

The score is decay-weighted with a seven-day half life and a floor at a tenth,
so recency competes with volume. A skill used 100 times sixty days ago scores
`100 * 0.1 = 10` and loses its description to one used 12 times today, which
scores 12. Any wording that says descriptions are shed "starting with the
least-invoked skills" describes a mechanism the product does not have.

The floor matters at both ends. A never-used skill scores exactly zero and sorts
last, so it loses its description first under any material overflow, which is the
feedback loop this whole skill exists to expose. It is not *always* shed, though:
because the walk is first-fit, a zero-scored skill with a very short description
can still be granted from what the others left. A once-used skill never decays
below `0.1 * usageCount`, so it never falls back into the never-used band.

Two more properties the ordering depends on:

- **Ties keep catalog order, not alphabetical.** The product's sort is stable, so
  equal scores stay in input order. This decides everything in the `unscored`
  case, where every score is zero and the tiebreak IS the whole ordering.
- **The grant budget is computed forward from a floor**, `budget - V`, where `V`
  is what the listing costs before any description is granted: every listed entry
  pays for its own name, the exempt classes pay their full rendering, and the
  separators are charged too. Deriving it by subtracting the overflow instead
  gets the grant boundary wrong, not just the ordering.

## Why a bare usage key does not move the band

The stores record a skill's usage under either its qualified `<plugin>:<leaf>`
name or its bare leaf, as separate rows. `zPe` looks up the listing entry's name
directly and does no fallback between the two; the product's own display helper
(`oKn`) does, but the scorer does not.

So the mirror does not either. Feeding it the merged total would predict a
truncation the product will not perform, and predicting the product wrongly is
the one thing this band must not do. `observation` asks a different question,
"how much has this skill been used", and takes every event, merged.

That means the product can leave an entry unscored while the skill is heavily
used under its other key. Faithfully reproducing that is the point.

## When the band means nothing

`listing.score_basis` is `unscored` whenever no usage survives to weigh. The
ordering is then the catalog-order tiebreak and carries no signal, so competing
rows report `confidence: "unscored"` rather than `inferential`. The distinction
is load-bearing: `inferential` claims a ranking exists and may be imprecise;
`unscored` says no ranking was possible. An unscored listing that overflows
therefore withholds the per-row verdict as well: every competing row reports
`verdict: "withheld"` with `reason: "unscored"` and no band, while the count of
descriptions that cannot fit, which is budget arithmetic rather than ordering,
is reported as usual. A catalog that happens to be
alphabetical makes the unscored order look alphabetical, but the mechanism is
input order under a stable sort, and a catalog in another order would show it.

## On drift

This is a minified bundle, not a published interface. The recheck trigger is a
release note naming the skill listing, its character budget, or the usage
counters, or the counters changing shape in `~/.claude.json`. On a mismatch the
honest degradation is back to `unscored`, never a confidently wrong band.

**Locate the scorer by shape, never by name.** The minified identifier moves
between builds. It was `zPe` in 2.1.251, `WPe` in 2.1.252 and `t$e` in 2.1.263,
with a byte-identical body, so a recheck that greps the old name finds nothing
and concludes the mechanism was removed. Grep the arithmetic instead:

```bash
grep -a -o -E '.{0,180}Math\.pow\(0\.5,.{0,180}' "$(command -v claude)"
grep -a -o -E '.{0,260}budgetTruncatedSkills:.{0,60}' "$(command -v claude)"
grep -a -o -E '.{0,120}SLASH_COMMAND_TOOL_CHAR_BUDGET.{0,160}' "$(command -v claude)"
```

The third grep lands on the budget arithmetic; its `bytesPerToken` parameter
and the `?? 200000` fallback are where the per-model inputs show up.

Stamp: verified 2026-09-11 against Claude Code 2.1.263. The formula, the
descending-sort first-fit truncation, the two truncator sites, and the per-model
bytes-per-token all hold at that build.
