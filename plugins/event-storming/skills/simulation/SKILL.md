---
name: simulation
description: "Agentic AI-driven multi-persona EventStorming simulation on Miro. Use when: 'simulate a workshop', 'run an EventStorming simulation', 'agentic EventStorming', 'multi-persona domain modeling on Miro'. Actions: --simulate [domain] (full multi-persona agentic workshop), --process-model / --design-level [board] (deep-dive against an existing board), --evaluate, --retrospective, --induction, --value, --crc, --ux, --discover-bcs (BC heuristics vs Miro board). Needs a Miro MCP server; degrades to structured-markdown output when Miro is absent. For methodology / facilitation reference use /event-storming:methodology."
user-invocable: true
argument-hint: "[--simulate|--process-model|--design-level|--evaluate|--retrospective|--induction|--value|--crc|--ux|--discover-bcs] [domain]"
---

## Variables

Arguments: `$ARGUMENTS`

## Argument Parsing

Parse `$ARGUMENTS` for a simulation mode:

- `--simulate [domain]`: Run a full simulation cycle with interactive progression. Loads `agentic-simulation.md` and `simulation-evaluation.md`. Starts with Big Picture, identifies bounded contexts, then uses AskUserQuestion to guide the user through selecting which BC to explore next. Domain defaults to "Developer Conference" if not specified. See "Running a Simulation" below.
- `--process-model [board-url-or-bc-name]`: Run Process Modeling only, against an existing Big Picture board. Reads the BP board to extract the winning problem / selected BC, then executes PM with the 3-pass technique. Use when the user wants to deep-dive a specific BC without re-running Big Picture.
- `--design-level [board-url-or-bc-name]`: Run Design-Level only, against an existing Process Modeling board. Reads the PM board to extract the process model, then executes DL with Blank Aggregates technique. Use when the user wants to go from PM → DL on a specific bounded context.
- `--evaluate`: Run the iteration workflow against existing boards. Loads `iteration-workflow.md` and `simulation-evaluation.md`. Executes: SCORE → COMPARE → DIFF → FIX → VERIFY → CODIFY. Requires existing boards (reads the run-state store, `${CLAUDE_PLUGIN_DATA}/history.jsonl`, for board URLs).
- `--retrospective [domain]`: Run Big Picture as an organization retrospective — exploring an existing business process to find improvement opportunities. Frames exploration as "what ACTUALLY happens?" vs the official version. Same phases as `--simulate` but with a focus on problems/opportunities in existing flows rather than new product discovery. (Book Ch. 1 story 4, Ch. 10)
- `--induction [domain]`: Run Big Picture as a new hire onboarding exercise. The New Hire persona leads (models based on guessing/assumptions), senior personas correct and explain. Implements Brandolini's "give newcomers the leading role" (Ch. 10). Produces a learning-oriented model, not a definitive one.
- `--value [domain]`: Run standalone Value Exploration against an existing Big Picture board. Executes all 5 sub-rounds: Financial value → Non-financial currencies → Contrasting perspectives → Diverging perspectives (customer segments) → Explore Purpose. (Book Ch. 5)
- `--crc [board-url]`: Run Event-Driven CRC Cards validation against an existing Design-Level board. Assigns each aggregate to a separate agent, passes command/event cards between them with "tell don't ask" constraint. Validates interaction patterns work. (Book Ch. 22)
- `--ux [domain]`: Run UX-Driven EventStorming — Process Modeling with a user journey focus. Follows the customer/user through the process, evaluating emotional experience, friction points, and "flawless execution" at each step. Uses standard PM color grammar plus emotional annotations. (Book preface + Brandolini's "Transactions Redefined" talk)
- `--discover-bcs [board-url]`: Run Bounded Context discovery against an existing Big Picture board. Reads ALL board items via MCP, applies Brandolini's 6 heuristics (Ch. 6) mechanically against the data, and produces a structured BC analysis with heuristic evidence. Can be run at any time against any completed BP board — results are reproducible. See "Bounded Context Discovery Protocol" below.

If no simulation mode is specified, ask whether to run a full `--simulate` cycle (defaulting the domain to "Developer Conference") or to read facilitation reference instead (`/event-storming:methodology`).

For facilitation knowledge, format guidance, notation, and the no-args interactive discovery flow, use `/event-storming:methodology`.

---

## Miro availability & graceful degradation

This skill drives an EventStorming model onto a **Miro board** via the first-party **`miro` plugin**
— a bundled local-stdio MCP server, enabled separately (`event-storming` does not bundle it). The
plugin exposes its tools under the **`mcp__plugin_miro_miro__`** prefix, so before any mode runs
check whether e.g. `mcp__plugin_miro_miro__miro_list_boards` / `mcp__plugin_miro_miro__miro_create_board`
are callable. A bare `miro_*` name does not resolve for a plugin-bundled server, so the gate must
probe the prefixed form. Every `miro_*` tool named in this skill and its reference docs denotes that
plugin's tool under the `mcp__plugin_miro_miro__` prefix.

- **Miro available** → run normally: create boards, place stickies, screenshot-verify each phase.
- **Miro absent** → do NOT fail. Tell the user the `miro` plugin isn't enabled, then offer two paths
  and let them choose:
  1. **Structured-markdown mode (default, recommended):** run the same agentic multi-persona
     workshop, but emit the model as structured markdown instead of board stickies — an ordered
     event timeline, a persona roster, bounded-context tables, and hot-spot / opportunity lists.
     Every phase that would place stickies instead appends to the markdown artifact. The
     facilitation logic, personas, phase ordering, and rubric scoring are identical; only the
     rendering surface changes. Persist the artifact under `${CLAUDE_PLUGIN_DATA}/sessions/`.
  2. **Install + enable the `miro` plugin, then retry:** a fresh user has only `event-storming` — the
     `miro` plugin must be installed from an available marketplace first, then enabled through
     the `/plugin` interface with a Miro API token (stored by Claude Code's secure credential
     mechanism). Do not assume a marketplace name. Stop until its tools are available. Full setup:
     `reference/miro-integration.md`.

Modes that read an *existing* board (`--process-model`, `--design-level`, `--evaluate`, `--crc`,
`--discover-bcs` with a board URL) require Miro — if it's absent, say so and offer path 2, since
there is no board to read. One check precedes that gate: for a BC-name input, `--design-level`
resolves its prerequisite first — the run-state store lookup (`${CLAUDE_PLUGIN_DATA}/history.jsonl`)
needs no Miro, so a missing Process Modeling board is surfaced as the missing prerequisite (offer
`--process-model` first) before any Miro gating.

## Running a Simulation (`--simulate`)

`--simulate` executes the full agentic EventStorming cycle following Brandolini's "transition funnel": Big Picture discovers bounded contexts, then the user selects which to explore deeper (Process Modeling → Design-Level). The hub frames the flow and the interactive-progression contract; execution detail lives in the spokes.

**Required reading before execution:**

1. `@./reference/agentic-simulation.md` — execution guide: personas, round-based orchestration (every Big Picture phase, in order), board setup, session lifecycle
2. `@./reference/simulation-evaluation.md` — phase-by-phase rubric, chapter index, pre-flight checklist
3. `@./reference/iteration-workflow.md` — the meta-process for evaluation
4. Prior-run state under `${CLAUDE_PLUGIN_DATA}/` (see "Cross-run state" below) — previous-version metrics for comparison, if any

**Flow:**

1. **Setup** — MCP preflight (Miro availability per "Miro availability & graceful degradation" above), domain research (3+ web-research searches — Perplexity MCP if present, else `WebSearch`; default domain "Developer Conference"), persona setup (4-7 personas, three-zone DEEP/GREY/PRETEND knowledge, 5 shared focal moments). Session lifecycle (ID, dirs, teardown) and preflight detail: `@./reference/agentic-simulation.md` "Session lifecycle".
2. **Big Picture** (always first) — run every workshop phase in order (Chaotic Exploration → Enforce Timeline → People & Systems → Explicit Walk-through → Reverse Narrative → [optional] Add the Money / Value Exploration → Problems & Opportunities → Arrow Voting → Wrapping Up) per `@./reference/agentic-simulation.md` "Round-Based Orchestration", taking a visual-verification screenshot at each transition; then run the post-workshop visual check (Ch. 9) and score against the Big Picture rubric.
3. **Post-workshop analysis + interactive progression** — run bounded-context discovery (architect's homework, not a workshop phase — see `--discover-bcs` below), present the arrow-voting winner and discovered BCs, then use AskUserQuestion to let the user pick the next BC to Process Model, then Design-Level, repeating per BC. **Never auto-advance formats — the user chooses each step.**
4. **Evaluation & codification** — score all boards against the full rubric, compare against the `${CLAUDE_PLUGIN_DATA}/history.jsonl` baselines, run the retrospective protocol (`@./reference/simulation-evaluation.md`), update the run-state store with version metrics / board URLs / findings, present the version comparison, and clean up old boards with user approval.

Throughout, maintain an **exploration map** (Big Picture URL, all BCs explored + unexplored, per-BC Process Modeling and Design-Level board URLs) on the Big Picture board as a cyan sticky and in the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) — layout detail in `@./reference/agentic-simulation.md`.

## Running a Deep Dive (`--process-model` or `--design-level`)

When invoked with `--process-model` or `--design-level`, run a single format against an existing board from a previous session. This is for continuing exploration of bounded contexts identified during a prior Big Picture.

**`--process-model [board-url-or-bc-name]`:**

1. Read the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) for the Big Picture board URL and the list of identified BCs
2. If a BC name is given, extract relevant events from the BP board for that context
3. If a board URL is given, read it directly
4. Execute Process Modeling with 3-pass technique on the selected scope
5. Score against PM rubric
6. Ask user if they want to continue to Design-Level

