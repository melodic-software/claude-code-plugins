# Plugin topology — copied-external-content plugin

The structural layout the plan will build. Working name `provenance` (thread T1). The ai-slop
plugin is the structural precedent (Q1 rationale); departures from it are flagged and argued.

```text
plugins/<name>/
  .claude-plugin/plugin.json        # manifest, version, description
  README.md                         # boundary vs adjacent owners, config keys, marker forms
  CHANGELOG.md                      # plugin versioning; rubric changes land here
  skills/
    audit/
      SKILL.md                      # actions: audit (default, read-only) | fix | sweep
      scripts/
        list-corpus.sh              # capability 1   (+ list-corpus.test.sh)
        extract-breadcrumbs.sh      # capability 2   (+ extract-breadcrumbs.test.sh)
        check-stamps.sh             # capabilities 3-4 (+ check-stamps.test.sh)
        fingerprint.mjs             # capability 8   (+ fingerprint.test.mjs)
        emit-findings.sh            # capability 12  (+ emit-findings.test.sh)
        score-golden.sh             # capability 16 tally (+ score-golden.test.sh)
      reference/
        rubric.md                   # the versioned, source-pinned rubric catalog
        dispositions.md             # fix discipline: three dispositions, guards, demotion
        source-fetch.md             # operational fetch route: rungs, identity, cache, budgets
        nomination.md               # nomination + judge prompt templates (untrusted spine inline)
      context/
        persist-findings.md         # relay mechanics: fetch contract, refuse-when-unreachable
      evals/
        evals.json                  # house CI warrant for the judgment-bearing skill
        fixtures/
          golden/                   # runner-agnostic cases; categorically excluded from scans
            c01-verbatim/ (case.md, source.md, expected.json)
            ...
    setup/
      SKILL.md                      # config management: keys, markers, override enablement
      evals/evals.json
```

## Load order and dependency direction

- `SKILL.md` orchestrates; scripts never call the LLM and never call each other (each is
  invoked by the flow, output JSON composed by the flow). No script imports another; the
  fingerprint module is the one pure library, and only its own CLI wraps it.
- `reference/` files are read by the flow at the step that needs them, never preloaded:
  `rubric.md` at judgment, `dispositions.md` only inside `fix`/`sweep`, `source-fetch.md` at
  the first fetch, `nomination.md` when spawning subagents.
- `context/persist-findings.md` follows ai-slop's model: the emitter fetches the
  detector-findings contract at run time and refuses to write when unreachable.
- Subagents (nomination, judges, semantic-diff verifier) are fresh-context dispatches from the
  audit flow using prompt templates in `reference/nomination.md` and `dispositions.md`; the
  plugin ships no `agents/` directory. Departure from nothing: ai-slop ships none either; the
  planning plugin's dispatcher precedent is for pipelines, which this is not.

## Where state lives (topic-docs tiers)

| Artifact | Tier | Path |
|---|---|---|
| Findings file (relay) | Memory, branch-keyed | resolved via the topic-docs rung order |
| Machine-parseable report sidecar | Memory | `.work/<topic-slug>/` of the run |
| Sweep closure ledger | Memory | `.work/<topic-slug>/sweep-ledger.md` |
| Fetch cache | Memory | under the run's memory slice, never tracked |
| Human report | Conversation | plus optional ephemeral HTML view, temp API path |

Nothing durable lands outside the consuming repo's own config (`.claude/<name>.json`) and the
edits `fix` makes to target files.

## Boundary statement (goes in README.md, argued once here)

- In-repo duplication: `docs-hygiene:extract-ssot` and `reference-dont-duplicate` own it.
- Doc-vs-code drift: `review:doc-drift-detector` and `codebase-health:audit` own it.
- AI-writing style: `ai-slop` owns it (same corpus, different defect).
- In-flight discipline (do not copy while writing): `discipline:point-dont-copy` owns it.
- The stamped-record format and fetch-route contract: the upstream-drift convention owns them;
  this plugin implements checks against them and carries an operational restatement in
  `reference/source-fetch.md` with a four-part record citing the convention (the plugin ships
  to consumers who do not have this repository, so a bare pointer cannot serve at run time).
- Code comments: out of scope v1; route-out note toward `code-tidying:audit-comment-residue`.
