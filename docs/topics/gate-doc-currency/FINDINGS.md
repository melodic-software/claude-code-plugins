# Gate and check-skill doc-currency audit — findings

Audited 2026-08-10 against `code.claude.com/docs`. Scope: **pass (a)** — do the claims this
repository's gates, check skills, and philosophy make about *how Claude Code behaves* still match the
current documentation? Pass (b), whether the enforced doctrine is still best practice, is deliberately
not attempted here.

## Method, and its one hard rule

Each page was asked to **state its own current rule**, never to confirm or deny a sentence from this
repo. A fetch summarizes through a small model, so "the page doesn't mention X" is a routine false
negative — and a false negative read as drift would mean editing correct doctrine on the strength of a
lossy read, which is worse than missing drift. **No verbatim quote, no drift classification.** Anything
without a quote is recorded as `unverifiable`, not `drifted`.

Claim inventory: ~260 dated verification stamps across the repo, spanning **2026-07-15 to 2026-08-08**,
citing **73 distinct** `code.claude.com/docs/en/` pages.

## Verified — no drift

Each confirmed by verbatim quote from the current page.

| Claim | Where it is load-bearing | Current text |
|---|---|---|
| A subagent starts fresh; a fork inherits | `PLUGIN-PHILOSOPHY.md` fresh-eyes rule (:565, :613), and everything downstream of it | "Each subagent starts with a fresh, isolated context window. It doesn't see your conversation history… The exception is a fork, which inherits the parent conversation instead of starting fresh." |
| Agent `model` values and default | Philosophy Model tiers (:647) | "`sonnet`, `opus`, `haiku`, `fable`, a full model ID …, or `inherit`. Defaults to `inherit`" |
| Agent `effort` values and default | Philosophy Effort tiers | "Options: `low`, `medium`, `high`, `xhigh`, `max` … Default: inherits from session" |
| Frontmatter `name` optional, defaults to directory | Philosophy Naming; `check-skill-leaf-names.sh` derives every leaf from the directory | "`name` … No … Defaults to the directory name." |
| A declared `name` registers a bare alias | Philosophy Naming | "The bare `/fancy` also invokes the skill unless another command already uses that name." |
| The v2.1.216 command-name history | Philosophy Naming's own history note | "Before v2.1.216, the frontmatter name replaced the whole command name, so the menu showed `/fancy` without the plugin prefix and `/my-plugin:fancy` didn't autocomplete." |
| `disable-model-invocation` default `false`; `user-invocable` default `true` | The `setup` contract in `validate-plugin-contracts.mjs` | Both quoted from the frontmatter table. |

The fresh-eyes rule — the single highest-blast-radius claim in the repo — is **exactly current**.

## Drifted — fixed in this change

**1. The per-session subagent cap no longer exists.** Three sites recorded it as a live constraint:

- `plugins/session-flow/skills/orchestrate/context/sources.md` — "at most 200 subagents per session"
  (`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`, v2.1.212+), read 2026-07-29
- `plugins/session-flow/skills/orchestrate/SKILL.md` — listed among three separately-overridable caps
- `plugins/discipline/skills/sweep-all/SKILL.md` — dispatch budget counted against it

