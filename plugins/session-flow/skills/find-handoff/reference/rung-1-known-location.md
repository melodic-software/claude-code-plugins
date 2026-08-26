# Rung 1: known-location glob

Rung 1 of the recovery ladder in [`../SKILL.md`](../SKILL.md), the first thing tried and the only
rung that needs no transcript. Read-only throughout, like every rung. When it produces a strong,
recent candidate the ladder ends here and rung 3's grep machinery never runs.

Resolve `<memory_dir>/handoffs/` for the **current repo** through the plugin binding
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)),
never assume the literal `.work`; the memory root is consumer-configurable. Add the fallback
`${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` **only when project-root resolution fails**: the
producer writes there only on its no-project-root branch (topic-docs binding), so inside a repo
that shared location holds unrelated sessions' save-points, and a newer one could hijack the
short-circuit ahead of the transcript holding this repo's lost handoff. Glob `*-handoff-*.md`,
keep only files whose frontmatter is `type: handoff`, rank by mtime. A strong, recent candidate
→ jump to step 4 (step 5's chain validation then locates the producer transcript by the file's
`session_id`, since this path found no transcript), **but run step 3's re-arm-note capture
before that jump**, or this short-circuit surfaces a looping handoff with its `/loop` re-arm
missing while step 4 claims to present it. Locate the producer transcript by the candidate's
own `session_id` (`<session_id>.jsonl` under `~/.claude/projects/*/`, the same lookup step 5
performs, pulled ahead). That is a bounded, read-only read of ONE already-named file, not the
step-2 scan reintroduced. **Bind the note to THIS candidate by content, never by taking the
transcript's last one:** one session can emit several handoffs, so find the rails block whose
`Read @…` directive names this exact file and capture only the note adjacent to that block. A
tail read would hand back a later handoff's note, and if the loop was stopped and relaunched
with a different prompt in between, that re-arms the wrong recurring work, which is worse than
returning nothing. This is the same correlate-by-content rule the background-delivery screening
above already runs on. No block names this file, transcript missing, or no note → surface the
candidate without a note and say which, never block on it. **Exception. Operator says the handoff was
prompt-only:** then no file is the target (prompt-only writes none), and handoff files
intentionally accumulate, so a recent file here belongs to some *other* handoff. Skip this
short-circuit and go straight to the transcript scan. **Screen for background-delivery
save-points before short-circuiting:** `/session-flow:continue-in-background` writes an
indistinguishable `type: handoff` file with the same engine, but its rails prompt was
*delivered*, to the agent it launched. Locate the candidate's producer transcript by the file's
`session_id` and look for the launch signature (`claude --bg --name "continue-…"`, or the
continue-in-background invocation), then **correlate the launch with this exact file**: a
launch delivers one specific rails prompt, and its `Read @…` directive names the exact
timestamped file it delivered. The `--name "continue-<topic>"` slug identifies only the topic,
same-topic files from the same session all match it, so slug-only evidence is **ambiguous**
unless it uniquely resolves to one candidate. One session can produce a manual
handoff *and* later a background launch, and both files carry the same `session_id`, so a
session-wide signature match must never exclude by itself. **"Succeeded" means
verified-visible, not exit-0**, the producer itself warns a zero-exit `claude --bg` can still
be invisible and verifies the agent actually appeared, so exclusion requires transcript
evidence of that verification (the agent listed/confirmed); this definition governs every
screening site in this skill. Matched launch references this candidate and verifiably
succeeded → **recheck the CURRENT agent state before excluding**. Transcript evidence proves
only launch-time persistence, and a continuation that has since died leaves this save-point as
the artifact needed to restart the work.

