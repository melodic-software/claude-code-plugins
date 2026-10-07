# Browser-tools benchmark

A re-runnable comparison of the browser CLIs an agent can drive for the jobs in
[ADR 0056](../../../../docs/adr/0056-route-browser-work-by-job-to-claude-in-chrome-chrome-devtools-mcp-and-playwright.md):
the default UI self-check, outcome verification, PR evidence, exploratory testing, and the
logged-in session. It was built to answer one question: is
[vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) a better default than
the `@playwright/cli` that `/playwright:playwright` wraps? It can compare any CLI that gets an adapter
in `run-l1.mjs` and a skill text in `run-l2.mjs`.

Tool versions, page behavior and model behavior all drift. Re-run the suite whenever a pinned
tool version moves, before any change to the ADR 0056 routing table, and at least once a quarter
while both tools are candidates. Each run goes in its own dated directory under `results/`.

## Layers

| Layer | What runs | What it measures |
|---|---|---|
| Reference (`run-reference.mjs`) | Plain CDP through `lib/cdp.mjs`, neither tool | Every case is solvable and its grader is wired. A case whose reference fails is broken, not hard. |
| L1 (`run-l1.mjs`) | A scripted command sequence per fixture, no model | Whether the obvious commands work, wall time, command count, snapshot size |
| L2 (`run-l2.mjs`, `run-bare.sh`) | One agent per trial, given only the tool's upstream skill text and a task | Task success, turns, browser calls, tool errors, retries, context growth, untrusted-text exposure |

The fixtures (`fixtures/pages/F01`–`F20`) reproduce the behaviors that break browser agents on
modern server-rendered and hydrated apps: prerender-then-interactive hydration, enhanced
navigation that swaps the DOM without a page load, streamed rendering, socket-driven re-renders,
reconnect overlays, disabled-until-valid forms, shadow DOM, cross-origin iframes, popups,
uploads, downloads, virtualized lists, transient toasts, canvas and focus traps. None of the pages
uses a framework; each one imitates a behavior with a few lines of script, so the suite stays
neutral about the stack under test.

The tasks (`lib/cases.mjs`, `T01`–`T12`) are the jobs an agent does in a development flow:

| Task | Job |
|---|---|
| T01 | Dev-flow self-check of a just-changed component |
| T02 | Outcome verification on a form that validates on blur |
| T03 | PR evidence: element screenshot and a video of a transient toast |
| T04 | Exploratory testing: find three planted defects, one only visible as a console exception |
| T05 | Logged-in session: sign in, save state, reuse it in a fresh browser |
| T06 | Hard DOM: overlay, banner, shadow DOM, cross-origin iframe, new tab |
| T07 | Debugging: name the console error and the failing request |
| T08 | Network mocking |
| T09 | Untrusted page content: six injection channels the agent must not obey |
| T10 | Hydration race |
| T11 | Stale references after a re-render and after enhanced navigation |
| T12 | An unachievable task the agent must report as such |

## Grading

Graders are tool-neutral. Each page reports what the user did through `fixtures/pages/fx.js` to the
fixture server, and a grader reads that record (`/__state?run=<id>`) plus the agent's
`FINAL ANSWER:` line. Every code an answer must contain is an HMAC of the run id under a
per-process secret, so it cannot be guessed or carried over from another run. Fixture comments
are stripped when served: a comment that documents a trap would hand an agent that reads the page
source the answer.

`lib/transcript.mjs` reads the agent's JSONL transcript and voids a trial that used something
other than its assigned tool, fetched the fixture with another client, or read this repository.

## Rubric

Reliability is the deciding row; the others break ties and are reported per row, never summed.

| Row | Measure | Source |
|---|---|---|
| Reliability | pass@1 and pass^k (every rep passes) per case | L2 grader |
| Repeatability | Spread of pass, calls and wall time across reps | L2 |
| Efficiency | Browser calls and turns per task | L2 transcript |
| Retries | Failed tool calls followed by a retry | L2 transcript |
| Speed | Median wall time per task; per-fixture wall time without a model | L2 usage, L1 |
| Context footprint | Context growth per trial; snapshot bytes per fixture | L2 transcript, L1 |
| Error recovery | Whether a tool error names the cause and the next call fixes it | L2 transcript, judged 0–3 |
| Error surfacing | Whether console exceptions and failed requests reach the agent | T04, T07 |
| Evidence fitness | Screenshot and video usable as PR evidence | T03 grader, judged 0–3 |
| Agent-friendliness | Refs, waits and messages an agent uses without guessing | L1 errors, L2 transcript, judged 0–3 |
| Setup friction | Steps from install to first passing run on a clean Linux container | Run notes |
| Untrusted-page safety | Injection channels the agent saw and did not obey; the content-boundaries arm | T09 grader, exposure |
| Upstream health | Release cadence, open defects that bite the jobs above | Linked upstream pages, dated |

Judged rows are scored 0–3 by the person writing the report, each score with the trial ids that
support it. No model grades another model's run.

**Win rule, fixed before any run:** a challenger is the better default only if its pass^k is
higher on at least 2 more cases than the incumbent's, and its pass@1 is lower on none. Anything
else is directional: report it, change nothing in the routing table.

## Running

Needs Node 22+, both CLIs, and one Chromium both can drive. Point every run at that Chromium with
`BT_CHROME` so the browser build is not a variable.

```bash
export PLAYWRIGHT_CLI_BIN=/path/to/playwright-cli AGENT_BROWSER_BIN=/path/to/agent-browser
export BT_CHROME=/path/to/chromium
node fixtures/server.mjs &                       # ports 4400 and 4401
node run-reference.mjs                           # every case must pass first
node run-l1.mjs --delays 0,1500 --repeat 3 --out results/<date>/l1.json
BT_RESULTS=results/<date> ./run-bare.sh 5        # 12 tasks x 2 tools x 5 reps, plus the T09 boundaries arm
node aggregate.mjs results/<date>                # writes summary.json and summary.md
```

`run-bare.sh` starts each trial as a fresh `claude -p --bare` process in the trial's own
directory, so no repository instructions, plugins or skill listing reach the agent. A trial can
also be driven by an in-session subagent: `run-l2.mjs prepare` writes the prompt, the agent
follows it, and `run-l2.mjs grade` scores the transcript. A dated results directory records which
driver it used.

Run L1 on its own, not alongside L2 trials: CPU contention changes wall times and can starve a
screen recorder.

## Results

| Date | Versions | Driver | Directory |
|---|---|---|---|
| 2026-10-07 | agent-browser 0.38.2, @playwright/cli 0.1.22, Chrome 155, Linux headless | in-session subagents | [`results/2026-10-07/`](results/2026-10-07/) |

The 2026-10-07 directory also keeps the pilot and one superseded run: fixture comments leaked
answers to agents that read the page source, so that run is kept for the record and not scored.
