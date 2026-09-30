# Paused wait and account switch

`SKILL.md`'s inlined floor owns the **Account switch** rule; this file owns how the paused lane
applies it: the `latched_account` field, the read, the decision at pause entry and on each wake and
Monitor tick, and the telemetry event.

## The `latched_account` field

The durable state block carries `latched_account` beside `rate_limit_latch` and `paused_until`. It
is the first 16 hex characters of the SHA-256 of the `account.email` on the snapshot that tripped,
not of the address `.claude.json` names now: the snapshot can be up to 10 minutes old and may
describe an account the operator has since left. It is a fingerprint because the telemetry comment
is public and the floor forbids printing the address. Write it in the same write as `paused_until`.
It is `null` or absent when the lane is not paused or that snapshot has no `account.email`; both
read as no latched account. The unsalted short hash keeps the address from casual readers only;
anyone holding a candidate address can confirm it.

## Reading the account

```shell
set -o pipefail; jq -er '.oauthAccount.emailAddress | strings | select(length>0)' < "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" | sha256sum | cut -c1-16
```

The file goes in on stdin because a native Windows `jq` cannot open an MSYS-style path argument. A
non-zero exit (file absent, unparsable, key missing or not a string) means **cannot attribute**;
discard the output. A failed `jq` still leaves `sha256sum` printing the hash of empty input,
`e3b0c44298fc1c14`; that value is never a fingerprint, so it also means cannot attribute. The
address never reaches the output, a variable, or a command line. Fingerprint a tee snapshot's
`account.email` the same way, feeding the snapshot on stdin (`jq -er '.account.email | strings |
select(length>0)' < "$HOME/.claude/rate-limit-guard/rate-limits.json" | sha256sum | cut -c1-16`),
to test whether it describes the new account.

`.oauthAccount.emailAddress` is internal Claude Code state, not a documented surface. Its
verification record is the recheck trigger in the `rate-limit-guard` reader contract
(`plugins/rate-limit-guard/reference/reader-contract.md` in the marketplace repository, cited for
provenance only).

The Monitor armed on the tee file fires only when the tee is written, and a machine running only
headless sessions never writes it. Wakes carry the detection there: a paused lane still wakes on its
`ScheduleWakeup` schedule, whose maximum delay bounds how late a switch is seen.

## At pause entry

1. Fingerprint the `account.email` of the snapshot the trip was read from. No `account.email`: the
   entry is **unattributed**, so `latched_account` stays `null`.
2. Write `paused_until` and `latched_account` together.
3. Read the `.claude.json` fingerprint. Stay paused when it cannot be attributed, when
   `latched_account` is `null` (nothing to differ from), or when the two are equal. Different: the
   operator switched after that snapshot, so apply step 4 below at once.

## On each wake and each Monitor tick

1. Read the fingerprint. Cannot attribute: no switch is detectable, so keep the latch and continue
   the ordinary re-evaluation (the latched pause end still applies).
2. `latched_account` absent and the read succeeds: the pause began unattributed, so there is no
   switch to detect. Record the fingerprint as `latched_account` and continue the ordinary
   re-evaluation.
3. Fingerprint equals `latched_account`: no switch; continue the ordinary re-evaluation.
4. Fingerprint differs: re-evaluate against the new account with a tee snapshot that is fresh
   (`captured_at` within 10 minutes) and whose `account.email` fingerprint equals the new one.
   - Both windows below 90: **resume**. Clear `rate_limit_latch`, `paused_until`, and
     `latched_account` together, and resume claiming work.
   - Either window at or above 90: **re-latch**. Stay paused, rewrite `paused_until` to the new
     account's pause end (the floor's Pause end rule) and `latched_account` to the new fingerprint.
     `rate_limit_latch` stays set.
   - No fresh, attributable snapshot: windows are **unknown**. Clear `rate_limit_latch`,
     `paused_until`, and `latched_account`, resume, and run reactive-only.
5. On a switch, add one `account-switch:` line to that cycle's report, `resumed`, `re-latched`, or
   `unknown`. Never write the address or the fingerprint into the report.

A resume through step 4 leaves no `paused_until` behind: a future value there reads as a live pause
to the instance-collision check and is misread harmfully.