**Read that state with `claude agents --json --all`, never the bare `--json`.** The bare form
lists ACTIVE sessions only. A background session that has reached a terminal state is excluded
by the CLI and surfaces only under `--all`, where it carries a `state` (observed: `done`, which
reports completion, and `stopped`, which does not) in place of the active `status` (observed:
`idle`, `busy`). That is `claude agents --help` ("`--all`. With --json: also include completed
background sessions") and the same
verified contract this repo already relies on in `claude-ops`'
`skills/lanes/scripts/lane-launcher.sh` (`load_sessions`). **So absence from the bare list is
NOT evidence of failure: a continuation that finished the work successfully looks exactly like
one that died.** Resolve four ways, and never collapse them:

- **Live**. Present with an active `status`. The work is in progress, so the save-point is not
  the lost handoff: exclude it from the default winner, say so, point the operator at
  `claude agents`, and keep looking for the older manual handoff.
- **Terminal and completed**. Present under `--all` with a `state` reporting completion.
  **Also exclude it from the default winner**, and say the continuation FINISHED rather than
  failed. This branch is why the recheck cannot key on presence alone: presenting a completed
  continuation's save-point as the lost handoff invites the operator to redo work already done,
  and it can bury the older manual handoff they were actually looking for. Point them at that
  session's output, not at a rerun.
- **Terminal and not completed**. Present under `--all` with a `state` that does not report
  completion (an interrupted or stopped one). **Keep** the candidate as the restart artifact and
  name the state observed. This is the case the recheck exists for.
- **Absent even from `--all`**. **UNKNOWN, never "failed."** The `--all` history is bounded, so
  a long-finished session can age out of it, and a lookup that cannot see a session cannot say
  why. Keep the candidate, and report that the continuation's outcome could not be determined
  instead of asserting a failed background attempt.

Read the `state` value as reported and say which branch it took, the values above are observed,
not a closed set, so an unfamiliar one is reported rather than forced into a branch. **Key the
lookup on the launched session's `sessionId`/`id`, the `claude agents --json` field, NOT the
`session_id` this file uses elsewhere for transcript frontmatter, when the launch-verification
listing recorded one in the transcript.** With no recorded ID the recheck is UNKNOWN and the
candidate is kept, and that holds even when the `--name "continue-<topic>"` slug matches exactly
one entry: `--all`'s history is bounded, so the candidate's own session may have aged out while a
newer same-topic continuation remains, and a unique match is then a DIFFERENT session wearing the
same name. Uniqueness at snapshot time is not identity across time. The slug is the same
ambiguous key here as at launch time, and no match count makes it unambiguous. Launch references
a different file, failed at launch, or is unverified/ambiguous → keep the candidate (surfacing
the provenance at the confirm gate when ambiguous). **This four-way resolution governs every
screening site in this skill, prompt-only included.**

**v1 scope: current repo only.** The cross-repo *filesystem* sweep (deriving
other repo roots from transcript `cwd` fields) is deferred. Step 2's transcript scan already
recovers handoffs written in other repos, since transcripts are indexed by session, not repo.

**OPEN, this rung cannot correlate a candidate to the repository the work was in.** Run from a
directory that is not the worked-in repo but has its own handoffs dir, the glob returns conforming
`type: handoff` files from unrelated sessions and the target is not among them; nothing here can
reject a same-cwd, different-repo candidate, because a handoff file records no durable repository
identity. `structure.md`'s frontmatter carries `type`, `date`, `topic`, `session_id`, and
`previous_handoff`, and none of those names a repo. Closing it needs a new frontmatter field, a
cross-cutting schema change every existing handoff on disk would lack, decided on its own merits
rather than inside a path fix (#1778). Until then: prefer the transcript scan whenever this rung's
candidates are merely recent rather than clearly this work's, and never present a glob candidate
as repo-verified. Reading the repository off the producer transcript is deliberately NOT used as
a substitute. It depends on a transcript that may be absent, which this skill's own Gotchas say
is the reason transcripts are the reliable index over the filesystem, and it returns nothing for
every rootless legacy handoff, i.e. exactly where a correlation check is needed.
