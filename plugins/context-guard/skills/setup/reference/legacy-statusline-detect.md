# Legacy statusline detection — shared classification

The shared, plugin-name-free half of the two statusline guard plugins' legacy detection, synced
byte-identical between them by `scripts/sync-legacy-statusline-detect.sh` and registered in
`scripts/cross-plugin-source-registry.txt`. The hub SKILL.md supplies every concrete path: the
DURABLE SHIM COPY (the `bin/statusline-shim.sh` under this plugin's own operator-home directory)
and the SHIPPED SOURCE (`${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh`). These surfaces live
under `~/.claude/`, machine scope, outside the repo-scope retirement-manifest schema (ADR 0018,
decision 6), so their detection stays prose and is deduplicated here instead.

## Installed shim state

Compare the durable shim copy against the shipped source (the installed copy is byte-identical by
contract, so `cmp -s` is the test):

- **Absent.** FAIL when the statusline is wired to it (that wiring cannot run), INFO otherwise.
  Remediation: `apply`.
- **Present and identical.** PASS. Nothing about it needs revisiting on a plugin update; that is
  the whole point of the shim.
- **Present but differing.** Classify by what the installed revision can still do, not by the fact
  that it differs. Report the shipped `# shim-revision:` marker against the installed one either
  way, say which of the two behaviors the installed copy has, and offer `apply` as the refresh.
  - Installed revision **>= 3.** INFO: an older-but-adequate or hand-edited copy that still
    resolves the newest tee correctly. A refresh is housekeeping.
  - Installed revision **< 3, or unmarked.** FAIL. Revision 3 is the first that skips a candidate
    whose version directory carries the orphan marker; every earlier revision picks the newest tee
    by mtime alone, so it also resolves one left behind by an UNINSTALLED plugin and keeps teeing
    from that directory for the ~14 days before Claude Code reaps it, writing files the operator
    has no reason to expect. The statusline keeps rendering, which is why this reads as harmless
    and is not: it is a behavior defect in what the operator is running, and INFO would file it
    under a heading operators are told they can defer.
  - **The migration matters more than the classification.** The durable copy is what the
    statusline actually runs; a plugin update never overwrites it. An operator who ran `apply`
    before revision 3 shipped therefore keeps running the old shim until they re-run `apply`, and
    if they uninstall the plugin first, this skill is gone and the stale shim keeps teeing with no
    remaining way to reach the remediation. Say that in the finding, so the reason to act now is
    on screen.
- **The SHIPPED source is absent** (no `${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh`). INFO,
  and skip the comparison entirely: this installed plugin version predates the shim (< 0.2.0).
  Never report the operator's installed copy as drifted on this branch. Remediation: update this
  plugin (`/plugin update`), then re-run `check`. Until then the legacy version-pinned wiring
  below is the only wiring this version can offer.

## Legacy version-pinned wiring

A `statusLine` command that references this plugin's `statusline-tee.sh` under the plugin cache
(`.../plugins/cache/<marketplace>/<plugin>/<version>/scripts/…`) is LEGACY VERSION-PINNED WIRING,
regardless of whether that file currently exists. It is running today only until the next version
bump, and it breaks the whole statusline once the old version directory is pruned (~14 days after
an update). Report it as the failure mode this plugin's shim exists to remove, and print the shim
wiring as the fix (`apply` first if the shim is not installed). An interim `[ -f … ]` existence
guard around such a path is the same state: it survives pruning but still stops teeing on a
version bump.
