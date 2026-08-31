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

then sorts that score descending, grants descriptions greedily until the budget
is spent, and renders the remainder name-only.

Recovered from `claude.exe` at Claude Code 2.1.251 (`zPe` the scorer, `Ymt` the
truncator), then re-verified unchanged at 2.1.252. The scorer has two further
call sites, the slash-menu top-five pin and the command-search score boost, which
is corroboration that it is the product's general usage-priority function rather
than a listing-local helper. What the counts it reads actually mean, including
the seeding and throttle traps, is [usage-counters.md](usage-counters.md).

## Why "least invoked" was the wrong description

The score is decay-weighted with a seven-day half life and a floor at a tenth,
so recency competes with volume. A skill used 100 times sixty days ago scores
`100 * 0.1 = 10` and loses its description to one used 12 times today, which
scores 12. Any wording that says descriptions are shed "starting with the
least-invoked skills" describes a mechanism the product does not have.

The floor matters at both ends. A never-used skill scores exactly zero and is
always shed first, which is the feedback loop this whole skill exists to expose.
A once-used skill never decays below `0.1 * usageCount`, so it never falls back
into the never-used band.

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
ordering is then the alphabetical tiebreaker and carries no signal, so competing
rows report `confidence: "unscored"` rather than `inferential`. The distinction
is load-bearing: `inferential` claims a ranking exists and may be imprecise;
`unscored` says no ranking was possible.

## On drift

This is a minified bundle, not a published interface. The recheck trigger is a
release note naming the skill listing, its character budget, or the usage
counters, or the counters changing shape in `~/.claude.json`. On a mismatch the
honest degradation is back to `unscored`, never a confidently wrong band.

**Locate the scorer by shape, never by name.** The minified identifier moves
between builds. It was `zPe` in 2.1.251 and `WPe` in 2.1.252, with a
byte-identical body, so a recheck that greps the old name finds nothing and
concludes the mechanism was removed. Grep the arithmetic instead:

```bash
grep -a -o -E '.{0,180}Math\.pow\(0\.5,.{0,180}' "$(command -v claude)"
grep -a -o -E '.{0,260}budgetTruncatedSkills:.{0,60}' "$(command -v claude)"
```

The first run of that recheck happened the same day the stamp was written: the
CLI auto-updated from 2.1.251 to 2.1.252 mid-session, the trigger fired, and both
the formula and the descending-sort truncation came back unchanged.
