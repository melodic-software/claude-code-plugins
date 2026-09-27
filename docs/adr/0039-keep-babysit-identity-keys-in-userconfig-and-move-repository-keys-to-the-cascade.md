# Keep babysit identity keys in userConfig and move repository keys to the cascade

- Status: accepted
- Date: 2026-09-27

## Context

source-control declares 17 `userConfig` keys for `/source-control:babysit-prs` and
`/source-control:pull-request`: who the operator is, which owners the loop watches, which bots it
trusts, and how a repository merges and reviews. `userConfig` values live in `pluginConfigs`, which
Claude Code reads from user settings, the `--settings` flag, and managed settings only; a project's
`.claude/settings.json` is ignored
([hook-config-delivery](../conventions/hook-config-delivery/README.md), fact 5). A sandbox probe on
Claude Code 2.1.283 (2026-09-27) also showed that `claude plugin install --config` writes the value
to user settings whatever `-s` says (fact 9). So each of these keys has one value per machine.

The layered `.claude/source-control.md` cascade (user-global, team-tracked, local overlay, per key,
last wins) is the plugin's other configuration surface, and it can hold a different value per
repository. The question was whether to move the babysit keys to the cascade (the default proposed
by the lane notes, with a deprecation window) or to keep them in `userConfig` on purpose.

The question was answered by an unattended interview: the lane lead took the default, and a
fresh-context validator, given the question with the lead's rationale withheld, returned the
verdict HYBRID, which this record adopts.

## Decision

1. **Identity and trust keys stay in `userConfig`**: `babysit_watched_owners`,
   `babysit_self_logins`, `babysit_intended_write_identity`, `babysit_lane_logins`,
   `babysit_approver_bot_logins`, `babysit_extra_bot_logins`. A repository-writable layer would let
   the repository being worked on widen the loop's own authority:
   - the owner trust boundary (which repositories the loop acts in at all);
   - the self exemption, under which the operator's own PRs skip the unprotected-base hold and get
     neutral replies;
   - the lane and approver logins that decide a PR's merge tier;
   - the bot logins whose threads the loop resolves on its own.

   `babysit_watched_owners` is also circular when read from a repository: the loop needs it to
   decide which repositories to read in the first place.
2. **`branch_issue_pattern` moves now.** It only affects drafting, it applies to one checkout, and a
   plain per-key override is safe for it. `parse-branch-issue.sh` reads the three cascade layers
   first; the `userConfig` value is a deprecated fallback that prints a note naming the cascade
   key. A later minor release removes the fallback with a CHANGELOG `Removed` entry, no earlier
   than 2026-12-27.
3. **Ten repository-policy keys move later**, under
   [#4572](https://github.com/melodic-software/claude-code-plugins/issues/4572):
   `babysit_merge_method`, `babysit_merge_block_labels`,
   `babysit_extra_dependency_manager_logins`, `babysit_approval_downgrade_logins`,
   `babysit_skip_downgrade_logins`, `babysit_review_trigger_phrase`, `babysit_review_bot_logins`,
   `babysit_review_settle_minutes`, `babysit_review_gate_context`, `babysit_ci_gateway_context`.
   The loop acts on many repositories from one session, so that move needs a resolver that reads
   each target repository's cascade from its default branch, a union (policy-floor) merge mode for
   hold lists so a repository layer can add holds but not remove them, the review trigger and
   review bot keys bound as one unit, and the same deprecated `userConfig` fallback.
4. **Out of scope:** any design letting a repository-writable layer set a key that widens
   authority, or replace a hold list under plain per-key override. That loosens a security policy
   and is the operator's call.

## Consequences

- An operator with several identity domains on one machine (for example a work account and a
  personal account) gets one value per machine for each key in decision 1 and for the ten keys in
  decision 3 until they move. Such an operator either leaves those keys unset or launches the lane
  with a per-domain `--settings` file. `--settings` is a documented `pluginConfigs` read source
  (fact 5); how its `pluginConfigs` merges with the user settings value is unverified.
- Repositories can set `branch_issue_pattern` for themselves today; the `userConfig` twin keeps
  working with a deprecation note until its removal release.
- `plugins/source-control/reference/config-resolution.md` states the split and the multi-domain
  consequence, and cites this record.
- The ten deferred keys keep today's behaviour until #4572 ships.
