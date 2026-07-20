---
name: update
description: "Maintainer-facing drift-check and upstream sync for the firecrawl plugin's wrapper skill — tracks the firecrawl-cli npm release and the upstream SKILL.md source. Run only from a working-tree checkout. Actions: --check (default, read-only drift report) and the bare full update (gated npm upgrade + advisory skill-content integration). Not for consumers — consumers update via /plugin marketplace update."
argument-hint: "[--check] (bare = full gated update pipeline)"
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash(grep -m1 *UPSTREAM.md*)
---

## Pre-computed context

Last upstream sync: !`grep -m1 '^- Last sync:' "${CLAUDE_SKILL_DIR}/UPSTREAM.md" 2>/dev/null | sed 's/^- //' || echo "never — run this skill with --check"`

## Purpose

Keep the `/firecrawl:firecrawl` wrapper skill in sync with its two upstream dependencies: the
`firecrawl-cli` npm package (ships new versions roughly weekly) and the upstream canonical skill at
`https://www.firecrawl.dev/agent-onboarding/SKILL.md` (evolves alongside it). The wrapper skill
**owns** its content — upstream is a *source*, not a parallel install.

Maintainer-facing: run this in a working-tree checkout of this plugin (the marketplace clone, or a
directory loaded via `--plugin-dir`), never against an installed marketplace copy — the apply path
rewrites `UPSTREAM.md` inside this skill directory, and consumers receive updates through
`/plugin marketplace update`. Drift detection uses the sidecar `UPSTREAM.md` (SHA tracking): upstream
`SKILL.md` is fetched fresh on `--check` and hashed; the sidecar records the prior hash for diff. No
vendored snapshot is kept. The action is advisory — the two approval gates in Safety below keep every
mutation behind an explicit yes. Do NOT auto-fire this skill — it is maintainer-invoked only.

## Invocation

| Invocation | Effect |
|---|---|
| `/firecrawl:update --check` (default) | Read-only drift report. Fetches upstream + npm metadata, compares against `UPSTREAM.md`. **No mutations.** |
| `/firecrawl:update` | Full update pipeline with two approval gates |

**When to invoke, the modes, and the full update pipeline:** read `context/update-flow.md`. The
preservation invariants and safety guarantees below stay inline.

## Preservation rules (for any skill-content integration)

These are the invariants an integration run must keep in the `/firecrawl:firecrawl` wrapper skill,
in this exact form:

- Single-line YAML `description` with `Use when:` and skip guidance phrase lists
- Frontmatter fields: `name`, `description`, `argument-hint`, `user-invocable: true`, `disable-model-invocation: false`
- Pre-computed context block at top, using `firecrawl --status` for the health line
- "Core pattern — write to disk, Read selectively" rule: every non-trivial example uses `-o /tmp/fc-<nonce>.<ext>` then `Read`
- "When NOT to use this skill" section with the doc-site-reader-first and synthesis-tool escalation ordering
- The pointer to this maintainer update skill (`/firecrawl:update`) — the wrapper skill delegates its update/drift concern here rather than carrying it inline
- Gotchas section with the "don't run `firecrawl init`, don't run `firecrawl login`" prohibitions
- Imperative tone, no marketing language

The helper at `scripts/update.sh` does the deterministic parts (fetch, SHA, diff); this skill body
does the Claude-facing decisions (integration and approval). For a non-trivial content delta, the
`/skill-creator:skill-creator` plugin skill (if installed) can drive the rewrite under the
preservation rules above; otherwise inline-edit.

## Safety

Nothing destructive happens without explicit approval. Four guarantees:

1. **Two approval gates.** The update action never runs `npm install -g` or rewrites SKILL.md
   without asking first. Gate 1 covers the binary install; Gate 2 covers the skill content. Either
   `No` exits cleanly.
2. **Atomic fetching.** `update.sh --check` completes all network I/O (npm metadata + upstream
   fetch) before printing anything. A mid-run 404 or DNS failure leaves state untouched — no partial
   write.
3. **Rollback path.** `UPSTREAM.md` records the *previous* CLI version before each upgrade. If a new
   version breaks something, the rollback is one line: `npm install -g firecrawl-cli@<previous-version>`.
   Revert the plugin PR for skill-content changes.
4. **Post-install verification.** After `npm install -g`, the flow re-runs `firecrawl --status` and
   diffs `firecrawl --help` against the pre-install snapshot. A removed command or auth failure is
   flagged before the skill-content integration step begins.

**Network requirement.** The update path needs `registry.npmjs.org` and `www.firecrawl.dev`
reachable. Some sandboxed/cloud egress proxies intermittently 503 with "DNS cache overflow" — retry
after ~30s, or run the update from an unrestricted session.

**Idempotency.** Running the update action with `--check` twice with no upstream change: "no drift,
current." Running a full update when already at latest: reports "no drift" and exits before Gate 1.
Safe to schedule or re-run.

## What this skill does NOT do

- **Does not run against an installed marketplace copy** — maintainer-facing; the apply path writes
  `UPSTREAM.md` in this skill directory. Consumers update via `/plugin marketplace update`.
- **Does not auto-rewrite the wrapper SKILL.md** — `update.sh` owns only the deterministic record
  (`UPSTREAM.md`); skill-content integration is Claude's step behind Gate 2, governed by the
  Preservation rules above.
- **Does not run `firecrawl init` or `firecrawl login`** — those install a parallel shadow copy /
  second auth source of truth. This plugin IS the maintained integration.

## Related

- `UPSTREAM.md` (this skill root) — sync-state anchor (last sync date, upstream SHA, previous CLI
  version for rollback). Updated only by the update action.
- `scripts/update.sh` — deterministic helper invoked by the update flow (npm version lookup, upstream
  fetch + SHA, help diff). Regression tests: `scripts/update.test.sh`.
- `context/update-flow.md` — when to invoke, the modes, and the full pipeline.
- The user-facing wrapper skill this maintains: `/firecrawl:firecrawl`.
- Firecrawl docs: <https://docs.firecrawl.dev/sdks/cli>. Upstream skill source: <https://www.firecrawl.dev/agent-onboarding/SKILL.md>.
