---
description: "Structured retrospective of a session, or of chosen CI lane runs from their sealed transcripts: transcript metrics, quality across five dimensions, feedback-memory regression check, and codified learnings. Use when: 'retro', 'what did we learn', 'retro these CI runs', 'why did this lane run go wrong', or at end of session. Mid-session: /session-flow:running-retro."
argument-hint: "[session [--pattern '<regex>']|quick|ci-runs <run>…] [--sink <dir>] [--unattended]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: retro
  summary: Structured session retrospective with codified learnings
---

**Arguments.** `[session [--pattern '<regex>']|quick|ci-runs <run>…] [--sink <dir>] [--unattended]`. Full `ci-runs` form: `ci-runs [quick] (<run url or id>… | --lane <workflow stem> --last <n> | [--lane <stem>] --since <day> [--until <day>] [--outcome <o>] [--model <m>]) [--sink <dir>] [--unattended] ["<your view of the result>"]`. e.g., /retro, /retro session, /retro session --pattern 'PROJ-\d+', /retro quick, /retro quick --unattended, /retro ci-runs `<run url>`, /retro ci-runs 4471, /retro ci-runs --lane pr-verify --last 3, /retro ci-runs quick --since 2026-11-01 --outcome error --sink /srv/lane-transcripts "it approved a change it should have stopped"

## Context. Gather first

Take `session-id`, `branch`, `status`, `recent-commits` at `-5`, and `changed-files`.
Probe commands, the one-command-per-call and treat-failure-as-unknown rules, and the `$`-expansion
rationale for gathering at run time rather than pre-computing:
[`${CLAUDE_PLUGIN_ROOT}/reference/gather.md`](${CLAUDE_PLUGIN_ROOT}/reference/gather.md).

## Purpose

The self-improvement loop. Answers: "What happened, what did we learn, and how do we prevent the
same mistakes next time?"

**Three concepts this skill enforces:**

1. **Analyze**. Examine what happened with evidence (transcript metrics, conversation context,
   feedback regressions)
2. **Identify**. Find errors, behavioral adjustments, process improvements, and skill/tool
   candidates
3. **Codify**. Persist learnings durably (the consuming repo's instruction files and rules, or
   Claude Code auto-memory for contributor-specific facts)

**What this skill is not:** not a code review (design judgment on current work), not outcome
verification (does the change match intent), and not Claude Code's built-in `/insights`
(cross-session usage analytics); this is structured quality analysis with codification.

## Paths

Resolve at runtime, never hardcode machine-specific paths:

- **Session data root**. `~/.claude/projects/<project-slug>/`, where `<project-slug>` is the
  project's absolute path with every character outside `[A-Za-z0-9]` replaced by `-`:

  ```bash
  PROJECT_SLUG=$(pwd -W 2>/dev/null || pwd)          # Windows drive form when available
  PROJECT_SLUG=$(printf '%s' "$PROJECT_SLUG" | sed 's/[^A-Za-z0-9]/-/g')
  SESSION_DATA_DIR="$HOME/.claude/projects/$PROJECT_SLUG"
  ```

  Verify the directory exists before use; if the computed slug misses, find it by locating the
  current session's JSONL: `ls "$HOME/.claude/projects"/*/"${CLAUDE_CODE_SESSION_ID}.jsonl"`.
- Transcript: `<SESSION_DATA_DIR>/<session-id>.jsonl`; subagents:
  `<SESSION_DATA_DIR>/<session-id>/subagents/`
- **Auto-memory** (feedback regression check): `<SESSION_DATA_DIR>/memory/`. Present only when the
  consumer uses Claude Code auto-memory; degrade gracefully when absent
