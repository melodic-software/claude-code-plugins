# Scan flag detail

Flag-by-flag behavior of the `scan` flags `--quiet`, `--root-children` with `--root-child`, and
`--sizes-only`, plus the inventory flag `--deep`, for `/disk-hygiene:clean`. The parse contract, the rejection rules, and the
confirmation gate stay in [SKILL.md](../SKILL.md#arguments-and-boundaries).

## `--quiet`

`--quiet` shapes the scan's stdout and nothing else: it omits `children_rollup`, prints
`truncated_paths` as a count instead of the list, and shortens the closing note, leaving every
counter, byte total, error and policy source in place. The snapshot file carries the rollup and the
truncated-path list in full in both modes, so read per-child detail and the coverage gaps there and
pass `--quiet` whenever the run only needs the frontier summary.

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
when the target is the user's home directory, so the flag matters for any other target. It is not a
`scan` flag: it takes no `--max-depth`, snapshot or entry cap, and it produces a JSONL report that
`preview` and `apply` refuse. The `KEEP` reason rule and the unchanged gates:
[SKILL.md](../SKILL.md#deep-inventory).

Rows stream to `<data-root>/inventory/inventory-<stamp>.jsonl` with no entry cap, beside a `.json`
summary (`deep-inventory-report`; status `inventory-failed` and exit 5 when the validator rejects a
row). The shared listing schema is defined in `scripts/deep_inventory.py`: one row per entry with
the columns `name`, `ext`, `size`, `mtime`, `owner`, `producer`, `category`, `disposition`
(`KEEP`, `CANDIDATE`, `UNKNOWN`), `reason`, and `evidence`. A directory's `size` is the sum of the
files beneath it. Named categories: `superseded-version` (dotted versioned directories),
`plugin-cache-version` (cache versions no installed plugin references), `tmp-producer` (`/tmp`
entries by producer prefix), `transcript-dir` (project transcript directories whose source path is
gone), `dangling-symlink`, and `not-walked` (an unreadable or mounted subtree, one `UNKNOWN` row).
Every other entry is `unclassified`. Other read-only listings that need the same columns reuse this
schema instead of defining their own
([#5214](https://github.com/melodic-software/claude-code-plugins/issues/5214),
[#4006](https://github.com/melodic-software/claude-code-plugins/issues/4006)); their scope stays
their own.

## `--sizes-only`

`--sizes-only` as implemented: it does not ask the large-scan question, so a known-large root walks
without `--max-depth` or `--confirmed-large-scan`. It does not stop at VCS or protected
directories: it sums through them, read-only, and writes no entries. It has no entry cap.
