# Third verification, #3784 (`claude/posttool-hooks-review-ji6rl5`, 3d267e02a)

No BLOCKER. ~24,400 payloads driven through `hook::emit_telemetry` with a stub sink. No valid
JSON payload, and no truncation of one, put a decoy on the spine. All REPRODUCED unless marked.

**Sweeps, 0 spoofs:** 3,713 cuts of a 300 KB payload; 4,332 and 5,432 cuts around both seams and
the 65536 gate; 9,001 cuts holding depth-2/3/4 decoys inside the tail window (carry verified
engaged); 1,600 payloads sliding the tail seam byte by byte through a decoy region (carry engaged
1600/1600); 286 hand-built cases (backslash runs 1..70 on each seam, straddles at both seams
offset by offset, tiled `\"tool_use_id\"` decoys, root array, scalar root, concatenated
documents, non-JSON, empty, only quotes, invalid UTF-8 and every control byte before an unescaped
middle quote, `\\"` and `\\\"` middles).

- **Feature (2):** all four ids at 70000, 153600, 286720 and exactly 294912 bytes; exactly two at
  294913 and above. 53b4b9e6 gives two at all three lower sizes.
- **Tests (3):** all 8 mutations caught, none survived. M1 corr_js 311/1, M2 depth-0 break 311/1,
  M3 `corr_steps=$corr_n` 311/1, M4 cap 1048576 310/2, M4b cap 131072 307/5, M5 carry gate 311/1,
  M6 drop glob2 311/1, M6b drop glob1 308/4.
- **Envelope paths (4):** identical key set and order on both
  (`…,duration_ms,session_id,prompt_id,tool_use_id,agent_id,data`); wrapped jq counted 0
  invocations on the builtin path, 1 on the jq path (`{"k":"v","n":1.5}`).
- **Gates (6):** `PASS=312 FAIL=0`; shellcheck clean; sync `--check` all 17 match;
  validate-plugins pass; changelog `--check-bump` and `--check` pass. `cache-content-check` fails
  2/24 on unmodified `origin/main` too (process-budget trace probe). Not a finding.
- **Measurements (5):** before/after ms per emit: 16 KiB 5/5, 64 KiB 6/6, 128 KiB 10/8, 512 KiB
  32/12, 2 MB 131/41. "Not slower at 512 KiB or 2 MB" holds with margin; absolute numbers differ
  from the PR's but agree in order of magnitude and direction.

## Findings

**1. MINOR (regression, malformed input only).** The carried tail pass runs from a state the head
walk abandoned. `corr_carry` is decided from raw field-count parity before the head walk, and
neither break site (the `corr_js` structure check, which also does `corr_out=""`, and
`((corr_depth > 0)) || break`) clears it or invalidates `corr_depth`. The tail then walks from a
stale depth and a depth-2 `tool_use_id` reaches the spine. Repro: `{"a"Z"b":{"x":"<120000 A>",
"tool_use_id":"SPOOFSCZ"}}` yields `…,"duration_ms":0,"tool_use_id":"SPOOFSCZ"` and no other id;
53b4b9e6 yields no id at all. Needs a byte outside `corr_js` between two root strings, so not
reachable from valid or truncated JSON. Fix: `corr_carry=0` at both break sites.

**2. MINOR (pre-existing, not a regression).** The commit message and code comment claim the
depth-0 break stops a second concatenated document contributing a root key. It does not when the
root close and the next root open share one structure field: `}{` or `}\n{` takes depth 1 to 0 to
1 inside a single field, so the `>0` test never sees 0. `{"session_id":"REALSESS"}{"tool_use_id":
"SPOOFCAT3"}` puts SPOOFCAT3 on the spine, on this commit and on 53b4b9e6 alike. The guard is
real for `}` followed by a quote; the claim as written is too strong.

**3. MINOR (doc).** README "Correlation keys" lists four ways a key goes out of reach; there is a
fifth. A middle holding `\\\"` (escaped backslash then escaped quote, i.e. file content with a
backslash before a quote) never leaves the string, yet glob2 `*\\\\\"*` rejects the carry. A
98438-byte valid payload, both seams on `A`, under the cap, key not between the windows, yields
only session_id and prompt_id, while the same payload with `\"` or `\\x` there yields all four.
The code comment owns this ("rejects middles that are fine"); the README list does not. Also
README "the root-only guarantee above holds at every payload size" and CHANGELOG 1.1
"tool-supplied arguments cannot put a value on the spine, at any payload size" are false for a
malformed payload (finding 1) and for concatenated documents (finding 2). Every other sentence I
checked in both files is accurate.
