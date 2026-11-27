# Mine every fleet transcript source through one shared ingest

- Status: accepted
- Date: 2026-11-26
- Related: [ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md) (the synced
  copies the shared modules ship through);
  [consumer-agnostic plugins](../../.claude/rules/consumer-agnostic-plugins.md)

## Context

Every transcript-mining skill (audit-sessions, audit-friction, recall, codify preferences,
turns-to-complete, go-faster, retro and the harness-ops audits) read only the Claude Code
configuration directory it ran in, and each found that directory its own way: seven root
resolvers. A person with several hosts, each with more than one platform (a Windows side and a WSL
side), got findings built from a fraction of their sessions. Earlier whole-tree mining runs
exhausted memory on WSL. The fleet itself (host names, SSH aliases, paths) is personal and must not
ship in a public plugin. The transcript JSONL format is internal to Claude Code and may change on
any release.

## Decision

1. **One shared ingest.** session-flow's `collect.py` is the only writer of the store
   (`session-record/v2`, partitioned by source). Skills that mine many sessions (audit-sessions,
   audit-friction, recall, codify preferences) read the store; the others (find-handoff, retro,
   go-faster, turns-to-complete, audit-performance, audit-skill-visibility, inventory) call the
   source resolver, which also renders the shared report header.
2. **The fleet lives in a sources file the person owns.** `lib/transcript_sources.py` reads the JSON
   file named by the file-type userConfig option `transcript_sources_file` (in session-flow,
   harness-ops, performance and discovery); unset, it reads only the local configuration directory
   (`CLAUDE_CONFIG_DIR` or `~/.claude`). The person's dotfiles render the file from their fleet
   manifest. Limits are defaults in the resolver, overridable per host in the file.
3. **A remote host runs the ingest itself, through the remote-run protocol.** `lib/transcript_run.py` sends the shipped modules over
   each source's `via` argv (for example `ssh <alias>`) as
   `python3 -c "<fixed loader>"`; stdin carries a manifest of length-prefixed modules and data
   files, then the caller's fingerprints; stdout returns JSON lines starting with a versioned
   `hello`, then records, carried-over records, history prompts, diagnostics and gaps. Nothing is
   installed or written on the remote host; the caller writes its own store. Local reads use the
   same protocol with an empty via, so memory limits apply in a child process.
4. **One parser.** Every reader parses through `lib/transcript_reader.py`; each run's diagnostics
   count format drift. The three modules sync into each adopting plugin through
   `scripts/shared-copies.txt` (ADR 0019).
5. **One reader per host, without remote writes.** A Linux abstract-namespace socket is the per-host
   lock: no file, released when the process exits. A local read also takes `fcntl.flock` on a lock
   file in the caller's own data directory, because a sandboxed run has its own network namespace
   and cannot see the socket; when that fails the read reports a `sandboxed` gap. Capped lookups
   skip the lock.
6. **Every miss is visible.** An unreachable, busy, partial or sandboxed source is a named gap with
   a retry command, recorded in a diagnostics record and printed in every mining report's header,
   as is a source not collected within half its `cleanupPeriodDays`. Published output passes one
   publish redactor that replaces host-tied identifiers with stable per-host placeholders and
   fails closed.

## Alternatives considered

- **Remote-run protocol, candidate B: `python3 -` with the fingerprints after a sentinel inside the
  script text.** Fingerprints become code text, with size and escaping costs, and stdin cannot
  stream. Not chosen.
- **Remote-run protocol, candidate C: a base64 bundle in argv.** Hits ARG_MAX and remote-shell
  quoting. Not chosen.
- **Copy transcripts to the caller (rsync over SSH), then ingest locally.** Moves the whole tree
  (18.5 GB in one measured manual run) on every run and keeps a second copy. Not chosen; reconsider
  if a host cannot run Python 3.10+.
- **Install the plugin on each host and pull its store.** Writes on the remote host and needs every
  host's plugin version in step. Not chosen; reconsider if Claude Code ships a supported remote
  collect.
- **A lock file on each host.** Writes on the remote host. Not chosen; the abstract socket needs
  none. A remote read off Linux takes no lock, and diagnostics declare the lock missing.
- **A store per source** (audit-friction's former `--source` store). Every consumer would merge
  many stores. Folded into the one store.
- **The fleet in a plugin setting or a team convention layer.** A host list is one person's data, so
  it would ship personal values or need a layer this setting has no use for. Not chosen.

## Consequences

- With no sources file, every skill reads the local configuration directory as before.
- Each host that runs the ingest needs `python3` 3.10+ on the non-interactive PATH of its via.
- A source read through another platform's mount (the Windows side from WSL) is stamped with its
  declared platform and a null Claude Code version, since it cannot report itself.
- CPU and disk priority apply only on Unix; elsewhere the run declares them missing and warns on a
  slow read.
- Recheck when Claude Code documents a transcript schema or a bulk export (the parser choice), or
  when a reader host that is not Linux joins the fleet (the lock).
