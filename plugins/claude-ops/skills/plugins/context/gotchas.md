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

## Concurrency / TOCTOU

`fleet-state.sh`'s output is a snapshot. A background `autoUpdate` sweep (random delay up to ten
minutes after session start) or a concurrent Claude Code session can mutate installed/enabled state
between when you read it and when you act on it. Re-read state immediately before each mutating
step (`sync.md`'s "Concurrency" section, `converge.md` Step 4) rather than driving a whole multi-step
sync off one snapshot taken at the start. When a mutation's actual result doesn't match what the
snapshot predicted, that's this race — note it in the report, don't treat it as a bug to chase.

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

## This host's `jq` build CRLF-terminates its output

Discovered empirically while implementing `fleet-state.sh` (Windows/MSYS `jq`): even single-line
compact JSON output ends `\r\n`, not just `\n`. `$(...)` command substitution strips only the
trailing `\n`, so a stray `\r` survives at the end of a captured value and corrupts it once
re-embedded in another `--argjson` argument (`jq: invalid JSON text passed to --argjson`). Any new
script in this skill that shells out to `jq` and captures its output should route every call through
the same `jq() { command jq "$@" | tr -d '\r'; }`-style wrapper `fleet-state.sh` already uses —
don't rediscover this the hard way in a second script.
