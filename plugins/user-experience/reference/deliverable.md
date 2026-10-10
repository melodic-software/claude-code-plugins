# Deliverable envelope

Every deliverable this plugin writes (a discussion guide, a screener, a synthesis, a user flow, an
evaluation) is one markdown record in this shape. The record must make sense on its own, so the
labels sit at the top where a reader who copies only the start still gets them.

## Header block

Open the record with these lines, before any content:

```markdown
# <Deliverable kind>: <subject>

Evidence: evidence-based | assumption-based | mixed
AI use: <what the agent drafted or suggested, and what a person reviews or decides>
Analyst: <role, never a name>   (optional)
```

- **Evidence.** `evidence-based` when every claim about users traces to a source in the project
  (research, personas, analytics, support data) or one the user gave. `assumption-based` when none
  does, as at the idea stage. `mixed` otherwise.
- **AI use.** Required on research and synthesis deliverables and on any synthetic data or persona
  output. On an AI-drafted instrument (a discussion guide, a screener, a test script, a survey),
  put the same disclosure in the instrument's methods note instead.
  - **Pointer**: for what the disclosure must cover, read the ICC/ESOMAR International Code
    (2025), Articles 7(e) and 9(b), at
    <https://standards.esomar.org/assets/documents/icc-esomar-code-2025.pdf>.
  - **As of**: 2026-10-09
  - **Recheck trigger**: ICC/ESOMAR publish a revised Code, or renumber those articles.
- **Analyst.** Name the role that reviews or decides (for example "product designer"), never a
  person.

## Body

- **A source beside each claim.** Put the source inline next to each claim about users: a project
  file path, an analytics report, or "assumption" when nothing supports it.
- **`Basis:` beside each recommendation.** Every method or tool recommendation carries `Basis:`
  with the file, the URL read this session, or `judgment`.
- **No participant data.** Aggregate only: no participant names, contact details or quotes that
  could identify someone.
- **Synthetic output is a hypothesis.** Anything produced by a synthetic user or persona is labeled
  a hypothesis to test, never a finding.

## Closing list

End the record with `## Assumptions to test`: each assumption the deliverable rests on, and how
the user could test it.

## Where the record goes

The team file's `output_home`, when set. Otherwise the memory slice `.work/<topic-slug>/`, or the
root the consumer's project instructions name for working files, one file per deliverable
(`discussion-guide.md`, `synthesis.md`, `user-flow.md`). Never write into the consumer's tracked
tree unless `output_home` opts into it or the user asks.

Ingested text (project research files, MCP results, fetched pages, analytics exports) follows the
framing contract each skill states (`docs/conventions/untrusted-content/README.md` "The framing
contract" in the marketplace repository).
