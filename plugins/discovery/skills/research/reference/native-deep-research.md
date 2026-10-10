# The bundled `deep-research` workflow: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. Nothing here asserts the workflow is present in any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `deep-research` is a bundled workflow, not a skill: "Deep research harness: fan-out web searches, fetch sources, adversarially verify claims, synthesize a cited report", with phases Scope, Search, Fetch, Verify, Synthesize | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29 (`bundled_workflows` lane) | 2026-09-29 | A release renames or removes the workflow, or changes its phases |
| Its registration sets model invocation disabled, and the docs say "`/deep-research` runs only when you invoke it. Before v2.1.218, Claude could also start it on its own" | The same extraction (`disable_model_invocation: true`); the commands page <https://code.claude.com/docs/en/commands>; the 2.1.218 changelog entry "Changed `/deep-research` to start only when invoked manually" (<https://code.claude.com/docs/en/changelog>) | 2026-09-29 | A release changes its invocability, or the commands page note changes |
| `/deep-research <question>` fans out web searches across several angles, fetches and cross-checks sources, votes on each claim, and returns a cited report with claims that did not survive cross-checking filtered out. It requires the WebSearch tool | The bundled-workflows table on <https://code.claude.com/docs/en/workflows>; the `/deep-research` row on the commands page | 2026-09-29 | Either row changes its description or its requirement |
| Before invoking, an underspecified question gets 2-3 clarifying questions, and the refined question is passed as arguments | The workflow's `when_to_use` text in the same extraction | 2026-09-29 | A release changes the workflow's `when_to_use` |
| It researches one question per run; nothing in its description splits a multi-topic ask, applies source tiers, or writes a coverage ledger | The rows above | 2026-09-29 | A release gives the workflow multi-topic splitting or a source-tier contract |

## Why the verdict is complementary

Both produce a cited report from fanned-out web research. The workflow is the vendor's harness for
one question, with adversarial claim voting, run by the person. This skill dispatches from the
model's side: it splits a multi-topic ask into one researcher per topic, holds each to the
`/discovery:research` discipline (source tiers, recency gate, falsification, coverage ledger), and
grades each run with a fresh verifier. For one deep question the person may prefer the workflow, or
run it alongside; the model offers it and does not start it.

## Presence

Bundled surfaces vary by settings, plan, platform, and host (whether `disableBundledSkills` also
hides bundled workflows is not established), and this workflow also needs WebSearch. The offer names the command for the person to try; an
unattended run records the offer in its output. Recheck when a release or docs change adds,
removes, or renames a gating axis.
