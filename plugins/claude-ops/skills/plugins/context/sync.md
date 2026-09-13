# Sync algorithm

## Contents

- [Execution: one script runs Steps 1 through 5b](#execution-one-script-runs-steps-1-through-5b)
- [Concurrency](#concurrency)
- [Downgrade guard](#downgrade-guard)
- [Version capture for the report](#version-capture-for-the-report)
- [Run journal](#run-journal)
- [Marketplace scoping: Steps 2–5 are the per-marketplace loop body](#marketplace-scoping-steps-25-are-the-per-marketplace-loop-body)
- [Projecting a step's id list: the shape every mutating step uses](#projecting-a-steps-id-list-the-shape-every-mutating-step-uses)
- [Step 1: Marketplace refresh](#step-1-marketplace-refresh)
- [Step 2: In-repo update (the primary value path)](#step-2-in-repo-update-the-primary-value-path)
- [Step 3: User-scope update sweep](#step-3-user-scope-update-sweep)
- [Steps 4 and 5: install and enable](#steps-4-and-5-install-and-enable)
- [Step 5b: Cache content check](#step-5b-cache-content-check)
- [Step 6: Report](#step-6-report)

`sync` is the default action: bring the effective fleet current where you stand. Every step below
is CLI-mediated: never edit `installed_plugins.json`, `known_marketplaces.json`, or any
`.claude/settings*.json` directly. `audit` runs this same sequence with every mutating call replaced
by a prediction (see SKILL.md's "Action: audit").

## Execution: one script runs Steps 1 through 5b

`scripts/sync-run.sh` is this algorithm's executable form. One invocation runs Steps 1 through 5b
for every target marketplace and prints ONE JSON digest; the model reads that digest and writes
Step 6's report from it. This file stays the normative statement of what each step does and why.
The script is bound to it, so a rule changed here is a rule changed in the script and its tests.

```bash
sync-run.sh [--marketplace <name> | --all] --journal-root <dir> \
            [--install-new all|none|ask] [--allow-downgrade]
sync-run.sh [--marketplace <name> | --all] --audit [--install-new all|none|ask]
sync-run.sh --only-install <ids> --run-dir <dir> [--marketplace <name> | --all]
```

Why a script rather than a step-per-turn transcript: every guarantee below is a property of the
ORDER and the STATUS CHECKS between calls, not of a human-readable narration between them. Running
them in one process keeps the re-read boundary, the `rc` checks, and the journal exactly where this
file puts them, and it removes the retyping error that a per-step transcript invites.

What the model still owns, because the script cannot:

- **The `install_new` policy.** The `user_config.install_new` placeholder substitutes only when Claude Code
  renders SKILL.md; a `context/*.md` spoke is read raw. SKILL.md's "Configured value" line is the
  rendered value, and the model passes it as `--install-new`. On `ask` with a non-empty install gap
  the script reports the gap and STOPS before Step 4, because only the model can run the batched
  prompt; it then re-enters with `--only-install <ids> --run-dir <the digest's run_dir>`, which
  performs Step 4 and Step 5 against the same run journal and re-emits the digest.
- **The journal root.** `${CLAUDE_PLUGIN_DATA}` substitutes in SKILL.md and not here, so SKILL.md
  passes the substituted path as `--journal-root`.
- **The reload guidance.** Step 6's report is rendered by the script too (`render-report.jq`
  over the digest, printed under `--render` and written to `<run_dir>/report.txt`); the model
  appends the reload guidance SKILL.md's Report section fixes and answers questions.

The digest carries, per marketplace: the refresh result, `project_root`, the marketplace's
`auto_update` and `catalog_source`, the in-repo and user-scope sweep outcomes with each pair's
direction, withheld downgrades, the install and enable gaps, what was installed and enabled, the
installs whose CLI output named userConfig options left unset
(`installed_with_unset_user_config[]`, one `{id, options_unset, required}` each), the project-scope
enable rows, the normalizer result, the cache-content counts and stale ids, the catalog regression
interval, the three-snapshot divergence split, whether the sweep updated this plugin itself, the
moved plugins whose installed build declares a monitor (`updated_with_monitors[]`, one
`{id, scope, monitors}` each, read from the record's own cache directory in the post-sweep
snapshot), and `timings`: seconds to three decimals for
`pre_refresh_read`, `marketplace_update`, `in_repo_update`, `user_sweep`, `install_enable`,
`cache_content_check`, `post_read`, and the marketplace's `total`, with `resolution` naming the
clock that produced them (`microseconds` from bash's `EPOCHREALTIME`, `nanoseconds` from a
validated `date +%s.%N`, else `seconds`). A step this invocation did not run, because `audit`
predicted it, the policy stopped before Step 4, or an `--only-install` re-entry reuses the first
pass's result, reads `null`, never 0. The digest's top-level `timings.total` times the whole
invocation, and its `cwd` is what the `In-repo:` row names when no project root resolved. Ids and
counts only: the per-file cache detail and every snapshot stay in the run directory, which the
digest names.

## Concurrency

The `claude plugin` CLI is the serialization point. There is no separate lock this skill manages.

**The re-read boundary is the STEP, not the individual mutation.** Re-run `fleet-state.sh`
immediately before each mutating step rather than mutating off a snapshot taken several steps ago; a
background `autoUpdate` sweep or a concurrent session can change installed/enabled state between
steps. Inside a step, the loop body is deliberately snapshot-driven: Step 3 reads its id list once
and then issues one `claude plugin update` per line. That is the intended design, not a violation of
the rule above. Re-reading state before each of sixty-odd calls would buy nothing: the CLI is the
serialization point, so the worst outcome of losing the race on any single id is that the id was
already updated by whoever won it, and the call degrades to a no-op.

Detecting that race is not something this step can do from CLI output, so do not pretend to. An
id reported "already at the latest version" is *equally* consistent with a benign no-op and with a
concurrent sweep having just updated it; the two are indistinguishable, and a report row that claims
to tell them apart would be inventing a signal. The one outcome that **is** distinguishable, and
worth a report row under "Action needed", is an id present in the pre-mutation snapshot that the CLI
then reports as **not installed**. That is a genuine concurrent uninstall, not this benign race.

## Downgrade guard

**A sweep never moves an install backward by default.** `fleet-state.sh` compares direction, not
just difference: when both the installed and the catalog version parse as a numeric
major.minor.patch triple and the catalog's is lower, that id is a proven downgrade, and it is
withheld from `update-candidates-user` and `update-candidates-project`, the two selectors the
sweeps loop. `downgrade-candidates` is the selector that names them, one line of
`<id>\t<scope>\t<installed>\t<catalog>` each. The guard is proof-based and fails open the same way
the equality pre-filter does: a version either side cannot parse, and a catalog version that is
unknown, is not a proven downgrade and stays a sweep candidate.

The reason is the failure it prevents. A sweep keyed on "the catalog differs from what is
installed" has no direction in it, so a catalog that moved backward turns the whole sweep into a
fleet rollback, and `claude plugin update` prints each rollback as `updated from X to Y`, which
reads as success.

**The opt-in is explicit: the `--allow-downgrade` argument to `sync`.** Without it, Step 3 leaves
every downgrade candidate untouched and reports it under `Action needed`. With it, Step 3 acts on
them and their outcomes render under `Downgraded:`, never under `Updated:`.

**Name the likely cause in the report: a marketplace source that moved backward.** A `directory`
source whose checkout is parked on an old branch, or a git source that was force-pushed or
re-pointed, both make the catalog read lower than what is installed. The remediation is to fix the
source and rerun `sync`, not to accept the downgrade, so `--allow-downgrade` belongs to the case
where the rollback is what the operator actually wants.

## Version capture for the report

SKILL.md's report requires `<id>@<marketplace>: <old> → <new>` for every updated plugin, so both
values have to be collected while the sweep runs. Neither can be reconstructed afterward.

**Retain the pre-sweep `fleet-state.sh` output for the whole run.** It is the sole source of every
`<old>`, and once Step 2/3 have run there is nothing left on the machine that still holds those
values. The pre-update versions are gone. Do not hold it in context and hope: a sweep of several
dozen mutations whose report depends on the `<old> → <new>` pairs is one context compaction away
from being unable to emit its own report. Write it to the run journal below, and read it back in
Step 6.

Three sources, in precedence order, and **never** a synthesized value:

1. **`<old>`**: that id's `installed[].version` from the pre-mutation `fleet-state.sh` re-read the
   section above already requires. It is the pre-update value by construction.
2. **`<new>`**: the `claude plugin update` call's own output for that id when it names a version.
   Capture the CLI's line as it runs; it is the only source that reflects the update immediately.
3. **`<new>` fallback**: that id's `installed[].version` from one `fleet-state.sh` re-read after
   the Step 2 + Step 3 sweep completes, diffed against the pre-sweep snapshot.

Source 3 is a fallback rather than the primary because `claude plugin update`'s own help says
"restart required to apply", and this skill has not established when the CLI writes
`installed_plugins.json` relative to that restart. If the write is deferred, the post-sweep re-read
shows the pre-update version for a plugin that did update. So: when the CLI reported an update for
an id and the post-sweep version is unchanged, report the CLI's reported value, or `<unknown>` if it
named none. Never report `<old> → <old>`, and never count that id as not-updated. A report line
that says nothing changed for a plugin that did change is worse than one that admits it cannot tell.

One data point, not a licence to drop the fallback: on Claude Code 2.1.228 a 63-plugin user-scope
sweep had all 21 CLI-reported updates already reflected in a post-sweep `fleet-state.sh` re-read, so
source 3 agreed with source 2 on every id. That establishes the write landed before the re-read on
that run, not that it is synchronous per call, and not that it holds on another version. Keep
source 2 primary and keep the divergence handling above.

## Run journal

Every `sync` run keeps its own directory on disk, so Step 6 reads what happened rather than
reconstructing it from conversation. Nothing in the report then depends on the transcript surviving
a compaction, and `converge` or a later audit gets a real before-state.

`fleet-state.sh` does not write it. It stays the read-only inspector its own header advertises.
The journal is agent-executed shell around the calls the algorithm already makes.

**The journal is durable across `sync` runs and session restarts, but not across the removal of its
own marketplace.** It lives under `${CLAUDE_PLUGIN_DATA}`, and running
`claude plugin marketplace remove` on the marketplace this plugin came from deletes that directory
along with every install record for the marketplace, so a remediation that needs the journal copies
`plugins-sync/runs/` out first, or uninstalls the plugins individually with `--keep-data` instead of
removing the marketplace. It stays in the data directory anyway, because that is the documented
per-plugin persistent location. See
[gotchas.md](gotchas.md), "`marketplace remove` is a bulk uninstall, not a declaration removal, and it deletes this skill's own run journal".

At run start the script creates one directory for this run under the `--journal-root` SKILL.md
passes (the `${CLAUDE_PLUGIN_DATA}` value substitutes there and **not** here: a `context/*.md`
spoke is read raw, so a token written here would resolve to nothing).

It is `mktemp -d` on a UTC timestamp, not a bare `mkdir -p` on the timestamp alone: the stamp has
one-second resolution, so two `sync` sessions started within the same second compute the *same* path
and `mkdir -p` succeeds for both: snapshots overwrite each other and the two runs' `journal.log`
lines interleave, which is exactly the reconstruction failure this journal exists to prevent.
`mktemp -d` creates the directory atomically or fails, so each run gets its own. The suffix means a
run directory is `<UTC timestamp>.XXXXXX`, not the bare timestamp; sort by name to order runs.

Then, for the rest of the run:

- **Save every `fleet-state.sh` report** the algorithm re-reads, rather than only reading it. These
  are the same calls the re-read-before-each-mutating-step rule already requires, so the journal
  costs a redirect, not an extra read, and `--from` never replaces one of them. It replaces only the
  second process a step used to launch to project its ids. Name them per marketplace:

  | File | The re-read it saves |
  |---|---|
  | `pre-refresh.<mp>.json` | Step 1's, taken by both actions before the point that marketplace's refresh occupies, so in `sync` the refresh's own effect on `catalog_versions` is visible and in `audit` the chain still starts where `sync`'s does |
  | `pre.<mp>.json` | Step 2's, before the in-repo update |
  | `mid.<mp>.json` | Step 3's, before the user-scope sweep |
  | `pre-install.<mp>.json` | Step 4's, before any install |
  | `pre-enable.<mp>.json` | Step 5's, before any enable |
  | `post.<mp>.json` | the post-sweep re-read Step 6 reads |

  The three the divergence attribution needs are `pre`, `mid`, and `post`; two more exist because
  Steps 4 and 5 mutate too, and `pre-refresh` exists for the catalog regression check below. Step 1
  saves it inside its own per-marketplace loop, at the point that marketplace's refresh call
  occupies in `sync`; the snippet is there rather than restated here. It is a read, so `audit`
  saves it too, into that run's scratch directory.

- **Catalog regression check.** Step 6 diffs `catalog_versions` across every consecutive saved
  snapshot for the marketplace, `pre-refresh` then `pre` then `mid` then `post`, and reports the
  FIRST interval in which any id's catalog version moved backward. Both actions have all four
  snapshots, so both have the full chain. That interval is the signal that names the cause: in
  `sync` a regression across the `pre-refresh` to `pre` boundary is the Step 1 refresh pulling a
  source that moved backward, while one appearing later is the checkout changing under the run. In
  `audit` no refresh runs, so a regression in that same first interval is the checkout changing
  under the run as well, never this run's doing. The interval names when; the action names what it
  means. This diff is REPORT-ONLY and its output never becomes an id list handed to the CLI, so
  the hand-written-`jq` prohibition that governs `--ids` does not apply to it.

  The script runs the triple compare per consecutive pair, stops at the first pair that finds a
  backward move, and reports that interval and its rows in the digest's `catalog_regression`.
  Emit SKILL.md's `Catalog regression:` line from it; report nothing when the field is null.
- **Append every mutating CLI call and its output** to `$run_dir/journal.log` as it runs, so the
  `<new>` values that only the CLI reports survive the step that produced them:

  ```bash
  { echo "\$ claude plugin update $id -s user"; claude plugin update "$id" -s user 2>&1; } \
    | tee -a "$run_dir/journal.log"
  rc=${PIPESTATUS[0]}
  ```

  **`rc=${PIPESTATUS[0]}` is not optional, and it has to be the very next statement.** A pipeline's
  own `$?` is `tee`'s status, and `tee` succeeds whenever it can write the log, so without this
  capture a `claude plugin update` that *failed* journals its own error text and is then read as a
  success, and the "Action needed" row the failure earns is never emitted. `PIPESTATUS[0]` is the
  first pipeline element, which here is the brace group, whose status is its last command's: the
  `claude plugin update` call. Any command between the pipeline and the capture, including an
  `echo`, overwrites `PIPESTATUS`, so read it first and branch on `rc` afterwards. (`set -o
  pipefail` before the pipeline is an equivalent fix, but it makes the *pipeline* fail rather than
  handing you the CLI's status, and every mutating step here needs the status itself.)

  **This is the canonical journaled-mutation shape.** The other mutating calls the algorithm makes,
  `claude plugin install`, `claude plugin enable`, and `claude plugin marketplace update`, are
  journaled the same way and capture `rc` the same way, including the ones in
  [sync-install-enable.md](sync-install-enable.md); that file points here rather than restating it.
- **Step 6 reads those files.** Every `<old> → <new>` pair comes from `pre.<mp>.json` plus
  `journal.log`, with `post.<mp>.json` as source 3's fallback, and the three `divergences[]`
  snapshots the attribution split needs come from the three saved reports. Do not re-derive any of
  it from memory of the run.

**`audit` writes no durable journal: it uses a throwaway scratch directory instead.** SKILL.md's
action table says `audit` mutates nothing, and a run that leaves directories behind under the plugin
data dir does not match that line even though the data dir is not fleet state. But `audit` runs this
same algorithm, and it writes reports: Step 1 saves its pre-refresh snapshot, and Steps 2–5 project
their id lists with `--from` against a saved report. So it does need somewhere to put them, and that
somewhere has to exist before Step 1. `--audit` makes one under `${TMPDIR:-${TEMP:-.}}` and removes
it on exit, including on the error paths. An audit that leaks one scratch directory per invocation
is its own drift. That expansion, and **not** a hardcoded POSIX temp literal: on Windows the literal
is an MSYS mount alias a native consumer resolves against the current drive root.

So `audit` and `sync` execute one algorithm, differing only in where the reports land and in
issuing no mutating call. `audit` has no `<old> → <new>` pairs to lose and nothing durable the
journal would protect, which is why its copy is disposable rather than kept.

A run directory that cannot be created is a run that cannot journal, so the script exits 2 and names
the root rather than sweeping unjournaled: without it the `--from` projections have no saved report,
the `<old> → <new>` pairs have nowhere to survive to Step 6, and the report the run owes would be a
reconstruction from memory of the run.

## Marketplace scoping: Steps 2–5 are the per-marketplace loop body

**Every `fleet-state.sh` call in Steps 2–5 carries `--marketplace "$mp"`, and in `all` mode the whole
of Steps 2–5 is the loop body, run once per marketplace.** Without this, `all` mode refreshes every
marketplace in Step 1 and then performs install, update, enable, and divergence maintenance against
exactly **one** of them, the resolved default, while emitting a report that names no coverage
boundary. That is a silent partial sweep: the plugins of every other marketplace are neither updated
nor reported as skipped.

`--all` takes the names from `fleet-state.sh --marketplaces`, never from a hand-written `jq` over
`known_marketplaces.json`: enumerating names has exactly the trailing-`\r` hazard that enumerating
ids does, and for the same reason.

The bare (no `--marketplace`) form is not a fleet-wide form; it resolves the default marketplace and
scopes to it. Nor can the sweep be widened by combining flags. The script refuses that composition
outright and names the fix in its own error text:

```text
$ fleet-state.sh --all --ids installed-user
ERROR: --ids cannot be combined with --all
  Run --ids once per marketplace with --marketplace <name>.
```

(This is `fleet-state.sh`'s own argument guard, not Claude Code CLI behaviour. The earlier
"verified on Claude Code 2.1.240" attribution was a category error. Re-verified 2026-09-05 by
running the command: the script exits 2 with exactly this text.) `--all` exists for the JSON report, which nests one block per
marketplace; `--ids` projects a single block, so it takes one marketplace at a time. Loop it.

The per-marketplace failure rule from Step 1 carries through: a marketplace whose iteration fails is
reported inline and never aborts the loop for the rest.

## Projecting a step's id list: the shape every mutating step uses

Steps 2–5 all do the same three things: take the live re-read the concurrency rule already requires
and **redirect it to the run journal**, project the step's selector out of that file with `--from`,
and loop the result. `--from` replaces only the second process a step used to launch to project its
ids; it never replaces the re-read.

**The projection's exit status is checked before the loop: an empty projection is ambiguous and the
status is the only thing that disambiguates it.** Every `--from` rejection (a missing or malformed
report, an `--all` envelope, a report lacking the field the selector reads, a `--marketplace`
disagreeing with the report's own name) exits 2 with **empty stdout**, deliberately, so a failure can
never be handed to `claude plugin update` as an id. That makes the two outcomes identical to a
`while read … done < <(fleet-state.sh …)` consumer, which never sees the exit status at all: zero
lines read, step reports nothing to do. So:

- **exit 0, empty output**: genuinely nothing to do for this selector. Proceed.
- **exit 2, empty output**: the projection failed. It reaches the digest's per-marketplace
  `errors[]` and the report's "Action needed" with the script's own error text, and the step counts
  as not run; never as "nothing to do".

Each projection lands in a file inside the run directory alongside the reports, rather than in a
process substitution whose status a loop discards, so the status is available where the branch is.

Steps 2 through 5 each name their own report file and selector below; the redirect, the status
check, and the loop-from-a-file shape are this section's and are not restated at each step.

## Step 1: Marketplace refresh

For each target marketplace (the resolved default, the named one, or every marketplace when the
argument is `all`), save that marketplace's pre-refresh snapshot and then refresh it.

**The snapshot is a read, and BOTH actions take it.** It is the earliest link in the catalog
regression check's snapshot chain, and an action that skips it starts that check at `pre` and loses
its first interval. It is saved as `pre-refresh.<mp>.json`. When no marketplace argument was given,
that same read is what resolves the default marketplace's name, so resolution costs no extra process.

**The refresh is the mutation, and it is `sync` only.** `claude plugin marketplace update "$mp"` is
the one call this step replaces with `would run: claude plugin marketplace update <mp>` in an
`audit` report.

The update call attempts to re-fetch from the marketplace's registered source; this skill never re-clones or
performs cache surgery by hand. It does not reliably self-heal: the refresh is known to fail against an
existing non-empty marketplace directory
([anthropics/claude-code#76129](https://github.com/anthropics/claude-code/issues/76129), reported on
macOS and reproduced on Windows), where it reports `Failed to clone marketplace
repository: fatal: destination path '...' already exists and is not an empty directory`. Treat a
successful refresh as the expected case, not a guarantee.

That issue is closed as not planned, so the failure stands unfixed and this step keeps its manual
recovery path. Basis: `gh api repos/anthropics/claude-code/issues/76129`. Verified 2026-09-06
against Claude Code 2.1.263. Recheck when the issue reopens or closes as completed, or when a
refresh against a non-empty marketplace directory succeeds here; route the recheck through
`/claude-ops:known-issues check-all`.

The snapshot goes first because it is the only read taken while the catalog is still pre-refresh,
which is what gives the Run journal's catalog regression check its first interval. It belongs to
this step's own loop, not to the Steps 2-5 loop body.

What a regression in that first interval means differs by action. In `sync`, a backward move across
the `pre-refresh` to `pre` boundary is this run's own refresh pulling a source that moved backward.
In `audit` no refresh runs, so the same move is the catalog changing under the run: a concurrent
session, or a background `autoUpdate` sweep. Report the interval either way; read its cause per the
action.

In `all` mode, loop this per marketplace name (rather than the bulk no-argument form) so a single
marketplace's failure is attributable and reported inline without aborting the sweep for the rest.

**On a non-zero exit, in every mode including single/default.** Not fatal, and never silently
absorbed: the marketplace and the CLI's own error text reach that marketplace's `errors[]` and the
report's "Action needed", the block's `install_enable_deferred` is set, and the run continues to
Step 2.

Which later steps a stale catalog compromises, and how each one degrades:

- **Step 2 is unaffected.** It operates purely on installed state, which a failed refresh leaves
  untouched, and it is deliberately not catalog-pre-filtered (see Step 2).
- **Step 3 still runs, and keeps the guarded selector.** Its sweep is installed-state-driven, so
  the updates themselves are safe, but the `catalog_versions` pre-filter reads the marketplace
  *checkout*, and a checkout that failed to refresh may be behind the real catalog. An id whose
  installed version matches the **stale** catalog version is then withheld from the sweep as
  "already current" when a newer version may exist upstream. That is a real cost, and it is the
  smaller one: a failed refresh means the checkout is UNTRUSTED, and sweeping every user-scope id
  unconditionally against an untrusted catalog is the rollback path, since a catalog that reads
  lower is exactly what an unrefreshed or misdirected source produces. So Step 3 keeps
  `update-candidates-user`, and reports the ids it withheld as already-current as a LOWER BOUND:
  they may still be behind upstream, and the run says so and tells the operator to rerun after the
  refresh succeeds. That is the same shape `audit` already uses for its own unrefreshed prediction.
- **Steps 4–5 are skipped entirely.** Step 4 derives installations from the catalog
  (`missing_from_user_install`) and Step 5 consults catalog metadata (`defaultEnabled`), so running
  them against a stale catalog can install a since-removed plugin or enable one the publisher has
  since made opt-in-only. For a marketplace whose refresh failed, **skip Steps 4–5** and list what
  they would have done under "Action needed" as deferred until a sync run where the refresh
  succeeds.

**A refresh that SUCCEEDS is not a trust signal about direction.** It establishes that the checkout
is current with its source, nothing else: a current catalog can still read lower than what is
installed, because the source itself can have moved backward. The downgrade guard applies on every
run, refreshed or not.

Say so in the report: `Marketplace: <name>, refresh failed, catalog may be stale; update sweep
ran guarded, its already-current ids are a lower bound; install/enable maintenance deferred`,
rather than claiming it is current. Do not
delete, rename, or re-clone the marketplace directory to work around it. That is cache surgery
this skill does not do. To learn how stale the catalog actually is, compare
`git -C <installLocation> rev-parse HEAD` against `git ls-remote origin HEAD` run in that
directory. `ls-remote` queries the remote
without writing `FETCH_HEAD`, remote-tracking refs, or objects, all three of which a plain
`git fetch` writes (mutations of the marketplace's internal clone, outside this skill's boundary).

## Step 2: In-repo update (the primary value path)

Always call `fleet-state.sh` first. Never gate this step on `CLAUDE_PROJECT_DIR` being set before
calling it. `fleet-state.sh` resolves the project root itself (`CLAUDE_PROJECT_DIR` when set, else
the cwd's git toplevel, else a non-git cwd corroborated by its own `.claude` directory, with
`$HOME` excluded; see [gotchas.md](gotchas.md)), so a headless session where the env var is unset can still
correctly compute `currentProject`; gating on the raw env var directly would skip this step in
exactly the case that fallback exists for.

**Before looping, branch on the report's top-level `project_root`: this step must never skip
silently.** It is the primary value path; a run where it did nothing has to say so, and until it
does, "no project context at all" and "a project with no in-repo installs" produce an identical
report. They are categorically different answers and the user cannot tell them apart:

- **`project_root` is `null`**: no project root resolved (a run from `$HOME`, or from a non-git
  directory with no `.claude` of its own). Nothing in-repo can be updated because there is no
  "here". Emit the skipped `In-repo:` row from SKILL.md's Report section, naming the cwd, and go to
  Step 3. Do **not** report this as "0 updated".
- **`project_root` is a path and no record carries `currentProject: true`**: a project resolved and
  it simply has no project/local-scope installs. Emit the `In-repo:` row as `0` **for that root**,
  which is an honest zero rather than an absent step.
- **`project_root` is a path and records carry `currentProject: true`**: the success path below.

`sync-run.sh` carries this branch into its digest as `project_root` plus `in_repo_records`, the
count of records with `currentProject: true`. A report written over the digest branches on those
two fields; the record-level read below is the same question asked of the `fleet-state.sh` report
directly.

Reading `project_root` costs nothing extra: this step already calls `fleet-state.sh` above, and the
field is in the JSON it returned. Do not try to recover the distinction from
`--ids update-candidates-project` alone: that selector emits nothing in both of the first two cases,
so a step keyed on it no-ops invisibly. And do not infer it from `currentProject` per record either: that flag is a
tri-state whose `null` covers user-scope records, records with no `projectPath`, *and* the
no-project-context case all at once.

Then look at `installed[]` entries with `currentProject: true` and run
`claude plugin update <id> -s <that record's scope>` for **every one of them the downgrade guard
does not withhold**.

`fleet-state.sh --ids update-candidates-project` emits exactly those records. Use it rather than a
hand-written `jq` over `installed[]` (see Step 3 for why the hand-written form breaks on Windows).
`current-project` names the same set unguarded and is not what this step loops.
Project it with `--from` off the report this step just saved rather than running a second live
process: that process would re-parse `installed_plugins.json`, re-walk the catalog manifests, and
re-run `realpath` to recompute a block already on disk. Same script, same projection, so the
`\r` protection is identical.

Per the projection section above, this step's own re-read is redirected to `pre.<mp>.json`, which
is what the branch on `project_root` above reads and what `--from update-candidates-project`
projects, and the projection's exit status is checked before the loop. Each projected line is
`<id>\t<scope>`, so the `-s` flag comes off the same line as the id it belongs to.

The status check matters more here than anywhere else: this is the primary value path, and an
unchecked failed projection is indistinguishable from the honest "a project resolved and it has no
in-repo installs" zero the step is required to report.

The scope rides on the record for a reason: one plugin can hold **both** a `project`- and a
`local`-scope record for the same repo (the multi-scope case `divergences[]` tracks), and both are
`currentProject: true`. An id-only list would show that id twice with nothing to distinguish the
lines. `sort -u`, or pairing against a separately-extracted scope list, would silently drop one of
the two updates. Do not re-derive scope from the id afterwards.

Do **not** pre-filter on `divergences[]`. `divergences[]` only contains ids with *more than one*
scope record: a project/local install with no other scope pinning the same id (the common single-
pin case) never appears there at all, and neither does a multi-scope install where every scope
happens to already share the same stale version (`versionsMatch: true`, still behind the catalog,
just not internally disagreeing). Both are real staleness `divergences[]` cannot express, so the only
correct signal here is "is this entry present": just call `update`, letting the CLI report
"already at the latest version" as a no-op when nothing changes.

Filtered for proven downgrades and for **nothing else**: `update-candidates-project` withholds an
id the catalog would move backward, and declines the catalog EQUALITY filter Step 3's selector
applies. The two filters are not the same kind of thing. Equality is an optimization, and it buys
nothing here: the in-repo population is small (a handful of records, against Step 3's dozens), so
the saving is negligible, while a project/local pin is far more likely than a user-scope install to
sit at a version the catalog does not carry, a deliberate pin or a local build, and paying one
redundant no-op call per in-repo record buys the primary value path a signal that does not depend on
the catalog resolving at all. The downgrade guard is not an optimization: it withholds a call whose
effect would be wrong, not one whose effect would be nothing, and skipping it here would let a
catalog that moved backward roll back exactly the deliberate pins this step is most likely to be
holding. Verified safe: `plugin update
-s project` does not write the committed `.claude/settings.json` (see
[scope-semantics.md](scope-semantics.md)), so no settings-diff review is needed for this step,
unlike `converge`.

## Step 3: User-scope update sweep

Partially catalog-dependent: the sweep itself is installed-state-driven and always runs, but its
pre-filter reads the marketplace checkout. Two cases where that checkout cannot be trusted to prove
an id current, and what each does:

- **Step 1's refresh failed for this marketplace.** Keep `--ids update-candidates-user`, and
  report the ids it withheld as already-current as a lower bound: they may still be behind
  upstream, so rerun after the refresh succeeds. Acting unconditionally on an untrusted catalog is
  the rollback path, which is the larger risk of the two. See Step 1.
- **`audit` mode**: `audit` issues zero mutating calls, so Step 1's refresh never runs (its
  snapshot is a read and is still taken) and the catalog is
  simply however stale it already was, by an unbounded amount. The pre-filter still runs (predicting
  the real algorithm is the point of a dry run), but its output is a **lower bound**: a real `sync`
  refreshes first and may find more to update. Say so, and quantify the uncertainty with the
  catalog's own age rather than leaving it implicit. `fleet-state.sh` reports
  `marketplace.lastUpdated`:

  ```text
  Would update: <N> plugin(s) (lower bound, predicted against a catalog last refreshed
    <lastUpdated>, which `audit` does not refresh; `sync` refreshes first and may find more)
  Would withhold: <N> downgrade(s) (the catalog reads lower than what is installed; `sync`
    reports these under Action needed unless it is run with --allow-downgrade)
  ```

  The withheld count comes from `--ids downgrade-candidates`, projected off the same saved report
  as the `Would update` count. Print it whenever it is non-zero: a prediction that names only what
  would move forward hides the direction problem the guard exists to surface.

  Never present an `audit` prediction of zero as "the fleet is current": it means "nothing is
  behind the catalog as it stands on disk", which is a different claim.

Update the catalog plugins installed at `user` scope with `claude plugin update <id> -s user`.

One call per plugin: `claude plugin update` takes a single `<plugin>` argument, there is no bulk
"update everything" flag. Loop it; a single plugin's update failure is reported inline (under
"Action needed") and does not abort the sweep for the rest.

Take the ids from `fleet-state.sh --ids`, never from a hand-written `jq` over its JSON, and use the
**`update-candidates-user`** selector rather than `installed-user`. This step makes its own live
re-read, the one the concurrency rule requires before a mutating step, redirects it to
`mid.<mp>.json`, and projects two selectors from that file, for the reason Step 2 gives:
`update-candidates-user` into `ids.mid.<mp>.txt` and `downgrade-candidates` into
`downgrades.<mp>.txt`.

Reading an unchecked empty projection as "already current" is the silently-skipped-update failure
this step exists to prevent, so the sweep projection's status is checked per the projection section
before concluding the sweep had nothing to do. The same check governs the downgrade projection: an
unchecked failure there reads as "no downgrades", which is the guard reporting an all-clear it never
established.

### The withheld set

`downgrades.<mp>.txt` carries one `<id>\t<scope>\t<installed>\t<catalog>` line per proven downgrade,
across user scope and this repo's in-repo records both, so it covers what Step 2's selector withheld
as well as Step 3's. What happens to it is the operator's call, not this step's:

- **`--allow-downgrade` was NOT given.** Do not touch them. Report each under `Action needed` with
  both versions and the likely cause, per SKILL.md's `downgrade withheld:` row.
- **`--allow-downgrade` WAS given.** Loop them too, taking `-s <scope>` from field 2 the way Step 2
  takes it off its own line, journaled through the same `tee` plus `PIPESTATUS[0]` shape as every
  other mutating call. Their outcomes render under `Downgraded:`, never under `Updated:`, whatever
  the CLI's own line calls them. The digest carries them in `downgraded`, which is a separate array
  from `user_sweep.updated` for exactly that reason.

### Why the pre-filter, and why it can only ever be a candidate list

Each plugin's version lives in its own manifest inside the marketplace checkout
(`<installLocation>/<entry.source>/.claude-plugin/plugin.json`), even though the `marketplace.json`
entry itself carries no version. `fleet-state.sh` reads those manifests into `catalog_versions` with
no network call and no `claude plugin` invocation, and `update-candidates-user` withholds the ids it
positively proved already sit at the catalog version, plus the ids it positively proved the catalog
would move backward. On an already-current fleet that turns the whole sweep into zero
`claude plugin update` calls instead of one per user-scope install.

It is not free, just far cheaper than what it replaces: the read costs one `jq` over every manifest
the shell located plus one batched `realpath` over every manifest that exists, per marketplace,
against `claude plugin update` process launches it removes. Local file reads, no network, no CLI,
and a process count that does not grow with the catalog.

**Correctness dominates the saving, so the selector fails open by construction.** An id whose
catalog version cannot be read is emitted as a candidate, exactly as if no pre-filter existed. That
covers an entry whose `source` is a remote spec rather than a repo-relative path, a checkout that
never materialized that directory, a manifest carrying no `version`, and JSON that does not parse.
That is not a rare branch: across the marketplaces registered on the authoring machine
(Claude Code 2.1.240) the
version resolved for every entry of some and for a small minority of others', so a marketplace where
the pre-filter withholds nothing at all is an ordinary outcome, not a malfunction. Read a shrunken
sweep as a bonus, never as evidence that the ids it skipped were checked.

`installed-user` is available for a caller that deliberately wants every user-scope id, and **the
sync algorithm does not use it.** An unconditional user-scope sweep is what turns a catalog that
moved backward into a fleet rollback, and a marketplace whose Step 1 refresh failed is the likeliest
place for a catalog that reads backward, so it is the last place for an unguarded sweep.
The pre-filter's guarantee is "this id matches the version in the local checkout"; that is only a
statement about staleness when the checkout is current, which is why a failed refresh downgrades the
sweep's already-current set to a reported lower bound rather than widening the sweep.

`--ids` emits the fully-qualified `<name>@<marketplace>` form, one per line, CR-free: a bare name
is ambiguous across marketplaces and has failed with "Plugin not found" on earlier CLI versions,
and on Windows a hand-written
`jq -r ... | while read` silently appends a `\r` to every id but the last, which fails with the
*same* "Plugin not found" text and so misreads as the bare-name problem. Both are
[gotchas.md](gotchas.md); `--ids` is why neither can happen here.

## Steps 4 and 5: install and enable

**Take a fresh live re-read first, and gate on THAT report, never on Step 1's.** Step 4 is a
mutating step, so the concurrency rule already requires its own re-read; it is taken here, before
either step decides whether it has anything to do, and saved as `pre-install.<mp>.json`.

**Read [sync-install-enable.md](sync-install-enable.md) only when `pre-install.<mp>.json` has a
non-empty `missing_from_user_install` or a non-empty `missing_from_enabled`, or when Step 1's
refresh failed for this marketplace.** Both arrays are empty on an already-current fleet, which is
the common case, and then both steps are no-ops with nothing to load.

Gating on the Step 1 report instead would be a real hole, not a nicety: another session can
uninstall a plugin or change enable state between Step 1 and here, and a gate keyed on the older
report would then decline to load the spoke, skip the live pre-install and pre-enable reads the
spoke mandates, and leave the new gap silently unresolved, while the step-level concurrency
boundary this file opens with says the decision belongs to the step's own re-read. The progressive
disclosure is kept; only the report it keys on moves. Step 4 reuses this file rather than reading
again, so the honest gate costs nothing.

**Step 5 still takes its own re-read.** Step 4 mutates in between, installing and normalizing
the user-scope `enabledPlugins` map, so `pre-install.<mp>.json` is stale by the time Step 5 runs and
cannot stand in for `pre-enable.<mp>.json`. The two are never collapsed.

**Step 4 stops for the `ask` policy.** When `install_new` renders as `ask` and the install gap is
non-empty, the script reports the gap and issues no install: the batched prompt belongs to the
model, which runs it and re-enters with `--only-install <the chosen ids>` against the same run
directory. The digest says so in `stopped_before_install`, so a gap left unresolved is a reported
state rather than a silent skip. Under `all` the gap is installed; under `none` it is reported and
Step 5 still runs.

- **Step 4: install new catalog plugins.** Installs the `missing_from_user_install` ids at `user`
  scope per the configured `install_new` policy, then normalizes the user-scope `enabledPlugins`
  key order the install just disturbed.
- **Step 5: `enabledPlugins` completeness.** Enables the `missing_from_enabled` ids at `user` and
  `local` scope, and reports rather than writes at `project` scope.

When Step 1's refresh failed for this marketplace, both steps are deferred rather than run: the
spoke carries what to say about that; see Step 1 above for why.

## Step 5b: Cache content check

Read-only, runs after Step 5's enables and before the report, and is the same call in `sync` and in
`audit`. It is not gated on anything: an unchanged manifest version is exactly the case in which
every earlier step reports success, so a check that only ran when something else looked wrong would
never fire on the condition it exists to catch.

**One call per marketplace.** `cache-content-check.sh --marketplace "$mp"` writes its JSON to
`cache-content.<mp>.json`, and the stale ids come out of that same JSON, CR-stripped in the shell
the way every id list in this algorithm is. A second call for the id list would recompute a
fleet-wide byte comparison the first call already did, which is the most expensive read in the run.

In `sync` that redirect lands in the run journal beside the `fleet-state.sh` snapshots, so Step 6
reads the finding rather than remembering it. In `audit` it lands in the throwaway scratch directory
that run deletes, the same way `audit` handles every other report it writes. The `--only-install`
re-entry reuses the report already in the run directory rather than checking again.

The extraction is CR-safe by construction, for the reason [gotchas.md](gotchas.md) gives: on Windows
a `jq -r … | while read` appends a `\r` to every id but the last, so the ids are captured and
stripped in the shell instead of piped. The checker's own `--ids` form is the fallback for a JSON
that could not be produced, never a second pass beside a JSON that was.

**Neither action repairs what this finds, and `sync` is no exception.** The remediation is a
directory removal under Claude Code's own plugin cache, which is outside the boundary the rest of
this skill keeps: `sync` mutates only through documented `claude plugin` CLI calls, and no CLI verb
rewrites a cache directory whose version number has not moved. So both actions report the ids and
the remediation and stop. Emit SKILL.md's `Cache content:` row, and omit it entirely when the check
found nothing.

The check reads the marketplace clone at the recorded commit. It never fetches one it does not
have, since that would be a network mutation and would repair the very condition being reported, so
an install whose sha is not in the clone is reported as `sha-not-local` and counted as unverifiable,
not as a pass. A report in which most installs are unverifiable has established very little; say so
rather than leading with the match count.

## Step 6: Report

The script renders the report from the digest (`render-report.jq`), filling each updated plugin's
`<old> → <new>` from the sources the "Version capture for the report" section above fixes. The
digest carries them, resolved from the run journal rather than from memory of the run, and the run
directory it names holds every snapshot behind them. The paragraphs below state what the render
does with each field and why, so a reader can check a rendered row against the field it came from;
the model's one addition is the reload guidance at the end.

**Every `<old> -> <new>` pair reaches the report already classified by direction.** Apply the same triple
compare the guard uses: a pair whose new version is higher, or whose direction the compare cannot
read, goes under `Updated:`, with an unreadable one flagged `(direction unknown)`; a pair whose new
version is lower goes under `Downgraded:`. A pair whose two versions differ as strings but whose
triples tie, `1.2.3` to `1.2.3-beta`, goes under `Updated:` flagged `(direction unknown)` too,
because the compare cannot rank suffixes. This classification is what makes a backward move
unprintable as `Updated:` for the ids that still reach the CLI on the guard's fail-open path, the
ones whose catalog version was null or unparsable and so could never be proven a downgrade in
advance. The guard withholds what it can prove; this classification catches what only the outcome
reveals. In the digest that is the split between each block's `updated` arrays, whose rows carry
`direction`, and its `downgraded` array.
The same classification governs the `In-repo:` count: it counts forward moves only, and an in-repo
record that moved backward renders under `Downgraded:` with its scope instead of being counted
there.

**Report the catalog regression check.** Emit SKILL.md's `Catalog regression:` line for the first
snapshot interval in which any id's catalog version moved backward, per the "Run journal" section's
jq. It is the signal that names the cause behind every withheld downgrade, so it belongs in the
report even when `--allow-downgrade` moved them anyway.

**Split the Divergences count into pre-existing and run-caused.** A user-scope sweep that moves user
scope ahead of untouched project records *manufactures* actionable divergences, the run's own
correct consequence, not drift it discovered. Reporting the total as a single discovered number
routes the user to `converge` for skew this run just created.

**Attribute it to the right step: that needs THREE snapshots, not two.** Steps 2 and 3 both mutate
versions, so a single pre-Step-2 / post-Step-3 bracket cannot tell which one created a new
divergence, and labelling the whole delta "the user-scope sweep" is wrong whenever Step 2 caused it.
Concretely: equal project and user records at `v1`, Step 2 updates the project record to `v2`, Step 3's
user update fails. The skew is Step 2's, and a two-snapshot diff blames Step 3. Take the
`divergences[]` read from each of the three `fleet-state.sh` calls the algorithm already makes, the
pre-Step-2 snapshot, the pre-Step-3 re-read the concurrency rule requires anyway, and the post-sweep
re-read, saved as the run journal's `pre.<mp>.json`, `mid.<mp>.json`, and `post.<mp>.json`, then
attribute each new row to the interval it first appeared in. No extra call is needed; this is
bookkeeping over reads that already happen.

**The names carry the marketplace, and in `all` mode there is one set per marketplace.** Steps 2–5
are the per-marketplace loop body, so a three-marketplace run leaves three `pre.<mp>.json`, three
`mid.<mp>.json`, and three `post.<mp>.json` files in one `run_dir`. Do the attribution split per
marketplace against that marketplace's own three snapshots; a cross-marketplace diff compares
unrelated fleets.

Report as
`<N> actionable (<M> newly created by this run: <a> by the in-repo update, <b> by the user-scope
sweep, <N-M> pre-existing)`. When the two intervals genuinely cannot be separated (a snapshot was
missed), say `<M> newly created by this run` without splitting it, rather than assigning the whole
delta to one step.

**Say when the sweep updated `claude-ops` itself.** Step 3 sweeps every user-scope id, which
necessarily includes the plugin providing this skill. When it does, the algorithm that ran is the
**pre-update** one: `${CLAUDE_PLUGIN_ROOT}` keeps resolving to the version loaded at session start,
so every later `fleet-state.sh` call and every remaining step executes the old copy, and the report
describes work done by a version the user no longer has installed. Current docs, `plugins-reference`
(fetched 2026-08-22): "When a plugin updates mid-session, hook commands, monitors, MCP servers, and
LSP servers keep using the previous version's path." This is not a crash risk, since the previous
version directory is retained on a grace period and the running script does not vanish mid-run. It
is a reporting obligation. The render emits the self-update note when the digest's `self_updated`
is true.

**Name the monitors.** A monitor is not covered by `/reload-plugins`, so a moved plugin whose
installed build declares one needs a session restart. The script reads each moved record's own
cache directory from the post-sweep snapshot (`installPath`) and counts monitors declared inline
under the manifest's `experimental.monitors` key, in the manifest file that key names, or in
`monitors/monitors.json` at the plugin root; the render lists the ids under `Action needed` and
attributes the restart requirement to the plugins reference.

End with the reload guidance per SKILL.md's Report section: recommend bare `/reload-plugins`, and
state the recovery step rather than pre-judging which case will trigger it. That line is the
model's; everything above it is the render's.
