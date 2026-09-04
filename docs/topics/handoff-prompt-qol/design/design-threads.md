# Design threads — handoff save-point artifact shape

Topic: `handoff-prompt-qol`. Scope: `data` (schema of the handoff file and its chain). Source
proposals (memory tier, `.work/handoff-prompt-qol/design/proposal-{A,B,C}.md`): A = every file
self-contained, B = per-topic index + thin hops, C = store the minimum, derive by script.

Locked upstream by the interview (not threads here): no hooks; `## Resume prompt` is the final
body section, verbatim with two U+2500 rails; `Next:` ≤5 headlines between the rails, `Then:
/<skill>` at a stage boundary; the directive tells the successor to invoke the skill; one
`Handoff origin:` form; a minimal validator runs before the rails; prompt-only path untouched.

Status legend: resolved / directional / deferred / open.

## T1 — Where the chain lives (resolved)

| option | shape | cost | risk |
|---|---|---|---|
| A: in every file | frontmatter `chain:` rows (hop/file/sid/ts/transcript/tldr), copied forward + appended | +1 row/hop; long flow-style YAML rows the model must copy verbatim | copy errors; validator can only check the last two rows against `previous_handoff`/`session_id` unless it also diffs the predecessor |
| B: per-topic index file | `<TS-of-hop-1>-index-<topic>.md` owns chain, rollup, root entry; hop files thin | two writes per handoff; a new artifact type and filename pattern | drift when a writer skips the index (the free-hand failure mode); self-repair by orphan-row detection |
| C: derived by script | store `hop` + `root_handoff` + `previous_handoff`; `chain-walk.sh walk` prints the chain | constant-size file; one script | a script stands between the agent and its breadcrumbs; manual fallback stored in `## Chain` |
| **A-lite (chosen)** | frontmatter `chain:` = bare filenames root-first; body `## Prior sessions` table one row/hop (date · session id · tldr · file) copied forward verbatim from the predecessor and appended | +2 lines/hop; no script at resume | validator byte-compares the predecessor's `chain:` and table as a prefix of this one → copy-forward is mechanical, not authored |

Recommendation: A-lite. One file, nothing between the agent and the chain, simple YAML, and the
only duplicated content is validator-diffed. C's `hop` count is kept as a cheap completeness
checksum (`len(chain) == hop`).

## T2 — Root reference and the opening ask (resolved)

Options: A copies `Entry prompt (verbatim)` forward every hop (>15 lines → opening lines + path);
B stores it once in the index, redacted; C stores it verbatim in the root file only, later hops
carry `see <root> § Original goal`.

Recommendation: C's placement inside A-lite — `## Original goal` gains an `Opening ask:` line:
hop 1 verbatim (redacted, capped at ~15 lines with the transcript as the full source), hop N>1 a
pointer to `chain[0]`. The goal quote + dated amendments stay copied forward every hop as today.
Bounded per file; the user's words are never re-summarized.

## T3 — Per-hop TLDR (resolved — all three proposals agree on the guardrail)

Yes, one line per PRIOR hop, declawed: past tense, what landed, no imperative, no "next". The
current hop never carries its own TLDR (A: a summary is only read about a finished session; B:
beside high-res detail it gets read instead of it). Source of the line: the position panel's
`Done this session —` line verbatim (A) or a `did: … · left: …` ledger bullet (C).

Recommendation: the `## Prior sessions` row's tldr column = the predecessor's own `did/left`
line, which the predecessor wrote about itself at its save-point in a `## This session` one-liner
(C's Hop card, renamed). Written once by the session that knows, copied forward by everyone else.

## T4 — What carries forward: cumulative sections with provenance tags (resolved)

A's mechanism: sections §4 Constraints, §6 Side effects, §8 Decisions, §9 Abandoned, §10 Findings
are CUMULATIVE — copied forward off disk, each entry prefixed `[hN]` (the hop that asserted it),
new entries appended, disproved entries moved to a `Superseded:` line, never deleted. The `[hN]`
tag IS the engine's existing `UNVERIFIED (<source>)` marker; re-verifying re-tags to the current
hop. §2/§5/§7/§11–§13 are rewritten each hop (state of now). B and C rely on the existing spec rule
"carry still-binding facts into your own sections" without tagging.

Recommendation: adopt A's tagging for those five sections. It is the concrete anti-loss mechanism
the operator asked for ("high-res last, fuzzy prior") and it costs nothing at resume; growth
tracks knowledge, not hops. Orthogonal to T1.

## T5 — Shape version and validator contract (resolved — consensus)

`handoff_shape: 2` in frontmatter. Absent → shape 1: WARN, shape checks skipped, rails still
emitted, file never rewritten. Higher than the validator knows → hard fail with "read it, do not
rewrite it" (never a partial pass, never prompt-only silently). Validator checks (union of the
three, minus index checks): required keys; `date` ISO Z; `session_id` UUID regex; `previous_handoff`
bare filename (`^\d{8}T\d{6}Z-handoff-.+\.md$`) existing beside the file; `len(chain) == hop`,
`chain[-1] == basename`, `chain[-2] == previous_handoff`; predecessor's `chain:` and `## Prior
sessions` are a prefix of this file's; the 14 headings + `## Prior sessions` + `## Resume prompt`
in order, last; exactly two U+2500 rails; `Read @` absolute forward-slash path; `Prior session:`
UUID; `Handoff origin:` two-slot form; `Next:` ≤5 lines. Non-zero exit blocks the rails.

