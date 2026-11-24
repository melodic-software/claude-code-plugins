# Split intake and discovery by responsibility and compose runs by cost

- Status: accepted
- Date: 2026-11-23
- Related: owner interview, 2026-11-23 (the triage, exploration and research boundary; the
  claim check; the hand-off of the lane restructure);
  [`docs/glossary.md`](../glossary.md) (**approve**, **admission**, **stage**)

## Context

An issue passes through several kinds of work before a build run starts: triage (what the issue is,
whether it is actionable, its verdict), codebase exploration (`/discovery:explore`), external
research (`/discovery:research`), and, for an effort that spans sessions, a wayfind map whose shared
evidence lives on a dossier branch (`dossier_branch_prefix` in
[`source-control.yaml`](../conventions/source-control.yaml)). Today the intake lane writes the
verdict, a Knowable issue is researched inside its build run, and no lane runs exploration on its
own.

Two pressures pull apart. Separate modules with one responsibility each can be renamed and changed
alone. Separate agent runs cost a run, a rate-limit draw and a hand-off each, and GitHub chains
`workflow_run` workflows at most three levels deep
([events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)),
while a GitHub App's rate limit is per installation
([REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)).

## Decision

1. **Modules are split by responsibility.** Triage owns classification, actionability and checking
   the issue's factual claims against the code, because its verdict rests on those checks.
   Exploration and research stay separate skills.
2. **Runs are composed by cost.** A module runs inside whichever run consumes its output: research
   and exploration inside the build run today, or inside a wayfind item for a multi-session effort,
   with the dossier branch as the store several sessions read. No run is added per role.
3. **A separate run is added only on measured context bloat:** run logs showing the consuming run's
   context filling with a module's output before it does its own work.

## Alternatives considered

- **(a) A separate exploration lane**, started by an issue field or label and writing its findings
  to the dossier branch for the build run. Cleanest boundary and reusable output, but one more run,
  App token draw and chain level per issue. Not chosen.
- **(b) One agent run per role** (triage, explore, research, plan, build). Each role isolated, but
  Anthropic's current guidance is to merge specialists that chain on each other's output, touch the
  same data, or are often called together
  ([When to fold subagents into your main agent loop](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop),
  2026-10-22; [Building multi-agent systems](https://claude.com/resources/articles/building-multi-agent-systems-when-and-how-to-use-them),
  2026-01-23, on coordination cost). Not chosen.

The split follows Parnas's criterion of decomposing by the decisions likely to change rather than
by the steps of a flow ("On the Criteria To Be Used in Decomposing Systems into Modules", CACM,
1972), and matches established triage practice, where triage is a cheap first pass and
investigation and design are later states
([Kubernetes issue triage](https://www.kubernetes.dev/docs/guide/issue-triage/),
[Rust issue triaging](https://forge.rust-lang.org/release/issue-triaging.html)).

## Consequences

- The claim check lands in the intake lane's rubric first. Consumers of the shipped
  `/work-items:triage` skill get it once the intake lane runs that skill instead of a separate
  rubric, a lane change made after this record.
- Renaming a lane today touches many files because lane ids live in three vocabularies; one lane
  registry the other files read comes before any rename.