**`--design-level [board-url-or-bc-name]`:**

1. Read the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) for the Process Modeling board URL for the specified BC
2. If no prior Process Modeling board exists for the BC, surface the missing prerequisite and offer to run `--process-model` first — never fabricate a process model or aggregates from scratch
3. Extract the process model (events, commands, policies)
4. Execute Design-Level with Blank Aggregates technique
5. Score against DL rubric
6. Update the exploration map with the new aggregate information

## Running an Evaluation (`--evaluate`)

When invoked with `--evaluate`, run the iteration workflow against existing boards WITHOUT re-running the simulation. Use this to re-score boards, compare versions, or verify that fixes improved quality.

**Execution:** Follow `iteration-workflow.md` steps 2-7 (SCORE → COMPARE → DIFF → FIX → VERIFY → CODIFY). Read board data via Miro MCP, score against rubric, compare against the `${CLAUDE_PLUGIN_DATA}/history.jsonl` baselines.

## Bounded Context Discovery Protocol (`--discover-bcs`)

When invoked with `--discover-bcs [board-url]`, run Brandolini's 6 heuristics (Ch. 6) against an existing Big Picture board. This is the architect's post-workshop homework — reproducible and evidence-based. The board data can arrive two ways: a board URL (live Miro read — requires Miro per the availability gate) or a directly-supplied board export (a structured-markdown board dump), which substitutes for the live read and needs no Miro.

