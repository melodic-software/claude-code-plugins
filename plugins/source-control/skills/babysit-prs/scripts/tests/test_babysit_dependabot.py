"""The Dependabot tier: `auto` only for verified Dependabot commits whose every
update is semver-patch or semver-minor; anything else is `review`.

Commit shapes are those of the REST pull-request commits API. The metadata
block is the one Dependabot writes into its commit message and
`dependabot/fetch-metadata` parses; the github-actions[bot] commit is the
repository's `[dependabot skip]` version bump (pr-bump-plugin-version.yml), as
`scripts/lib/changelog-fragments.sh` (`dependabot_only`) accepts it.
"""

from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_dependabot as dependabot

SHA = "d" * 40
ACTIONS_SHA = "e" * 40


def metadata(*updates: tuple[str, str | None]) -> str:
    lines = ["Bumps things.", "", "---", "updated-dependencies:"]
    for name, kind in updates:
        lines += [f"- dependency-name: {name}", "  dependency-version: 4.2.0"]
        lines += ["  dependency-type: direct:production"]
        if kind is not None:
            lines.append(f"  update-type: version-update:{kind}")
    lines += ["...", "", "Signed-off-by: dependabot[bot] <support@github.com>"]
    return "\n".join(lines)


def commit(
    message: str,
    *,
    sha: str = SHA,
    name: str = "dependabot[bot]",
    email: str = "49699333+dependabot[bot]@users.noreply.github.com",
    committer: str = "noreply@github.com",
    verified: bool = True,
) -> dict[str, Any]:
    return {
        "sha": sha,
        "commit": {
            "message": message,
            "author": {"name": name, "email": email},
            "committer": {"name": "GitHub", "email": committer},
            "verification": {"verified": verified},
        },
    }


def no_files(sha: str) -> list[str] | None:
    raise AssertionError(f"files read for a Dependabot commit {sha}")


