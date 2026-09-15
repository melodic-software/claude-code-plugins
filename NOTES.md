# Notes — #497 / PR #1395

## Correction to the orchestration brief's premise

The dispatch brief described this change as hoisting `resolve_authors` above `build_config` in
`pr_queue_snapshot.py`, "activating `detect_foreign_activity` in `--pr` mode and adding a `gh api
user` network call to a path that previously avoided it," and asked for a high-blast-radius diff
review on that basis.

That describes issue #497's *Suggested fix direction*, not this branch's diff. The actual diff
touches **no production code**. Verified:

- `git diff origin/main...HEAD --stat` covered only `plugin.json`, `CHANGELOG.md`, and
  `tests/test_pr_queue_snapshot.py`.
- The hoist already shipped in #882 (`0.16.0`). On `main`, `resolve_self_logins` is at
  `pr_queue_snapshot.py:187`, above `build_config` (`:190`) and above the `--pr`/`--queue` split
  (`:195`). `git log -S resolved_self_logins` attributes it to `7d3b596801` (#882).
- The new `gh api user` call therefore also belongs to #882, not here. The new tests stub the whole
  `babysit_gh` seam, so they spawn no `gh` process.

So the blast radius is *lower* than briefed, not higher. #497 is closed by proving acceptance, which
is what #882 explicitly deferred.

## Verification performed

- Full engine suite (#497's explicit verification note — the whole suite, not just
  `test_babysit_delta.py`): `python -m unittest discover -s tests -t .` from
  `plugins/source-control/skills/babysit-prs/scripts/` → **350 tests, OK**, including
  `test_integration.py`.
- Mutation check (stronger than the commit-message evidence the brief asked for): forcing
  `resolve_self_logins` to return `[]` — the pre-#882 condition — fails **both** new tests; restoring
  it passes them. The tests are genuine regression guards, not vacuous.

## Branch-owned defect found and fixed during the gate

The branch bumped `source-control` `0.26.3 → 0.26.4` and added a `## [0.26.4]` changelog entry. While
the branch sat unmerged, `main` independently shipped its own `0.26.4` for #601. That collided on
both the manifest value and the changelog heading — `git merge-tree` reported a real conflict, and
sibling PR #1382 had already claimed `0.26.5`.

Resolution: dropped the bump and the changelog entry rather than renumbering into the version race.
Rationale, from `docs/MIGRATION-PLAYBOOK.md` ("Version pinning and update delivery"): the bump is the
consumer *delivery vehicle*, and a consumer never runs the plugin's unit tests, so a tests-only
change earns no bump. CI's `changelog-parity-gate` is conditional (`--check-bump` fires only *if* a
version changed), so no-bump is gate-clean — confirmed green on the PR. Post-fix `git merge-tree`
reports zero conflicts and GitHub reports `MERGEABLE`.

Note: PRs #1350, #1347, #1344, #1341 are all still pinned at `0.26.3` against a `main` at `0.26.4`;
#1341 already shows `CONFLICTING / DIRTY`. Out of scope here (brief: do not touch other PRs), but
they are latent conflicts, not a convention to copy.

## Environment issue encountered

Mid-run, the Bash/Git-Bash tool wedged — even `echo alive` timed out, while PowerShell and the D:
drive stayed responsive. Root cause was not stale git locks (`find` for `*.lock` came back empty);
other agents' git processes were contending on the shared object store. Recovered by switching to
the PowerShell tool. No processes were killed.
