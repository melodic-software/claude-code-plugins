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
CHECKS = dict(policy.REVIEW_LANES)
PULL = {
    "number": 99,
    "created_at": PR_CREATED,
    "head": {"sha": HEAD, "ref": "fix/cost", "repo": {"full_name": REPO}},
    "base": {"sha": "89abcdef0123456789abcdef0123456789abcdef", "ref": BASE},
}
TF = {"filename": "infra/main.tf", "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}


def _run(
    sha: str,
    at: str = "2026-10-22T11:00:00Z",
    *,
    criteria: str = "cost",
    lane: str = "pr-review-hosted.yml",
    job: str | None = None,
    notice: str | None = None,
    created: str = "2026-10-22T10:30:00Z",
    repo: str | None = REPO,
) -> dict[str, Any]:
    """A review lane's pull_request run on `sha` with its head in `repo`,
    started at `created`, whose status job (or `job`) finished at `at` and
    recorded a hold notice naming `notice` (default `sha`)."""
    message = (
        f"claude-lane-hold lane=claude-review sha={notice or sha} "
        f"criteria={criteria} label=needs-human"
    )
    return {
        "lane": lane,
        "sha": sha,
        "at": at,
        "job": job or CHECKS[lane],
        "created": created,
        "repo": repo,
        "notes": [{"annotation_level": "notice", "message": message}],
    }


def _net(*files: dict[str, Any]) -> dict[str, Any]:
    return {"files": list(files)}


class Lanes:
    """The head reads of `_noticed_head` over `runs`, and the compares: a
    run's head answers _net(TF) unless `compares` names it. A read whose label
    (or `compare <sha>`) is `unreadable` fails. `reads` logs every endpoint and
    `envs` the environment each lane read took."""

    def __init__(self, runs: list[dict[str, Any]], compares: dict[str, Any], unreadable: str = "") -> None:
        self.runs = runs
        self.compares = {r["sha"]: _net(TF) for r in runs} | compares
        self.unreadable = unreadable
        self.reads: list[str] = []
        self.envs: list[Any] = []

    def get(self, endpoint: str, env: Any = None) -> tuple[int | None, Any]:
        self.reads.append(endpoint)
        sha = endpoint.rsplit("...", 1)[1]
        if sha in self.compares and self.unreadable != f"compare {sha}":
            return 200, self.compares[sha]
        return 404, None

    def paginated(
        self, endpoint: str, label: str, items_key: str | None = None, env: Any = None
    ) -> list[dict[str, Any]]:
        self.reads.append(endpoint)
        self.envs.append(env)
        if label == self.unreadable:
            raise policy.PolicyReadError(label)
        prefix = "repos/owner/repo/"
        if "/actions/workflows/" in endpoint:
            lane = endpoint.split("/actions/workflows/", 1)[1].split("/", 1)[0]
            assert endpoint == (
                f"{prefix}actions/workflows/{lane}/runs?event=pull_request"
                "&branch=fix%2Fcost&per_page=100"
            ), endpoint
            assert items_key == "workflow_runs"
            return [
                {
                    "id": i + 1,
                    "head_sha": r["sha"],
                    "created_at": r["created"],
                    "head_repository": r["repo"] and {"full_name": r["repo"]},
                }
                for i, r in enumerate(self.runs)
                if r["lane"] == lane
            ]
        if "/jobs?" in endpoint:
            assert items_key == "jobs"
            n = int(endpoint.split("/actions/runs/", 1)[1].split("/", 1)[0])
            run = self.runs[n - 1]
            return [{"id": n, "name": run["job"], "completed_at": run["at"]}]
        n = int(endpoint.split("/check-runs/", 1)[1].split("/", 1)[0])
        assert endpoint == f"{prefix}check-runs/{n}/annotations?per_page=100", endpoint
        return self.runs[n - 1]["notes"]


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
        runs: list[dict[str, Any]] | None = None,
        compares: dict[str, Any] | None = None,
        unreadable: str = "",
        pull: dict[str, Any] | None = None,
        head: str = HEAD,
    ) -> str | None:
        created = PR_CREATED if created is None else created
        self.lanes = lanes = Lanes(
            [_run(HEAD)] if runs is None else runs, compares or {}, unreadable
        )
        self.reads = lanes.reads

        def get(endpoint: str, env: Any = None) -> tuple[int | None, Any]:
            if "/compare/" in endpoint:
                return lanes.get(endpoint, env)
            self.reads.append(endpoint)
            return status, comment if comment is not None else _comment()

        answer = {"lastEditedAt": edited} if node is ... else node

        def graphql(query: str, what: str, **variables: Any) -> dict[str, Any]:
            self.assertEqual(query, policy.COMMENT_EDITED)
            return {"node": answer}

        with (
            mock.patch.object(policy, "_get", side_effect=get),
            mock.patch.object(policy, "_paginated", side_effect=lanes.paginated),
            mock.patch.object(policy, "_graphql", side_effect=graphql),
        ):
            return policy.cost_decision(
                REPO,
                (pull or PULL)
                | {"body": body, "created_at": created}
                | ({} if head == HEAD else {"head": {"sha": head, "ref": "fix/cost"}}),
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
                "repos/owner/repo/actions/workflows/pr-review-hosted.yml/runs"
                "?event=pull_request&branch=fix%2Fcost&per_page=100",
                f"repos/owner/repo/compare/{BASE}...{HEAD}",
                "repos/owner/repo/actions/runs/1/jobs?filter=all&per_page=100",
                "repos/owner/repo/check-runs/1/annotations?per_page=100",
                "repos/owner/repo/actions/workflows/pr-review-security-hosted.yml/runs"
                "?event=pull_request&branch=fix%2Fcost&per_page=100",
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
        runs = [_run(HEAD, "2026-10-21T08:00:00Z", created="2026-10-21T07:50:00Z")]
        self.assertEqual(self.decide(body=link, comment=comment, runs=runs), link)
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
        return self.decide(runs=[_run(OLD)], compares=compares, **change)

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
        for label in (
            "pr-review-hosted.yml runs",
            "pr-review-security-hosted.yml runs",
            "run 1 jobs",
            "job 1 annotations",
            f"compare {OLD}",
        ):
            with self.subTest(label):
                self.assertIsNone(self.later(same, unreadable=label))
        self.assertIsNone(self.later({OLD: _net(TF), HEAD: {"status": "diverged"}}))

    def test_the_decided_head_is_the_newest_cost_notice_before_the_decision(
        self,
    ) -> None:
        added = {"filename": "b.tf", "status": "added", "patch": "+b"}
        changed = {OLD: _net(TF), HEAD: _net(TF, added)}
        older_head = [_run(HEAD, "2026-10-22T10:40:00Z"), _run(OLD, "2026-10-22T11:30:00Z")]
        self.assertIsNone(self.decide(runs=older_head, compares=changed))
        late = "2026-10-22T11:30:00Z"
        for name, extra in {
            "a later notice at the head": _run(HEAD, late),
            "from the security lane": _run(HEAD, late, lane="pr-review-security-hosted.yml"),
            "with cost among its criteria": _run(HEAD, late, criteria="cost,trust-gate"),
        }.items():
            with self.subTest(name):
                self.assertEqual(self.decide(runs=[_run(OLD), extra], compares=changed), LINK)
        for name, extra in {
            "a job done after it": _run(HEAD, "2026-10-22T12:30:00Z"),
            "a run started after it": _run(HEAD, late, created="2026-10-22T12:10:00Z"),
            "a job other than the status job": _run(HEAD, late, job="pr-review / review-key"),
            "the other lane's status job name": _run(
                HEAD, late, job=CHECKS["pr-review-security-hosted.yml"]
            ),
            "a notice naming another head than its run's": _run(OLD, late, notice=HEAD),
            "a notice without cost": _run(HEAD, late, criteria="trust-gate"),
            "a run whose head is in another repository": _run(HEAD, late, repo="fork/repo"),
            "a run with no head repository": _run(HEAD, late, repo=None),
            "two heads at the newest time": _run(
                HEAD, lane="pr-review-security-hosted.yml"
            ),
        }.items():
            with self.subTest(name):
                self.assertIsNone(self.decide(runs=[_run(OLD), extra], compares=changed))
        # A run that started after the decision is not read at all.
        self.decide(runs=[_run(HEAD), _run(OLD, "2026-10-22T12:30:00Z", created="2026-10-22T12:10:00Z")])
        self.assertNotIn("repos/owner/repo/actions/runs/2/jobs?filter=all&per_page=100", self.reads)

    def test_a_lane_run_on_a_head_it_cannot_vet_decides_nothing(self) -> None:
        for name, answer in {
            "the code lane's workflow": _net(TF, {"filename": ".github/workflows/pr-review-hosted.yml"}),
            "the security lane's workflow": _net(
                {"filename": ".github/workflows/pr-review-security-hosted.yml"}
            ),
            "300 files": _net(*({"filename": f"f{i}"} for i in range(300))),
            "no file list": {"status": "diverged"},
        }.items():
            with self.subTest(name):
                self.assertIsNone(self.decide(compares={HEAD: answer}))
                runs = [_run(OLD, "2026-10-22T10:40:00Z"), _run(HEAD)]
                self.assertIsNone(self.decide(runs=runs, compares={OLD: answer}))

    def test_the_lane_reads_take_the_actions_token_when_set(self) -> None:
        with mock.patch.dict(policy.os.environ, {policy.ACTIONS_TOKEN_ENV: "job"}):
            self.assertEqual(self.decide(), LINK)
        self.assertEqual(self.lanes.envs, [{"GH_TOKEN": "job"}] * 4)
        with mock.patch.dict(policy.os.environ, {policy.ACTIONS_TOKEN_ENV: ""}):
            self.assertEqual(self.decide(), LINK)
        self.assertEqual(self.lanes.envs, [None] * 4)

    def test_the_decided_head_is_never_read_from_a_comment(self) -> None:
        self.decide()
        self.assertFalse(any("/issues/99/comments" in r for r in self.reads))

    def test_with_no_notice_before_the_decision_nothing_carries(self) -> None:
        link = "https://github.com/owner/repo/pull/99#issuecomment-7"
        own = _comment(issue_url="https://api.github.com/repos/owner/repo/issues/99")
        for body, comment in ((link, own), (LINK, None)):
            with self.subTest(body):
                self.assertIsNone(self.decide(body=body, comment=comment, runs=[]))
                self.assertFalse(any("/compare/" in r for r in self.reads))

    def test_at_the_decided_head_it_carries_with_no_net_change_compare(self) -> None:
        self.assertEqual(self.decide(), LINK)
        self.assertEqual(
            [r for r in self.reads if "/compare/" in r],
            [f"repos/owner/repo/compare/{BASE}...{HEAD}"],
        )
        # With no usable base no run can be vetted, so nothing carries.
        self.assertIsNone(self.decide(pull=PULL | {"base": {"ref": "-unusable"}}))

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

        def pick(body: str, runs: list[dict[str, Any]]) -> str | None:
            lanes = Lanes(runs, changed)

            def get(endpoint: str, env: Any = None) -> tuple[int | None, Any]:
                if "/compare/" in endpoint:
                    return lanes.get(endpoint, env)
                return 200, rows[endpoint.rsplit("/", 1)[1]]

            with (
                mock.patch.object(policy, "_get", side_effect=get),
                mock.patch.object(policy, "_paginated", side_effect=lanes.paginated),
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
        self.assertEqual(pick(every, [_run(HEAD, "2026-10-22T11:15:00Z")]), on_pull(9))
        older_head = [
            _run(HEAD, "2026-10-22T10:00:00Z", created="2026-10-22T09:50:00Z"),
            _run(OLD, "2026-10-22T11:15:00Z"),
        ]
        self.assertIsNone(pick(every, older_head))
        self.assertEqual(pick(f"Closes #40\n{LINK}", [_run(HEAD)]), LINK)

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
