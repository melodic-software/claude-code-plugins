# Scan flag detail

Flag-by-flag behavior of the `scan` flags `--quiet`, `--root-children` with `--root-child`, and
`--sizes-only` for `/disk-hygiene:clean`. The parse contract, the rejection rules, and the
confirmation gate stay in [SKILL.md](../SKILL.md#arguments-and-boundaries).

## `--quiet`

`--quiet` shapes the scan's stdout and nothing else: it omits `children_rollup`, prints
`truncated_paths` as a count instead of the list, prints `truncation_reasons` as a per-reason tally
instead of a path map, and shortens the closing note, leaving every
counter, byte total, error and policy source in place. The snapshot file carries the rollup, the
truncated-path list and each path's reason in full in both modes, so read per-child detail and the coverage gaps there and
pass `--quiet` whenever the run only needs the frontier summary. `truncation_reasons` covers every
unwalked path, including a directory whose scan failed (`scan-error`, also listed in `errors`), which
`truncated_paths` omits, so the tally can sum to more than the `truncated_paths` count.

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

## `--sizes-only`

`--sizes-only` as implemented: it does not ask the large-scan question, so a known-large root walks
without `--max-depth` or `--confirmed-large-scan`. It does not stop at VCS or protected
directories: it sums through them, read-only, and writes no entries. It has no entry cap.
