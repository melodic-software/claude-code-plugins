# Plugin-data report keying, retention, and overwrite

Version: 1.0.0
Last updated: 2026-08-12

A marketplace-wide contract for **how a plugin names what it writes under `${CLAUDE_PLUGIN_DATA}`** —
the key, the retention shape, and whether a write may overwrite. It does not govern *what* may live
there; that is `docs/MIGRATION-PLAYBOOK.md`'s seam 4 (`${CLAUDE_PLUGIN_DATA}` for machine state
only), and this convention sits underneath it.

## The harness fact this exists for

[Plugins reference](https://code.claude.com/docs/en/plugins-reference), § *Persistent data
directory*, fetched 2026-08-12:

> The `${CLAUDE_PLUGIN_DATA}` directory resolves to `~/.claude/plugins/data/{id}/`, where `{id}` is
> the plugin identifier with characters outside `a-z`, `A-Z`, `0-9`, `_`, and `-` replaced by `-`.

**The formula is keyed to the plugin identifier and nothing else.** No project, no checkout, no
worktree, no session. A plugin that writes a fixed filename there has one such file *per machine*,
shared by every repository the operator works in.

Same page, on lifetime:

> The data directory is deleted automatically when you uninstall the plugin from the last scope where
> it is installed. … The CLI deletes by default; pass `--keep-data` to preserve it.

So anything stored there is also **uninstall-fragile**, which is an argument against unbounded
per-project trees and for a bounded shape.

Upstream is *silent* on naming, not permissive — reports and audit history are not among the
documented intended uses ("installed dependencies such as `node_modules` … generated code, and
caches"). There is nothing to wait for; this is ours to decide.

## The two failure modes, which need different fixes

Distinguish them before choosing a shape. Conflating them is how a fix ships that closes one and
leaves the other open.

| | **Collision** | **Overwrite** |
|---|---|---|
| What happens | Two projects share one path | Two runs of **one** project share one path |
| Symptom | Project B is served project A's content | Yesterday's artifact is gone |
| Fixed by | **Keying** the path by project | **Retention** — one file per run, or an appended history |
| Severity | Higher when the artifact is **read back** | Data loss only |

**Keying is not optional; retention is a judgment.** A non-destructive history closes overwrite and
does nothing about collision: serving *the newest* report is not the same as serving *this project's*
report. A writer whose artifact is only ever written (a cache, a scratch file) may key and stop
there.

## Rule 1 — key every write by project identity [SPEC]

A plugin writing under `${CLAUDE_PLUGIN_DATA}` puts a **state key** between the plugin's own
namespace and the filename:

```
${CLAUDE_PLUGIN_DATA}/<component>/<state-key>/<filename>
```

**`<state-key>` = `<repo-identity>/<worktree-discriminator>`.** The scheme originated in the
`claude-config:audit-pass` skill and is specified in full **here** — this doc is the definition every
adopter derives from, that skill included:

- **`repo-identity`** — the **first configured remote** URL (not necessarily one named `origin`)
  normalized to `host/owner/repo`, lowercased, scheme/credentials/`.git` stripped. No remote →
  `local/<sha256 of the canonicalized repo root, 12>`. Not a repository at all →
  `nonrepo/<sha256 of the working directory, 12>`.
- **`worktree-discriminator`** — `sha256` of the canonicalized worktree root, truncated to 8. Two
  worktrees of one repository legitimately hold different content and must not share an artifact.

**Do not mint a second scheme.** A shared implementation ships as `lib/state-key.sh`, byte-identical
across the plugins that carry it and registered in `scripts/cross-plugin-source-registry.txt`.
Adopting is one line:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"
```

### 1a — derive the key by running commands, never by testing a placeholder [SPEC]

Do **not** write the path as a condition over `${CLAUDE_PROJECT_DIR}` "when set". That placeholder is
substituted inline in skill and agent content before the model sees the file, so the literal token
never appears and the condition is not the model's to evaluate. The key comes from commands the run
actually executes.

### 1b — a key is a path segment, so validate it like one [SPEC]

A remote URL is arbitrary text that becomes **directory components**. A remote of `../../../etc`
walks the artifact out of the plugin's namespace. Accept an identity only in the shape the scheme
means — segments of `[a-z0-9._-]`, each starting alphanumeric — and **hash anything else** so it
still keys deterministically and still stays inside the namespace. This is not hypothetical: an
unvalidated version of exactly this derivation was caught normalizing a report path outside its
skill's namespace during review.

### 1c — the "looks scoped but isn't" case, named so it is not repeated

`plugins/bug-report/skills/write/SKILL.md:97` keys on the **kebab-cased basename of the project
root**:

> `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/` … The plugin data directory is per-plugin, not
> per-project — without the slug, Step 2's duplicate scan would match another repository's report on
> the same symbol.

The line states the hazard correctly and then picks a colliding key: two same-named checkouts — a
fork, a same-named worktree, `~/work/api` and `~/oss/api` — share one slug directory, and the
duplicate scan cross-matches between them. It escapes *overwrite* only because its filenames are
timestamped. `plugins/claude-config/skills/unhobble/SKILL.md:53-62` names the same insufficiency in
prose: "`${CLAUDE_PLUGIN_DATA}` is machine-global, so two checkouts sharing a basename…".

**This is recorded here as the worked example, not filed as a `bug-report` defect.** A basename is
not project identity. Nothing here obliges an immediate migration of an existing keyed-by-basename
writer; it obliges the next one not to repeat it.

## Rule 2 — choose retention by whether the artifact is read back [SPEC]

| The artifact is… | Shape | Why |
|---|---|---|
| Written and never read by the plugin | `<state-key>/<name>` — a rolling latest is fine | Nothing can be served wrongly |
| Read back and served to the operator | `<state-key>/<name>` **and** the read must derive the same key | Serving the newest ≠ serving this project's |
| A trend or a history | one file per run **plus** an appended line | A same-day rerun must not erase the earlier point |

The reference implementation of the third row is `plugins/machine-health/skills/audit/SKILL.md`, steps
6 and 7: `<OutputBase>/reports/health-<UTC-timestamp>.md` — "one file per run, so a same-day rerun
does not overwrite the earlier report" — plus `<StateBase>/state/latest.json` and one appended line in
`<StateBase>/state/history.jsonl`, "the trend source of truth". Note it is *not* an adopter of rule 1:
its roots are passed in explicitly by the caller rather than keyed, for a reason that file states — a
subprocess can inherit another plugin's `CLAUDE_PLUGIN_DATA` value. Cited here for retention shape
only.

**A rolling latest is a legitimate choice, and it must be a stated one.** `claude-memory:audit` keeps
`last-audit.md` deliberately: the report is a working artifact, not a series. Say so where the path is
defined, so a reader can tell a decision from an oversight.

## Rule 3 — never serve an artifact you cannot attribute [SPEC]

This is the rule that makes rule 1 worth having, and it governs **migration** as much as reads.

An artifact written under an older unkeyed layout has **no project segment**, so nothing records which
repository produced it. It therefore cannot be adopted into any project's key — doing so invents an
attribution, which is precisely the defect keying removes.

- Missing at the derived key → say *"no artifact for this project"* and offer to produce one. Do not
  fall back to an unkeyed path to find something.
- A legacy unkeyed file is present → name its path to the operator as a leftover they may delete.
  Do not read it, do not move it under a key, do not compute anything from it.

The last clause matters where a writer *derives* from the prior artifact. `audit-instructions`'s
report header carries a per-surface token delta "versus the previous catalog version"; under a
colliding path that computation runs against another project's surface set and prints a **number**
rather than declining. A silently wrong figure is worse than a missing one.

## Rule 4 — state the uninstall fragility where the artifact is the only copy

Uninstalling from the last scope deletes the whole data directory unless `--keep-data` is passed. A
component whose sole durable output lives there should say so once, near the path, rather than
letting an operator discover it. Keying does not change this; it multiplies it, since a keyed tree
holds every project's artifact under the same deletable root.

## Adoption

| Writer | State |
|---|---|
| `claude-config:audit-pass` | Keyed since it shipped (`runs/<state-key>/<run-id>/`); this scheme's origin |
| `claude-config:audit-prompting-postures` | Keyed (#2250) |
| `claude-config:audit-instructions` | Keyed, plus rule 3 on the delta computation |
| `claude-memory:audit` | Keyed on write **and** on both read paths (`report`, `fix`), plus rule 3 |
| `bug-report:write` / `bug-report:setup` | Keyed by project-root **basename** — rule 1c's worked example; not migrated |
| `claude-config:unhobble` | Different solution, same problem: keys by `<experiment-id>` whose basename is *a label*, and records the canonical checkout identity (absolute worktree path, and the origin URL when one exists) **in the manifest**, verifying it before every later phase. Verification instead of a keyed path; acceptable because the artifact is never *served* — a mismatch aborts and names the conflicting path |
| `docs/conventions/topic-docs/` non-repo fallback | Keyed by **topic slug**, not project (`${CLAUDE_PLUGIN_DATA}/topic-docs/<slug>/`, the non-interactive branch when no project root resolves) — an instance of the gap, recorded here rather than silently declared conformant |
| `machine-health:audit` | Not keyed — roots are passed in by the caller, deliberately, per that skill's own inherited-variable hazard. Cited above for retention shape only |

## Related

- `docs/MIGRATION-PLAYBOOK.md` seam 4 — what may live under `${CLAUDE_PLUGIN_DATA}` at all. This
  convention governs naming beneath that.
- `docs/conventions/topic-docs/` — tier placement, including the `${CLAUDE_PLUGIN_DATA}` machine-state
  tier.
- #1568 — the `${CLAUDE_*}` substitution-scope question. Rule 1a stands on the plugins reference's own
  substitution table for skill and agent *content*, and deliberately does not depend on the
  unsettled question of whether that extends to bundled spoke files loaded on demand; a component
  whose spokes might not substitute derives in `SKILL.md` and passes the resolved path down.
