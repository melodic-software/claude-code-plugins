#!/usr/bin/env python3
"""Post the verification evidence comment from the merge gate.

The pr-merge lane posts it after the verifier passed the head and before the
head is enqueued or armed: from `babysit_merge.unattended_enqueue` (the
`merge-pr` activity) and, through `post`, from enable-auto-merge.mjs (the
`enable-auto-merge` activity). The pr-verify jobs hold read tokens only, so
neither can post it there.

The comment links the head's `pr-capture-<pr>-<head>` artifact and says when
it expires; it uploads no file. An artifact counts only when the run that
uploaded it is `.github/workflows/pr-verify-capture.yml` on main, started by
`workflow_run`, in this repository, succeeded, and its title names the head:
any other workflow, a fork's pull request run included, can upload an artifact
by the same name. With no such artifact, nothing is posted and the merge goes
on. The comment carries the marker `/source-control:pull-request evidence`
writes, one per pull request, updated in place for each new head.

`post --repo <owner/repo> --pr <n> --head <sha> --identity <login>` prints one
JSON line, `{"outcome": ...}`: `created`, `updated`, `unchanged`,
`no-capture`, or `error: <detail>`. It exits 0 on every outcome. The Actions
reads run under `BABYSIT_VERIFY_GH_TOKEN` when it is set, the comment write
under `GH_TOKEN`.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections.abc import Callable
from typing import Any

from babysit_util import is_json_object, json_array, json_object

MARKER = "<!-- evidence-verification -->"
CAPTURE_WORKFLOW = ".github/workflows/pr-verify-capture.yml"
TOKEN_ENV = "BABYSIT_VERIFY_GH_TOKEN"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})T")
# The capture workflow's run-name: its upstream run and the head.
TITLE_RE = re.compile(r"pr-verify-capture [1-9][0-9]* ([0-9a-f]{40})")

Read = Callable[[list[str]], Any]


def artifact_name(number: int, head: str) -> str:
    return f"pr-capture-{number}-{head}"


def capture_run(run: Any, repo: str, head: str) -> bool:
    """Whether `run` is a successful pr-verify-capture run on main for `head`."""
    if not is_json_object(run):
        return False
    title = TITLE_RE.fullmatch(str(run.get("display_title") or ""))
    return (
        run.get("path") == CAPTURE_WORKFLOW
        and run.get("event") == "workflow_run"
        and run.get("head_branch") == "main"
        and json_object(run.get("repository")).get("full_name") == repo
        and run.get("conclusion") == "success"
        and title is not None
        and title.group(1) == head
    )


def find_capture(
    repo: str, number: int, head: str, read: Read
) -> dict[str, Any] | None:
    """The newest unexpired capture artifact for `head` whose run is the
    capture workflow's, or None. Raises what `read` raises."""
    name = artifact_name(number, head)
    listed = json_object(
        read(["api", f"repos/{repo}/actions/artifacts?name={name}&per_page=100"])
    )
    artifacts = [
        a
        for a in map(json_object, json_array(listed.get("artifacts")))
        if a.get("name") == name
        and a.get("expired") is False
        and isinstance(a.get("id"), int)
        and isinstance(json_object(a.get("workflow_run")).get("id"), int)
    ]
    # A same-name artifact from another workflow costs one run read; one run
    # that cannot be read does not hide a later capture run's artifact.
    unread: Exception | None = None
    for artifact in sorted(artifacts, key=lambda a: a["id"], reverse=True):
        run_id = json_object(artifact.get("workflow_run"))["id"]
        try:
            run = read(["api", f"repos/{repo}/actions/runs/{run_id}"])
        except Exception as exc:  # noqa: BLE001 -- reported below if nothing is found
            unread = exc
            continue
        if capture_run(run, repo, head):
            return {
                "name": name,
                "runId": run_id,
                "artifactId": artifact["id"],
                "expiresAt": artifact.get("expires_at"),
            }
    if unread is not None:
        raise unread
    return None


def evidence_body(
    repo: str, head: str, capture: dict[str, Any], server: str = "https://github.com"
) -> str:
    """The comment, in the layout of the pull-request skill's evidence-comment
    template with no capture sections: CI attaches no file."""
    run, artifact = capture["runId"], capture["artifactId"]
    url = f"{server.rstrip('/')}/{repo}/actions/runs/{run}/artifacts/{artifact}"
    date = DATE_RE.match(str(capture.get("expiresAt") or ""))
    expiry = (
        f"expires on {date.group(1)}"
        if date
        else "expires with the repository's artifact retention setting"
    )
    return "\n".join(
        [
            MARKER,
            f"### Verification evidence for {head}",
            "",
            "The verifier passed this head. The capture artifact holds the "
            "capture summary, which says whether the capture ran, and any "
            "screenshot or video that passed the mask check; this comment "
            "uploads no file.",
            "",
            f"Capture artifact: [{capture['name']}]({url}), {expiry}.",
            "",
            "<sub>One comment per pull request, updated in place for each new head.</sub>",
            "",
        ]
    )


def post(
    repo: str,
    number: int,
    head: str,
    read: Read,
    write: Callable[[str], str],
    server: str = "https://github.com",
) -> str:
    """Find the head's capture and hand its comment body to `write`, which
    upserts it and returns its outcome. Returns `no-capture` with nothing
    written, or `error: <detail>` when a read or the write fails: the
    comment never stops the merge that follows it."""
    if not SHA_RE.match(head):
        return "error: the head is not a commit SHA"
    try:
        capture = find_capture(repo, number, head, read)
        if capture is None:
            return "no-capture"
        return write(evidence_body(repo, head, capture, server))
    except Exception as exc:  # noqa: BLE001 -- any failure is the outcome
        return f"error: {str(exc).strip()[:300]}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n", 1)[0], allow_abbrev=False
    )
    sub = parser.add_subparsers(dest="command", required=True)
    cmd = sub.add_parser("post", allow_abbrev=False)
    cmd.add_argument("--repo", required=True)
    cmd.add_argument("--pr", type=int, required=True)
    cmd.add_argument("--head", required=True)
    cmd.add_argument("--identity", required=True)
    args = parser.parse_args(argv)

    # Imported here: babysit_merge imports this module.
    import babysit_merge
    from babysit_gh import gh_json

    token = os.environ.get(TOKEN_ENV)
    env = {"GH_TOKEN": token} if token else None
    outcome = post(
        args.repo,
        args.pr,
        args.head,
        lambda call: gh_json(call, env),
        lambda body: babysit_merge.upsert_marker_comment(
            args.repo, args.pr, args.identity, body, None, marker=MARKER
        ),
        os.environ.get("GITHUB_SERVER_URL") or "https://github.com",
    )
    print(json.dumps({"outcome": outcome}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
