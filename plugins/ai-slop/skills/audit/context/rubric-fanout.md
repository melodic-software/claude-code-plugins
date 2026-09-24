# Rubric fan-out: how a repo-wide rubric pass runs

The judgment rubric is applied by reading, so its cost scales with the words in scope. A
repo-wide audit over a large corpus is hundreds of thousands of words, which is more than one
context can read and more than one session can afford to lose to a rate limit or a crash. The
pass therefore fans out, persists as it goes, and resumes from the last completed batch.

`${CLAUDE_SKILL_DIR}/scripts/rubric-fanout.sh` does every counting, ordering, digest and
merge step. The orchestrator runs it and reads its output; it never packs, digests or totals
by hand.

## Batching

1. Start from the list file the audit's step 2 wrote with `detect.sh --list-targets`. Its keys
   are the detector's `file=` spelling, so script and rubric findings for one file share a key.
2. Run `rubric-fanout.sh plan --out <batch dir> <list>`. It orders the files (impact class,
   then 90-day change count, then key inside a repository; newest modification time first,
   then key, outside one; `--order repo|mtime` overrides the choice), packs them into batches
   of at most 50,000 words by `wc -w` (`--budget N` changes it; a larger file is its own
   batch), and writes `batch-NN.txt`, one key per line. It prints one line per batch:
   `batch=NN list=<path> files=N words=W digest=<sha256 of the list>`.
3. The batch directory is the findings home, beside the result files, so a later session can
   resume from it; a non-repository target uses the session scratchpad. `plan` refuses a
   directory that already holds batch lists, so a new scope gets a new batch directory. A
   resume keeps the existing one and skips `plan`: re-planning can reorder the files (a new
   commit moves the change counts), which changes every list's digest.

## Dispatch

Run `rubric-fanout.sh extract --out <rubric file>` once. It writes the catalog's `v1: rubric`
entries plus the "Signs of human writing" section to that file.

One fresh-context subagent per batch, all dispatched in one message so they run concurrently.
Each subagent receives:

- the path of the extracted rubric file, and nothing else from the catalog;
- the path of its batch list and the digest `plan` printed for it, which the subagent copies
  verbatim into its result;
- the result path it must write to (below);
- the finding shape: `- L<line> rule-<id>: "<verbatim quote, max 25 words>" -- <reason, max 20
  words>`, grouped under `## <path>` headings in the batch list's spelling, files without
  findings omitted, with `batch: <digest>`, `files_reviewed:`, and `files_with_findings:`
  lines at the top;
- the boundary rules: skip fenced code, blockquotes, double-quoted spans, inline code, YAML
  frontmatter, and table cell literals except for `rule-unusual-tables`; a file that quotes a
  tell to document it is not a finding; cap 6 findings per file and 30 per batch, worst first.
  For a non-repository target, add that `rule-style-shift` is not evaluable, because there is
  no history to compare against, and is never reported as a finding.

The subagent writes its result file before it replies, and replies with counts and its three
strongest findings only. The orchestrator never reads the batch's source files itself.

## Persistence and resume

Result files live in the findings home the persist contract resolved, as
`<findings home>/rubric-batch-NN.md`, beside the detector's findings file. That directory is
memory tier and self-ignored, so nothing here is ever committed. A non-repository target has no
findings home: batch lists, result files and the merged file go under the session scratchpad,
else the system temp directory.

A result file belongs to one batch list, not to a batch number: a leftover
`rubric-batch-03.md` from an earlier scope can sit exactly where the current third batch will
write. Before dispatching, and on every resume, run
`rubric-fanout.sh status --batches <batch dir> --results <findings home>`. It prints one row
per batch:

- `status=complete`: the result carries the list's digest on its `batch:` line, a
  `files_reviewed:` count equal to the list's length, and no `## <path>` heading outside the
  list. Skip the batch.
- `status=missing`, or `status=stale reason=digest|files_reviewed|foreign-heading`: dispatch
  the batch again and let the subagent overwrite the file.

A terminated subagent therefore costs one batch, a rerun after a limit resets dispatches only
the batches that did not finish, and a run over a changed scope never inherits a result from
the scope it replaced. `status` exits 0 only when every batch is complete.

## Merge

When `status` reports every batch complete, check each batch's evidence before accepting it:
spot-check a sample of its findings against the cited file and line, and dispatch the batch again
when a quoted span is not there. Then run `rubric-fanout.sh merge --batches <batch dir>
--results <findings home> --out <findings home>/<TS>-ai-slop-rubric.md`. It refuses while any
batch is incomplete, and otherwise writes summed `files_reviewed` and `files_with_findings`,
one `rule_total:` line per rule, and each result body in batch order. That file is the rubric
half of the human report. Rubric findings never enter the detector's findings file: they have
no crosswalk row and no relay.

## What this is not

- Not a budget mechanism. Every file in scope gets its rubric read; the fan-out changes how the
  reading is paid for, never whether it happens.
- Not a substitute for the detector. The two layers run over the same scope and report
  separately.
