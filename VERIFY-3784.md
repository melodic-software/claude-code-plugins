# Independent verification — correlation-key extraction (#3784)

**Verified tip: `abe04b6c`** on `claude/posttool-hooks-review-ji6rl5`. The handoff named `0999e73a`
as the tip; the branch actually carries **two** new commits (`0999e73a` bound the trailing-whitespace
strip, `abe04b6c` moved the close check onto a 64-byte suffix). Everything below is against
`abe04b6c`. No repo file was modified; this report is the only commit.

## (a) Safety — no finding. REPRODUCED.

Own generators, driving `hook::emit_telemetry` directly. **4,497 payloads at the tip, 0 decoys on the
spine, 0 missing envelopes.**

| sweep | cases | result |
|---|---|---|
| depth-2/3/4 decoys in `tool_input`/`tool_response`, root arrays, arrays-of-objects, escaped-quote decoys in root and nested strings, `\"},\"tool_use_id\":\"SPOOF-BREAKOUT\"` breakouts, braces in string content, truncated mid-string, CRLF, UTF-8 tails, quotes-only and non-JSON | 190 | `bad=0` |
| tail boundary (`len-16448`) swept through backslash runs m=1..70 at every offset, and through the 64-byte slack | 3,535 | `bad=0` |
| head cut (16384) swept through a decoy in a nested string, a raw depth-2 key, a root string | 167 | `bad=0` |
| randomised structural fuzz, sizes 65530..700000, compact/pretty, ASCII/non-ASCII, truncated, whitespace-padded | 400 | `bad=0` |
| nested decoy as the last root member + trailing whitespace 0..80, 128, 1000 | 166 | `bad=0` |
| trailing-whitespace probe (below) | 39 | `bad=0` |

Non-vacuous: 3,498/3,535 boundary cases and 305/400 fuzz cases still extracted a real key (184 a
tail-side `tool_use_id`). Head precedence holds: duplicate root `session_id` yields the head copy.
Also survives `set -euo pipefail` with globbing on and off, restoring `-f` correctly both ways.

## (a2) Trailing-whitespace bound — behaves as specified. REPRODUCED.

200 KiB payload, documented root order, nested `SPOOF-NESTED` decoy, trailing run of spaces / CRLF /
mixed at 0,1,2,10,32,62,**63,64,65**,66,100,5000,40000 (39 payloads):

- **0..63 bytes** → all four ids, every whitespace flavour.
- **>=64 bytes** → `session_id` + `prompt_id` only. Tail keys **omitted, never wrong**, no SPOOF.

The regression these commits fix is real: same payload with 5000 trailing spaces cost
**1656 ms** per emit at `0dea2b68` (40000 spaces: **3331 ms**), against 6-7 ms at `53b4b9e6` and
**6 ms** at `abe04b6c`.

## (b) Completeness — no finding. REPRODUCED.

All four ids at 4 KiB, 60 KiB, 65477 B, 100 KiB, 512 KiB, 2 MB with escape-bearing `tool_input.content`.

## (c) Both envelope paths — no finding. REPRODUCED.

First attempt was invalid: pretty-printed data is still compactor-provable, so both modes took the
builtin path. Forcing the jq path with a fraction (`{"k":"v","n":1.5}`) plus a logging `jq` wrapper
gave `builtin=0 / jq=1` invocations at all six sizes, and a field-by-field diff (timestamp
normalised) reported **identical fields and identical order** every time.

## (d) Measurements — reproduce in shape, not in absolutes. REPRODUCED.

Best-of-5 per emit, payload in a plain shell variable:

| payload | `53b4b9e6` | `abe04b6c` | ids |
|---|---|---|---|
| 16 KiB | 4 ms | 4 ms | 4 -> 4 |
| 64 KiB | 11 ms | 13 ms | 4 -> 4 |
| 128 KiB | 4 ms | 7 ms | **2 -> 4** |
| 512 KiB | 13 ms | 15 ms | **2 -> 4** |
| 2 MB | 57 ms | 42 ms | **2 -> 4** |

Both headline claims hold (not slower at 512 KiB; four ids where the old code got two). My absolutes
run below the claimed 17/17 and 82/64 — same order of magnitude, same shape.

## (e) Synced copies — no finding. REPRODUCED.

`sync-hook-utils.sh --check` -> `All 17 plugin copies match lib/hook-utils.sh` (rc=0). Independent
`diff` of six copies (guardrails, claude-ops, autonomy, typos-format, eol-normalizer,
markdown-format) -> identical.

## (f) Suites — no finding. REPRODUCED.

`lib/hook-utils.test.sh` -> `PASS=306 FAIL=0`. `shellcheck lib/hook-utils.sh` -> rc=0.
`validate-plugins.sh` -> rc=0. `check-changelog-parity.sh --check-bump origin/main` and `--check` ->
rc=0. Extra: `affected-tests.sh --run` -> 148 shell suites passed (12 python suites not in that
runner's lane); the three relevant python suites -> 44 passed.

## Findings

**1. MAJOR — the two new commits change observable behaviour and add no test. REPRODUCED.**
`git diff 0dea2b68..abe04b6c` touches 18 files (lib + 17 copies) and nothing else: no test, no doc.
`grep -c 'corr:' lib/hook-utils.test.sh` is 15 at both `0dea2b68` and `abe04b6c`, and the suite total
is `PASS=306` at both. But a payload over 64 KiB ending in >=64 whitespace bytes went from four ids
at `0dea2b68` to two at the tip. Nothing in the suite pins the 63/64 boundary, so a later edit to the
suffix length or the strip order regresses it silently. Suggested fix: one case per side of the
boundary, asserting four ids at 63 and no tail keys at 64.

**2. MINOR — the docs state the large-payload limitation as if it were the only one. REPRODUCED.**
`README.md`: *"What a window cannot see is a root key sitting more than 16384 bytes from both ends,
which is omitted."* `CHANGELOG.md` 1.1 says the same, and neither was touched by the two new commits.
Three further omission modes exist, all reproduced, all failing safe (omit, never guess):
(i) the tail window is dropped when the last 16448 bytes open with >=64 consecutive backslashes
(37 of my boundary cases lost a real tail-side `session_id`); (ii) it is dropped when the payload
does not end in `}`/`]` (truncated — the suite covers this, the docs do not); (iii) **new at this
tip**, it is dropped when >=64 trailing whitespace bytes follow the root close. (iii) is the one a
real producer is most likely to hit, since a caller that leaves a newline run on the buffered value
is exactly the case the surrounding code comments elsewhere call out as ordinary.

**3. NIT — the window size in prose is not the one in the code.** REASONING (code read; the
direction is confirmed by the sweeps). Docs say "a 16384-byte window at each END"; the tail window is
taken at 16448 bytes and trimmed by up to 64 bytes of slack, so its span is 16384-16447. The error is
in the safe direction, so the stated limitation stays true; the number is just not the code's.

No BLOCKER. Nothing else. Every claim above is REPRODUCED except finding 3, marked REASONING.
