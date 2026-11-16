# Interview pacing eval: `round` versus `single`

The `interview-pacing-*` cases compare `/planning:interview`'s default `round` pacing (the whole
frontier in one message) with `single` pacing (one question per message) on one task: a CSV
export of invoices with four open decisions the prompt does not list.

- A. which date range one export covers;
- B. how amounts and the three currencies appear in the file;
- C. which role may export;
- D. how an export of about 40,000 rows completes when in-request downloads time out at 30 s.

The owner keeps `round` as the default; these cases exist so a run can decide whether `single`
does better. No result changes the default by itself.

## Cases

| Case | Pacing | What the prompt states | Runs |
|---|---|---|---|
| `interview-pacing-round-arm` | round | round 1 answered | 6 |
| `interview-pacing-single-arm` | single | round 1 answered | 6 |
| `interview-pacing-single-arm-step-2` | single | round 1, then A and D answered, D's mechanism deferred to planning | 6 |
| `interview-pacing-single-arm-step-3` | single | as step 2, plus B answered | 6 |

The step cases put single pacing's later questions (B and C) in front of the grader. Their earlier
answers are stated in the prompt, as round 1's are in every case.

## Graders

Every grader is a free regex over the final reply, the same pattern in every case. A question line
is the skill's `Q<N>: **<question>**` (an optional marker before it), so recap lines such as
`Q2: one calendar month` are not questions.

| Grader | Passes when |
|---|---|
| `covers-a` to `covers-d` | some question line is on that decision |
| `quality-a` to `quality-d` | some question on that decision has a `Context:` block citing a fact the user stated, `My recommendation:` with a `Basis:` line or a `Withheld:` line, and an `Alternatives:` list |
| `closing-probe` | the reply carries "something else that would change" |
| `one-question` (single only) | exactly one question line |
| `one-recommendation` (single only) | exactly one `My recommendation:` or `Withheld:` |

A question line that mentions planning is no coverage of any decision. The skill's mechanism
tripwire (`SKILL.md`, "What, not how: the mechanism tripwire") asks whether mechanism decisions
wait for planning beside the first mechanism-naming question, so a reply asking D and then "should
the job runner and storage wait for planning?" covers D through D's own question, and a reply
whose only D-shaped question is that deferral does not cover D. The `covers-d` samples hold both
shapes plus D settled in a preface line with no question.

Each grader's samples are checked offline by `/evals:validate`, which runs the patterns in node.
The CLI runs them in JavaScriptCore (Bun), which gave different verdicts on an earlier form of the
quality patterns, so check a pattern change under `bun` as well. The patterns were also run against
the ten kept replies of the earlier judge-graded run: all five round replies cover A to D, which a
hand reading confirmed and the judge missed in three of them.

## Metrics

