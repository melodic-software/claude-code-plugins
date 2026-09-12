# Rubric fan-out: how a repo-wide rubric pass runs

The judgment rubric is applied by reading, so its cost scales with the words in scope. A
repo-wide audit over a large corpus is hundreds of thousands of words, which is more than one
context can read and more than one session can afford to lose to a rate limit or a crash. The
pass therefore fans out, persists as it goes, and resumes from the last completed batch.

## Batching

1. Take the ordered target list the audit's scope step produced (impact class first, then change
   frequency). Batch order is that order, so the highest-priority files are judged first.
2. Pack files into batches by word budget, not by file count: walk the list, adding files to the
   current batch until adding the next would exceed roughly 50,000 words, then start a new
   batch. A single file larger than the budget is its own batch. Measure with `wc -w` over the
   list; never estimate.
3. Write each batch's file list to the scratchpad as `batch-NN.txt`, zero-padded, one
   repo-relative path per line.

## Dispatch

One fresh-context subagent per batch, all dispatched in one message so they run concurrently.
Each subagent receives:

- the path of the extracted rubric text (the catalog's `v1: rubric` entries plus the "Signs of
  human writing" section, extracted once to the scratchpad);
- the path of its batch list and that list's digest (`sha256sum` over the list file, first
  field), which the subagent copies verbatim into its result;
- the result path it must write to (below);
- the finding shape: `- L<line> rule-<id>: "<verbatim quote, max 25 words>" -- <reason, max 20
  words>`, grouped under `## <repo-relative path>` headings, files without findings omitted,
  with `batch: <digest>`, `files_reviewed:`, and `files_with_findings:` lines at the top;
- the boundary rules: skip fenced code, blockquotes, double-quoted spans, inline code, YAML
  frontmatter, and table cell literals except for `rule-unusual-tables`; a file that quotes a
  tell to document it is not a finding; cap 6 findings per file and 30 per batch, worst first.

The subagent writes its result file before it replies, and replies with counts and its three
strongest findings only. The orchestrator never reads the batch's source files itself.

## Persistence and resume

Result files live in the findings home the persist contract resolved, as
`<findings home>/rubric-batch-NN.md`, beside the detector's findings file. That directory is
memory tier and self-ignored, so nothing here is ever committed.

A result file belongs to one batch list, not to a batch number. Batch numbers are reused across
runs, and a later run over a different scope or order packs different files under the same
number, so a leftover `rubric-batch-03.md` from an earlier run can sit exactly where the current
run's third batch will write. Before dispatching, compute each current batch list's digest and
check the result files that already exist. A batch is complete only when its result file:

1. carries a `batch:` line equal to the current list's digest;
2. carries a `files_reviewed:` count equal to the current list's length; and
3. names no `## <path>` heading that is absent from the current list (`grep '^## '` over the
   result, each path checked against the list).

Skip a complete batch. Any other result file, whether absent, short, from another list, or
naming a file outside the list, is stale: dispatch the batch again and let the subagent
overwrite it. A terminated subagent therefore costs one batch, and a rerun after a limit resets
dispatches only the batches that did not finish; a run over a changed scope never inherits a
result from the scope it replaced.

## Merge

When every batch has a complete result file, concatenate them in batch order into
`<findings home>/<TS>-ai-slop-rubric.md`, with per-rule totals, `files_reviewed` summed, and
`files_with_findings` summed at the top. That file is the rubric half of the human report. Rubric
findings never enter the detector's findings file: they have no crosswalk row and no relay.

## What this is not

- Not a budget mechanism. Every file in scope gets its rubric read; the fan-out changes how the
  reading is paid for, never whether it happens.
- Not a substitute for the detector. The two layers run over the same scope and report
  separately.
