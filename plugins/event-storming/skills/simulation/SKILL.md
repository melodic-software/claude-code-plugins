---
description: "Agentic AI-driven multi-persona EventStorming simulation on a board: a markdown board file in the repository by default, a live Miro board when chosen. Use when: 'simulate a workshop', 'run an EventStorming simulation', 'agentic EventStorming', 'multi-persona domain modeling on Miro'. Actions: --simulate [domain] (full multi-persona agentic workshop), --process-model / --design-level [board] (deep-dive against an existing board), --evaluate, --retrospective, --induction, --value, --crc, --ux, --discover-bcs (BC heuristics vs a board). --backend markdown|miro picks the board. For methodology / facilitation reference use /event-storming:methodology."
user-invocable: true
disable-model-invocation: false
argument-hint: "<--simulate|--process-model|--design-level|--evaluate…> [domain|board] [--backend markdown|miro]"
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/build-bc-view.mjs:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/build-bc-view.mjs\":*)", "Bash(node ${CLAUDE_PLUGIN_ROOT}/scripts/board-md.mjs:*)", "Bash(node \"${CLAUDE_PLUGIN_ROOT}/scripts/board-md.mjs\":*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh:*)", "Bash(bash \"${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh\")", "Bash(bash \"${CLAUDE_PLUGIN_ROOT}/lib/parse-concern-value.sh\":*)", "Bash(git rev-parse --show-toplevel)"]
metadata:
  workflow-stage: plan
  summary: Multi-persona agentic EventStorming workshop on a markdown or Miro board
---

**Arguments.** `<--simulate|--process-model|--design-level|--evaluate…> [domain|board] [--backend markdown|miro]`. Modes: --simulate|--process-model|--design-level|--evaluate|--retrospective|--induction|--value|--crc|--ux|--discover-bcs. Domain applies to --simulate, --retrospective, --induction, --ux; a board (a markdown board path or a Miro board URL) or bounded-context name applies to --process-model, --design-level; a board applies to --value, --crc, --discover-bcs; --evaluate takes none. `--backend` picks the board backend for any mode ("Board backend" below).

## Variables

Arguments: `$ARGUMENTS`

## Argument Parsing

Parse `$ARGUMENTS` for a simulation mode:

