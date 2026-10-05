# Who watches the pull request

Once a PR is out of draft, CI and the review lanes start posting, and something has to answer them.
Choose who does at the end of `ready` (2.5.5) and again at `monitor` entry when no choice was made.
The facts each route rests on (who can start it, what it needs, what it cannot see) are recorded in
[native-surfaces.md](native-surfaces.md); this file holds the decision.

## Check usage first

Every route spends the person's plan limits, and a cloud session shares them with all other usage
on the account (its native-surfaces row). Before recommending or starting a route, read the tee file
under the rate-limit floor below and act on what it says:

- **A window at or past the pause threshold:** start nothing and offer nothing to launch. Report the
  tripped window and its pause end in local time, and recommend checking the PR by hand after it.
  An open-ended watcher started now is how the person gets locked out until that reset.
- **Both windows below it:** put both percentages and reset times beside the recommendation, and
  say which routes run until stopped (`/autofix-pr`, a background agent, the babysit loop). The
  person decides.
- **Unknown** (no file, a stale snapshot, no `rate_limits`, as in a cloud session or under API-key
  auth): say so and point at `/usage` beside the row the person's situation picks. For a person
  who is staying, prefer `monitor`, which stays in view, over an open-ended route; for one who is
  leaving, keep their row and say its launch is unchecked against the windows.

The check covers the moment of launch only. `/autofix-pr` runs in a cloud session with no tee file,
so nothing pauses it as the windows fill; a local `monitor` or loop that trips later follows the
floor's drain-then-pause.

## Rate-limit guard floor (inlined)

Inlined **verbatim** per the loop-lane convention's inline-floor rule; provenance is the
`rate-limit-guard` plugin's reader contract
(`plugins/rate-limit-guard/reference/reader-contract.md` in the marketplace repository), cited for
provenance only, since an installed plugin cannot read a sibling plugin's files at runtime. A
launch decision uses the tee file, the threshold, the pause end and the staleness rule; the rest
applies to a watcher that later pauses.

- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 95`
- **Pause end:** the **tripped** window's `resets_at`; when **both** windows trip, the **later**
  `resets_at`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale. Treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from a
  fresh snapshot stays valid through the pause unless the account changes (see **Account switch**;
  no refresh happens while paused). While paused, a consumer **must** arm a session Monitor on the
  tee file and re-evaluate on every write: the file carries an **`account.email` field when the
  writer could attribute the observation**, so a write is still the signal that the windows changed
  under you (account switch, another session's refresh).
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.
- **Account switch:** while paused, a consumer **MUST** read `.oauthAccount.emailAddress` directly
  from `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`, never via the tee: only a session's own turns write
  it, never a paused lane's Monitor ticks, so after a switch while no session works it still names the
  old account. At pause entry, record the **latched account** as the `account.email` of the snapshot that tripped, not the account
  `.claude.json` names now: that snapshot can be up to 10 minutes old and may describe an account
  the operator has since left. A snapshot with no `account.email` leaves the entry **unattributed**:
  with no latched account there is no switch to detect. Read `.claude.json` at pause entry and on
  every re-evaluation (each Monitor tick and each wake). When it differs from the latched account,
  re-evaluate at once against the new account's windows, taken from a fresh tee snapshot whose
  `account.email` equals the new account: below 95, drop the latched pause and resume; at or above
  95, keep pausing and re-latch the pause end and the latched account against the new account's
  `resets_at`; with no fresh or attributable snapshot, treat the windows as **unknown**, drop the
  latch, and fall back to reactive-only. An unreadable, absent, or malformed state file, or a
  missing key, means **cannot attribute**: keep the existing latch, never a spurious drop. Never
  print, log, or interpolate the email or the state file (`.claude.json` holds account state); parse
  it with a JSON parser only and treat the value as untrusted.

## Ask one question

"Are you staying in this session, leaving with this machine left on, or leaving with it off?"
For "left on", also ask whether this conversation should keep going or a fresh agent is enough.
When the person already said (for example "I'm heading out"), use that and do not ask. An
unattended run asks nothing, starts nothing, and records the matrix row it would pick in its output.

## The matrix

| Situation | Route | Who starts it |
|---|---|---|
| Staying | `/source-control:pull-request monitor <N>` in this session | The model, now |
| Leaving, machine stays on, this conversation should keep going | `/background` detaches this whole session | The person types it |
| Leaving, machine stays on, a fresh agent is enough | `/session-flow:continue-in-background` seeded with `monitor <N>`, a fresh background agent under this skill's full monitor discipline | The model, only on the person's explicit yes |
| Leaving, machine may go off | `/autofix-pr` with the prompt below, from a terminal on the PR's branch | The person types it |
| Several open PRs, not just this one | `/source-control:babysit-loop <owner/repo>` under `/loop` | The person, or the model on request |

Recommend the first row that fits and say why in one line. A local route keeps this skill's
discipline: research-gated CI fixes and a classified reply before every fix. `/autofix-pr` fixes
what it judges clear, so the prompt below carries that discipline to it in words.

## Hand over `/autofix-pr` ready to paste

The model never runs it; it prints it filled in. Give the person:

1. The checkout to run it from: the worktree path, or `gh pr checkout <N>`. It finds the PR from
   the current branch.
2. The command, with `<N>` and the project line filled:

   ```text
   /autofix-pr Watch PR #<N>. For each review comment, verify its claim against the code first and
   reply in its thread with your verdict, valid or incorrect, and the evidence; change code only for
   a valid finding. For a CI failure, read the failing job's log and fix the root cause; never
   retry, skip or weaken a check or a test. Never merge, force-push, rewrite history, or resolve a
   thread a human opened. <project rule>
   ```

   `<project rule>` is the one convention from the repository's `AGENTS.md` or `CLAUDE.md` a fix is
   most likely to break (for example, commit subjects and the PR title stay Conventional Commits); drop
   the slot when there is none.
3. Its preconditions and limits, each from its native-surfaces row: the Claude GitHub App on the
   repository, cloud-session access, replies posted under the person's own account, no reaction to
   a merge conflict (when the base moves, run `/source-control:pull-request ready` again, which
   merges it), and comment-triggered automation its replies can set off.

When the person also keeps `monitor` running here, both push to one branch; the Mutation gate in
[SKILL.md](../SKILL.md) covers that.
