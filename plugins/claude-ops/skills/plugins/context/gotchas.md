# Gotchas

Failure modes this skill is specifically built to avoid, and what breaks if the safeguard is
bypassed. Underlying facts are in [scope-semantics.md](scope-semantics.md) — this file is the
"here's what goes wrong" companion, not a restatement.

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
is expected, common, and not itself something to "fix" silently. `fleet-state.sh`'s `versionsMatch`
field is what separates that benign case from a real, actionable version skew — see
scope-semantics.md. Never report a raw `divergences[].length` count; always filter to
`versionsMatch == false` first, or the report overstates drift with entries that need no action.

## Internal-schema drift — fail loud, never guess

`installed_plugins.json` and `known_marketplaces.json` are Claude Code's *internal* state — not a
published, versioned contract. `fleet-state.sh` validates their top-level shape
(`{plugins: {...}}` / a JSON object) before trusting them, and exits 2 with a clear message on a
mismatch rather than silently emitting an empty or wrong report. If a future Claude Code version
changes this shape, that exit-2 failure is the signal to re-verify against a live install (not
training-data recall) and update the parser — never widen the shape check to "whatever doesn't
crash the script."

## Captured values on Windows carry `\r` — strip it before embedding in any command or JSON

Discovered empirically while implementing `fleet-state.sh` (Windows/MSYS `jq`): even single-line
compact JSON output ends `\r\n`, not just `\n`. But this is **not a `jq`-only hazard** — *any* value
captured on Windows/MSYS (a native `python` `print(...)`, a PowerShell interop line, `git config`
output, a CRLF-terminated file read) can arrive with a trailing `\r`. `$(...)` command substitution
strips only the trailing `\n`, so the `\r` survives at the end of the captured value and corrupts it
once it is either:

- re-embedded in another `jq --argjson` argument (`jq: invalid JSON text passed to --argjson`), or
- **embedded in a constructed `claude plugin` id.** A `<name>@<marketplace>\r` id is passed with the
  full id present, yet the CLI reports `Plugin "<name>" not found` — the marketplace suffix is
  silently corrupted. The symptom is byte-identical to the bare-name gotcha above and actively
  misdirects diagnosis (the full id *was* passed). Observed live: extracting ids via
  `python -c "print(...)"` on Windows gave every id but the last a trailing `\r`, and 57/58
  `claude plugin update` calls failed this way.

Route every `jq` call through the `jq() { command jq "$@" | tr -d '\r'; }`-style wrapper
`fleet-state.sh` already uses, **and** strip `\r` (`tr -d '\r'`, or `${var%$'\r'}`) from every value
captured from any other source before embedding it in a `claude plugin` command or a JSON argument.
Don't rediscover this the hard way in a second script.
