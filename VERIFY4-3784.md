# Fourth verification pass, #3784 correlation-key walk

Verified at `5a3600636`. Drove `hook::emit_telemetry` with a stub sink over ~2200 payloads carrying
grep-able `SPOOF` decoys, plus a 12-mutation battery on a copy of library+suite. All REPRODUCED
unless marked. **Rounds 1-3 CONFIRMED CLOSED**: backward-tail cut points, concatenated docs (`}{`,
`}\n{`, `}}{`, `}]{`, `} {`, `},{`, `}0{`, `}true{`, small and 240 KB) and the round-3 head-stop
payload all emit at most the genuine root keys.

**1. MAJOR. The carry is set when the head window ends OUTSIDE a string.** The parity rule at
`lib/hook-utils.sh:2137` counts fields, but bash drops the trailing empty field, so `{"a":"b"` (ends
outside a string) and `{"a":"b` (ends inside one) both split into 4 fields. When the head window's
last byte is a closing quote the carry is set falsely and the tail is walked one quote out of step:
a 232768-byte payload with byte 16384 a closing quote and tail `","tool_use_id":"SPOOF"}` puts
`"tool_use_id":"SPOOF"` on the spine, and shifting one byte either way removes it. The comment "an
even field count means an odd number of quotes, which means the window ended inside a string" is
therefore false. Not a blocker: out of step, every real key and value lands in a walker STRUCTURE
slot and dies on the `corr_js` class test, so only bytes at a real structure position lift, and I
could not reach it from valid or truncated-valid JSON (250+ cut points, valid array roots with
numeric middles, 162 byte-by-byte seam slides, 1278 backslash-run payloads, all clean). Malformed
payloads only, but it does contradict "malformed keys are omitted, never guessed".

**2. MAJOR. Mutation `M2b` NOT CAUGHT: deleting `corr_carry=0` in the DEPTH branch (line 2176)**;
suite still PASS=319 FAIL=1 (/tmp baseline). Load-bearing, not redundant:
`{"session_id":"A"}{"pad":"<pad>"` + quote-free middle + `","tool_use_id":"SPOOF"}` emits only
`session_id` on the real library and `session_id` plus `tool_use_id":"SPOOF` on the mutant, which is
round 2's second-document threat reintroduced through the depth path.

**3. MAJOR. Mutation `M8c` NOT CAUGHT: deleting the `$corr_mid == \"*` seam test.** Load-bearing,
not covered by the globs: a middle whose first byte is an unescaped quote and holding no other quote
matches neither (glob 1 needs a preceding non-backslash byte, absent at offset 0; glob 2 needs two
backslashes). Repro emits `tool_use_id":"SPOOF` on the mutant, `session_id` alone on the real.

**4. BLOCKER (gate). `check-changelog-parity.sh --check-bump origin/main` fails.** VERSION COLLISION
for `guardrails` 0.32.8, `markdown-format` 0.11.47, `source-control` 0.55.56: `origin/main` moved
from merge-base `6b728c2c4` to `b3c15edca` and claimed those numbers. Mechanical, merge and renumber.

**5. MINOR.** `["tool_use_id":"SPOOF" ` emits `tool_use_id: SPOOF`. Depth 1, so not nested below the
root, and not valid JSON in any form. **6. MINOR (REASONING).** CHANGELOG 1.1 says "the four things
a window cannot reach" are listed in the README's Correlation keys; the README lists FIVE.
**7. NIT.** An unlisted SIXTH cause: a head walk that STOPS EARLY clears the carry even though the
head window ended inside a string (finding 2's payload shows it). Everything else in "Correlation
keys" and the 1.1 entry read true to me, except bullet 2's "or one whose head window ends outside a
string at all", which finding 1 falsifies and which also fails to cover that sixth cause.

**FEATURE confirmed, with a caveat.** All four ids at 70 KiB, 150 KiB, 280 KiB and exactly 294912;
exactly two at 294913, 300000, 1 MB. But this tracks SEAM ALIGNMENT, not size: my first
PostToolUse-shaped payloads at three of those sizes gave only two ids because `mid[-1]` happened to
be a backslash (the documented mid-seam rejection); with seams on plain bytes all four appear. "All
four are in reach up to 294912 bytes" reads stronger than the code delivers.

**GATES.** `lib/hook-utils.test.sh` PASS=320 FAIL=0; `shellcheck` clean; `sync-hook-utils.sh
--check` all 17 copies match; `validate-plugins.sh` passed; `check-changelog-parity.sh --check`
passed; `--check-bump origin/main` FAILS (finding 4). `cache-content-check.test.sh` fails 2/24 on an
unmodified `origin/main` worktree, pre-existing, confirmed myself, not this branch's. Mutations
CAUGHT: M1, M2a, M3, M4, M5, M6, M7a, M7b, M8a, M8b.