class Classify(unittest.TestCase):
    TITLE = "build(deps): bump actions/checkout from 4.1.0 to 4.2.0"

    def test_a_patch_or_minor_update_is_auto(self) -> None:
        for kind, title in (
            ("semver-patch", "build(deps): bump x from 1.2.3 to 1.2.4"),
            ("semver-minor", self.TITLE),
        ):
            with self.subTest(kind=kind):
                result = dependabot.classify(
                    title, [commit(metadata(("x", kind)))], no_files
                )
                self.assertEqual((result.tier, result.reason), ("auto", None))
                self.assertEqual(result.updates, (dependabot.Update("x", kind),))

    def test_a_major_update_is_review(self) -> None:
        result = dependabot.classify(
            "build(deps): bump x from 4.2.0 to 5.0.0",
            [commit(metadata(("x", "semver-major")))],
            no_files,
        )
        self.assertEqual((result.tier, result.reason), ("review", "title-major"))
        # The metadata alone decides when the title names no versions.
        result = dependabot.classify(
            "build(deps): bump x", [commit(metadata(("x", "semver-major")))], no_files
        )
        self.assertEqual((result.tier, result.reason), ("review", "major:x"))

    def test_a_title_reading_major_overrides_minor_metadata(self) -> None:
        result = dependabot.classify(
            "Bump x from 1.9.0 to 2.0.0", [commit(metadata(("x", "semver-minor")))],
            no_files,
        )  # fmt: skip
        self.assertEqual((result.tier, result.reason), ("review", "title-major"))

    def test_a_zero_major_minor_change_reads_as_major_from_the_title(self) -> None:
        result = dependabot.classify(
            "Bump x from 0.3.1 to 0.4.0", [commit(metadata(("x", None)))], no_files
        )
        self.assertEqual(result.tier, "review")

    def test_a_missing_update_type_takes_the_title_or_is_review(self) -> None:
        result = dependabot.classify(
            "Bump x from 1.2.0 to 1.3.0", [commit(metadata(("x", None)))], no_files
        )
        self.assertEqual(result.tier, "auto")
        result = dependabot.classify(
            "Bump x", [commit(metadata(("x", None)))], no_files
        )
        self.assertEqual(
            (result.tier, result.reason), ("review", "update-type-unknown:x")
        )

    def test_a_group_with_one_major_entry_is_review(self) -> None:
        message = metadata(
            ("actions/checkout", "semver-minor"),
            ("actions/setup-node", "semver-major"),
            ("github/codeql-action", "semver-patch"),
        )
        result = dependabot.classify(
            "build(deps): bump the github-actions group with 3 updates",
            [commit(message)],
            no_files,
        )
        self.assertEqual(
            (result.tier, result.reason), ("review", "major:actions/setup-node")
        )

    def test_a_non_major_group_is_auto(self) -> None:
        message = metadata(("a", "semver-minor"), ("b", "semver-patch"))
        result = dependabot.classify(
            "build(deps): bump the vendor-actions group across 1 directory with 2 updates",
            [commit(message)],
            no_files,
        )
        self.assertEqual(result.tier, "auto")
        self.assertEqual(len(result.updates), 2)

    def test_a_group_count_the_metadata_does_not_match_is_review(self) -> None:
        result = dependabot.classify(
            "bump the g group with 3 updates",
            [commit(metadata(("a", "semver-minor"), ("b", "semver-patch")))],
            no_files,
        )
        self.assertEqual(result.reason, "group-count:3-of:2")

    def test_a_commit_not_dependabots_is_review(self) -> None:
        cases = {
            "commit-unverified": commit(
                metadata(("x", "semver-patch")), verified=False
            ),
            # A pusher can write any author and committer, not the signature.
            "commit-not-committed-by-github": commit(
                metadata(("x", "semver-patch")), committer="someone@example.com"
            ),
            "commit-not-dependabot": commit(
                "fix: tweak", name="octocat", email="octocat@example.com"
            ),
        }
        for reason, other in cases.items():
            with self.subTest(reason=reason):
                result = dependabot.classify(
                    self.TITLE, [commit(metadata(("x", "semver-minor"))), other],
                    no_files,
                )  # fmt: skip
                self.assertEqual(result.tier, "review")
                self.assertEqual(result.reason, f"{reason}:{SHA[:12]}")

    def test_the_repositorys_version_bump_commit_is_accepted(self) -> None:
        bump = commit(
            "chore(plugins): release bump for Dependabot update [dependabot skip]",
            sha=ACTIONS_SHA,
            name="github-actions[bot]",
            email="41898282+github-actions[bot]@users.noreply.github.com",
        )
        paths = {
            ACTIONS_SHA: [
                "plugins/miro/.claude-plugin/plugin.json",
                "plugins/miro/CHANGELOG.md",
            ]
        }
        result = dependabot.classify(
            self.TITLE, [commit(metadata(("x", "semver-minor"))), bump], paths.get
        )
        self.assertEqual(result.tier, "auto")
        # Any other path, an unreadable listing, or no skip marker is review.
        for files, message in (
            (["plugins/miro/server.js"], bump["commit"]["message"]),
            (None, bump["commit"]["message"]),
            (paths[ACTIONS_SHA], "chore(plugins): release bump"),
        ):
            with self.subTest(files=files, message=message):
                other = {**bump, "commit": {**bump["commit"], "message": message}}
                result = dependabot.classify(
                    self.TITLE,
                    [commit(metadata(("x", "semver-minor"))), other],
                    lambda sha, f=files: f,
                )
                self.assertEqual(result.tier, "review")

    def test_no_commits_or_no_metadata_is_review(self) -> None:
        self.assertEqual(
            dependabot.classify(self.TITLE, [], no_files).reason, "commits-missing"
        )
        result = dependabot.classify(self.TITLE, [commit("Bump x")], no_files)
        self.assertEqual(result.reason, "metadata-missing")


class IsDependabot(unittest.TestCase):
    def test_every_login_form_the_code_sees(self) -> None:
        for login in (
            "app/dependabot",
            "dependabot[bot]",
            "dependabot",
            "Dependabot[bot]",
        ):
            self.assertTrue(dependabot.is_dependabot(login), login)
        for login in ("dependabot-preview[bot]", "renovate[bot]", "", None):
            self.assertFalse(dependabot.is_dependabot(login), login)


if __name__ == "__main__":
    unittest.main()
