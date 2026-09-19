# Stale project records and cache content: reported, never fixed

Two report sections the render emits only when their digest field is non-zero. Read this file
when `stale_project_records.total > 0` or `cache_content.stale_content > 0`, or when the user asks
why either section says what it says. On a fleet with neither finding, nothing here changes the
report.

## Stale project records: reported, never converged, never reaped

A project/local install record keeps its `projectPath` after that directory is gone. Ephemeral
checkouts make this ordinary rather than exceptional: a throwaway worktree can leave a record per
installed plugin behind, so one deleted directory can strand dozens of records at once.

`fleet-state.sh` annotates every project/local record with `projectPathPresent` (see
[scope-semantics.md](scope-semantics.md)). The render puts these in their **own section**, and
three boundaries hold:

- **Never counted in Divergences.** `converge`'s every project/local command is
  `(cd "<projectPath>" && claude plugin …)`, because `-s project`/`-s local` have no path flag. A row
  whose `projectPath` is absent cannot be `cd`'d into, so routing it to `converge` hands the user a
  command guaranteed to fail. Folding these into the actionable count also inflates it with rows no
  action can clear. They are a separate observation, not a divergence.
- **Never suppressed, and never called dead.** `projectPathPresent: false` means *not present on this
  machine right now*. Nothing more. An unmounted volume, an offline network share, an external drive
  that is unplugged, and a deleted worktree are indistinguishable to a directory test. Filtering these
  rows out would hide real drift from anyone whose repos live on removable or network storage. Say
  "not present on this machine", never "dead" or "orphaned".
- **Never reaped by this skill.** No `claude plugin` verb removes an install record by path;
  `prune` acts on auto-installed *dependencies* and its own `-s project` has the same
  no-path-flag limitation (re-verified on Claude Code 2.1.261). Editing `installed_plugins.json`
  directly is outside this skill's boundary, the same rule the rest of this skill follows. So this
  section names the condition and stops. If the records came from a tool that owns those directories'
  lifecycle, that tool is where they should be dropped at teardown; this skill does not reach into
  another plugin's configuration to find out.

A record does not have to come from a deliberate install. A repo whose committed `.claude/settings.json`
carries an `enabledPlugins` block mirroring what the user already has at user scope writes one
project record per `true` entry at the first session start in that checkout, pinned to the version
the user scope holds (verified on Claude Code 2.1.263). A `false` entry writes nothing. The render
reports the count and the distinct paths; name the block as the source when the path's repo carries
one. [scope-semantics.md](scope-semantics.md) "Where project-scope records come from, and why the
skill cannot reap them" holds the sourcing, the precedence rule, the reap boundary, and the probe
recipe that established the write.

The render gives the section a count plus the distinct paths, not one row per record, because a
hundred records naming a dozen directories is a report about a dozen directories: `K` is
`stale_project_records.total`, `P` is the length of `stale_project_records.by_path`, and each
`by_path` entry is the `{path, count}` one row renders. The section is omitted when `K` is 0.

A project-scope enable gap is a row `sync` deliberately does not fix. Step 5 enables automatically
only where the write is not team-shared state. The render lists each one under `Action needed` as
its runnable command, `(cd "<projectPath>" && claude plugin enable <id>@<marketplace> -s project)`,
with the note that it writes that repo's committed `.claude/settings.json`, so acting on it is a
copy, not a reconstruction. Only ids that Step 5 did not enable at `user`/`local` scope in this run
appear there. For the rest the command would fail rather than run, and Step 5 explains why.

When a project root resolved, the render leads the `Divergences:` line with *this* project's
actionable count and folds the rest of the machine into one trailing clause, e.g. `2 behind here
→ converge; 27 more elsewhere on this machine`. Per-row detail (naming exact `<old> → <new>`
versions per repo) is reserved for genuine conflicts: an unknown/orphaned plugin id, or a CLI call
that failed, never for the routine bulk case. (Enable-state mismatches, a plugin `true` in one
scope's `enabledPlugins` and `false` in another, are a known blind spot, not a reportable category:
`fleet-state.sh` only exposes the merged effective value, never each scope's raw map, so this skill
cannot detect one to report it. See [converge.md](converge.md) "V1 scope".)

## Cache content: reported, never repaired

A version-and-sha check is not proof that the files on disk are the build the record names. When a
plugin's manifest version does not change across a commit, `claude plugin update` re-points the
record's `gitCommitSha` and leaves the existing version directory in place, so the metadata claims
the new commit while the directory still holds the old build. See
[scope-semantics.md](scope-semantics.md) "An unchanged version number keeps the old cache directory
while `gitCommitSha` moves" for the observation this rests on.

Step 5b runs `cache-content-check.sh`, which byte-compares every file in each cache directory
against the recorded commit in the marketplace clone. The render omits the `Cache content:` row
when it finds nothing. When it finds something, the render names the ids and gives the remediation
that was actually proved to work, rather than a suggestion: remove that version's directory under
the plugin cache, then re-run `claude plugin update <id>@<marketplace>`, which recreates it from
the clone.

`N` is `cache_content.stale_content`, and one row comes from each `cache_content.stale[]` entry:
`id`, `version`, and `files_differ`, which sums every direction of disagreement: bytes that
changed, files the tree has and the cache lacks, and files the cache holds and the tree does not.
`files_differ` reads `null` when the digest fell back to the checker's `--ids` form, which knows the
ids and no per-file detail; the row then carries the id alone.

**The check never repairs.** It does not delete a cache directory, does not re-run an update, and
does not `git fetch` a commit the marketplace clone lacks. A commit that is not local is reported as
`sha-not-local` and left alone: fetching is a network mutation this audit does not perform, and it
would also silently erase the condition the verdict exists to report. Every verdict other than
`match` and `stale-content` is counted as `unverifiable`, meaning the audit looked and could not decide,
which is its own number and never folded into either side.

**Expect a substantial `unverifiable` share, and never read it as a pass.** Claude Code clones a
marketplace shallow, so any install whose recorded commit predates that clone's window reports
`sha-not-local` through no fault of the fleet. On the machine this check was first run against, 11
of 74 user-scope installs were unverifiable for exactly that reason. The render says so alongside
the match count rather than leading with the match count alone: a row with the unverifiable share
when nothing is stale, and a sub-line under the finding when something is.
