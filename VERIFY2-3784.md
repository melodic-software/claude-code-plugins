# VERIFY2-3784: independent re-check of the correlation windows

Tip verified `2c9a9de6c`. My own payloads, not suite fixtures. All REPRODUCED, none reasoning-only.
`hook-utils.test.sh` PASS=309 FAIL=0; `shellcheck` clean; `sync-hook-utils.sh --check` 17/17;
`validate-plugins.sh` passed; `check-changelog-parity.sh --check-bump origin/main` **FAILS** (MINOR 1).

**BLOCKER: G2 misses a payload cut inside a string whose content ends in `}` or `]`.** The tail walk
takes its phase from the payload's last byte, and G2 accepts any payload whose last non-whitespace
byte is `}` or `]`, which a string cut mid-content can be. Every field is then a quote out of phase:
string bodies become "structure" (attacker text sets the depth) and structure becomes "string bodies
at depth 1", so a nested key reaches the spine. With `FIL` 70000 bytes of `x`, driving
`hook::emit_telemetry t PostToolUse ok "$EPOCHREALTIME" '{}' /tmp` against
`HOOK_TELEMETRY_PAYLOAD='{"session_id":"s","f":"'$FIL'","tool_input":{"tool_use_id":"SPOOF","z":"}'`
emits `{"session_id":"s","tool_use_id":"SPOOF"}`. Also reproduced for `agent_id` under a `]` ending
and at depth 4 (`a.b.c.tool_use_id`). The small path is immune only because it demands an odd field
count; the large path has no parity equivalent, and requiring the last field to be pure structure
would not close it (content of exactly `}` wins). Falsifies README "the root-only guarantee above
holds at every payload size", "A payload cut off inside a string is the case this catches", and
CHANGELOG 1.1 "cannot put a value on the spine, at any payload size".

**MAJOR: G3 is load-bearing and untested.** Deleting `corr_out=""` before the negative-depth `break`
leaves my scratch copy at its 308/1 baseline (that failure is the git-root test running outside a
repo). Not cosmetic: `"q":"{{"` ahead of the BLOCKER payload makes the tip omit and the mutant spoof.

**MAJOR: the cut-edge fragment drop is load-bearing and untested.** `corr_steps=$((corr_n - 1))` to
`corr_steps=$corr_n` also stays at 308/1, yet the head window then emits a truncated root value
instead of omitting: at pad lengths 16330..16340 a root `"tool_use_id":"toolu_TRUNCATED_VALUE_MARKER"`
comes out as `toolu_TRUNC`, `toolu_TRUN`, ... down to `t`. The two pinned guards do discriminate:
`-64` to `-128` reddens the 64-trailing-whitespace case, `0:64` to `0:256` the all-backslash case.

**A fifth omission the documented list misses.** A root key starting INSIDE a window but straddling
its cut edge dies with the fragment: `{"session_id":"sE","pad":"<16335 y>","tool_use_id":"toolu_edge",
"f":"<70000 x>"}` puts the key at byte 16363, inside the forward window, yet omits it, and the list's
first entry ("more than a window from BOTH ends") does not describe this key.

**MINOR 1: changelog parity fails** (`rate-limit-guard` 0.7.36 regresses past main's 0.8.0,
`source-control` 0.55.55 collides; branch behind `ddbd6e03f`). **MINOR 2:** two concatenated documents put the second one's root key on the spine, undocumented.

**Clean under everything else** (no decoy reached the envelope): depth 2/3/4 decoys in
`tool_input`/`tool_response` at both ends; root arrays of strings and of objects; key-like pairs in
root arrays; 2000 tiled `\"tool_use_id\":\"SPOOFESC\"` decoys in one content string; backslash runs of
length 1..70 with the window start at offsets 0, n/2, n-1 inside it (210 payloads, 7 correctly dropped
by G1); trailing whitespace 0/1/63/64/65/5000, 64 tabs, 63 newlines; braces and brackets in string
content near both ends; decoys straddling 16384 (121) and `len-16448` (101); a big root array.
