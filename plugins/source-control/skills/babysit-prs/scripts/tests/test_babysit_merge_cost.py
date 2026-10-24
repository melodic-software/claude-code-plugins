"""`cost_decision`: only an owner `**Decision recorded.**` comment on the
pull request, or on its linked issue naming it as `#<number>`, linked from
the body, clears a cost hold, for the head it decided and a later head whose
every change since is a base merge (owner decisions Q17 c and Q18 d on
#9436)."""

from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy

REPO = "owner/repo"
LINK = "https://github.com/owner/repo/issues/40#issuecomment-7"
IDENTITY = "agent-lanes[bot]"
PR_CREATED = "2026-10-22T10:00:00Z"
HEAD = "0123456789abcdef0123456789abcdef01234567"
BASE = "main"
OLD = "fedcba9876543210fedcba9876543210fedcba98"
LANE = {"login": "github-actions[bot]", "type": "Bot"}
PULL = {
    "number": 99,
    "created_at": PR_CREATED,
    "head": {"sha": HEAD, "ref": "fix/cost", "repo": {"full_name": REPO}},
    "base": {"sha": "89abcdef0123456789abcdef0123456789abcdef", "ref": BASE},
}
TF = {"filename": "infra/main.tf", "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}


def _marker(
    sha: str,
    at: str = "2026-10-22T11:00:00Z",
    criteria: str = "cost",
    user: dict[str, Any] = LANE,
) -> dict[str, Any]:
    body = f"<!-- claude-lane-hold lane=claude-review sha={sha} criteria={criteria} -->\nHeld."
    return {"user": user, "node_id": "IC_M", "created_at": at, "body": body}


def _net(*files: dict[str, Any]) -> dict[str, Any]:
    return {"files": list(files)}


def _comment(**changes: Any) -> dict[str, Any]:
    return {
        "issue_url": "https://api.github.com/repos/owner/repo/issues/40",
        "user": {"login": "owner-person", "type": "User"},
        "performed_via_github_app": None,
        "body": "**Decision recorded.** Cost: approve the larger runner for #99.",
        "node_id": "IC_7",
        "created_at": "2026-10-22T12:00:00Z",
    } | changes


class CostDecision(unittest.TestCase):
    def decide(
        self,
        *,
        body: str = f"Closes #40\n\nCost decision: {LINK}\n",
        comment: dict[str, Any] | None = None,
        status: int = 200,
        permission: str = "admin",
        edited: Any = None,
        issue: int | None = 40,
        node: Any = ...,
        created: Any = None,
        markers: list[dict[str, Any]] | None = None,
        compares: dict[str, Any] | None = None,
        unreadable: str = "",
        pull: dict[str, Any] | None = None,
        marker_node: Any = ...,
    ) -> str | None:
        created = PR_CREATED if created is None else created
        self.reads: list[str] = []
        compares = compares or {}

        def get(endpoint: str) -> tuple[int | None, Any]:
            self.reads.append(endpoint)
            if "/compare/" in endpoint:
                sha = endpoint.rsplit("...", 1)[1]
                if sha in compares and unreadable != f"compare {sha}":
                    return 200, compares[sha]
                return 404, None
            return status, comment if comment is not None else _comment()

        def paginated(endpoint: str, label: str) -> list[dict[str, Any]]:
            self.reads.append(endpoint)
            if label == unreadable:
                raise policy.PolicyReadError(label)
            self.assertEqual(endpoint, "repos/owner/repo/issues/99/comments?per_page=100")
            return [_marker(HEAD)] if markers is None else markers

        answer = {"lastEditedAt": edited} if node is ... else node
        held = {"lastEditedAt": None} if marker_node is ... else marker_node

        def graphql(_query: str, what: str, **variables: Any) -> dict[str, Any]:
            if variables.get("id") != "IC_M":
                return {"node": answer}
            self.reads.append("marker edited")
            if unreadable == "marker edited":
                raise policy.PolicyReadError(what)
            return {"node": held}

        with (
            mock.patch.object(policy, "_get", side_effect=get),
            mock.patch.object(policy, "_paginated", side_effect=paginated),
            mock.patch.object(policy, "_graphql", side_effect=graphql),
        ):
            return policy.cost_decision(
                REPO,
                (pull or PULL) | {"body": body, "created_at": created},
                issue,
                permission=lambda login: permission,
                agent_identity=IDENTITY,
                self_logins=frozenset({"lane-operator"}),
            )

    def test_an_owner_decision_on_the_closing_issue_clears(self) -> None:
        self.assertEqual(self.decide(), LINK)
        self.assertEqual(
            self.reads,
            [
                "repos/owner/repo/issues/comments/7",
                "repos/owner/repo/issues/99/comments?per_page=100",
                "marker edited",
            ],
        )

    def test_a_decision_on_the_pull_request_itself_clears(self) -> None:
        link = "https://github.com/owner/repo/pull/99#issuecomment-7"
        comment = _comment(
            issue_url="https://api.github.com/repos/owner/repo/issues/99",
            body="**Decision recorded.** Cost: approve it.",
        )
        self.assertEqual(self.decide(body=link, comment=comment), link)

    def test_an_issue_decision_counts_only_when_it_names_the_pull_request(
        self,
    ) -> None:
        for text in ("for #99.", "(#99)", "#99", "see #99, then"):
            with self.subTest(text):
                comment = _comment(body=f"**Decision recorded.** Cost: ok {text}")
                self.assertEqual(self.decide(comment=comment), LINK)
        for text in (
            "for another change.",
            "for #98.",
            "for #990.",
            "for owner/repo#99.",
            "for x#99.",
            "for pull 99.",
            "for &#99;",
            "for ##99.",
        ):
            with self.subTest(text):
                comment = _comment(body=f"**Decision recorded.** Cost: ok {text}")
                self.assertIsNone(self.decide(comment=comment))

    def test_a_refs_issue_decision_naming_the_pull_request_clears(self) -> None:
        # The caller passes `_linked_issue`'s number: here the Refs issue.
        self.assertEqual(self.decide(body=f"Refs: #40\n\n{LINK}\n"), LINK)

    def test_a_decision_on_the_pull_request_needs_no_time_check(self) -> None:
        link = "https://github.com/owner/repo/pull/99#issuecomment-7"
        comment = _comment(
            issue_url="https://api.github.com/repos/owner/repo/issues/99",
            created_at="2026-10-21T09:00:00Z",
        )
        markers = [_marker(HEAD, "2026-10-21T08:00:00Z")]
        self.assertEqual(self.decide(body=link, comment=comment, markers=markers), link)
        # With no time it decides no head, so it carries to none.
        timeless = comment | {"created_at": None}
        self.assertIsNone(self.decide(body=link, comment=timeless))

    def test_a_decision_on_another_issue_does_not_cover_it(self) -> None:
        other = "https://github.com/owner/repo/issues/12#issuecomment-7"
        self.assertIsNone(self.decide(body=other))
        self.assertEqual(self.reads, [])

    def test_a_link_into_another_repository_is_ignored(self) -> None:
        self.assertIsNone(self.decide(body=LINK.replace("owner/repo", "evil/repo")))

    def test_a_comment_that_is_not_on_the_linked_issue_is_refused(self) -> None:
        moved = _comment(issue_url="https://api.github.com/repos/owner/repo/issues/41")
        self.assertIsNone(self.decide(comment=moved))

    def test_each_failing_condition_holds(self) -> None:
        cases = {
            "write, not admin": dict(permission="write"),
            "edited": dict(edited="2026-10-22T10:00:00Z"),
            "unreadable": dict(status=404),
            "no decision line": dict(comment=_comment(body="Sounds fine to me.")),
            "quoted decision": dict(
                comment=_comment(body="> **Decision recorded.** quoted")
            ),
            "posted through an App": dict(
                comment=_comment(performed_via_github_app={"slug": "cursor"})
            ),
            "a non-admin naming the pull request": dict(
                permission="write",
                comment=_comment(
                    user={"login": "someone", "type": "User"},
                    body="**Decision recorded.** Cost: approve #99.",
                ),
            ),
            "a bot": dict(
                comment=_comment(user={"login": "agent-lanes[bot]", "type": "Bot"})
            ),
            "the agent identity": dict(
                comment=_comment(user={"login": "agent-lanes", "type": "User"})
            ),
            "no body link": dict(body="Closes #40"),
            "no cost marker": dict(
                comment=_comment(body="**Decision recorded.** Option 2.")
            ),
            "a cost marker on the next line": dict(
                comment=_comment(body="**Decision recorded.**\nCost: approve it.")
            ),
            "a cost marker on a later line": dict(
                comment=_comment(body="**Decision recorded.** Option 2.\n\nCost: n/a")
            ),
            "a self login": dict(
                comment=_comment(user={"login": "lane-operator", "type": "User"})
            ),
            "a link inside an HTML comment": dict(
                body=f"Closes #40\n<!-- {LINK} -->\n"
            ),
            "a link after an unclosed HTML comment": dict(
                body=f"Closes #40\n<!--\n{LINK}\n"
            ),
            "a null node": dict(node=None),
            "a decision older than the pull request": dict(
                comment=_comment(created_at="2026-10-21T09:00:00Z")
            ),
            "a decision at the pull request's creation": dict(
                comment=_comment(created_at=PR_CREATED)
            ),
            "no comment time": dict(comment=_comment(created_at=None)),
            "no pull request time": dict(created=""),
            "no lastEditedAt key": dict(node={}),
        }
        for name, change in cases.items():
            with self.subTest(name):
                self.assertIsNone(self.decide(**change))

    # The carry rule (#9436 Q18 d): the decided head is OLD, the head HEAD.
    def later(self, compares: dict[str, Any], **change: Any) -> str | None:
        return self.decide(markers=[_marker(OLD)], compares=compares, **change)

    def test_a_base_merge_after_the_decision_carries(self) -> None:
        self.assertEqual(self.later({OLD: _net(TF), HEAD: _net(TF)}), LINK)
        # The same decision at a head whose net change moved does not.
        self.assertIsNone(self.later({OLD: _net(), HEAD: _net(TF)}))

    def test_a_pull_request_commit_after_the_decision_re_holds(self) -> None:
        script = {"filename": "scripts/run.sh", "status": "modified", "patch": "+y"}
        self.assertIsNone(self.later({OLD: _net(TF), HEAD: _net(TF, script)}))
        self.assertEqual(
            self.reads[-2:],
            [
                f"repos/owner/repo/compare/{BASE}...{OLD}",
                f"repos/owner/repo/compare/{BASE}...{HEAD}",
            ],
        )

    def test_a_rebase_with_the_same_net_change_carries_in_any_file_order(
        self,
    ) -> None:
        doc = {"filename": "docs/a.md", "status": "added", "patch": "+a"}
        self.assertEqual(self.later({OLD: _net(TF, doc), HEAD: _net(doc, TF)}), LINK)
        # A rebase that drops one of its files is a change of its own.
        self.assertIsNone(self.later({OLD: _net(TF, doc), HEAD: _net(TF)}))

    def test_a_conflict_resolution_that_changes_the_net_change_re_holds(
        self,
    ) -> None:
        for name, changed in {
            "an edited patch": TF | {"patch": "@@ -1 +1 @@\n-a\n+c"},
            "a rename": TF | {"status": "renamed", "previous_filename": "old.tf"},
            "a status": TF | {"status": "added"},
        }.items():
            with self.subTest(name):
                self.assertIsNone(self.later({OLD: _net(TF), HEAD: _net(changed)}))

    def test_a_compare_of_300_files_or_a_file_with_no_patch_does_not_carry(
        self,
    ) -> None:
        def many(n: int) -> dict[str, Any]:
            return _net(
                *({"filename": f"f{i}", "status": "added", "patch": "+x"} for i in range(n))
            )

        self.assertEqual(self.later({OLD: many(299), HEAD: many(299)}), LINK)
        self.assertIsNone(self.later({OLD: many(300), HEAD: many(300)}))
        binary = {"filename": "a.png", "status": "modified"}
        self.assertIsNone(self.later({OLD: _net(binary), HEAD: _net(binary)}))

    def test_a_failed_read_does_not_carry(self) -> None:
        same = {OLD: _net(TF), HEAD: _net(TF)}
        self.assertIsNone(self.later(same, unreadable=f"compare {HEAD}"))
        self.assertIsNone(self.later(same, unreadable="cost hold markers"))
        self.assertIsNone(self.later({OLD: _net(TF), HEAD: {"status": "diverged"}}))

    def test_the_decided_head_is_the_latest_bot_marker_before_the_decision(
        self,
    ) -> None:
        added = {"filename": "b.tf", "status": "added", "patch": "+b"}
        changed = {OLD: _net(TF), HEAD: _net(TF, added)}
        older_head = [_marker(HEAD, "2026-10-22T10:30:00Z"), _marker(OLD, "2026-10-22T11:30:00Z")]
        self.assertIsNone(self.decide(markers=older_head, compares=changed))
        newer_head = [_marker(OLD, "2026-10-22T10:30:00Z"), _marker(HEAD, "2026-10-22T11:30:00Z")]
        self.assertEqual(self.decide(markers=newer_head, compares=changed), LINK)
        for name, extra in {
            "after": _marker(HEAD, "2026-10-22T12:30:00Z"),
            "a person": _marker(HEAD, "2026-10-22T11:30:00Z", user={"type": "User"}),
            "another bot": _marker(
                HEAD, "2026-10-22T11:30:00Z", user={"login": "claude[bot]", "type": "Bot"}
            ),
            "not on the first line": _marker(HEAD, "2026-10-22T11:30:00Z")
            | {"body": f"Held.\n<!-- claude-lane-hold lane=claude-review sha={HEAD} criteria=cost -->"},
            "not cost": _marker(HEAD, "2026-10-22T11:30:00Z", criteria="trust-gate"),
        }.items():
            with self.subTest(name):
                self.assertIsNone(
                    self.decide(markers=[_marker(OLD), extra], compares=changed)
                )
        both = _marker(HEAD, "2026-10-22T11:30:00Z", criteria="cost,trust-gate")
        self.assertEqual(self.decide(markers=[_marker(OLD), both], compares=changed), LINK)

    def test_with_no_marker_before_the_decision_nothing_carries(self) -> None:
        link = "https://github.com/owner/repo/pull/99#issuecomment-7"
        own = _comment(issue_url="https://api.github.com/repos/owner/repo/issues/99")
        for body, comment in ((link, own), (LINK, None)):
            with self.subTest(body):
                self.assertIsNone(self.decide(body=body, comment=comment, markers=[]))
                self.assertFalse(any("/compare/" in r for r in self.reads))

    def test_an_edited_or_unreadable_newest_marker_does_not_carry(self) -> None:
        same = {OLD: _net(TF), HEAD: _net(TF)}
        for name, change in {
            "edited": dict(marker_node={"lastEditedAt": "2026-10-22T11:05:00Z"}),
            "a null node": dict(marker_node=None),
            "no lastEditedAt key": dict(marker_node={}),
            "unreadable": dict(unreadable="marker edited"),
        }.items():
            with self.subTest(name):
                self.assertIsNone(self.decide(**change))
                self.assertIsNone(self.later(same, **change))
        # An older unedited marker at this head does not stand in.
        older = [_marker(HEAD, "2026-10-22T10:00:00Z"), _marker(OLD)]
        edited = {"lastEditedAt": "2026-10-22T11:05:00Z"}
        self.assertIsNone(self.decide(markers=older, compares=same, marker_node=edited))

    def test_at_the_decided_head_it_carries_with_no_compare_read(self) -> None:
        pull = PULL | {"base": {"ref": "-unusable"}}
        self.assertEqual(self.decide(pull=pull), LINK)
        self.assertFalse(any("/compare/" in r for r in self.reads))

    def test_a_duplicate_filename_a_pure_rename_or_an_unusable_base_does_not_carry(
        self,
    ) -> None:
        self.assertIsNone(self.later({OLD: _net(TF, TF), HEAD: _net(TF, TF)}))
        moved = {"filename": "b.tf", "status": "renamed", "previous_filename": "a.tf"}
        self.assertIsNone(self.later({OLD: _net(moved), HEAD: _net(moved)}))
        same = {OLD: _net(TF), HEAD: _net(TF)}
        for base in ("-main", "a..b", "a b", "", "x" * 256, None):
            with self.subTest(base):
                pull = PULL | {"base": {"ref": base}}
                self.assertIsNone(self.later(same, pull=pull))
                self.assertFalse(any("/compare/" in r for r in self.reads))
        pull = PULL | {"base": {"ref": "release/2.x"}}
        self.assertEqual(self.later(same, pull=pull), LINK)
        self.assertIn(f"repos/owner/repo/compare/release/2.x...{OLD}", self.reads)

    def test_the_decision_is_the_newest_on_the_pull_request_else_the_issue(
        self,
    ) -> None:
        def on_pull(n: int) -> str:
            return f"https://github.com/owner/repo/pull/99#issuecomment-{n}"

        rows = {
            "7": _comment(created_at="2026-10-22T12:00:00Z"),
            "8": _comment(
                issue_url="https://api.github.com/repos/owner/repo/issues/99",
                created_at="2026-10-22T11:00:00Z",
            ),
            "9": _comment(
                issue_url="https://api.github.com/repos/owner/repo/issues/99",
                created_at="2026-10-22T11:30:00Z",
            ),
        }
        changed = {OLD: _net(TF), HEAD: _net(TF, {"filename": "b.tf", "status": "added", "patch": "+b"})}

        def pick(body: str, markers: list[dict[str, Any]]) -> str | None:
            def get(endpoint: str) -> tuple[int | None, Any]:
                if "/compare/" in endpoint:
                    sha = endpoint.rsplit("...", 1)[1]
                    return 200, changed[sha]
                return 200, rows[endpoint.rsplit("/", 1)[1]]

            with (
                mock.patch.object(policy, "_get", side_effect=get),
                mock.patch.object(policy, "_paginated", return_value=markers),
                mock.patch.object(
                    policy, "_graphql", return_value={"node": {"lastEditedAt": None}}
                ),
            ):
                return policy.cost_decision(
                    REPO,
                    PULL | {"body": body},
                    40,
                    permission=lambda login: "admin",
                    agent_identity=IDENTITY,
                )

        every = f"Closes #40\n{LINK}\n{on_pull(8)}\n{on_pull(9)}"
        self.assertEqual(pick(every, [_marker(HEAD, "2026-10-22T11:15:00Z")]), on_pull(9))
        older_head = [_marker(HEAD, "2026-10-22T10:00:00Z"), _marker(OLD, "2026-10-22T11:15:00Z")]
        self.assertIsNone(pick(every, older_head))
        self.assertEqual(pick(f"Closes #40\n{LINK}", [_marker(HEAD)]), LINK)

    def test_a_failed_permission_read_clears_nothing(self) -> None:
        def refuse(login: str) -> str:
            raise policy.PolicyReadError("permission unreadable")

        with (
            mock.patch.object(policy, "_get", return_value=(200, _comment())),
            mock.patch.object(policy, "_graphql") as graphql,
        ):
            decision = policy.cost_decision(
                REPO,
                PULL | {"body": LINK},
                40,
                permission=refuse,
                agent_identity=IDENTITY,
                self_logins=frozenset({"lane-operator"}),
            )
        self.assertIsNone(decision)
        graphql.assert_not_called()


class PulumiDirs(unittest.TestCase):
    PR = {"base": {"sha": "a" * 40}}

    def test_each_directory_holding_a_pulumi_yaml(self) -> None:
        tree = {
            "Pulumi.yaml": "100644",
            "infra/x/pulumi.YAML": "100644",
            "a.md": "100644",
        }
        with mock.patch.object(policy, "_tree_modes", return_value=tree):
            self.assertEqual(policy.pulumi_dirs_at(REPO, self.PR), ("", "infra/x"))

    def test_an_unlisted_tree_is_unknown(self) -> None:
        with mock.patch.object(policy, "_tree_modes", return_value=None):
            self.assertIsNone(policy.pulumi_dirs_at(REPO, self.PR))
        self.assertIsNone(policy.pulumi_dirs_at(REPO, {"base": {}}))


if __name__ == "__main__":
    unittest.main()
