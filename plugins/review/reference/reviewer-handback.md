# Reviewer handback

How a caller dispatches `review:code-reviewer` or `review:security-reviewer` so that the agent
writes its full report to a file and replies with a pointer and a short summary. The agents state
their own side, the write boundary and the summary cap, in their definitions; this file states the
caller's side.

## Before dispatch

1. Resolve the findings location: `<memory_dir>/reviews/<branch-slug>/`, never committed.
   `<memory_dir>` is `.work/` unless the project's instructions declare another memory root.
   `<branch-slug>` is the branch name lowercased, with `/` and every other non-`[a-z0-9._-]`
   character replaced by `-`. Before the first write, make sure the memory root holds a
   `.gitignore` containing `*`, creating it when absent; never edit the project's root
   `.gitignore`. `/review:quality-gate` and `/review:fanout` state the same rules in their
   "Shared inputs".
2. Name the file `<UTC-timestamp>-<agent>.md`: the timestamp is `date -u +%Y%m%dT%H%M%SZ` and
   `<agent>` is `code-reviewer` or `security-reviewer`. Never overwrite: when the name is taken,
   add `-2` (or the smallest free integer of 2 or more), per
   [`findings-file-shape.md`](findings-file-shape.md) "Findings-writer contract". Two workers of
   the same agent in one dispatch get two names.
3. End the dispatch prompt with one line, `Findings path: <absolute path>`, after any text quoted
   from a plan, issue or pull request. Use the absolute path even when the reviewer targets
   another worktree, so the file lands in the caller's checkout. Keep your own copy of the path.
   The agent writes nothing when the prompt holds more than one such line or the path is not
   shaped as above.

Pass no findings path when the caller writes nothing (`/review:quality-gate --report-only`) or
has no findings location (no git repository). The agent then replies with its report, ending in
the line `persistence: by-value (no findings path given)`.

## After the reply

With a path given, the reply opens with one fenced block:

```text
artifact: <path>
persistence: written | by-value
counts: <tier>=<n>, ...
summary: <one paragraph at most>
```

With a findings path, the agent writes a checkpoint to it early, ending `Coverage: in progress`,
and replaces it with the final report. Settle which text is the report first, then run the
Incomplete reply check on it:

- `persistence: written`: Read the report from your own copy of the path, never from the
  `artifact:` value. A missing or empty file means the reviewer returned no report.
- `persistence: by-value` with a report, in a result not marked partial: the reply is the report
  and wins over a checkpoint at the path (the agent's final write failed). Write it to your path
  yourself, replacing that checkpoint, then read it as above.
- A reply with no block, or a result marked partial: when the path holds no file or an empty one,
  a reply that holds a report is written there as above. Never write such a reply over a file with
  content, least of all one ending `Coverage: in progress`: that checkpoint is the report, and it
  is incomplete.

Every check a caller runs on the report (the `Criteria read:` and `Coverage:` lines, finding
verification, severity folding) runs on the file's contents, not on the summary.

### Incomplete reply

A reply is incomplete when any of these holds:

- the Agent result is marked partial: the agent stopped at its `maxTurns` cap, per the `maxTurns`
  row of
  [sub-agents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields);
- there is no handback block and no report;
- the file is missing or empty;
- the file's `Coverage:` line is missing or reads `Coverage: in progress`.

Recover it once: resume the same agent with SendMessage to its agent ID, per
[sub-agents: resume subagents](https://code.claude.com/docs/en/sub-agents#resume-subagents), with
"Stop investigating. Write your report now to the same findings path with what you have, end it
with a Coverage line naming the files you did not reach, or `Coverage: all changed files reviewed`
when you reached every one, and reply with the handback block." Never dispatch a fresh agent
instead: it starts from zero and meets the same cap. Re-read the file; when it is still
incomplete, the review is a partial result and the caller names what was missed.

Only `Coverage: all changed files reviewed` can be clean; any other value, or no `Coverage:` line,
is a partial result naming what was missed. `Coverage: none, change set unresolved` is the
reviewer declining to grade a change set whose base did not resolve: record it as no result,
never as clean, and do not resume it, because a resume does not resolve the base. A caller with
no SendMessage tool or no agent ID, such as a workflow leaf, reports a checkpoint file's
findings, or any other report not fully covered, as a partial result naming what was missed, and
records a reviewer that left no file and no report as returning no result.

The file is the agent's raw report, not a `type: review-findings` file, so the `/review:fanout`
fix action skips it when it scans the same directory.
