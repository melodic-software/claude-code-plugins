"""`read_pins`: the pin read-back for many pull requests, batched.

Expected values come from the pin contract `read_pin` documents (the agent
identity's newest unedited `babysit-merge-pin` comment, through every page of
100) and from GitHub's GraphQL connection shape: a page carries `pageInfo`
`hasNextPage`/`endCursor`, and an alias the response leaves out is a pull
request it did not return. Each fixture thread states its pin by
construction, so no expected SHA is computed by the code under test.
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as pm  # noqa: E402

REPO = "example-org/example-repo"
IDENTITY = "agent-lanes[bot]"
APP = {"__typename": "Bot", "login": "agent-lanes"}
HUMAN = {"__typename": "User", "login": "maintainer"}


def sha(n: int) -> str:
    return f"{n:040x}"


def pin(n: int, *, edited: str | None = None) -> dict[str, Any]:
    return {"author": APP, "body": pm.pin_comment(sha(n)), "lastEditedAt": edited}


def chatter(count: int) -> list[dict[str, Any]]:
    return [{"author": HUMAN, "body": "lgtm", "lastEditedAt": None}] * count


class Threads:
    """The GraphQL API over fixed comment threads by pull request number:
    pages of 100, a cursor naming the next offset. `missing` numbers are not
    returned; `errors` makes every batch carry an error."""

    def __init__(self, threads: dict[int, list[dict[str, Any]]]) -> None:
        self.threads = threads
        self.missing: set[int] = set()
        self.errors = False
        self.calls: list[str] = []

    def page(self, n: int, offset: int) -> dict[str, Any]:
        nodes = self.threads[n][offset : offset + 100]
        more = offset + 100 < len(self.threads[n])
        return {
            "pageInfo": {
                "hasNextPage": more,
                "endCursor": str(offset + 100) if more else None,
            },
            "nodes": nodes,
        }

    def __call__(
        self, args: list[str], **_: object
    ) -> subprocess.CompletedProcess[str]:
        joined = " ".join(args)
        self.calls.append(joined)
        if "PostMergeHeadPins" in joined:
            body: dict[str, Any] = {
                "data": {
                    "repository": {
                        f"p{n}": {"number": n, "comments": self.page(n, 0)}
                        for n in map(int, re.findall(r"p(\d+):pullRequest", joined))
                        if n not in self.missing
                    }
                }
            }
            if self.errors:
                body["errors"] = [{"message": "Something went wrong"}]
        else:
            n = int(next(a for a in args if a.startswith("n="))[2:])
            cursor = next((a[2:] for a in args if a.startswith("c=")), "0")
            pull = (
                None
                if n in self.missing
                else {
                    "comments": self.page(n, int(cursor)),
                    "reviews": {"nodes": []},
                }
            )
            body = {"data": {"repository": {"pullRequest": pull}}}
        return subprocess.CompletedProcess(args, 0, json.dumps(body), "")

    def batches(self) -> list[str]:
        return [c for c in self.calls if "PostMergeHeadPins" in c]

    def singles(self) -> list[str]:
        return [c for c in self.calls if "PostMergePin(" in c]


# 25 pull requests: a pinned head on every one except 103 (no pin), 104 (an
# edited pin), 105 (a pin by a human), and 106, whose pin sits behind 150
# later comments, on its second page.
THREADS: dict[int, list[dict[str, Any]]] = {
    n: [*chatter(2), pin(n)] for n in range(100, 125)
}
THREADS[101] = [pin(9), *chatter(3), pin(101)]
THREADS[103] = chatter(4)
THREADS[104] = [pin(104, edited="2026-10-12T10:30:00Z")]
THREADS[105] = [
    {"author": HUMAN, "body": pm.pin_comment(sha(105)), "lastEditedAt": None}
]
THREADS[106] = [*chatter(120), pin(106), *chatter(150)]
EXPECTED = {n: sha(n) for n in THREADS} | {103: None, 104: None, 105: None}


class ReadPins(unittest.TestCase):
    def read(self, api: Threads, numbers: list[int]) -> dict[int, str | None]:
        with mock.patch.object(pm, "gh_capture", api):
            return pm.read_pins(REPO, numbers, IDENTITY)

    def test_a_batch_of_25_reads_every_pin(self) -> None:
        api = Threads(THREADS)
        self.assertEqual(self.read(api, list(THREADS)), EXPECTED)
        # Two queries of at most 20 pull requests, and #106's later pages alone.
        self.assertEqual(len(api.batches()), 2)
        self.assertEqual(len(re.findall(r":pullRequest\(", api.batches()[0])), 20)
        self.assertEqual(len(api.singles()), 2)
        self.assertTrue(all("n=106" in c for c in api.singles()))

    def test_a_thread_over_100_comments_reads_every_page(self) -> None:
        api = Threads(THREADS)
        self.assertEqual(self.read(api, [106]), {106: sha(106)})
        self.assertEqual(
            [("c=100" in c, "c=200" in c) for c in api.singles()],
            [(True, False), (False, True)],
        )

    def test_an_edited_pin_is_no_pin(self) -> None:
        self.assertEqual(
            self.read(Threads(THREADS), [104, 100]), {104: None, 100: sha(100)}
        )

    def test_every_batched_pin_equals_its_single_read(self) -> None:
        batched = self.read(Threads(THREADS), list(THREADS))
        with mock.patch.object(pm, "gh_capture", Threads(THREADS)):
            single = {n: pm.read_pin(REPO, n, IDENTITY) for n in THREADS}
        self.assertEqual(batched, single)

    def test_a_pull_request_missing_from_the_response_raises(self) -> None:
        api = Threads(THREADS)
        api.missing = {110}
        with self.assertRaisesRegex(pm.PostMergeReadError, "#110 pin"):
            self.read(api, list(THREADS))
        # As the single read fails on it.
        with (
            mock.patch.object(pm, "gh_capture", api),
            self.assertRaises(pm.PostMergeReadError),
        ):
            pm.read_pin(REPO, 110, IDENTITY)

    def test_an_error_in_the_response_raises(self) -> None:
        api = Threads(THREADS)
        api.errors = True
        with self.assertRaises(pm.PostMergeReadError):
            self.read(api, [100])

    def test_a_thread_past_the_page_limit_is_no_pin(self) -> None:
        threads = {7: [pin(7), *chatter(100 * pm.PIN_PAGE_LIMIT)]}
        self.assertEqual(self.read(Threads(threads), [7]), {7: None})

    def test_no_numbers_reads_nothing(self) -> None:
        api = Threads(THREADS)
        self.assertEqual(self.read(api, []), {})
        self.assertEqual(api.calls, [])


class Reader(unittest.TestCase):
    """`PinReader`: a prefetch serves each merge; anything else reads alone."""

    def merge(self, n: int) -> Any:
        return mock.Mock(number=n)

    def test_prefetched_merges_cost_no_further_read(self) -> None:
        api = Threads(THREADS)
        with mock.patch.object(pm, "gh_capture", api):
            reader = pm.pin_reader(REPO, IDENTITY)
            reader.prefetch([100, 104])
            calls = len(api.calls)
            self.assertEqual(
                [reader(self.merge(n)) for n in (100, 104)], [sha(100), None]
            )
            self.assertEqual(len(api.calls), calls)
            self.assertEqual(reader(self.merge(102)), sha(102))
            self.assertEqual(len(api.singles()), 1)

    def test_a_new_prefetch_reads_afresh(self) -> None:
        api = Threads({1: [pin(1)]})
        with mock.patch.object(pm, "gh_capture", api):
            reader = pm.pin_reader(REPO, IDENTITY)
            reader.prefetch([1])
            api.threads[1] = [pin(1, edited="2026-10-12T10:30:00Z")]
            reader.prefetch([1])
            self.assertIsNone(reader(self.merge(1)))


if __name__ == "__main__":
    unittest.main()