- **Q, per-question quality rate**, per arm: the number of (run, decision) slots where `quality-X`
  passes, over the number where `covers-X` passes, pooled over the arm's cases. Round slots number
  up to 4 per run; single up to 1 per run. Scoped to the four planted decisions: the CLI scores
  each grader once per run ("A grader is a pass/fail check on what Claude produced",
  <https://code.claude.com/docs/en/plugin-evals>), so it cannot count a reply's other questions,
  whose number varies.
- **Cr, round coverage**: round runs where all four `covers-X` pass, over valid round runs.
- **F, turns (derived, not observed)**: the median number of question lines in the round replies.
  Single pacing needs about F user turns for what round asks in one. Reported, no rule input.

## Multi-turn: what the harness supports

`claude plugin eval` gives each run one user turn and no simulated user: it "sends the prompt, and
lets Claude work until it finishes or hits the case's turn or time limit"; `context.history_file`
resumes a fixed transcript and "the case's prompt becomes the next user turn"
([What happens in a run](https://code.claude.com/docs/en/plugin-evals#what-happens-in-a-run),
[case.yaml fields](https://code.claude.com/docs/en/plugin-evals#case-yaml-fields)). A
resumed history carries no skill body (`plugins/discipline/evals/hmh-cancel-ends-phasing`), and its
assistant turns are written by the case author, not produced by the run. So no case drives an
interview to a locked Brief, and turn counts are derived.

## Deciding rule

Pre-registered before the first run of these cases. Run once with:

```text
env TMPDIR=<dir of at most 24 characters> claude plugin eval <plugin copy> --case 'interview-pacing-*'
  --model claude-opus-5-5 --ablation none --threshold 0 --runs 6 -j 4 --keep-temp --no-publish
  --trust-plugin --max-cost-usd 20 --json <results file>
```

`<plugin copy>` is the planning plugin copied outside any repository, which the CLI needs when a
checkout has many linked worktrees. No judge model: every grader is a regex.

- **ROUNDS HOLD UP**: Cr >= 5/6 and Qr >= Qs - 0.10.
- **SINGLE DOES BETTER** (the result that would support switching the default, which stays the
  owner's call): Qs - Qr >= 0.20, or Cr <= 3/6.
- **INCONCLUSIVE** otherwise.

Basis: judgment. 0.10 is about two of the round arm's 24 slots; 0.20 is the margin a pacing change
would have to show before it is worth the extra turns.

**INVALID** (reported as no result, with its reason):

- `run-validity.py` gives `verdict: INVALID`, or the results report `partial: true`;
- fewer than 5 valid round runs, or fewer than 9 single slots where some `covers-X` passes;
- any grader, sample or prompt in these cases changes after the first run starts;
- the model under test is not `claude-opus-5-5` in every kept trace.

A run that errors or hits its turn cap is excluded and named.

## Amendment 1 (2026-11-16, written before run 2)

Run 1 (cases at `739e558d5d`) is INVALID and gives no result. Its validity gate read VALID, but the
`quality-*` patterns, then written as "no question on X lacks a part" (a negative lookahead over the
whole reply), failed well-formed replies under JavaScriptCore, the CLI's engine, while node passed
them; `bun` reproduced the CLI's verdict on all 24 runs. The spot-read also found keyword defects in
the coverage patterns. Grader changes for run 2:

- `quality-*` now passes when some question on the decision has every part; bun and node agree on
  every sample and on all 24 run-1 replies.
- `covers-a` drops a bare "calendar month", so "which date puts an invoice in a month" no longer
  counts as the date-range decision.
- `covers-d` adds "after the click", "during the click" and "once it's ready", and drops "finished
  file" and a bare "request", so a role question mentioning the finished file is no longer D.
- New samples hold each of those shapes.

The thresholds, runs per case, model, command and INVALID list above are unchanged. One INVALID
condition is added: a committed grader's verdict under `bun` differs from the CLI's on any run.
Run 2 is a deviation from "run once": the cases as fixed must be run before they merge.

## Result (run 2)

2026-11-16, cases at `b3ec2b9075`, Claude Code 2.1.325, `claude-opus-5-5` in 24 of 24 traces,
249 s, reported cost 9.80 USD (list-price estimate). `run-validity.py --runs 6`: VALID, warnings
skill fired (slash-command prompts make no Skill call, and no case has a skill-fired grader) and
models (no judge model, as none is used). No run errored. Every committed grader's verdict under
`bun` matches the CLI's on all 24 runs.

| Measure | Value |
|---|---|
| Qr, round per-question quality | 24/24 = 1.00 |
| Qs, single per-question quality | 17/17 = 1.00 |
| Cr, round coverage | 6/6 |
| Single slots by decision | A 6, B 0, C 11, D 0; one step-2 run asked a non-planted question (which date places an invoice in a month) |
| F, question lines per round reply | 12, 9, 11, 9, 9, 12; median 10 |

Verdict: **ROUNDS HOLD UP** (Cr 6/6 >= 5/6; Qr 1.00 >= Qs 1.00 - 0.10). Both arms reach the
ceiling on per-question quality, so the measure does not separate them on this task: round asks
every planted decision in one turn, and single pacing needs about 10 turns for the same frontier.
Single pacing never reached B in these runs: after A and D, both step cases asked C first.

## Amendment 2 (2026-11-16, written before run 3)

A deviation from the rule above, from a review finding on the pull request: the step cases state
decisions as answered whatever an earlier case asked, so run 2's Qs held only A and C while Qr held
all four, and pooling different decision mixes can credit pacing for a difference in how hard each
decision is to ask well. Run 2's verdict is withdrawn; read under this amendment it is
INCONCLUSIVE (only A and C matched).

- **Matched decisions.** For each decision X, an arm's observations are its runs where `covers-X`
  passes. X is matched when the round arm and the single arm each have at least **3** observations
  of X. Basis: judgment, half of one six-run case.
- **Metric.** Qr and Qs become per-question quality pooled over matched decisions only:
  `quality-X` passes over `covers-X` passes, summed over the matched X, per arm. Report each
  decision's numbers for both arms beside them.
- **Rule.** INCONCLUSIVE when fewer than all four decisions are matched. With all four matched, the
  thresholds above apply unchanged to the matched Qr and Qs, with Cr as before.
- **Cases.** Two single-arm cases are added so B and D reach the single arm:
  `interview-pacing-single-arm-open-b` (A, C, D and the month's date already answered) and
  `interview-pacing-single-arm-open-d` (A, B, C and the month's date already answered), 6 runs
  each, same graders.
- **Run 3** runs all six cases once with the command above, `--max-cost-usd 25` (36 runs at run 2's
  cost per run is about 15 USD), and a `TMPDIR` only this session uses. The INVALID list holds,
  with "fewer than 9 single slots" read over all five single cases.

## Result (run 3, under Amendment 2)

2026-11-16 4:13 PM EST, cases at `0626bcd0f5`, Claude Code 2.1.325, `claude-opus-5-5` in 36 of 36
traces, reported cost 14.47 USD (list-price estimate), own `TMPDIR`. `run-validity.py --runs 6`:
VALID, warnings skill fired and models, as in run 2. No run errored. Every committed grader's
verdict under `bun` matches the CLI's (0 mismatches over 384 verdicts).

| Decision | Round quality / coverage | Single quality / coverage | Matched (>= 3 each) |
|---|---|---|---|
| A, date range | 6/6 | 5/5 | yes |
| B, amounts and currencies | 6/6 | 5/5 | yes |
| C, who may export | 6/6 | 8/8 | yes |
| D, large exports | 5/5 | 6/6 | yes |
| Pooled over matched | Qr 23/23 = 1.00 | Qs 24/24 = 1.00 | 4 of 4 |

Cr = 5/6. F, question lines per round reply: 12, 10, 12, 13, 12, 11; median 12. Six single runs
asked a ready question outside A to D (the month's date, or one row per invoice), which counts for
no decision.

Verdict: **ROUNDS HOLD UP** (all four decisions matched; Cr 5/6 >= 5/6; Qr 1.00 >= Qs 1.00 -
0.10). Both arms are at the quality ceiling on every decision, so the measure does not separate the
pacings on this task; what differs is turns, about 12 single-pacing messages for one round.

Grader miss, reported and not re-graded (graders are frozen once a run starts): round run 3 asks D
as "Can the export be asynchronous instead of an immediate download?", which `covers-d` does not
match, so it counts as no D. Read by hand, Cr is 6/6 and the verdict is the same.
