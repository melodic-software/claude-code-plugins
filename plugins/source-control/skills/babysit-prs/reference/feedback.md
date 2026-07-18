# Bot Feedback

Classification and disposition policy for review feedback. Classify structured state before
interpreting prose. The shared per-PR discipline — evidence-based comment state, structured
finding extraction, and the per-finding D1-D7 verification gates — lives at the plugin seam,
`${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md`; apply it as written and never restate it
here. Angle-bracket slots (`<state-dir>`, `<advisory-fix-round-cap>`) are filled from the
effective-configuration block in this skill's `SKILL.md`, which renders every key's resolved
value and its unset fallback; `<state-dir>` is the `state/babysit-prs` subdirectory of the plugin
data directory.

## Bot Identity Detection

Bot identity is detected structurally, never by hardcoding logins: on GraphQL surfaces a bot
author has `author.__typename == "Bot"` (login without suffix); on REST surfaces the login
carries the `[bot]` suffix. The `extra_bot_logins` configuration key — shipped empty — is the
only config-fed fallback, for automation accounts that post as ordinary users; it extends, never
replaces, the structural check.

## Blocking

- The GitHub review decision is `CHANGES_REQUESTED`.
- Observed checks fail, are cancelled/stale, or remain incomplete. Treat `NEUTRAL` and `SKIPPED`
  as terminal success-like conclusions.
- A bot reports an explicit `P0`, `P1`, actionable `P2`, high-severity defect, regression, or
  required fix.
- An approval-gate bot explicitly says it is not approving and its comment carries findings.

## Nonblocking But Material

- A bot reports that it could not run or encountered an execution error.
- An explicitly optional check is flaky or unavailable and needs user triage.
- Advisory feedback remains after approval.
- Merge state is temporarily `UNKNOWN`.
- A review-bot comment that states an explicit approval or non-blocking verdict (for example
  `Approve`, `ready to merge`, `none of the observations are blocking`) and contains no
  required-fix, `P0`, `P1`, or regression language. This applies prose parsing only after
  structured state: a `CHANGES_REQUESTED` review stays blocking, and an ambiguous or negated
  verdict stays blocking (fail-safe).
- A bot not-approval whose only stated reason is that its underlying reviewer skipped or could
  not run (for example a usage limit) and that contains no findings. Report it once; whether to
  lift the limit is a user decision.
- A blocking bot comment whose id has a recorded disposition (see Feedback Dispositions below).

Do not treat bare words such as `bug`, `failed`, or `not present` as blockers. Respect structured
approval state and negation before text heuristics.

## Feedback Dispositions

After triaging a blocking bot feedback item as an approval, stale, or non-actionable, the
orchestrator records a durable disposition — under that PR's worker lease, before acting on the
triage result — so later snapshots stop re-flagging it as a blocker:

```text
python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/manage_feedback_ledger.py" dispose --pr owner/repo#42 --expected-head-sha <head-sha> --feedback-id "comment:123456789" --reason approval --lease-token <worker-token> --state-dir <state-dir> --apply
```

- `--feedback-id` is the snapshot feedback id, verbatim; the helper requires stored snapshot
  state, the id present among that PR's blocking or material feedback ids, and the PR's worker
  lease.
- Dispositioned ids leave `blockers` and surface as material feedback with a `disposed_reason`,
  reported once through the new-feedback diff.
- A disposition never overrides structured `CHANGES_REQUESTED` review state; only GitHub resolves
  that.

## Advisory Fix-Round Cap

Autonomous fix rounds addressing advisory bot findings (`P2` or other nonblocking suggestions)
are counted per PR in the durable feedback ledger. Keep iterating and driving the PR toward
mergeable as long as each round makes real progress or responds to a genuinely new finding — do
not stop after a small, arbitrary number of rounds while real, still-fixable advisory findings
remain. Record each round write-ahead, before starting the fix, keyed by the snapshot head SHA
the findings were observed on:

```text
python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/manage_feedback_ledger.py" record-advisory-round --pr owner/repo#42 --expected-head-sha <head-sha> --lease-token <worker-token> --state-dir <state-dir> --apply
```

`<advisory-fix-round-cap>` sets the round ceiling deliberately high: it is not a normal
operational limit meant to halt legitimate fix work, but a safety backstop that only trips a
genuinely stuck or looping worker — one that keeps recording rounds without making real progress.
The helper refuses a round beyond that ceiling; from then on report new advisory findings and
wait for the user — after verifying actual thread content per `safety.md`'s Verify Before
Escalating Non-Convergence section. Clear blocking defects — failing checks, `P0`, `P1`,
regressions — are never capped. The snapshot surfaces the counter as `advisory_fix_rounds` and
adds a material finding when the cap is reached.

## Bot-Authored PRs: Dependency Bump Vs. Reviewed Content Return

Not every bot-authored PR is a dependency-acceptance decision. Distinguish by what the PR's diff
actually is, not by hardcoding a bot's login:

- **Dependency-manager PR** (Dependabot, Renovate, or an equivalent — detected structurally per
  Bot Identity Detection above, extended by `extra_bot_logins`): the diff bumps a pinned external
  dependency version (a lockfile, a manifest version field, a pinned Action SHA/tag for a
  third-party action). Accepting the new version is a human policy call. Dependency-manager PRs
  are never merged autonomously in any tier — `SKILL.md` states the invariant, and the merge
  wrapper enforces it mechanically (`safety.md`, Guarded Mutation Wrappers).
- **Policy/content-sync bot PR**: the diff is this repository receiving content it does not own
  back from an upstream repository, through a mechanism the repository itself declares (for
  example a sync manifest naming which local paths are managed from where). This is the reviewed
  return path for a change already authored and reviewed upstream, not a new dependency to
  accept. Ordinary fix-or-escalate and merge-when-green rules apply exactly as for a
  human-authored PR; do not hold it for a dependency-acceptance instruction that was never meant
  to gate it.

When the two are hard to tell apart from the diff alone, check whether the changed paths are
declared managed by a sync mechanism the target repo documents; if the repo declares no such
mechanism, default to treating an unfamiliar automation-authored PR as a dependency-acceptance
hold — the safer default when the structural signal is absent.

## Ignore For Auto-Fix

- Praise, summaries, duplicate bot chatter, and stale feedback superseded by a newer approval.
- Human-authored feedback, outside autopilot's addressed-thread widening — see Human Feedback
  below; classify and reply per the shared discipline, never auto-fix.

## Human Feedback

- `CHANGES_REQUESTED`, explicit blocking language, and unresolved inline human threads remain
  active stop-and-ask conditions until GitHub state resolves them — escalate; never fix or
  resolve past them.
- Ordinary human comments are classified, replied to with evidence, and surfaced per
  `${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md` — never auto-fixed, and never resolved
  on the human's behalf, outside autopilot's addressed-thread widening. Report each new stable
  comment id once, and do not keep an otherwise unchanged PR permanently active after the
  notification has been recorded.
