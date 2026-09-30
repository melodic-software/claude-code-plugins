# Scan flag detail

Flag-by-flag behavior of the `scan` flags `--quiet`, `--root-children` with `--root-child`, and
`--sizes-only`, plus the inventory flag `--deep`, for `/disk-hygiene:clean`. The parse contract, the rejection rules, and the
confirmation gate stay in [SKILL.md](../SKILL.md#arguments-and-boundaries).

## `--quiet`

`--quiet` shapes the scan's stdout and nothing else: it omits `children_rollup`, prints
`truncated_paths` as a count instead of the list, prints `truncation_reasons` as a per-reason tally
instead of a path map, and shortens the closing note, leaving every
counter, byte total, error and policy source in place. The snapshot file carries the rollup, the
truncated-path list and each path's reason in full in both modes, so read per-child detail and the coverage gaps there and
pass `--quiet` whenever the run only needs the frontier summary. `truncation_reasons` covers every
unwalked path, including a directory whose scan failed (`scan-error`, also listed in `errors`), which
`truncated_paths` omits, and every sibling a `--root-children` run left unselected
(`root-child-unselected`), so the tally can sum to more than the `truncated_paths` count.

## `--root-children` and `--root-child`

`--root-children` is the only way to address an OS-managed volume root (for example `C:\` or `/`):
it never walks that root recursively. The same flags also select immediate children of any other
target, so after a depth-1 home audit the operator can re-inventory the approved directories
without walking the rest of the home. Without `--root-child` names the engine returns
`root-children-selection-required` listing admitted immediate children. On every volume root, an
OS-managed one or a non-OS one such as a Windows Dev Drive, the strict ladder applies: OS-owned
(including `System Volume Information` and `$Recycle.Bin`), hidden, dot-prefixed, `$`-prefixed,
system, reparse, mount, protected-shell-folder, and non-regular types are withheld, and regular
files use the same admission ladder as directories. Only a target that is not a volume root, such
as a home directory, gets the relaxed listing: only directories are admitted, and hidden and
volume-OS-named directories stay selectable so approved home children can be named. With one or
more explicit `--root-child <name>` flags, after the human clears the confirmation gate's
root-children row, it audits only those admitted children into one snapshot. A general "clean
everything" is not selection.

## `--deep`

`--deep` selects the deep mode of the read-only `inventory` subcommand: every level of the target
is listed with bottom-up directory sizes instead of only its immediate children. It is the default
when the target is the user's home directory, so a bare `/disk-hygiene:clean ~` runs the deep
inventory before any `scan`, and the flag matters for any other target. The skill runs `inventory`
only for a home directory or with `--deep`; the engine's immediate-children listing is for a direct
call. It is not a `scan` flag: it takes no `--max-depth`, snapshot or entry cap, and it produces a
JSONL report that `preview` and `apply` refuse. The gates are unchanged:
[safety-model.md](safety-model.md#deep-inventory-is-report-only).

Every `KEEP` row needs a specific reason: who produced the entry and what still uses it. The
validator fails an empty reason or one that is only a category phrase ("tool-managed", "OS-owned",
"managed by <tool>") unless `evidence` shows the named tool still references the entry.

Rows stream to `<data-root>/inventory/inventory-<stamp>.jsonl` with no entry cap, beside a `.json`
summary (`deep-inventory-report`; status `inventory-failed` and exit 5 when the validator rejects a
row). The shared listing schema is defined in `scripts/deep_inventory.py`: one row per entry with
the columns `name`, `ext`, `size`, `mtime`, `owner`, `producer`, `category`, `disposition`
(`KEEP`, `CANDIDATE`, `UNKNOWN`), `reason`, and `evidence`. A directory's `size` is the sum of the
files beneath it. Named categories: `superseded-version` (sibling entries, directories or files,
under a parent that holds two or more dotted version names), `plugin-cache-version` (cache versions
no installed plugin references), `tmp-producer` (`/tmp` entries by producer prefix),
`transcript-dir` (project transcript directories whose source path is gone), `dangling-symlink`,
and `not-walked` (an unreadable or mounted subtree, one `UNKNOWN` row). Every other entry is
`unclassified`.

`superseded-version` keeps the newest version (a release outranks its own prerelease), a version a
running process executes, and a version a symlink points at, read from the symlinks beside the
versions, in their parent directory, and in `~/.local/bin` and `~/bin`. A version chosen by a file
rather than a symlink (an nvm alias, `.tool-versions`) is not seen, so its row can be a
`CANDIDATE` for a version that is in use.

`plugin-cache-version` candidates carry the `.orphaned_at` marker age and whether it is past the
sweep window (`ORPHAN_SWEEP_DAYS` in `scripts/deep_inventory.py`), in `evidence` and in the reason,
so a version Claude Code removes itself reads differently from one it has not.

`tmp-producer` covers the entries of `/tmp` itself, not `$TMPDIR`, and produces rows only when the
target is `/tmp` or contains it, so a home inventory has none: run `--deep /tmp` as its own
target. It runs only where `/tmp` is an ordinary directory a target can name (Linux): macOS rejects
`/tmp` (a link) and `/private/tmp` (an OS-managed root), so the category has no rows there.

`superseded-version` and `tmp-producer` also keep an entry a running process uses; where `/proc`
cannot be read (macOS, Windows), a row that would be a `CANDIDATE` on that basis is `UNKNOWN`,
because nothing checked the process table. Other read-only listings that
need the same columns reuse this schema instead of defining their own
([#5214](https://github.com/melodic-software/claude-code-plugins/issues/5214),
[#4006](https://github.com/melodic-software/claude-code-plugins/issues/4006)); their scope stays
their own.

## `--sizes-only`

`--sizes-only` goes through the same large-scan gate as an ordinary unbounded walk: a known-large
root returns `large-target-confirmation-required` without `--max-depth` or `--confirmed-large-scan`.
It does not stop at VCS or protected directories: it sums through them, read-only, for exact totals,
and keeps no per-path entries. It has no entry cap. The snapshot carries `inventory_mode: sizes-only`
and `rollup_precision: exact` when every subtree was walked; a depth cut, a directory that failed to
scan, or a mount-state error marks `rollup_precision: partial`.

When an inventory scan hits the entry cap, the error lists the top five top-level children by entry
count so far. The child still being walked is a lower bound, and children not yet reached are not
counted. Size candidates with `--sizes-only`, then rerun with `--root-children --root-child <name>`
on bounded children or with `--max-depth`.

## Coverage and hint fields

`truncation_reasons` maps every unwalked path to `vcs-boundary`, `protected`, `depth-cut`,
`scan-error` or `root-child-unselected`, as a tally under `--quiet`. A directory whose scan failed is
in it as `scan-error` and in `errors`, and an unselected `--root-children` sibling is in it and in
neither `truncated_paths` nor the entries, so its keys can outnumber `truncated_paths`.

`target_logical_bytes` and `target_reclaimable_local_bytes` count walked subtrees only.
`totals_are_lower_bounds` is `true` on every scan that left any subtree unwalked and on every
`--root-children` scan, so read those totals as lower bounds then.

A hint may set `entry_types` (`file`, `directory`, `link`, `other`) to match only those entry kinds,
`link` being a symlink or reparse point; a hint that sets none matches every kind. The baseline
`*.tmp` and `*.lock` hints match files and links, so a directory such as `~/.codex/.tmp` is not
hinted. The scan does not probe processes, so a `common-lock-file` hint stays at confidence `low`
and whether the lock is stale is proven during investigation (step 2 of the skill).

The snapshot lists up to 200 sorted `empty_directory_paths` with `empty_directory_paths_truncated`;
`scan-complete` stdout carries only `empty_directory_count`.
