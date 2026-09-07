# Topic-docs placement — where review findings land

How `/review:quality-gate`, `/review:fanout`, and `/review:audit-enforceability` resolve where
review reports and enforcement-rung proposal stubs land in a consuming repo. All three skills read
this one document; none bakes its own paths.

Implements the topic-docs convention:
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/topic-docs/README.md#runtime-guards>.
The contract owns the tier table, concern-file schema, slug spec, and lifecycle; this document binds
this plugin's artifacts to it.

## What this plugin writes

**Memory tier only, concern-scoped.** A review report's axis is the **branch**, not a topic, so
reports sit under the memory root's reserved `reviews/` name rather than inside a topic slice:

| Artifact | Location (default) |
|---|---|
| `quality-gate` findings | `.work/reviews/<branch-slug>/<UTC-timestamp>-<mode>.md` — never committed |
| `fanout` ranked reports | `.work/reviews/<branch-slug>/<UTC-timestamp>-<topic>.md` — never committed |
| `fanout` consumption records | `.work/reviews/<branch-slug>/<UTC-timestamp>-fix-pass-applied-<sha256-12>.md` — never committed |
| `audit-enforceability` proposal stubs | `.work/enforceability/<branch-slug>/<rank>-<rung>-<slug>.md` — never committed |

Reports are process output that nothing outside this plugin enforces against, which is what makes
them memory-tier by the convention's placement question. One artifact is read back: the `fix`
action's consumption record is the ledger that bounds its next merge set, so losing one re-injects
already-applied findings — durability inside the lane matters even though nothing downstream gates
on it. They are therefore lane-local (contract
≥ 2.0.0): a sibling worktree or cloud clone never sees them. Findings that must cross lanes
graduate through the work-item tracker — the contract's cross-lane index — as tickets that point,
never as pasted report bodies.

## Resolution (the contract's five-rung order, earlier wins)

1. `.claude/topic-docs.yaml` present → its `memory_dir`: `<memory_dir>/reviews/<branch-slug>/`.
2. A review-artifacts location declared in the consumer's `CLAUDE.md` / `.claude/rules` → use it,
   and offer to persist it into the concern file (prose is an inference source, not the runtime
   authority).
3. An existing conforming layout inferred from the repo (a self-ignoring memory root holding
   review reports) → confirm with the user, persist to the concern file.
4. Ask once — one question, recommended option first; persist the answer to the concern file.
5. The documented default: `.work/reviews/<branch-slug>/`.

Only rung 1 and rung 5 compose `reviews/<branch-slug>` themselves. Rungs 2–4 yield whatever location
the consumer declared, inferred, or chose — **resolve the home, never assume its shape.** A skill
that hardcodes the default's shape reads or writes a directory the other side never touched, and the
fanout `fix` action's failure mode for that is a clean empty-set STOP indistinguishable from "no
findings".

## Resolution for the `enforceability` concern (the same five-rung order)

Enforcement-rung proposal stubs sit under their own reserved first-level concern name, resolved
through the same ladder and the same memory root:

1. `.claude/topic-docs.yaml` present → its `memory_dir`: `<memory_dir>/enforceability/<branch-slug>/`.
2. A location for enforcement-proposal artifacts declared in the consumer's `CLAUDE.md` /
   `.claude/rules` → use it, and offer to persist it into the concern file.
3. An existing conforming layout inferred from the repo → confirm with the user, persist to the
   concern file.
4. Ask once, recommended option first; persist the answer to the concern file.
5. The documented default: `.work/enforceability/<branch-slug>/`.

As with `reviews/`, only rungs 1 and 5 compose `enforceability/<branch-slug>` themselves, and only
at those two rungs is the stub home literally a sibling of `reviews/`. Rungs 2 to 4 yield whatever
location the consumer declared, inferred, or chose, and persisting at those rungs is ask-gated;
a non-interactive context takes the cited non-interactive collapse below rather than asking.
**Resolve the home, never assume its shape.**

At every rung the stub writer is handed BOTH resolved homes and refuses a stub home that is the
reviews location or sits under it, and equally a stub home inside the input findings file's own
directory. That fence is what keeps a stub out of the `fix` action's scan whatever the two ladders
resolve to, including the rungs where the two homes are not siblings at all.

No other binding in this plugin carries two ladders today. The precedent for a concern claiming
its own reserved first-level name with its own ladder is the enforcement-surface audit's
`overengineering/<branch-slug>/`.

**Non-interactive / forked mode.** Rungs 2–4 can require asking the user or persisting config. A
context that can do neither — a forked subagent, a dispatched worker, a headless run such as
`fanout`'s `fix --yes` — follows the contract's "Non-interactive / forked mode" section, which is
contract-owned and cited here rather than redefined.

Both skills review a git diff; with no git repo there is nothing to review, and the skills stop
before any write — the convention's no-project-root fallback surface never comes into play here.

## Branch slug and timestamps

- `<branch-slug>` — the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character
  replaced by `-`. This is the branch axis, deliberately distinct from the convention's topic-slug
  form: the mapping is lossy (`feature/foo` and `feature-foo` collide), which the fanout fix action
  compensates for with its `branch:` frontmatter check.
- Timestamps — ISO-basic UTC `YYYYMMDDTHHMMSSZ` (`date -u +%Y%m%dT%H%M%SZ`), colon-free and
  Windows-safe; lexical sort equals chronological sort.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory
  root** (whatever `memory_dir` names — never a hardcoded `.work`) contains a `.gitignore` with
  `*`, creating it (announced) when absent — fresh clones heal on first write. Once per session,
  per the contract. The contract also defines **invalid roots at which the guard does not run**;
  they are enumerated in its
  [Runtime guards](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/topic-docs/README.md#runtime-guards)
  section and deliberately not listed here, so this binding cannot drift from them.
- No skill in this plugin ever edits the consumer's root `.gitignore`.
