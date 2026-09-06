---
outcome: early-exit
tier: B
date: 2026-09-06
---

# Design resolution. Enforceability audit lane

## Outcome

Early exit at Tier B. No separate `/planning:design` session was run. The container Brief on
issue #3800 already fixes the shape of the one thing this lane builds: a read-only `audit` skill
in the review plugin that reads one findings file, applies a crosswalk, and writes one stub per
finding. What remained open were three contracts, and each was settled by reading the surfaces the
skill will actually touch rather than by a design round.

## Contracts this lane introduces

1. **The finding-class derivation ladder.** The findings-file shape carries no class column. The
   only class-bearing signals in a conforming file are a leading qualified rule id in the `Finding`
   cell (detector producers) and the `## By dimension` headings (fanout's own writer only). The
   crosswalk therefore keys on a small class vocabulary and the skill derives the class per row
   through a stated ladder, never dropping a row it cannot classify. Recorded in `PLAN.md`
   Phase 1 and in the implementation slice body.
2. **The stub shape and home.** A stub carries `type: enforceability-stub`, never a
   findings-file marker, and lands in the topic-slice memory tier, never under the branch findings
   directory. Recorded in `PLAN.md` Phase 1 and the slice body.
3. **The stub-writer CLI.** One script owns the deterministic half (parse the table, write stubs,
   refuse a home inside the findings directory, self-check for markers); the model owns
   classification. Recorded in `PLAN.md` Phase 2.

## Threads resolved by research, not by the Brief

- The Brief names "the upstream Roslyn analyzer skill" as the owner of the custom-analyzer rung.
  Research found no installable plugin carrying such a skill (only a personal marketplace's
  monolithic plugin and Roslynator's contributor-only skills), so that rung's owner is the
  Microsoft Learn analyzer tutorial, a doc pointer. The Brief is amended.
- The Trail of Bits Semgrep rule creator resolves to the `semgrep-rule-creator` plugin in the
  `trailofbits` marketplace and is presence-gated on the plugin name.
- The automation-gaps hooks lane has no findings input path. The handoff is the operator carrying
  the stub into that skill's candidate step, gated on the `claude-config` plugin.

## What would reopen design

A second consumer of the stubs (a recurrence detector, a realign-style executor) would turn the
stub from a proposal into an input contract and would argue for a reserved concern-scoped home
under the topic-docs convention rather than a topic slice. Cross-run recurrence is deferred on the
container and is the trigger.