Current: *"The 200-subagent-per-session cap is removed, so long-running sessions no longer refuse new
subagents; the concurrency and depth limits still apply"*
([2026-w32](https://code.claude.com/docs/en/whats-new/2026-w32), v2.1.220–v2.1.224). Both the cap and
its variable are gone from the sub-agents page, which now carries only the concurrency and depth
limits. Fixed at all three sites; `sources.md` keeps it as an explicit **Superseded** note so a reader
who remembers the cap learns what replaced it.

Two riders picked up on the same re-read: sessions with `ultracode` active are exempt from the
concurrency limit, and an in-session `/subtask` fork takes a slot but is never blocked by it.

## Platform surface the doctrine has never evaluated

The docs index (`llms.txt`) lists **112** core pages. The repo cites **73**. Of the 39 uncited, most are
irrelevant here (IDE integrations, mobile, gateways, accessibility). These are not:

| Page | Why it matters to this repo |
|---|---|
| `cross-session-messaging` | `ListAgents`/`SendMessage`, `crossSessionInbound`, `isolatePeerMachines`, `/list-agents`. A whole inter-session channel with its own permission semantics. **Not available on native Windows.** |
| `agent-teams` | A coordinated team of sessions Claude spawns and supervises — a rung the Delegation-mechanics ladder does not have. |
| `agents` | The docs' own comparison of every way Claude Code runs multiple agents. Directly the ladder's subject. |
| `feature-availability` | Which features exist on which platform and provider. This repo is explicitly cross-platform and has a `CROSS-PLATFORM CONTRACT` section; a per-feature availability matrix is exactly its input. |
| `sessions` | Resume semantics — the documented way to carry context, distinct from messaging. |
| `checkpointing` | Rollback surface, relevant to any skill that mutates. |
| `fast-mode` | Sits beside the model/effort tier doctrine. |

This is the audit's largest finding and it is **not drift**. Nothing here is wrong; the doctrine simply
predates these surfaces. `PLUGIN-PHILOSOPHY.md`'s Native-first adoption gate is the mechanism for
deciding each one, and it has not been run against them.

The Delegation-mechanics dispatch ladder is the most affected: it runs generic subagent → named agent →
cross-vendor advisor, and does not mention agent teams, background sessions, or cross-session messaging.

## Week-32 changes worth checking against gate doctrine

Shipped 2026-08-03→07, **after** most of the repo's stamps. Each needs a decision; none is assessed here.

- **Marketplaces can distribute a plugin as a zip archive**, new `archive` source, HTTPS with optional
  SHA-256 pin. A `marketplace.json` source type this repo's marketplace doctrine does not mention and
  `validate-plugins.sh` has never seen.
- **Auto mode becomes the default permission mode on Aug 14** for Pro/Max/Team. Four days out at audit
  time; touches every permission-mode assumption.
- **Worktree isolation now blocks Bash commands and git redirects** reaching the main checkout, in every
  session type and in subagents — adjacent to the `guardrails` plugin's territory.
- **PreToolUse auto-allow hooks no longer bypass tool restrictions** in internal side tasks such as
  summaries and compaction. Hook doctrine should confirm it never relied on the old behavior.
- **`/fork` now makes its changes in its own worktree.**
- **Plugins installed from `/plugin` activate in the current session when safe**, otherwise
  `/reload-plugins`.
- **Ultraplan removed**, including the `/ultraplan` command and the `ultraplan` keyword. One repo
  reference survives, in `docs/topics/context-engineering-claude-5/design/official-corroboration.md:355`
  — inside a topic-design doc, i.e. a record of what was true when written, so left alone.
- **`/review` is now an alias of `/code-review`**, and `/code-review` with no effort level reuses the
  last level typed.

## A gate defect, found by using the gates

`plugins/skill-quality/scripts/check-skill.sh` (`INTERNAL_DIRS`, ~line 357) extracts any bare
`context/…`, `reference/…`, `templates/…` path from a `SKILL.md` — **including paths in prose and inline
code, not only link targets** — and resolves each against the **citing** skill's own directory. Citing a
sibling skill's file by its natural relative name therefore fails with "no such file under the skill
dir" while the file plainly exists. The working form is `${CLAUDE_PLUGIN_ROOT}/skills/<other>/…`.

Hit twice while building `mutation-testing` (#2161). Not a doc-currency issue — a usability defect in a
gate. Either the convention needs stating where authors meet it, or the error needs to name the
sibling-skill case. Worth an issue of its own.

## Method note for whoever runs a gate locally

Two local runs gave false confidence during #2161, both from *how* the gate was invoked:

- `check-skill-portability.sh` with `--paths` over a hand-filtered list missed a file the CI base-ref
  form caught.
- `check-changelog-parity.sh --check-bump` run before anything was committed passed **vacuously** — it
  compares committed state, and nothing was committed.

**Run gates the way CI runs them**: base-ref form, against a committed tree.

## Not attempted

- Pass (b), doctrinal currency.
- `docs/topics/**`, `plugins/songwriting`, and prose asides — out of scope for a gate audit, and
  topic-design docs are records of what was true when written rather than live claims.
- The remaining ~66 cited pages whose claims are not enforced by a gate or check skill.
