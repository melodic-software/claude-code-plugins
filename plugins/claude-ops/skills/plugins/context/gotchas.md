# Gotchas

Failure modes this skill is specifically built to avoid, and what breaks if the safeguard is
bypassed. Underlying facts are in [scope-semantics.md](scope-semantics.md) — this file is the
"here's what goes wrong" companion, not a restatement.

Every claim here about Claude Code's or the `claude` CLI's own behaviour names the version it was
observed on. Where a section carries no version of its own, it was last checked against **Claude
Code 2.1.240**. **Recheck trigger:** any minor-version bump touching the plugin CLI, plugin
loading/caching, or `userConfig` substitution — a date alone is not a trigger.

## `claude plugin update <name>` (bare) fails "Plugin not found" — always pass the full id

**Verified empirically** (`claude plugin update <name> -s user` → `Plugin "<name>" not found`;
`claude plugin update <name>@<marketplace> -s user` → succeeds, same scope, same machine, back to
back). A bare plugin name is not enough for `update` even when it's unambiguous on this machine —
always pass the fully-qualified `<name>@<marketplace>` id, exactly as `fleet-state.sh`'s `installed[]`
and `catalog`-joined ids already are. `sync.md`'s Step 3 and `converge.md`'s CLI examples already use
the fully-qualified form for this reason — never shorten an id to the bare name when constructing an
actual `claude plugin update|install|uninstall|enable` command, even for readability in a report.

Caveat — same symptom, different cause: a `Plugin "<name>" not found` failure with the
**fully-qualified** `<name>@<marketplace>` id passed is NOT this gotcha. On Windows that is almost
always a trailing `\r` silently corrupting the marketplace suffix (`<marketplace>\r`) — see
"[Captured values on Windows carry `\r`](#captured-values-on-windows-carry-r--strip-it-before-embedding-in-any-command-or-json)"
below. Check the id for a trailing CR before concluding the id form is wrong.

## Trusting `plugin list` / `plugin details` for "what's loaded here"

Both show the highest installed version across every scope, not the cwd-effective one. Reporting a
plugin as "current" based on their output can be wrong for any project with its own project/local
scope pin. Always derive effective-version claims from `fleet-state.sh`'s `currentProject` flag and
scope precedence, never from `list`/`details` text.

## Native-Windows `projectPath` vs Git Bash `$PWD`

`installed_plugins.json` stores `projectPath` in native Windows form (`D:\repos\...`); a Bash-tool
`$PWD` reads POSIX form (`/d/repos/...`). A naive string-equality check between the two silently
never matches on Windows — the in-repo detection this skill's primary value depends on (Step 2 of
`sync.md`) would quietly no-op, and nobody would notice because the *rest* of sync (marketplace
refresh, user-scope sweep) still runs and still produces *a* report. `fleet-state.sh` avoids this by
routing both sides through `hook::normalize_path` (from the plugin's own `hooks/hook-utils.sh`
copy) before comparing — empirically verified to fold both representations to the identical
canonical string. Never hand-roll a separate path comparison anywhere else in this skill; always go
through the `currentProject` field `fleet-state.sh` already computed.

## A subdirectory install is invisible to this skill — `currentProject` cannot see it

Distinct from the spelling mismatch above: here both sides are spelled correctly and still never
match, because they name *different directories*. Per
[scope-semantics.md](scope-semantics.md), `claude plugin install -s project` records `projectPath` as
the **literal cwd** — verified on Claude Code 2.1.228, where installing from
`<checkout>/nested/subdir` recorded that subdirectory and created its own
`nested/subdir/.claude/settings.json`. `fleet-state.sh` resolves the project root to the **checkout
root** instead.

So a plugin installed at project scope from anywhere below the checkout root gets a `projectPath`
that `fleet-state.sh` will never match for `currentProject`: `currentProject` stays `false`, so
`sync`'s Step 2 never updates it — while `converge` can still target a divergence row for the same
id when another scope record exists, because `fleet-state.sh` groups every installed record by id
without filtering on `currentProject`. The subtree install still loads for anyone working there. The
failure is silent for sync/update in the same way the spelling mismatch is, and the same report
still gets produced.

This is a genuine gap, not a parser bug to fix by widening the comparison: matching a record against
every ancestor of the checkout root would claim project state the skill has not established is
project state. Treat an unexplained "installed but never converges" report as a candidate for this,
and confirm by reading the record's `projectPath` directly.

## Concurrency / TOCTOU