**Prerequisites:** A completed Big Picture board with People & Systems and Walk-through phases done. The more phases completed, the richer the signals.

**Execution sequence:**

1. **Read ALL board items** — via `miro_list_board_items` (full pagination) for a live board, or by parsing the supplied board export when one was provided instead of a URL. Parse into structured data: events by persona, people, external systems, hot spots, pivotal events.

2. **Apply Brandolini's 6 boundary heuristics mechanically** against the parsed data — canonical definitions in `/event-storming:methodology --big-picture` "Heuristics for Discovering Boundaries". Board-data signals: pivotal-event stickies (`dark_blue` / `--- PIVOTAL ---`) mark business-phase boundaries (H1); persona y-offset rows reveal parallel swimlanes (H2); per-persona event density per timeline zone assigns ownership (H3/H4); `[DIVERGENCE]` / hot-spot markers and same-noun-different-meaning phrasings signal boundaries (H5/H6). Use short BC names (2-3 words).

3. **Produce the BC analysis output** — a table of `# | BC Name (2-3 words) | Key Events | Primary Personas | Heuristic Evidence`, where the evidence column cites which heuristic fired (e.g. `H1: phase X→Y; H5: "Budget Approved" divergence; H6: "Ticket" means different things`).

4. **Place BC labels** on the board as cyan stickies at y=7100 (the canonical BC Labels row — bottom of board, below all other content per the Big Picture Y-Coordinate Table in `@./reference/miro-integration.md`), with `[BC]` prefix. Live-board path only — when working from a supplied export there is no board to write; the step 3 table is the complete deliverable.

5. **Cross-reference with arrow voting winner** — which BC does the winner scope to? Mark it as the recommended next exploration target.

**Reproducibility guarantee:** Running `--discover-bcs` against the same board state should produce the same BCs, because the heuristics are applied mechanically against data, not subjectively. The evidence column provides traceability.

**[Optional] HTML view:** Once the BC analysis table is produced, offer to render it as a self-contained HTML view of the bounded-context analysis (BC name, key events, primary personas, and per-heuristic evidence side-by-side) when the user wants a shareable visual. Markdown stays the durable tracked record; reach for the HTML view only when a shareable at-a-glance visual adds value, never as the source of truth.

---

## Reference Documents

Load these based on the mode being run:

**For agentic simulation (solo/AI-assisted EventStorming)**: `@./reference/agentic-simulation.md`

- Multi-persona agent setup, prompt templates, simulated workshop flow, output capture

**For Miro board integration**: `@./reference/miro-integration.md`

- MCP server setup, EventStorming-to-Miro color mapping, board layout, agentic placement

**For simulation evaluation and quality**: `@./reference/simulation-evaluation.md`

- Pre-simulation checklist, phase-by-phase rubric, version comparison framework, retrospective protocol, source material chapter index

**For simulation iteration and improvement**: `@./reference/iteration-workflow.md`

- Scoring, version comparison, and quick-reference checklists for improving a run's output

---

## Cross-run state

Persist all generated state — session archives, board URLs, version metrics, run findings — under
`${CLAUDE_PLUGIN_DATA}/` (the per-plugin directory that survives updates). Session archives go to
`${CLAUDE_PLUGIN_DATA}/sessions/<session-id>/`; comparison baselines (prior-version metrics) to a
JSON/JSONL file such as `${CLAUDE_PLUGIN_DATA}/history.jsonl`. Never write generated state inside
the plugin's own installed directory (`${CLAUDE_PLUGIN_ROOT}` is read-only under cache isolation)
or into the consumer's project tree.
