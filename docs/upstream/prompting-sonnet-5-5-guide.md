# Upstream source: "Prompting Claude Sonnet 5.5"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Guide sections](#guide-sections)
- [Model currency](#model-currency)
- [Left to other work](#left-to-other-work)

This is the provenance record for applying Anthropic's Sonnet 5.5 prompting guide across this
marketplace. It follows the record pattern set by [opus-5-5-usage-guide.md](opus-5-5-usage-guide.md).
Each guide section has one row. A row names the surfaces that carry the guidance, gives evidence
that they already did, or says why the section changes nothing in repository instructions. The
guidance itself stays at the guide: each surface states our rule in our words and points at the
live section.

## Status

Applied under #5685. The model-adaptation chapter is
`plugins/playbooks/reference/model-adaptation/sonnet-5-5.md`; meta-rule 3 in the `fable-5` skill
routes to it.

## Source and verification

- Guide: <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5>,
  raw `.md` read 2026-10-01 (27,412 bytes, MD5 `2bcb67cc9f72b68e8823f197034c06d6`).
- Read the same day for model currency: <https://code.claude.com/docs/en/model-config> (111,803
  bytes) and <https://platform.claude.com/docs/en/about-claude/models/overview> (17,143 bytes).
- Vendor-reported figures in the guide (the cost cut from the reviewer-subagent paragraph, the
  accuracy gain from the think-first line) are recorded as vendor-reported, not as verified facts.
- Recheck trigger: a re-fetch of the guide diverging from a row below, or a later Sonnet release.

## Guide sections

| Guide section | Ours | Verdict |
|---|---|---|
| Calibrate effort | The chapter's effort and thinking sections. `audit-instructions` I21 already names the Sonnet 5.5 default. The `effort:` pins on Sonnet-bound agents were set against Sonnet 5, and the guide says to sweep rather than carry a level over | ADOPT (chapter), TRACK #5682 |
| Steer initiative and scope | The chapter's low-effort and initiative sections. `AGENTS.md` ("When to stop and when to keep going") already states the keep-going and stop rule. `audit-prompting-postures` P2 and P6 cite the section | ADOPT (chapter, postures), already present (`AGENTS.md`) |
| Running without up-front thinking | `audit-instructions` I8-c widened to `sonnet-5-5`. I17 is not extended: the disable rejection for this model is sourced on the what's-new page, not the guide, and its remediation differs from I17's "leave thinking on" because `between_tools` exists | ADOPT (audit), KEEP I17 |
| Reasoning tasks with JSON output | API-side; the chapter carries it. I8-f is deliberately not widened, since the guide prescribes a think-first line for these tasks | ADOPT (chapter only) |
| User-facing progress updates | The chapter. No skill or agent body tells a model to hold findings for the final reply (searched for "hold", "only at the end"; no match). `audit-instructions` I8-e stays scoped to `sonnet-5`, and exact-match scoping keeps it off 5.5 | ADOPT (chapter), no site elsewhere |
| Tool use in chat and knowledge work | The chapter. No skill or agent text discourages tool use (searched "strictly necessary", "minimize tool calls"; no match). I28 covers the over-eager direction only | ADOPT (chapter), no site to fix |
| Mid-turn user messages | Harness-side. The chapter says nothing changes for the model and that tool-result text stays data | ADOPT (chapter only) |
| Verification on coding tasks | The chapter's low-effort section. `audit-prompting-postures` P5 cites the section. The `implementer` binds `opus` at `high`; the Sonnet-bound agents (four review agents and the explorer) investigate rather than edit source | ADOPT (chapter, postures) |
| Tolerant tool-call handling | Harness-side; the chapter tells the model to copy declared names exactly | ADOPT (chapter only) |
| Tools for complex visual inputs | The chapter. A shared crop and zoom capability is its own effort | ADOPT (chapter), TRACK #5681 |
| Safeguard refusals | The chapter's safeguards section. `audit-instructions` I10 widened to `sonnet-5-5`. `fable-5` meta-rule 3 names the Sonnet 5.5 fallback targets. The loop-lane known gap now covers the fast tier | ADOPT |

## Model currency

| Claim | Ours | Verdict |
|---|---|---|
| Sonnet 5.5 is the current Sonnet; `sonnet` resolves to it on the Anthropic API | `docs/official-docs.md` row, loop-lane alias binding (fast tier, reliable cutoff), `docs/plugin-philosophy.md` tier table | ADOPT |
| The Sonnet 5 chapter stays | Sonnet 5 is a legacy model and the cybersecurity fallback target for Sonnet 5.5. The 5.5 chapter lists what it reverses, narrows and leaves open | KEEP |
| Queue the guide and the what's-new page for a digest | `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-queue.md` | ADOPT |

## Left to other work

- Retuning the Sonnet-bound agents' effort pins is the effort eval sweep, #5682.
- The shared crop and zoom capability is #5681.