`fleet-state.sh`'s output is a snapshot. A background `autoUpdate` sweep (random delay up to ten
minutes after session start) or a concurrent Claude Code session can mutate installed/enabled state
between when you read it and when you act on it. Re-read state immediately before each mutating
step (`sync.md`'s "Concurrency" section, `converge.md` Step 4) rather than driving a whole multi-step
sync off one snapshot taken at the start. When a mutation's actual result doesn't match what the
snapshot predicted, that's this race — note it in the report, don't treat it as a bug to chase.

The catalog shifts the same way. A marketplace refresh landing mid-session — a background
`autoUpdate` sweep or a concurrent session's manual update — rewrites the marketplace's own
`marketplace.json` and moves `known_marketplaces.json`'s `lastUpdated` forward, so two reads of the
catalog within one session can legitimately disagree on plugin count and membership. Consequence:
comparing `fleet-state.sh`'s catalog against a separately-read raw `marketplace.json` is **not** a
valid staleness or correctness check — a mismatch is as likely to be this race as a defect, and
chasing it as an enumeration bug wastes the session. Compare only within one `fleet-state.sh`
snapshot, and when two reads must be compared, treat a difference as a re-read signal rather than
evidence about either read.

## Dual-scope divergence is normal, not a defect

A project pinning an older version at `project` scope while your personal `user` scope has moved on
is expected, common, and not itself something to "fix" silently. The rule that separates that benign
case from an actionable one — filter on `versionsMatch == false`, never report a raw
`divergences[].length` — is defined in
[scope-semantics.md](scope-semantics.md#divergence-is-not-automatically-actionable). What goes
*wrong* when it is skipped is the point here: the report overstates drift with entries that need no
action, and routes the user to `converge` for rows it would decline to change.

## A `projectPath` can outlive its directory

A project/local install record keeps the `projectPath` it was created with. Delete the directory and
the record stays — nothing in the `claude plugin` CLI reaps it (verified on Claude Code 2.1.240:
`prune` is a *dependency* axis, and its own `-s project` has the same no-path-flag limitation that
makes these records unreachable in the first place). Ephemeral checkouts turn this from an edge case
into a bulk one: a throwaway worktree with a dozen project-scope installs strands a dozen records the
moment it is removed, and every one of them still shows up as installed state.

What breaks: `converge` constructs every project/local command as
`(cd "<projectPath>" && claude plugin …)`, so a row naming an absent directory yields a command that
cannot execute. Routing such rows into the actionable Divergences count hands the user a list of
guaranteed failures.

`fleet-state.sh` annotates each project/local record with `projectPathPresent` so the condition is
visible, and `SKILL.md` reports those rows in their own section, out of the Divergences count.

**Do not turn that annotation into a filter, and do not call an absent path dead.** `[ -d ]` returns
false for an unmounted volume, an offline network share, and an unplugged external drive just as
readily as for a deleted worktree — and per
[scope-semantics.md](scope-semantics.md), two `git worktree` checkouts of one repo pin
independently, which makes worktree paths exactly the population most likely to look dead while
being perfectly recoverable. Suppressing a row on a directory test would hide real drift from anyone
whose repos do not live on a permanently-attached local disk. Annotate; never suppress.

## A spoke file never receives `${user_config.*}` substitution

Claude Code substitutes `userConfig` values when it renders the **skill**. A context file under
`context/` reaches the model as a later file read — plain bytes, no substitution pass. Write
`${user_config.install_new}` in a spoke and it arrives as that literal token, with **no error and no
warning**; the value simply never appears, and a step branching on it branches on a placeholder.

This is why `SKILL.md` holds the `install_new` render and `sync.md` Step 4 branches on *that* line
rather than on its own prose. Verified empirically: `context/sync.md` on disk shows the raw
`${user_config.install_new}` token in the same session where `SKILL.md`'s render shows the
configured value. Nothing enforces this — a future spoke that inlines such a token fails silently,
so it is a review-time rule, not a checkable one.

## `sync` updates the plugin that provides `sync`

Step 3 sweeps every user-scope install, and `claude-ops` is one of them. When that update lands
mid-run, `${CLAUDE_PLUGIN_ROOT}` keeps resolving to the version loaded at session start, so every
remaining step — including every later `fleet-state.sh` call — executes the **pre-update** script
while the report describes a version the user now has installed but is not running. Per
`code.claude.com/docs/en/plugins-reference` (fetched 2026-08-22): "When a plugin updates
mid-session, hook commands, monitors, MCP servers, and LSP servers keep using the previous
version's path." Observed on **Claude Code 2.1.240**: a `sync` run's Step 3 moved the `claude-ops`
install record to 0.35.3, while the session went on rendering the 0.33.2 skill it had loaded at
session start — and every `fleet-state.sh` call for the rest of that run came from the 0.33.2 tree.

Not a crash: per the same page, Claude Code "marks the previous version directory as orphaned and
removes it in a background sweep roughly 14 days later. The grace period lets concurrent Claude Code
sessions that already loaded the old version keep running without errors" — so the old script stays
readable to the end of the run. And the
*resolution* half is already handled — `fleet-state.sh`'s default-marketplace resolver carries a
version-agnostic fallback whose comment names this exact scenario, which is why the bare
(no `--marketplace`) path keeps working after the bump. Keep the two in step: if that fallback is
ever changed, this gotcha and the resolver comment both describe it.

What is missing without a deliberate report row is any *statement* of it — see `SKILL.md`'s
self-update row.

## Internal-schema drift — fail loud, never guess

`installed_plugins.json` and `known_marketplaces.json` are Claude Code's *internal* state — not a
published, versioned contract. `fleet-state.sh` validates their top-level shape
(`{plugins: {...}}` / a JSON object) before trusting them, and exits 2 with a clear message on a
mismatch rather than silently emitting an empty or wrong report. If a future Claude Code version
changes this shape, that exit-2 failure is the signal to re-verify against a live install (not
training-data recall) and update the parser — never widen the shape check to "whatever doesn't
crash the script."

## Captured values on Windows carry `\r` — strip it before embedding in any command or JSON

Discovered empirically while implementing `fleet-state.sh`: the native-Windows `jq` binary opens
stdout in **text mode**, so every `\n` it writes becomes `\r\n`. This is **not a `jq`-only
hazard** — *any* value produced on Windows/MSYS (a native `python` `print(...)`, a PowerShell
interop line, `git config` output, a CRLF-terminated file read) can arrive with a trailing `\r`.

**Which capture is actually corrupted depends on how you read it** (verified on jq 1.8.2 / MSYS
bash 5.3.9 — get this wrong and you will chase the wrong suspect):

- `x=$(… )` **single-line** output — *clean*. Command substitution strips the trailing `\r\n` as a
  unit, not just the `\n`. A one-value capture is safe, and that is a bash-side property, so it
  holds whatever produced the value.
- `x=$(… )` **multi-line** output — *every line but the last carries `\r`*, because only the final
  terminator is stripped. **This all-but-last pattern is the diagnostic signature**: if the last
  item in a batch is the only one that worked, stop looking for a logic bug and check for `\r`.
- `mapfile -t` / `readarray -t` — *every element carries `\r`*, including the last: `-t` removes the
  newline but not the CR, so there is no last-element reprieve here.
- `jq` output read back **by `jq`** (as raw input or as JSON) — *self-cleaning*. jq's stdin is
  text-mode too, so a CR it emitted is stripped again on the way back in. A jq→jq relay is
  therefore not a hazard; the danger is only jq's line output reaching a **non-jq** consumer.

`IFS=$'\n'` does **not** rescue any of these — `\r` is not the separator, it rides inside the token.

A surviving `\r` corrupts the value once it is either:

- re-embedded in another `jq --argjson` argument (`jq: invalid JSON text passed to --argjson`), or
- **embedded in a constructed `claude plugin` id.** A `<name>@<marketplace>\r` id is passed with the
  full id present, yet the CLI reports `Plugin "<name>" not found` — the marketplace suffix is
  silently corrupted. The symptom is byte-identical to the bare-name gotcha above and actively
  misdirects diagnosis (the full id *was* passed). Observed live twice, both with the all-but-last
  signature: extracting ids via `python -c "print(...)"` on Windows failed 57/58 `claude plugin
  update` calls, and a hand-written `jq -r … | while read` over `fleet-state.sh`'s JSON failed
  64/65 (#2578).

**Never hand-write an id extraction.** `fleet-state.sh --ids <selector>` emits the id list for each
`sync` step directly — one fully-qualified id per line, CR-free by construction — so the loop that
feeds `claude plugin` needs no `jq` of its own at all:

```bash
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  claude plugin update "$id" -s user
done < <(…/scripts/fleet-state.sh --ids installed-user)
```

For anything `--ids` does not cover: route every `jq` call through the
`jq() { command jq "$@" | tr -d '\r'; }`-style wrapper `fleet-state.sh` already uses, **and** strip
`\r` (`tr -d '\r'`, or `${var%$'\r'}`) from every value captured from any other source before
embedding it in a `claude plugin` command or a JSON argument. Don't rediscover this the hard way in
a second script.