## T6 — Transcript path (resolved)

A: stored absolute per hop. B: resolved + `stat`ed at write, `unresolved (session …, cwd-slug …)`
fallback. C: never stored; derived by `~/.claude/projects/*/<session_id>.jsonl` (UUID is unique
across project dirs; works outside a git repo; a bridge id surfaces as ABSENT).

Recommendation: B's rule as a column in `## Prior sessions` and a `transcript:` frontmatter field
for the current hop — resolved by C's glob and `stat`ed at write, `unresolved (…)` when absent. The
validator's stat at write is what catches the bridge-id bug. Cross-machine, the glob is the
documented re-derivation.

## T7 — Emit the validated text verbatim (resolved — from C)

After the validator passes, the skill prints `## Resume prompt` from the file (Bash `sed -n`) and
the on-screen rails are that output, not a regeneration. `find-handoff` rung 1 prints the same
section. Recommendation: adopt.

## T8 — Test-seam posture (resolved)

The validator script is the seam. Evals assert: validator invoked before the rails; exit 0; the
on-screen rails equal the file's section. Script-level fixtures under
`plugins/session-flow/scripts/tests/`: shape-1 legacy (WARN, exit 0), shape-2 good, shape-2 with a
prefixed pointer (fail), shape-2 with `hop ≠ len(chain)` (fail), shape 3 (hard fail). One seam,
highest altitude that covers the surface.

## T9 — Deterministic tiers of the write (resolved — from the script-the-deterministic-work audit)

`hop` dropped from T1/T5 (derivable as `len(chain)`). Every non-reasoning step of the write is
scripted; the model fills only judgment slots.

| step | tier | owner |
|---|---|---|
| filename + `date:`; `session_id` from `CLAUDE_CODE_SESSION_ID` (never `CLAUDE_CODE_BRIDGE_SESSION_ID`, the corpus bridge-id bug); transcript path by glob + `stat`; `Handoff origin:`; memory-dir + self-ignore guard; `chain:` and `## Prior sessions` copy-forward + append; `Original goal` quote/amendments copy-forward + `Opening ask` pointer; verbatim copy of the five `[hN]`-tagged sections; heading scaffold in order; rails block minus `Next:`; validation; emit | deterministic | generator / validator script |
| `Superseded:` candidates (dangling branch/PR/file refs), secret-shaped strings, leftover `FILL` slots | detect-then-judge | script flags, model rules |
| Resumption brief, criteria status, new tagged entries, remaining actions, open questions, blockers, suggested skills, `did · left`, `Next:` headlines, `Then: /<skill>`, drift-check sentence | reasoning-only | model |

Proposed surface: one script, three subcommands — `new` (skeleton with every deterministic field
filled and `<!-- FILL: … -->` slots), `validate` (T5 checks + no FILL slot remains), `emit`
(prints `## Resume prompt`). Language and dependency policy are a plan decision.

The resume-read budget figures below are measured by the headless harness (T8/Q24, Phase 5,
2026-09-04): live shape-2 chains for hops 1 to 4 and a generated 20-hop chain for hops 5 and 20.

## Consumer impact (all options)

find-handoff: no break; rung 1 gains "print `## Resume prompt`". continue-in-background: reads the
between-rails text from the file. retro: no break (`session_id`, bare `previous_handoff` kept);
optional upgrade reads `chain:`; independent fix tolerates a `handoffs/` prefix. orient /
keep-going / reanchor: section names unchanged. context-guard zone-gate: path still contains
`handoff`. Spec edit regardless: `save-point.md` says `<repo-identity>` "is NOT a stored field";
embedding the prompt makes it one; `structure.md` gains the two sections.

## Resume-read budget (A-lite)

Measured 2026-09-04 with `plugins/session-flow/scripts/harness/hop_chain.py` (tokens = chars/4,
one file per hop). Live chains ran the shape-2 skill headless on `claude-opus-5[1m]`, CLI 2.1.260,
three light chains plus one chain whose hop 1 read a 30k-token pad first; every hop passed all
seven harness checks. The generated chain comes from `hop_chain.py --budget`: `save_point.py new`
twenty times with per-section filler sized to the shape-1 corpus median at hop 1 (154 lines /
3.2k tokens) and each cumulative section growing two tagged entries per hop.

| hop | measured (live, light, 3 chains) | measured (live, padded, 1 chain) | generated |
|---|---|---|---|
| 1 | 139 to 155 lines / 2.6k to 3.1k tokens | 220 lines / 3.4k tokens | 156 lines / 3.2k tokens |
| 4 | 174 to 190 lines / 3.7k to 5.3k tokens | 308 lines / 5.4k tokens | not reported |
| 5 | not run live | not run live | 219 lines / 5.0k tokens |
| 20 | not run live | not run live | 474 lines / 12.2k tokens |

Growth per hop, live: 0.35k to 0.8k tokens (one `chain:` line, one `## Prior sessions` row, plus
the net-new tagged entries each session wrote). Extrapolating the live growth linearly lands hop
20 near 12k to 14k tokens, which agrees with the generated chain. The pre-measurement estimate
(hop 20 near 3.0k) assumed almost no tagged growth and is superseded: a 20-hop chain costs about
four hop-1 reads, still one file and still bounded, and a chain that long is the exception the
`## Prior sessions` pointers exist for.