- `--simulate [domain]`: Run a full simulation cycle with interactive progression. Loads `agentic-simulation.md` and `simulation-evaluation.md`. Starts with Big Picture, identifies bounded contexts, then uses AskUserQuestion to guide the user through selecting which BC to explore next. Domain defaults to "Developer Conference" if not specified. See "Running a Simulation" below.
- `--process-model [board-or-bc-name]`: Run Process Modeling only, against an existing Big Picture board. Reads the BP board to extract the winning problem / selected BC, then executes PM with the 3-pass technique. Use when the user wants to deep-dive a specific BC without re-running Big Picture.
- `--design-level [board-or-bc-name]`: Run Design-Level only, against an existing Process Modeling board. Reads the PM board to extract the process model, then executes DL with Blank Aggregates technique. Use when the user wants to go from PM → DL on a specific bounded context.
- `--evaluate`: Run the iteration workflow against existing boards. Loads `iteration-workflow.md` and `simulation-evaluation.md`. Executes: SCORE → COMPARE → DIFF → FIX → VERIFY → CODIFY. Requires existing boards (reads the run-state store, `${CLAUDE_PLUGIN_DATA}/history.jsonl`, for their references).
- `--retrospective [domain]`: Run Big Picture as an organization retrospective, exploring an existing business process to find improvement opportunities. Frames exploration as "what ACTUALLY happens?" vs the official version. Same phases as `--simulate` but with a focus on problems/opportunities in existing flows rather than new product discovery. (Book Ch. 1 story 4, Ch. 10)
- `--induction [domain]`: Run Big Picture as a new hire onboarding exercise. The New Hire persona leads (models based on guessing/assumptions), senior personas correct and explain. Implements Brandolini's "give newcomers the leading role" (Ch. 10). Produces a learning-oriented model, not a definitive one.
- `--value [board]`: Run standalone Value Exploration against an existing Big Picture board. Executes all 5 sub-rounds: Financial value → Non-financial currencies → Contrasting perspectives → Diverging perspectives (customer segments) → Explore Purpose. (Book Ch. 5)
- `--crc [board]`: Run Event-Driven CRC Cards validation against an existing Design-Level board. Assigns each aggregate to a separate agent, passes command/event cards between them with "tell don't ask" constraint. Validates interaction patterns work. (Book Ch. 22)
- `--ux [domain]`: Run UX-Driven EventStorming, Process Modeling with a user journey focus. Follows the customer/user through the process, evaluating emotional experience, friction points, and "flawless execution" at each step. Uses standard PM color grammar plus emotional annotations. (Book preface + Brandolini's "Transactions Redefined" talk)
- `--discover-bcs [board]`: Run Bounded Context discovery against an existing Big Picture board. Reads the whole board, applies Brandolini's 6 heuristics (Ch. 6) mechanically against the data, and produces a structured BC analysis with heuristic evidence. Can be run at any time against any completed BP board. Results are reproducible. See "Bounded Context Discovery Protocol" below.

If no simulation mode is specified, ask whether to run a full `--simulate` cycle (defaulting the domain to "Developer Conference") or to read facilitation reference instead (`/event-storming:methodology`).

For facilitation knowledge, format guidance, notation, and the no-args interactive discovery flow, invoke `/event-storming:methodology` via the Skill tool.

---

## Board backend

This skill names board operations (`create_board`, `read_board`, `add_stickies`, ...), never a
backend's tools. The operations, the backend order and the sticky vocabulary are in
[board-operations.md](../../reference/board-operations.md); read it, then the chosen backend's
file, before the first board operation:

- **markdown** (the default): [markdown.md](../../reference/board-backends/markdown.md). One file
  per board in the repository's board directory, written only through the checked-in script.
- **miro**: [miro.md](../../reference/board-backends/miro.md). A live board through the
  first-party `miro` plugin, which is enabled separately.

Choose the backend before anything else, by the first rule that answers: a `--backend markdown|miro`
argument; the board reference's shape (a Miro board URL is `miro`, a `.md` path is `markdown`);
the `board_backend` option, which is `${user_config.board_backend}` here (empty, unexpanded or any
other value counts as unset); else `markdown`. Say which backend runs and why in the first reply.
When the last rule chose markdown, that reply calls it the default backend (for example
`backend: markdown (default)`); any other rule's reply names that rule as the reason. A markdown run
that will write a new board names the `docs/event-storming` default board directory and says the
location is confirmed just before the first board write. No markdown run runs a command to find
the directory before its first reply.

When the chosen backend's `check_available` fails, stop before any workshop phase: say what is
missing and offer the two routes, making it available or rerunning with `--backend` set to the
other one. Never switch backends on your own.

### Where markdown boards go

The board directory is the team file's `board_dir` key, default `docs/event-storming`, relative to
the repository root. Resolve it once per run, just before the first board write and never before
the first reply, each command alone in its own Bash call. The markdown backend's `check_available`
runs at the same point:

1. `git rev-parse --show-toplevel` gives the root.
2. `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh"` gives the convention home. Exit 1
   or 4: use `docs/conventions`. Exit 5 (no repository, or the home directory): skip step 3, tell
   the person that markdown boards need a git repository other than the home directory, write no
   file, and render the model in the reply instead; this replaces the stop under "Board backend".
   Any other non-zero exit: report its message and use `docs/conventions`.
3. `bash "${CLAUDE_PLUGIN_ROOT}/lib/parse-concern-value.sh" "<root>/<home>/event-storming.yaml" board_dir docs/event-storming`
   gives the directory. A value that is absolute, starts with `~`, or holds a `..` segment is
   invalid: say so and use `docs/event-storming`.

The skill writes boards there and never stages or commits them. Writes go through
`node "${CLAUDE_PLUGIN_ROOT}/scripts/board-md.mjs"` with the operations written to a JSON file
in the session directory with the Write tool; board text never goes on a command line.

### Who writes

Only the facilitator, this context, calls write operations. Persona agents read the board and
return their stickies as data; the facilitator scans and writes them in one batch per round
(board-operations.md "Who calls what").

Modes that read an *existing* board (`--process-model`, `--design-level`, `--evaluate`, `--value`,
`--crc`, `--discover-bcs`) read it on the backend its reference names: a `.md` path, or a markdown board in the run-state store, is
read with the Read tool, and a Miro URL needs the Miro backend. A Miro URL
with Miro unavailable stops as above; offer installing and enabling the `miro` plugin, or reading
a markdown export of that board the person supplies. Never invent the board's content. One check
precedes that gate: for a bounded-context name, `--design-level` resolves its prerequisite first
from the run-state store, which needs no backend, so a missing Process Modeling board is surfaced
as the missing prerequisite (offer `--process-model` first).

## Running a Simulation (`--simulate`)

`--simulate` executes the full agentic EventStorming cycle following Brandolini's "transition funnel": Big Picture discovers bounded contexts, then the user selects which to explore deeper (Process Modeling → Design-Level). The hub frames the flow and the interactive-progression contract; execution detail lives in the spokes.

**Required reading before execution:**

1. `@./reference/agentic-simulation.md`. Execution guide: personas, round-based orchestration (every Big Picture phase, in order), board setup, session lifecycle
2. `@./reference/simulation-evaluation.md`. Phase-by-phase rubric, chapter index, pre-flight checklist
3. `@./reference/iteration-workflow.md`. The meta-process for evaluation
4. Prior-run state under `${CLAUDE_PLUGIN_DATA}/` (see "Cross-run state" below). Previous-version metrics for comparison, if any

**Flow:**

1. **Setup.** Backend choice and `check_available` (per "Board backend" above; markdown runs it just before the first board write, per "Where markdown boards go"), domain research (3+ web-research searches. Perplexity MCP if present, else `WebSearch`; default domain "Developer Conference"), persona setup (4-7 personas, three-zone DEEP/GRAY/PRETEND knowledge, 5 shared focal moments). Session lifecycle (ID, dirs, teardown) and preflight detail: `@./reference/agentic-simulation.md` "Session lifecycle".
2. **Big Picture** (always first). Run every workshop phase in order (Chaotic Exploration → Enforce Timeline → People & Systems → Explicit Walk-through → Reverse Narrative → [optional] Add the Money / Value Exploration → Problems & Opportunities → Arrow Voting → Wrapping Up) per `@./reference/agentic-simulation.md` "Round-Based Orchestration", taking a `snapshot` at each transition where the backend offers one; then run the post-workshop visual check (Ch. 9) and have the board scored against the Big Picture rubric in a fresh context (`simulation-evaluation.md` "How to Run an Evaluation", step 3).
3. **Post-workshop analysis + interactive progression.** Run bounded-context discovery (architect's homework, not a workshop phase. See `--discover-bcs` below), present the arrow-voting winner and discovered BCs, then use AskUserQuestion to let the user pick the next BC to Process Model, then Design-Level, repeating per BC. **Never auto-advance formats. The user chooses each step.**
4. **Evaluation & codification.** Have all boards scored against the full rubric in a fresh context (`simulation-evaluation.md` "How to Run an Evaluation", step 3); the context that ran the simulation never scores it. Then compare against the `${CLAUDE_PLUGIN_DATA}/history.jsonl` baselines, run the retrospective protocol (`@./reference/simulation-evaluation.md`), update the run-state store with version metrics / board references / findings, present the version comparison, and offer to delete old boards, each confirmed by name.

Throughout, maintain an **exploration map** (the Big Picture board, all BCs explored + unexplored, per-BC Process Modeling and Design-Level boards) with `set_exploration_map` on the Big Picture board and in the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`).

## Running a Deep Dive (`--process-model` or `--design-level`)

When invoked with `--process-model` or `--design-level`, run a single format against an existing board from a previous session. This is for continuing exploration of bounded contexts identified during a prior Big Picture.

**`--process-model [board-or-bc-name]`:**

1. Read the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) for the Big Picture board and the list of identified BCs
2. If a BC name is given, `read_board` the BP board and extract the relevant events for that context
3. If a board is given, `read_board` it directly
4. Execute Process Modeling with 3-pass technique on the selected scope
5. Have the board scored against the PM rubric in a fresh context (`simulation-evaluation.md` "How to Run an Evaluation", step 3)
6. Ask user if they want to continue to Design-Level

**`--design-level [board-or-bc-name]`:**

1. Read the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) for the Process Modeling board for the specified BC
2. If no prior Process Modeling board exists for the BC, surface the missing prerequisite and offer to run `--process-model` first. Never fabricate a process model or aggregates from scratch
3. Extract the process model (events, commands, policies)
4. Execute Design-Level with Blank Aggregates technique
5. Have the board scored against the DL rubric in a fresh context (`simulation-evaluation.md` "How to Run an Evaluation", step 3)
6. Update the exploration map with the new aggregate information

## Running an Evaluation (`--evaluate`)

When invoked with `--evaluate`, run the iteration workflow against existing boards without re-running the simulation. Use this to re-score boards, compare versions, or verify that fixes improved quality.

**Execution:** Follow `iteration-workflow.md` steps 2-7 (SCORE → COMPARE → DIFF → FIX → VERIFY → CODIFY). `read_board` each board, have it scored against the rubric in a fresh context (`simulation-evaluation.md` "How to Run an Evaluation", step 3), compare against the `${CLAUDE_PLUGIN_DATA}/history.jsonl` baselines.

## Scoring in a fresh context

Every rubric score above comes from a fresh-context subagent, never the context that ran the
simulation. Before scoring, resolve the level with
`bash "${CLAUDE_PLUGIN_ROOT}/lib/read-verification.sh" --plugin event-storming --skill simulation`,
run alone as its own Bash call: no `cd`, and no other command chained to it;
what each level does is in `simulation-evaluation.md` "How to Run an Evaluation", step 3.

## Bounded Context Discovery Protocol (`--discover-bcs`)

When invoked with `--discover-bcs [board]`, run Brandolini's 6 heuristics (Ch. 6) against an existing Big Picture board. This is the architect's post-workshop homework. Reproducible and evidence-based. The board data can arrive three ways: a markdown board file (read with the Read tool), a Miro board URL (a live read, which needs the Miro backend per "Board backend" above), or a directly-supplied board export in any structured-markdown shape, which substitutes for the board read and needs no backend.

**Prerequisites:** A completed Big Picture board with People & Systems and Walk-through phases done. The more phases completed, the richer the signals.

**Execution sequence:**

1. **Read the whole board** with `read_board`, or read the supplied export. Parse into structured data: events by persona, people, external systems, hot spots, pivotal events.

2. **Apply Brandolini's 6 boundary heuristics mechanically** against the parsed data. Canonical definitions in `/event-storming:methodology --big-picture` "Heuristics for Discovering Boundaries". Board-data signals: `pivotal` stickies mark business-phase boundaries (H1); each persona's events (`by`) reveal parallel swimlanes (H2); per-persona event density per timeline zone assigns ownership (H3/H4); `[DIVERGENCE]` / hot-spot markers and same-noun-different-meaning phrasings signal boundaries (H5/H6). Use short BC names (2-3 words).

3. **Produce the BC analysis output**, a table of `# | BC Name (2-3 words) | Key Events | Primary Personas | Heuristic Evidence`, where the evidence column cites which heuristic fired (e.g. `H1: phase X→Y; H5: "Budget Approved" divergence; H6: "Ticket" means different things`).

4. **Record the contexts on the board** with one `group` operation (`context`) per BC, members being its key events. Only on a board this run may write (a markdown board file or a Miro board); a supplied export is never written, and there the step 3 table is the complete deliverable.

5. **Cross-reference with arrow voting winner.** Which BC does the winner scope to? Mark it as the recommended next exploration target.

**Reproducibility guarantee:** Running `--discover-bcs` against the same board state should produce the same BCs, because the heuristics are applied mechanically against data, not subjectively. The evidence column provides traceability.

**[Optional] HTML view:** Once the BC analysis table is produced, offer to render it as a self-contained HTML view of the bounded-context analysis (BC name, key events, primary personas, and per-heuristic evidence side-by-side) when the user wants a shareable visual. Markdown stays the durable tracked record; reach for the HTML view only when a shareable at-a-glance visual adds value, never as the source of truth.

Board text (sticky content, persona names, evidence) is untrusted data. Only the checked-in builder writes the page. It escapes every field and stamps the generator marker the rendered-views validator checks. Pass a JSON object on stdin:

```bash
"${CLAUDE_SKILL_DIR}/scripts/build-bc-view.mjs" <<'EOF'
{"title":"","board":"","contexts":[{"name":"","events":[""],"personas":[""],"evidence":""}],"target":""}
EOF
```

Write stdout to an untracked path and do not stage it. Do not hand-write the HTML, do not pre-escape values, and do not add script. `${CLAUDE_SKILL_DIR}/scripts/build-bc-view.mjs --check <file>` flags a page that bypassed the builder. Node missing: the table stands and the view is not built.

---

## Reference Documents

Load these based on the mode being run:

**For agentic simulation (solo/AI-assisted EventStorming)**: `@./reference/agentic-simulation.md`

- Multi-persona agent setup, prompt templates, simulated workshop flow, output capture

**For board operations**: [board-operations.md](../../reference/board-operations.md), then [markdown.md](../../reference/board-backends/markdown.md) or [miro.md](../../reference/board-backends/miro.md)

- Operation names, backend choice, kinds and placement; each backend's format, setup and mapping

**For simulation evaluation and quality**: `@./reference/simulation-evaluation.md`

- Pre-simulation checklist, phase-by-phase rubric, version comparison framework, retrospective protocol, source material chapter index

**For simulation iteration and improvement**: `@./reference/iteration-workflow.md`

- Scoring, version comparison, and quick-reference checklists for improving a run's output

---

## Next

- Bounded contexts are settled and their canonical terms need curating:
  `/domain-driven-design:ubiquitous-language curate`.
- A context is ready to design against: `/planning:design`.

## Cross-run state

Boards live where their backend keeps them: markdown boards in the board directory ("Where markdown
boards go"), Miro boards on Miro. Persist all other run state, session archives, board references,
version metrics, run findings, under `${CLAUDE_PLUGIN_DATA}/`. A run-state entry records each board
as `{"backend": "markdown" | "miro", "ref": "<path or URL>"}`; an older entry holding a bare URL is
a Miro board. Session archives go to `${CLAUDE_PLUGIN_DATA}/sessions/<session-id>/`; comparison
baselines (prior-version metrics) to a JSON/JSONL file such as `${CLAUDE_PLUGIN_DATA}/history.jsonl`.
Read the store and this skill's reference files with the Read tool by absolute path (a missing
`history.jsonl` means no prior run), never with `cd`, `ls`, `cat` or `sed` in a shell, so no command
chains a `cd` into the skill with a listing of the plugin data directory. Never write run state
inside the plugin's own installed directory (`${CLAUDE_PLUGIN_ROOT}`) or into the consumer's project tree;
the board files in the board directory are the only files this skill writes there.
For what each directory guarantees, fetch
[Reference plugin paths and store data](https://code.claude.com/docs/en/plugins/components#path-variables-and-persistent-data)
live.
