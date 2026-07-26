# Converge — explicit scope consolidation

`converge` is the **only** action that can touch a committed `.claude/settings.json`. It never runs
implicitly from `sync` — `sync`'s report only names the `converge` command; the user runs it
explicitly.

## Autonomous-session abort (run this check FIRST, before any preview work)

`converge` is destructive-tier (it can uninstall a scoped plugin install and rewrite committed
settings). Per this repo's existing convention (`repo-hygiene`'s `clean` skill, preflight §1.5):
**abort immediately** when the session is autonomous — `CLAUDE_CODE_REMOTE` set, or the invocation
arrived via `/loop` or `/schedule` — since no human is present to receive an `AskUserQuestion`
confirm. Fail closed when the context is genuinely ambiguous (uncertain whether a human is present):
treat it as autonomous and abort. Report why, and that `converge` can be re-run interactively.

## V1 scope: version divergence only

`converge` resolves entries in `fleet-state.sh`'s `divergences[]` with `versionsMatch: false` —
scopes disagree on version. It does **not** currently resolve, and cannot even detect, an
enable-state mismatch (a plugin `true` in one scope's `enabledPlugins` and `false` in another) —
that needs comparing each scope's *raw* `enabledPlugins` map, which `fleet-state.sh` doesn't expose
today (only the merged effective value, in `enabled`). This is a genuine blind spot, not a deferred
fix: never claim the report surfaces an enable-state mismatch, and never hand-parse the settings
files directly to work around the gap — the fix is extending `fleet-state.sh` to expose the raw
per-scope maps, not something this skill's prompt layer can paper over.

## Step 1 — Detect

Call `fleet-state.sh` (default marketplace, named one, or the current invocation's target) and take
`divergences[]` filtered to `versionsMatch: false`.

## Step 2 — Preview per-plugin intent

For each actionable divergence, first find which of its `scopes[]` holds the **highest version**
(compare `scopes[].version` — semver dotted-numeric compare, not string/lexicographic). Never choose
a strategy from scope identity alone ("does a user entry exist") without this comparison first —
`fleet-state.sh` only proves the scopes *disagree*, never that `user` scope is the newer one. A repo
pinning `project: 0.9.0` against a stale `user: 0.8.0` has the project pin as the newest version
present; uninstalling it to "fall through to user scope" would regress the effective loaded version,
the opposite of bringing the fleet current.

Then decide the consolidation strategy:

- **`user` scope holds the highest version** → the default strategy is to make the *project/local*
  scope fall through to it: `claude plugin uninstall <id> -s project` (or `-s local`) removes the
  redundant lower-precedence pin, and scope precedence (local > project > user) means the project
  now loads whatever `user` scope has — always current from here on without a standing project pin.
- **A `project`/`local` scope holds the highest version** (including when there's no `user`-scope
  entry at all — only multiple `project`/`local`-scope pins across different repos) → the default
  strategy is to bring every lagging scope, `user` scope included, up to that version:
  `claude plugin update <id> -s <that scope>` for each scope below the highest.

**Every `project`/`local`-scope command targets its row's own `scopes[].projectPath`, never the
current working directory.** `-s project`/`-s local` have no path/target flag — the CLI always
operates on the *current directory's* `.claude/settings*.json`. A divergence row can legitimately
belong to a different repo than the one this session is standing in (the "elsewhere on this machine"
rows a bulk report collapses) — never construct the proposed command as a bare
`claude plugin uninstall|update <id> -s project`, only as
`(cd "<scopes[].projectPath>" && claude plugin uninstall|update <id> -s project)`. Presenting or
running the bare form for a row whose `projectPath` isn't the current directory would silently
mutate — or fail against — the wrong repo's settings.

Present every plugin's proposed strategy and exact CLI command(s) before running anything — do not
batch-apply. Per Brief Decision 6 (V1): confirm **every** pin individually, even when many plugins
share the same strategy — do not infer consent from one confirm to the next.

## Step 3 — Confirm

Use `AskUserQuestion` per plugin (or a clearly-enumerated batch the user can approve/override/skip
per row — never a single blanket "yes to all"). Options per plugin: apply the proposed strategy,
choose the other strategy, or skip this one.

## Step 4 — Execute

Run only the confirmed commands, one plugin at a time. Re-read `fleet-state.sh` state immediately
before each mutation (per `sync.md`'s concurrency note) — do not act on a snapshot taken during
Step 1 if meaningful time has passed or another mutation already landed.

## Step 5 — Surface the resulting diff

After all confirmed mutations run, `git diff` (or the equivalent status check) any project's
committed `.claude/settings.json` that `-s project` mutations may have touched. Per
[scope-semantics.md](scope-semantics.md), a plain `claude plugin update -s project` does **not**
write committed settings — but `claude plugin uninstall -s project` (this action's actual mechanism)
can remove an `enabledPlugins` entry from it. Show the diff; never commit it. The user reviews and
commits (or discards) it through their own normal git workflow.

## Non-interactive execution

`-y` only skips `uninstall`'s `--prune` confirmation — it has no effect otherwise, and this action's
`uninstall` calls never pass `--prune`. Do not add `-y` here: Step 3's per-plugin confirm is the
required gate, and `-y` would only ever bypass a different (unused) prompt, never that one.
