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

- `persistence: written`: Read the report from your own copy of the path, never from the
  `artifact:` value. A missing or empty file means the reviewer returned no report.
- `persistence: by-value`, or a reply with no block: the reply is the report. Write it to your
  path yourself, then read it as above.

Every check a caller runs on the report (the `Criteria read:` and `Coverage:` lines, finding
verification, severity folding) runs on the file's contents, not on the summary.

The file is the agent's raw report, not a `type: review-findings` file, so the `/review:fanout`
fix action skips it when it scans the same directory.
