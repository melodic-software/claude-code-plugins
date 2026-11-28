# Recheck the benchmark registry through a host-gated fetcher and a tool-less judge

- Status: accepted
- Date: 2026-11-23
- Related: [#18395](https://github.com/melodic-software/claude-code-plugins/pull/18395) (the
  change); owner interview and answers, 2026-11-22 and 2026-11-23 (Q35, the registry-mode fetch
  path, the two added hosts);
  [the benchmark registry](../../plugins/multi-agent/reference/benchmarks.json)
  (what this rechecks); [ADR 0057](0057-share-a-user-scope-docs-cache-across-plugins.md) (the cache the
  fetch goes through)

## Context

The benchmark registry goes stale as boards change, move or stop testing current
models. A recheck has to read leaderboard pages, which are untrusted third-party text, and turn
them into proposed registry changes. The existing `multi-agent:docs-fetcher` gate admits only
first-party docs hosts, and widening it would widen every audit that uses it.

## Decision

1. **`/multi-agent:audit-defaults registry` owns the recheck** (Q35) and proposes changes by pull
   request. A manual recheck always runs, whatever the switches or a schedule say.
2. **A separate `registry-fetcher` agent reads the boards.** Its Bash runs one fetch command,
   held there by its own `PreToolUse` gate (fail-closed), which admits only the hosts in the
   shipped `plugins/multi-agent/reference/benchmarks.json`. A host joins only by a reviewed pull
   request; `www.vals.ai` and `artificialanalysis.ai` joined on the owner's word (2026-11-23).
   The existing docs-fetcher gate is unchanged.
3. **A `registry-judge` agent reads the fetched text and returns a closed JSON verdict, never
   quoting page text.** Its only tool is `TodoWrite`, because an omitted `tools` field inherits
   every tool and an empty list is refused at launch.
4. **A row the audit could not read is partial, with no proposal.** An empty fetch or judge stage,
   or fetch output that fails its header, byte or hash check, never demotes a board. A large page
   returned as a section map is read again by its sections and judged.

## Alternatives considered

- **(a) Widen the docs-fetcher gate to the leaderboard hosts.** One gate to maintain, but every
  docs audit could then reach those hosts. Not chosen.
- **(b) Let one agent fetch and judge.** Simpler, but page text would reach an agent that holds a
  shell, and an instruction planted in a page could steer it. Not chosen.
- **(c) A scheduled recheck only.** It misses a model release between runs and cannot be forced.
  Not chosen: the manual recheck always runs.

## Consequences

- A new board needs a pull request to the gate's host list as well as its registry row.
- A page that changes shape is reported unread rather than misjudged, so a recheck can come back
  partial.
- Leaderboard text never reaches an agent that holds a shell or can write files.