- **Pointer**: when the computed transcript or auto-memory path misses, fetch
  [Where transcripts are stored](https://code.claude.com/docs/en/sessions#where-transcripts-are-stored)
  and [auto memory's Storage location](https://code.claude.com/docs/en/memory#storage-location) live.
- **Score history** (plugin state): `${CLAUDE_PLUGIN_DATA}/scores/<project-slug>.md`. Survives
  plugin updates, never lands in the consumer's repo
- Parser: `${CLAUDE_PLUGIN_ROOT}/scripts/parse_transcript.py`, run per
  [`${CLAUDE_PLUGIN_ROOT}/reference/transcript-parser.md`](${CLAUDE_PLUGIN_ROOT}/reference/transcript-parser.md)
- **Lane transcript sink** (`ci-runs` only): `--sink <dir>`, else the `lane_transcript_sink`
  option under "Session settings". Neither set: stop and ask for `--sink`. There is no default
  location. Its layout is the lane-transcripts contract
  (`docs/contracts/lane-transcripts/README.md` in this plugin's marketplace repository); the
  resolver is `${CLAUDE_PLUGIN_ROOT}/scripts/lane_legs.py`
- **Lane score history** (`ci-runs` only): `${CLAUDE_PLUGIN_DATA}/scores/lanes/<lane>.md`, one
  file per lane

## Step 0: Detect mode

| Signal | Mode | Context file |
|--------|------|-------------|
| End of session, bare `/session-flow:retro`, post-merge | **session** | [context/session.md](context/session.md), full 5-phase analysis |
| "quick retro", short session, limited context | **quick** | [context/quick.md](context/quick.md), abbreviated pass |
| `ci-runs`, or CI lane runs to look back on | **ci-runs** | [context/ci-runs.md](context/ci-runs.md), the session phases over sealed lane legs; `quick` after `ci-runs` is its depth, not quick mode |

Score history across sessions names no retro mode. Before reading any mode, stop on a bare "how am
I doing", a request for scores, or a `trends` argument, and name `/session-flow:audit-sessions trends`;
"how did I do this session", a question about this one session, still runs a retro.
That action reads the history this skill writes and adds delivery metrics; this skill analyzes no
session for it.

A retro of one pull request (its sessions, its review comments) names no retro mode: stop and name
`/session-flow:audit-sessions pr --number <n> --repo '<owner/repo>'`.

A `codify` argument, "codify reviews" or "mine review comments" names no retro mode: one recurring
mistake, or the lessons in recent merged pull requests' review comments, go to
`/corrections:codify` (its `reviews` action reads the review comments) when the `corrections`
plugin is enabled. Name that skill and stop; when it is not enabled, say that no enabled
skill codifies one mistake or mines review comments, and stop.

`--unattended`, anywhere in `$ARGUMENTS`, is the caller declaring that nobody is present: take it
out first. It only gates the user-only built-ins (`/export`, `/insights`): an unattended run neither suggests nor runs them. The bare
word `unattended` is neither this flag nor a mode: stop and name `--unattended`. A `--pattern '<regex>'` pair is taken out next and
kept for session mode's ticket section; it selects `session` when no mode is named, and with
another mode named, stop and say `--pattern` is session mode's only. A first token of `ci-runs`
selects ci-runs mode, which reads every remaining token itself ([context/ci-runs.md](context/ci-runs.md),
"Arguments"); `--sink` and the run selectors outside it are not this skill's, so stop and name
`ci-runs`. Read the mode from the remainder. If it specifies a
mode, use it. Otherwise infer from context; when the session is long or
degraded, or compaction has occurred, prefer `quick`; ambiguous → `session`. Read the mode's context
file before proceeding.

## Step 1: Execute the mode

Follow the selected context file. Each mode has its own phases, outputs, and interactive
checkpoints.

### Reference index. Load on demand

| File | Load when |
|---|---|
| [reference/ecosystem-improvement-catalog.md](reference/ecosystem-improvement-catalog.md) | Before filling session mode's Phase 3 recommendation table, and any other time a finding has to be mapped to an ecosystem target. It owns the project-vs-personal placement decision tree and the per-target recommendation format for memory, rules, hooks, skills, agents, MCP servers, and settings. |

### Session settings

The user options session and ci-runs modes read, as rendered for this run (a literal, unexpanded
placeholder, or an empty value, means unset): `retro_lenses` = `${user_config.retro_lenses}`;
`lane_transcript_sink` = `${user_config.lane_transcript_sink}`. [context/session.md](context/session.md) "Review lenses"
resolves `retro_lenses` against the repository's `docs/conventions/session-flow.yaml`, which wins.

## Step 2: Handoff

After the retrospective:

| Condition | Suggestion |
|-----------|-----------|
| End-of-session, retro complete | Suggest any wrap-up steps the consuming repo defines |
| Session mode, follow-ups queued | Suggest filing them in the consumer's work-item tracker |

## Multi-session awareness

When the sibling `handoff` skill's save-points exist (the resolved `<memory_dir>/handoffs/`,
default `.work/handoffs/`; or the consuming repo's documented location), the retro spans the
whole session chain, not just the current session: the
parser's `--chain-from` walks `previous_handoff` frontmatter pointers
backwards from the newest handoff file, adds every hop whose hot file is gone but whose hop file
remains, and aggregates metrics across every chained transcript. Its `handoff_journey` gives each
hop's Direction changes, This session and Observations, read from the hop files where a section
moved; reconstruct each hop's journey from it. See [context/session.md](context/session.md)
Phase 1.

**State the discovery basis, and never present a low-coverage chain retro silently.** The walk
follows `previous_handoff` pointers, so it stops at the first session that wrote no handoff file,
a chain linked by hand-pasted continuation prompts instead of save-points can end after one hop.
The parser reports what it saw in `chain_coverage` (`requested` / `found` / `available` / `ratio`,
where `available` is the requested chain, plus under `--chain-from` the other transcripts that
mention the handoff's topic; `project_transcripts` counts the whole project directory apart from
the ratio). When `ratio` is below ~0.5, say
so before presenting: name the found and available counts, and offer `--sessions` with the ids
enumerated explicitly. A retro authored from a fifth of the evidence must not read like a complete
one. Offer each `fork_candidates` entry the same way: a fork shares records with the chain but no
handoff points at it, so the walk never reaches it.

**Offer a durable copy when the session was worth retrospecting.** The transcripts this retro reads
are retention-swept (`cleanupPeriodDays`), and the conversation itself has no durable artifact.

- **Pointer**: [Data usage § Data retention](https://code.claude.com/docs/en/data-usage#data-retention),
  for the retention period and what `cleanupPeriodDays` adjusts.

If /export is available in your session (gate basis: **Verification record: `/export`** below), suggest that the person run it for a durable conversation copy at `<memory_dir>/exports/<YYYYMMDDTHHMMSSZ>-<topic>.txt` after verifying the memory root's self-ignore guard (a `.gitignore` containing `*`; create it and announce it when absent). This skill never invokes `/export` itself. **`--unattended`:** make no suggestion.

## Verification record: `/export`

- **Decision.** Suggest `/export` to the person and never run it: it is a built-in interactive command the Skill tool does not list and headless runs refuse. A command that is not available to the person is left out of the menu.
- **Probe record.** The `export` → `session-flow:retro` entry of `docs/native-surfaces.md` in this plugin's marketplace repository holds the headless refusal, the invocation mode, and the trigger that reopens this decision.
- **Pointer.** When deciding whether `/export` can run headless or take a format or redaction flag, fetch the `/export` row of [Commands § All commands](https://code.claude.com/docs/en/commands#all-commands) live.

## Boundary, the built-in `/insights` command

Both look back at how sessions went, so "how did I do" can land on either.

- **`/insights` (built-in command)**: a cross-session usage report; this skill never runs it. What
  it reports: the records in
  [reference/native-insights.md](reference/native-insights.md).
- **This skill (marketplace plugin).** A structured retrospective of one session or handoff chain:
  transcript metrics, five quality dimensions, feedback-memory regressions, and codification into
  rules or memory behind approval.

**Routing.** When the person asks about patterns across many sessions, offer it to the person: If /insights is available in your session (gate basis: ungated, though
some hosts lack it; records in [reference/native-insights.md](reference/native-insights.md)), you
can run it instead of or alongside this skill for a cross-session usage report. Make the offer at the end of the run. Prefer this skill for what one
session taught and for codifying it. When the caller passes `--unattended`, the run makes no
offer.

**Mutation gate.** This skill writes only approved codifications. It never runs `/insights` on the
person's behalf.

**Availability is never assumed.** This section states what to do when the person can run
`/insights`, never that it is present. What the report covers and where it is unavailable are read
live from the records in [reference/native-insights.md](reference/native-insights.md).

## What this skill does not do

- **Does not run builds or tests**. That's the consuming repo's verify stage
- **Does not fetch or open sealed lane transcripts.** CI only seals them; a puller with the private
  key opens them into the sink on the person's machine, and `ci-runs` reads that sink there
- **Does not review code quality**. That's its review stage
- **Does not write scores or reports into the consumer's repo**. Plugin state stays in
  `${CLAUDE_PLUGIN_DATA}`; only user-approved codifications (rule edits, memory entries) land
  outside it
- **Does not read a consumer-supplied scoring rubric**. The five dimensions are fixed plugin
  identity, not consumer config, and there is no seam to swap them. What adapts is what each
  dimension scores *against* (your repo's conventions, session-type calibration), never the
  dimensions themselves.

## Spoke paths

This skill's own [context/session.md](context/session.md), [context/quick.md](context/quick.md) and
[context/ci-runs.md](context/ci-runs.md), beside this SKILL.md, write the plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`. Put that path in place of the placeholder before running a command or
writing it into a brief: a `${…}` token in a spoke reaches the Bash tool unsubstituted.

- **Pointer**: <https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>

## Next

- /session-flow:audit-sessions trends: the score history session, quick and ci-runs modes write,
  across sessions and per lane, with delivery metrics.
- /session-flow:audit-sessions sweep: checks whether what this retro found recurs across every
  session on the machine.
- /session-flow:audit-sessions ticket --pattern '<regex>': every stored session for one work item.
  Session mode calls it when given `--pattern` ([context/session.md](context/session.md), "Ticket section").

## Gotchas

- **Run all phases by default** in session mode. Skip metrics only when the parser fails or the
  user asks
- **Always include skill-candidate and follow-up-candidate analysis**, even when the conclusion is
  "no candidates this session"
- **Codifying follows the workflow too**. A finding that lands as instruction text (a `CLAUDE.md`,
  `AGENTS.md` or rules-file line, the guidance tier of
  [reference/enforcement-ladder.md](reference/enforcement-ladder.md)) names its proof in the PR:
  an eval case, or a deletion watch with a date (`/harness-config:unhobble`, when the
  `harness-config` plugin is enabled). A mechanical finding goes to `/corrections:codify` (when
  the `corrections` plugin is enabled), which proves its own check, run once the user picks it at
  Phase 4
- **Phase 4 is an interactive checkpoint**, never persist codifications without explicit user
  approval
