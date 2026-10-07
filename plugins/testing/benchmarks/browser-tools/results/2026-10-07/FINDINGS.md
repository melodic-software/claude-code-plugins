# Findings, 2026-10-07

agent-browser 0.38.2 against `@playwright/cli` 0.1.22, both driving one Chrome 155 build, headless
on a Linux container. L2 trials were driven by in-session subagents at the session model's default
effort, each given only its tool's upstream skill text. `summary.md` holds the numbers; this file
holds what the numbers do not show, each with the trial or probe that shows it.

## Verdict

Every one of the 120 default-arm L2 trials passed (12 tasks, 5 reps, 2 tools), and every one of the 5
content-boundaries trials passed. Under the pre-registered rule there is **no reliability winner**,
so nothing in the ADR 0056 routing table changes. The task set hit a ceiling: a future revision needs
harder cases before reliability can separate these tools.

## Rubric

Judged rows are scored 0–3 by the report author from the cited trials; measured rows come from
`summary.json`.

| Row | agent-browser | playwright-cli | Evidence |
|---|---|---|---|
| Reliability | 60/60, pass^5 on 12/12 | 60/60, pass^5 on 12/12 | `summary.md` |
| Efficiency | median 15 browser calls | median 10 browser calls | `summary.md` totals |
| Retries | 21 retries, 12 of them on T04 | 6 retries, 5 of them on T02 | `summary.md` per task |
| Speed (agent) | median 34.6 s per task | median 35.3 s per task | `summary.md`; agent-browser faster on T01, T03, T06, T08, T11; playwright-cli on T02, T04, T05, T10 |
| Speed (scripted) | median 1.8 s per fixture (p10 1.5, p90 3.4) | median 6.1 s per fixture (p10 4.6, p90 8.5) | `summary.md` L1 |
| Repeatability (scripted) | 138/156; every row passed or failed 3 of 3 | 138/156; every row passed or failed 3 of 3 | `l1.json` |
| Context footprint | median 11.3k tokens added | median 12.0k tokens added | `summary.md`; lower on 11 of 12 tasks (not T07) |
| Error surfacing | 1 | 3 | Finding 1 |
| Error recovery | 3 | 3 | Findings 5 and 6: both name the cause and the next call fixes it |
| Evidence fitness | 3 | 3 | T03: every element screenshot and video passed; finding 2 |
| Agent-friendliness | 2 | 2 | Findings 3, 4, 5, 6 |
| Setup friction | 2 | 2 | Finding 4 |
| Untrusted-page safety | 3 | 3 | T09: no channel followed in 10 default trials; 5 boundaries trials also clean |
| Upstream health | weekly 0.x releases; open ref issues | 0.1.x, slower cadence | Finding 8 |

## Findings

1. **Uncaught page exceptions do not reach agent-browser agents.** T04's coupon button throws
   `TypeError: Cannot read properties of null (reading 'code')`. Every playwright-cli agent's final
   report named the TypeError (5 of 5); no agent-browser agent's did (0 of 5), and several reported
   that the console showed no errors. A direct probe matched: agent-browser's `console` printed
   nothing and `errors` printed a bare failure mark, while playwright-cli's `console` printed the
   error with a stack line. The grader still passed every agent-browser run, because the agents found
   the coupon defect from its behavior; on a page where the exception is the only signal, it would
   be missed.
2. **A 2-second toast is easy to miss on playwright-cli.** Its per-command startup is slower, so two
   playwright-cli agents (r3 and the r4 re-run of T03) read the toast's code from frames of their own
   recording with ffmpeg; one of them clicked "Save plan" a second time first. agent-browser agents
   read the toast live in every rep.
3. **References after a re-render.** On F05's row re-render, playwright-cli refuses a ref from a
   superseded snapshot ("Ref not found ... capture new snapshot") while agent-browser re-resolves it
   and clicks the intended row. On T10, where hydration replaces the button element, agent-browser
   also refused the old ref ("Unknown ref", r5). Both fail safe: neither clicked the wrong element.
4. **Setup.** playwright-cli's default `chrome` channel is not installed on a Linux container, so it
   needs a config naming `chromium` and, when its bundled revision is absent, an `executablePath`.
   agent-browser downloads its own Chrome for Testing, but long `AGENT_BROWSER_SESSION` or namespace
   values overflow its socket path and break every command; the harness uses short ids.
5. **Covered click targets.** On F07, agent-browser refuses a click whose point is covered and names
   the covering element (`<div#overlay>`); playwright-cli waits for the element to become actionable.
6. **Validation on blur.** On T02 both tools' `fill` sets the value without leaving the field, so the
   form's on-blur check never runs; agents on both tools found it and pressed Tab. This accounts for
   most of playwright-cli's retries.
7. **Recording under load.** In a superseded run, agent-browser's recorder reported "encoder fell
   behind by more than 16 buffered frames" and wrote an empty file; the agent re-recorded at a lower
   frame rate. Not seen in the scored run.
8. **Upstream health, as of 2026-10-07.** agent-browser ships weekly 0.x releases (0.38.2 on
   2026-10-01); open reports on durable refs after 0.38.0 include
   [vercel-labs/agent-browser#1922](https://github.com/vercel-labs/agent-browser/issues/1922) and
   [vercel-labs/agent-browser#1892](https://github.com/vercel-labs/agent-browser/issues/1892).
   `@playwright/cli` 0.1.22 shipped 2026-09-28. Recheck both when a pinned version moves.

## Scripted layer (L1)

The same fixtures driven by one fixed command sequence per fixture, no model: 26 fixture variants,
2 page delays (0 and 1500 ms), 3 repeats, 312 runs. Both tools passed 138 of 156, on different
fixtures, and no row was flaky: each passed or failed all 3 repeats.

- **Speed.** agent-browser took a median 1.8 s per fixture against playwright-cli's 6.1 s, and
  returned smaller snapshots (median 225 against 459 bytes). The gap is per-command startup, and it
  is what makes the 2-second toast (F15) unreachable for a scripted playwright-cli sequence at both
  delays.
- **Waiting.** agent-browser does not wait on a click: it refuses a covered target (F07, both
  delays) and clicks a still-disabled button without effect (F01 variant C at 1500 ms), where
  playwright-cli waits for the element to be actionable and passes both.
- **Stale refs.** playwright-cli refuses a ref from before F05's re-render (0 ms); agent-browser
  re-resolves it.
- **Both fail by design.** F01 variants A and B (the listener arrives after the page looks ready)
  and F19 at 1500 ms fail for both tools: the obvious script has no way to know the page is not yet
  interactive. In the agent layer every T10 trial on both tools waited for readiness and passed.

## Run notes

- **Container restart.** A restart during rep 4 stopped seven in-flight trials and the fixture
  server, whose run records and code secret live in memory. Those trials were never graded and were
  re-run under fresh run ids; every graded trial is unaffected.
- **Inherited hooks.** In-session subagents inherit this repository's guardrails hooks; one r5
  agent-browser agent had a session-name command blocked and used a fixed name. The hooks apply to
  both tools alike; `run-bare.sh` avoids them on a local re-run.
- **Superseded run.** `superseded-comment-leak-l2.jsonl` is an earlier run in which fixture HTML
  comments told agents that read the page source the answer. It is kept for the record and not
  scored.
- **Paths.** Answers in `l2.jsonl` show the trial directory as `<scratch>`.
