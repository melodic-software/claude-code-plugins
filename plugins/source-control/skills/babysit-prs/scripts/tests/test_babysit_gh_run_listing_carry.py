"""A workflow-run listing page read through `_run_pages` with its saved ETag.

The owner's rule: a saved or carried listing body is served only when a live
request for exactly the same path and query, sent with its ETag as
If-None-Match, answers 304. A 200 is used as it came and replaces the entry;
any other answer falls back to a plain read. gh exits 1 on a 304 and prints
`gh: HTTP 304` (gh api -i, observed 2026-11-15).
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh
import babysit_run_cache as run_cache

REPO = "melodic-software/claude-code-plugins"
LISTING = (
    f"repos/{REPO}/actions/workflows/pr-review-hosted.yml/runs"
    "?branch=feat%2Fx&event=pull_request&per_page=100"
)
PAGE_TWO = (
    "repositories/1277265216/actions/workflows/pr-review-hosted.yml/runs"
    "?branch=feat%2Fx&event=pull_request&per_page=100&page=2"
)
ETAG = 'W/"a7140079db318bd9eb5032bbfbc0c74f4b87931b97eaf8deee2220ff63327682"'
CARRIED_BODY = {"total_count": 1, "workflow_runs": [{"id": 7, "status": "completed"}]}
NEW_BODY = {"total_count": 2, "workflow_runs": [{"id": 8}, {"id": 7}]}
CARRY = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/carry-run-cache.mjs"
)


def answer(status: str, body: Any = None, **headers: str) -> tuple[int, str, str]:
    """A `gh api -i` answer: exit code, stdout, stderr."""
    head = f"HTTP/2.0 {status}\r\nX-Ratelimit-Resource: core\r\n"
    head += "".join(f"{name}: {value}\r\n" for name, value in headers.items())
    text = head + "\r\n" + ("" if body is None else json.dumps(body))
    code = 0 if status.startswith("200") else 1
    stderr = "" if code == 0 else f"gh: HTTP {status.split()[0]}\n"
    return code, text, stderr


class RunListingCarryTests(unittest.TestCase):
    def setUp(self) -> None:
        gh.reset_rate_guard()
        self.addCleanup(gh.reset_rate_guard)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        self.cache = self.dir / "run-cache.json"
        self.calls: list[list[str]] = []

    def seed(self, section: str, key: str, value: Any) -> None:
        data = json.loads(self.cache.read_text()) if self.cache.exists() else {}
        data.setdefault(section, {})[key] = {
            "at": run_cache.now().isoformat(),
            "value": value,
        }
        self.cache.write_text(json.dumps(data))

    def saved(self, key: str) -> Any:
        data = json.loads(self.cache.read_text())
        return data.get(gh.RUN_LISTING_SECTION, {}).get(key, {}).get("value")

    def read(
        self,
        endpoint: str,
        answers: list[tuple[int, str, str]],
        *,
        cache: bool = True,
        paged: bool = True,
    ) -> subprocess.CompletedProcess[Any]:
        queue = list(answers)

        def fake(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.calls.append(argv)
            code, out, err = queue.pop(0)
            return subprocess.CompletedProcess(argv, code, out, err)

        env = {run_cache.ENV: str(self.cache)} if cache else {}
        with (
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(gh, "run_command", fake),
        ):
            if not cache:
                os.environ.pop(run_cache.ENV, None)
            proc = gh._run_gh(
                ["api", endpoint, *(["--paginate", "--slurp"] if paged else [])],
                timeout_seconds=None,
                check=True,
            )
        self.assertEqual(queue, [], "every answer was asked for")
        return proc

    def carried(self, **value: Any) -> None:
        entry = {"etag": ETAG, "next": "", "body": CARRIED_BODY, **value}
        self.seed(gh.CARRIED_RUN_LISTING_SECTION, gh.run_listing_key(LISTING), entry)

    def test_a_304_to_the_carried_etag_serves_the_carried_body(self) -> None:
        self.carried()
        proc = self.read(LISTING, [answer("304 Not Modified", Etag=ETAG.removeprefix("W/"))])
        self.assertEqual(
            self.calls,
            [["gh", "api", "-i", LISTING, "-H", f"If-None-Match: {ETAG}"]],
        )
        self.assertEqual(json.loads(proc.stdout), [CARRIED_BODY])

    def test_a_304_keeps_the_entry_for_the_next_run(self) -> None:
        self.carried()
        self.read(LISTING, [answer("304 Not Modified")])
        self.assertEqual(
            self.saved(gh.run_listing_key(LISTING)),
            {"etag": ETAG, "next": "", "body": CARRIED_BODY},
        )

    def test_a_200_to_the_conditional_read_is_used_and_replaces_the_entry(self) -> None:
        self.carried()
        proc = self.read(LISTING, [answer("200 OK", NEW_BODY, Etag='W/"e2"')])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(json.loads(proc.stdout), [NEW_BODY])
        self.assertEqual(
            self.saved(gh.run_listing_key(LISTING)),
            {"etag": 'W/"e2"', "next": "", "body": NEW_BODY},
        )

    def test_another_query_sends_no_etag(self) -> None:
        self.carried()
        other = LISTING.replace("per_page=100", "per_page=50")
        proc = self.read(other, [answer("200 OK", NEW_BODY)])
        self.assertEqual(self.calls, [["gh", "api", "-i", other]])
        self.assertEqual(json.loads(proc.stdout), [NEW_BODY])

    def test_a_failed_conditional_read_falls_back_to_a_plain_read(self) -> None:
        self.carried()
        proc = self.read(
            LISTING,
            [answer("502 Bad Gateway", {"message": "x"}), answer("200 OK", NEW_BODY)],
        )
        self.assertEqual(
            self.calls,
            [
                ["gh", "api", "-i", LISTING, "-H", f"If-None-Match: {ETAG}"],
                ["gh", "api", "-i", LISTING],
            ],
        )
        self.assertEqual(json.loads(proc.stdout), [NEW_BODY])

    def test_a_failed_plain_read_after_it_raises_and_never_serves_the_body(self) -> None:
        self.carried()
        with self.assertRaises(RuntimeError):
            self.read(
                LISTING,
                [answer("502 Bad Gateway"), answer("502 Bad Gateway")],
            )

    def test_a_carried_entry_of_no_shape_is_never_sent(self) -> None:
        for label, bad in {
            "an ETag of no shape": {"etag": "e1"},
            "a body with no runs": {"body": {"total_count": 1}},
            "a next page of no shape": {"next": 7},
        }.items():
            with self.subTest(label):
                self.calls.clear()
                self.carried(**bad)
                proc = self.read(LISTING, [answer("200 OK", NEW_BODY)])
                self.assertEqual(self.calls, [["gh", "api", "-i", LISTING]])
                self.assertEqual(json.loads(proc.stdout), [NEW_BODY])

    def test_a_carried_next_page_is_read_after_a_304(self) -> None:
        self.carried(next=PAGE_TWO)
        proc = self.read(
            LISTING, [answer("304 Not Modified"), answer("200 OK", NEW_BODY)]
        )
        self.assertEqual(self.calls[1], ["gh", "api", "-i", PAGE_TWO])
        self.assertEqual(json.loads(proc.stdout), [CARRIED_BODY, NEW_BODY])

    def test_a_200_saves_the_page_with_its_etag_and_next_page(self) -> None:
        link = f'<https://api.github.com/{PAGE_TWO}>; rel="next"'
        self.read(
            LISTING,
            [
                answer("200 OK", CARRIED_BODY, Etag=ETAG, Link=link),
                answer("200 OK", NEW_BODY),
            ],
        )
        self.assertEqual(
            self.saved(gh.run_listing_key(LISTING)),
            {"etag": ETAG, "next": PAGE_TWO, "body": CARRIED_BODY},
        )

    def test_a_single_page_listing_get_is_served_on_a_304_and_replaced_on_a_200(
        self,
    ) -> None:
        self.carried()
        proc = self.read(LISTING, [answer("304 Not Modified")], paged=False)
        self.assertEqual(
            self.calls,
            [["gh", "api", "-i", LISTING, "-H", f"If-None-Match: {ETAG}"]],
        )
        self.assertEqual(json.loads(proc.stdout), CARRIED_BODY)
        proc = self.read(
            LISTING, [answer("200 OK", NEW_BODY, Etag='W/"e2"')], paged=False
        )
        self.assertEqual(json.loads(proc.stdout), NEW_BODY)
        self.assertEqual(
            self.saved(gh.run_listing_key(LISTING)),
            {"etag": 'W/"e2"', "next": "", "body": NEW_BODY},
        )

    def test_other_reads_and_a_run_with_no_cache_save_nothing(self) -> None:
        pulls = f"repos/{REPO}/pulls?state=open"
        self.read(pulls, [answer("200 OK", [], Etag=ETAG)])
        self.assertFalse(self.cache.exists())
        self.read(LISTING, [answer("200 OK", NEW_BODY, Etag=ETAG)], cache=False)
        self.assertFalse(self.cache.exists())

    def test_the_next_pr_merge_run_reads_a_carried_page_with_one_304(self) -> None:
        self.read(LISTING, [answer("200 OK", CARRIED_BODY, Etag=ETAG)])
        carried = self.dir / "carried.json"
        subprocess.run(
            ["node", str(CARRY)],
            env={
                "PATH": os.environ["PATH"],
                "CARRY_FROM": str(self.cache),
                "CARRY_TO": str(carried),
                "GITHUB_REPOSITORY": REPO,
            },
            check=True,
            capture_output=True,
        )
        self.cache = carried
        self.calls.clear()
        proc = self.read(LISTING, [answer("304 Not Modified")])
        self.assertEqual(
            self.calls,
            [["gh", "api", "-i", LISTING, "-H", f"If-None-Match: {ETAG}"]],
        )
        self.assertEqual(json.loads(proc.stdout), [CARRIED_BODY])


if __name__ == "__main__":
    unittest.main()
