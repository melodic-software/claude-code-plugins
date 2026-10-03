# One shared transcript reader parses session transcripts in session-flow

- Status: accepted
- Date: 2026-10-03

## Context

Before PR #5925, session-flow had three transcript readers: `retro`'s `parse_transcript.py`, the
observer's `observer.py` `summarize_record`, and `scripts/harness/hop_chain.py` `load_transcript`.
Each decoded the transcript JSONL on its own. `parse_transcript.py` summed usage per record, but
Claude Code writes one streamed assistant message as several records that share a `message.id`.
Its token totals were about twice the real figure, and it counted slash-command and injected records
as human messages (#5818). It also dropped record types it did not know without saying so.

The `audit-sessions` skill needed a fourth consumer of the same data. Anthropic documents the
transcript format as internal and changing between versions, so every reader carries the cost of
following those changes.

## Decision

1. **`plugins/session-flow/scripts/transcript_reader.py` is the only code in session-flow that
   parses transcript JSONL.** It owns record iteration, usage dedup by `message.id` (last record
   wins), typed-turn detection and the parse stats, including a count of unknown record types.
2. **Store readers never import it.** `audit-sessions`' `collect.py` imports the reader and writes
   the store. `census.py` and `sweep.py` read only the store, so a second parsing loop has no way back in.
3. **#5818 is fixed in place.** `parse_transcript.py` moves onto the shared reader. Its token and
   `human_messages` values change to the deduped numbers. Field names, the data-block shape, the CLI
   forms and exit codes stay as they were, and golden tests pin `data.plugin_usage`.
4. **The remaining readers migrate in their own changes**: `observer.py` (#5926) and `hop_chain.py`
   (#5927).

## Alternatives considered

- **A fourth reader beside `collect.py`.** Rejected: it adds a fourth copy of the parsing logic,
  and each copy has to follow format changes on its own.
- **Reuse `parse_transcript.py` as it stood.** Rejected: `audit-sessions` would inherit the double
  count.
- **Add a parallel `tokens_deduped` field and leave the old values.** Rejected: consumers keep
  reading the wrong number, and the contract carries two meanings for one quantity.
- **Migrate all three readers in one change.** Rejected: the observer is armed by a hook in every
  session, so a separate change keeps each change's blast radius small.

## Consequences

- `retro` trend lines step down once at session-flow 0.46.0, when the deduped values arrive. The
  session-flow CHANGELOG records the step.
- A format change in Claude Code is handled in one module. Unknown record types are counted and
  reported (#5931 tracks the ones current versions emit) rather than dropped silently.
- Until #5926 and #5927 land, two legacy readers remain. They are the migration backlog, not
  precedent for new code.
- New session-flow code that needs transcript data imports the shared reader or reads the
  `audit-sessions` store.
