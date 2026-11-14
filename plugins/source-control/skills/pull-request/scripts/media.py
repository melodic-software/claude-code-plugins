#!/usr/bin/env python3
"""The reviewer-media section of a pull request body (../reference/media.md).

  media.py claim <pr> --run-id <id>
  media.py post  <pr> --manifest <file> --run-id <id> [--artifact-url <url> [--retention-days <n>]] [--no-attach]
  media.py stale <pr> [--head <sha>] [--quiet]
  media.py fail  <pr> --run-id <id> --reason <code> [--run-url <url>]

Every action takes --repo <owner/repo>, and the label names as --label-requested, --label-posted and
--label-failed (`false` turns one off). Only the text between the two marker lines is ever rewritten.

Exit: 0 done; 1 a gh call failed or the read-back did not match; 2 usage, or a manifest that cannot be
used; 3 the claim is held by another run, the body changed under the edit, or its markers are broken;
4 nothing could host the media; 5 the leak scan found something; 6 a screenshot has no frame-text sidecar.
A refusal writes one `media: refused <code>: <detail>` line to stderr and posts nothing.
"""

from __future__ import annotations

import argparse
import datetime
import enum
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(
    0, str(Path(__file__).resolve().parents[3] / "tools" / "reviewer-media" / "lib")
)
import media_scan  # noqa: E402

START = "<!-- reviewer-media:start -->"
END = "<!-- reviewer-media:end -->"
HEADING = "## Reviewer media"
INTRO = (
    "For reviewers: a narrated walkthrough of this change. Watch it before the diff."
)
STALE_PREFIX = "Out of date: shows commit "

_SHA = r"[0-9a-f]{40}"
_RUN = r"[A-Za-z0-9._-]{1,64}"
_CLAIM = re.compile(rf"^<!-- reviewer-media:claimed ({_SHA}) ({_RUN}) -->$")
_POSTED = re.compile(rf"^<!-- reviewer-media:posted ({_SHA}) -->$")
_STALE = re.compile(rf"^{re.escape(STALE_PREFIX)}({_SHA})$")
_SUMMARY = re.compile(r"^## Summary[ \t]*\r?$", re.M)
_PR_URL = re.compile(
    r"^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$"
)
_ARTIFACT_URL = re.compile(
    r"^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/actions/runs/[0-9]+(/artifacts/[0-9]+)?$"
)
_RUN_URL = re.compile(
    r"^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/actions/runs/[0-9]+(/attempts/[0-9]+)?$"
)
_REASON = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")
_VIDEO = {".mp4", ".mov", ".webm"}
_IMAGE = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
MAX_RETENTION_DAYS = 90


class Refusal(Exception):
    def __init__(self, exit_code: int, code: str, detail: str):
        super().__init__(detail)
        self.exit_code, self.code, self.detail = exit_code, code, detail


class State(enum.Enum):
    NONE = "none"
    CLAIMED = "claimed"
    POSTED = "posted"
    STALE = "stale"


class Hosting(enum.Enum):
    ATTACH = "attach"
    ARTIFACT = "artifact"


@dataclass(frozen=True)
class Status:
    state: State
    claim: tuple[str, str] | None = None  # (head sha, run id)
    shown: str | None = None  # the commit the posted media show


@dataclass(frozen=True)
class Parts:
    before: str
    block: str | None
    after: str

    @property
    def outside(self) -> tuple[str, str]:
        return self.before, self.after


def _lines(block: str) -> list[str]:
    return block.replace("\r\n", "\n").split("\n")


def newline_of(body: str) -> str:
    return "\r\n" if "\r\n" in body else "\n"


def split(body: str) -> Parts:
    """The body as (before, block, after); block runs from the start marker line through the end marker."""
    starts = [m.start() for m in re.finditer(rf"^{re.escape(START)}\r?$", body, re.M)]
    ends = [m.start() for m in re.finditer(rf"^{re.escape(END)}\r?$", body, re.M)]
    if not starts and not ends:
        return Parts(body, None, "")
    if len(starts) != 1 or len(ends) != 1 or ends[0] < starts[0]:
        raise Refusal(
            3,
            "markers",
            "the body does not hold exactly one start marker line followed by one end marker line",
        )
    stop = ends[0] + len(END)
    return Parts(body[: starts[0]], body[starts[0] : stop], body[stop:])


def join(parts: Parts, block: str | None, original: str) -> str:
    """The body with `block` in place of the marked block; None removes it, and a first block goes before `## Summary`."""
    nl = newline_of(original)
    if parts.block is not None:
        if block is not None:
            return parts.before + block + parts.after
        after = parts.after
        for _ in range(2):
            after = after[len(nl) :] if after.startswith(nl) else after
        return parts.before + after
    if block is None:
        return original
    summary = _SUMMARY.search(original)
    if summary:
        return (
            original[: summary.start()] + block + nl + nl + original[summary.start() :]
        )
    gap = "" if not original else nl if original.endswith(nl) else nl + nl
    return original + gap + block + nl


def status_of(block: str | None) -> Status:
    claim = shown = None
    stale = False
    for line in _lines(block or ""):
        if m := _CLAIM.match(line):
            claim = (m[1], m[2])
        elif m := _POSTED.match(line):
            shown = m[1]
        elif m := _STALE.match(line):
            shown, stale = m[1], True
    state = (
        State.CLAIMED
        if claim
        else State.STALE
        if stale
        else State.POSTED
        if shown
        else State.NONE
    )
    return Status(state, claim, shown)


def claim_line(sha: str, run: str) -> str:
    return f"<!-- reviewer-media:claimed {sha} {run} -->"


def shown_line(sha: str, stale: bool) -> str:
    return f"{STALE_PREFIX}{sha}" if stale else f"<!-- reviewer-media:posted {sha} -->"


def with_claim(block: str | None, sha: str, run: str, nl: str) -> str:
    kept = [
        line for line in _lines(block or f"{START}\n{END}") if not _CLAIM.match(line)
    ]
    return nl.join([kept[0], claim_line(sha, run), *kept[1:]])


def without_claim(block: str, nl: str) -> str | None:
    kept = [line for line in _lines(block) if not _CLAIM.match(line)]
    return None if kept == [START, END] else nl.join(kept)


def as_stale(block: str, nl: str) -> str:
    return nl.join(
        shown_line(m[1], True) if (m := _POSTED.match(line)) else line
        for line in _lines(block)
    )


def md_text(text: object) -> str:
    """Manifest text as inert markdown: no markup, mention, issue link or line break of its own."""
    flat = " ".join(str(text).split())
    flat = re.sub(r"([\\`*_\[\]!|~])", r"\\\1", flat.replace("&", "&amp;"))
    for char, entity in (("<", "&lt;"), (">", "&gt;"), ("#", "&#35;"), ("@", "&#64;")):
        flat = flat.replace(char, entity)
    return flat


def clock(seconds: float) -> str:
    total = int(float(seconds))
    hours, rest = divmod(total, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


@dataclass(frozen=True)
class Asset:
    source: Path
    name: str  # the staged file name, which the section references as ./<name>
    label: str


@dataclass(frozen=True)
class Media:
    head: str
    videos: list[Asset]
    sheets: list[Asset]
    screenshots: list[Asset]
    chapters: list[tuple[str, str]]  # (start time, title)
    # Text the scan reads as written: escaping a chapter title would hide a secret in it.
    unrendered: dict[str, str]
    video_unhosted: str  # why the video cannot be attached, "" when it can

    @property
    def assets(self) -> list[Asset]:
        return [*self.videos, *self.sheets, *self.screenshots]


def _listed(base: Path, entry: object, kinds: set[str], what: str) -> Path:
    """A manifest path as a regular file inside the manifest's directory, of an attachable kind."""
    rel = entry.get("path") if isinstance(entry, dict) else entry
    if not isinstance(rel, str) or not rel:
        raise Refusal(2, "manifest", f"{what} names no path")
    path = (base / rel).resolve()
    if base not in path.parents or not path.is_file():
        raise Refusal(
            2, "manifest", f"{what} is not a file inside the manifest's directory"
        )
    if path.suffix.lower() not in kinds:
        raise Refusal(
            2,
            "manifest",
            f"{what} is not an attachable {'video' if kinds is _VIDEO else 'image'}",
        )
    return path


def load_media(manifest_file: str) -> Media:
    try:
        path = Path(manifest_file).resolve(strict=True)
        data = json.loads(path.read_text(encoding="utf-8"))
        head = data["head_sha"]
        video = data["video"]
        listed = data.get("chapters") or []
        chapters = [(clock(c["start_s"]), md_text(c["title"])) for c in listed]
        unrendered = {
            f"chapter {i} title": str(c["title"]) for i, c in enumerate(listed, 1)
        }
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise Refusal(
            2, "manifest", f"the manifest cannot be read ({type(exc).__name__})"
        ) from None
    if not isinstance(head, str) or not re.fullmatch(_SHA, head):
        raise Refusal(2, "manifest", "head_sha is not a full commit sha")
    if (data.get("scan") or {}).get("status") != "pass":
        raise Refusal(5, "scan", "the manifest does not record a passing scan")
    base = path.parent
    parts = data.get("parts") or []
    oversize = data.get("oversize")
    unhosted = "the video is over the upload limit" if oversize and not parts else ""
    sources = (
        []
        if unhosted
        else [_listed(base, p, _VIDEO, "a video part") for p in parts]
        or [_listed(base, video, _VIDEO, "the video")]
    )
    videos = [
        Asset(
            p,
            f"video-{i}{p.suffix.lower()}"
            if len(sources) > 1
            else f"video{p.suffix.lower()}",
            f"Walkthrough video part {i}",
        )
        for i, p in enumerate(sources, 1)
    ]
    sheets = [
        Asset(p, f"sheet-{i}{p.suffix.lower()}", f"Contact sheet {i}")
        for i, p in enumerate(
            (
                _listed(base, s, _IMAGE, "a contact sheet")
                for s in data.get("contact_sheet") or []
            ),
            1,
        )
    ]
    screenshots = []
    for i, entry in enumerate(data.get("screenshots") or [], 1):
        shot = _listed(base, entry, _IMAGE, "a screenshot")
        named = entry.get("sidecar") if isinstance(entry, dict) else None
        sidecar = (
            (base / named).resolve()
            if isinstance(named, str) and named
            else shot.with_name(shot.name + ".txt")
        )
        try:
            text = (
                sidecar.read_text(encoding="utf-8") if base in sidecar.parents else ""
            )
        except (OSError, ValueError):
            text = ""
        if not text.strip():
            raise Refusal(
                6,
                "sidecar",
                f"screenshot {i} has no frame-text sidecar, so its text cannot be scanned",
            )
        unrendered[f"screenshot {i} sidecar"] = text
        screenshots.append(
            Asset(shot, f"screenshot-{i}{shot.suffix.lower()}", f"Screenshot {i}")
        )
    return Media(head, videos, sheets, screenshots, chapters, unrendered, unhosted)


def _details(summary: str, lines: list[str]) -> list[str]:
    return [
        "",
        "<details>",
        f"<summary>{summary}</summary>",
        "",
        *lines,
        "",
        "</details>",
    ]


def render(
    media: Media, hosting: Hosting, stale: bool, artifact_line: str, nl: str
) -> str:
    """The marked block: video on top, contact sheet, chapters and screenshots each in a collapsed section."""
    out = [START, HEADING, "", INTRO, "", shown_line(media.head, stale)]
    if hosting is Hosting.ATTACH:
        for video in media.videos:
            out += ["", f"![{video.label}](./{video.name})"]
        for title, assets in (
            ("Contact sheet", media.sheets),
            ("Screenshots", media.screenshots),
        ):
            if assets:
                out += _details(
                    title,
                    [
                        line
                        for a in assets
                        for line in (f"![{a.label}](./{a.name})", "")
                    ][:-1],
                )
    if media.chapters:
        out += _details(
            "Chapters", [f"- {start} {title}" for start, title in media.chapters]
        )
    if artifact_line:
        out += ["", artifact_line]
    return nl.join([*out, END])


def artifact_line_of(
    url: str, name: str, days: int, hosting: Hosting, media: Media
) -> str:
    if not url:
        return ""
    expires = (
        (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=days))
        .date()
        .isoformat()
    )
    holds = (
        "The video, contact sheet and screenshots are"
        if hosting is Hosting.ARTIFACT
        else ("The video is" if media.video_unhosted else "A copy of the media is")
    )
    return f"{holds} in the run artifact [{name}]({url}), which expires {expires} (kept {days} days)."


class Forge:
    def __init__(self, pr: str, repo: str | None):
        self.pr, self.repo = pr, repo

    def gh(
        self, *args: str, check: bool = True, timeout: int = 120
    ) -> subprocess.CompletedProcess[str]:
        try:
            proc = subprocess.run(
                ["gh", *args],
                capture_output=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise Refusal(
                1, "gh", f"gh {args[0]} {args[1]} did not run ({type(exc).__name__})"
            ) from None
        if check and proc.returncode != 0:
            raise Refusal(1, "gh", f"gh {args[0]} {args[1]} exited {proc.returncode}")
        return proc

    def read(self) -> dict:
        scope = ["-R", self.repo] if self.repo else []
        out = self.gh(
            "pr", "view", self.pr, *scope, "--json", "number,url,headRefOid,body,labels"
        ).stdout
        try:
            data = json.loads(out)
            match = _PR_URL.match(data["url"])
            data["labels"] = [label["name"] for label in data["labels"]]
            if (
                not match
                or not isinstance(data["body"], str)
                or not re.fullmatch(_SHA, data["headRefOid"])
            ):
                raise ValueError
        except (ValueError, KeyError, TypeError):
            raise Refusal(
                1, "gh", "gh pr view did not return a github.com pull request"
            ) from None
        self.repo, self.pr = match[1], match[2]
        return data

    def edit(
        self, *args: str, check: bool = True, timeout: int = 120
    ) -> subprocess.CompletedProcess[str]:
        return self.gh(
            "pr",
            "edit",
            self.pr,
            "-R",
            self.repo or "",
            *args,
            check=check,
            timeout=timeout,
        )

    def write_body(self, body: str, *args: str) -> None:
        with tempfile.TemporaryDirectory(prefix="reviewer-media-") as tmp:
            target = Path(tmp) / "body.md"
            target.write_bytes(body.encode("utf-8"))
            self.edit("--body-file", str(target), *args)

    def can_attach(self) -> bool:
        return "--attach" in self.gh("pr", "edit", "--help", check=False).stdout


def swap_labels(
    forge: Forge, present: list[str], add: str | None, remove: list[str | None]
) -> str:
    dropped = [name for name in remove if name and name in present]
    added = [add] if add and add not in present else []
    if not dropped and not added:
        return "labels unchanged"
    args = [arg for name in dropped for arg in ("--remove-label", name)] + [
        arg for name in added for arg in ("--add-label", name)
    ]
    if forge.edit(*args, check=False).returncode != 0:
        return "labels not changed: gh pr edit refused (a label the repository lacks is never created here)"
    return "labels: " + ", ".join(
        [f"added '{name}'" for name in added]
        + [f"removed '{name}'" for name in dropped]
    )


def label(value: str) -> str | None:
    return None if value.strip().lower() == "false" else value


def cmd_claim(a: argparse.Namespace, forge: Forge) -> int:
    pr = forge.read()
    body, head = pr["body"], pr["headRefOid"]
    parts = split(body)
    held = status_of(parts.block).claim
    if held and held[0] == head and held[1] != a.run_id:
        raise Refusal(3, "claim", f"run {held[1]} holds the claim for commit {head}")
    requested = label(a.label_requested)
    drop = (
        ["--remove-label", requested] if requested and requested in pr["labels"] else []
    )
    forge.write_body(
        join(parts, with_claim(parts.block, head, a.run_id, newline_of(body)), body),
        *drop,
    )
    if status_of(split(forge.read()["body"]).block).claim != (head, a.run_id):
        raise Refusal(3, "claim", "another run took the claim")
    print(f"media: claimed {head} {a.run_id}")
    return 0


def cmd_post(a: argparse.Namespace, forge: Forge) -> int:
    if a.artifact_url and not _ARTIFACT_URL.match(a.artifact_url):
        raise Refusal(
            2,
            "usage",
            "--artifact-url must be a github.com Actions run or artifact URL",
        )
    if not 1 <= a.retention_days <= MAX_RETENTION_DAYS:
        raise Refusal(2, "usage", f"--retention-days must be 1 to {MAX_RETENTION_DAYS}")
    media = load_media(a.manifest)
    first = forge.read()
    mine = (media.head, a.run_id)
    if status_of(split(first["body"]).block).claim != mine:
        raise Refusal(
            3,
            "claim",
            f"run {a.run_id} does not hold the claim for commit {media.head}",
        )

    attachable = (
        []
        if a.no_attach or not forge.can_attach()
        else (
            media.assets
            if not media.video_unhosted
            else [*media.sheets, *media.screenshots]
        )
    )
    if media.video_unhosted and not a.artifact_url:
        raise Refusal(
            4, "no-host", f"{media.video_unhosted} and no --artifact-url was given"
        )
    hostings = ([Hosting.ATTACH] if attachable else []) + (
        [Hosting.ARTIFACT] if a.artifact_url else []
    )
    if not hostings:
        raise Refusal(
            4, "no-host", "this gh cannot attach files and no --artifact-url was given"
        )

    nl = newline_of(first["body"])
    stale = first["headRefOid"] != media.head
    name = a.artifact_name or f"reviewer-media-{forge.pr}-{media.head}"
    for hosting in hostings:
        section = render(
            media,
            hosting,
            stale,
            artifact_line_of(a.artifact_url, name, a.retention_days, hosting, media),
            nl,
        )
        scan = media_scan.scan({"section": section, **media.unrendered})
        if not scan.ok:
            found = (
                "; ".join(f"{f['source']}: {f['kind']}" for f in scan.findings)
                or "the scan rules did not load"
            )
            raise Refusal(5, "scan", found)
        # The body is read again here so a person's edit made while the section was built is never overwritten.
        now = forge.read()
        parts = split(now["body"])
        if (
            parts.outside != split(first["body"]).outside
            or status_of(parts.block).claim != mine
        ):
            raise Refusal(
                3,
                "changed",
                "the body outside the markers, or the claim, changed while the section was built",
            )
        target = join(parts, section, now["body"])
        with tempfile.TemporaryDirectory(prefix="reviewer-media-") as tmp:
            body_file = Path(tmp) / "body.md"
            body_file.write_bytes(target.encode("utf-8"))
            args = ["--body-file", str(body_file)]
            if hosting is Hosting.ATTACH:
                for asset in attachable:
                    shutil.copyfile(asset.source, Path(tmp) / asset.name)
                    args += ["--attach", str(Path(tmp) / asset.name)]
            done = forge.edit(*args, check=False, timeout=900)
        after = forge.read()
        if done.returncode != 0 and after["body"] == now["body"]:
            if hosting is hostings[-1]:
                raise Refusal(
                    4 if hosting is Hosting.ATTACH else 1,
                    "no-host" if hosting is Hosting.ATTACH else "gh",
                    f"gh pr edit exited {done.returncode} and wrote nothing",
                )
            print(
                "media: attaching failed, linking the artifact instead", file=sys.stderr
            )
            continue
        written = split(after["body"])
        local = [
            asset.name
            for asset in attachable
            if f"](./{asset.name})" in (written.block or "")
        ]
        if (
            done.returncode != 0
            or written.outside != parts.outside
            or status_of(written.block).shown != media.head
            or (hosting is Hosting.ATTACH and local)
        ):
            raise Refusal(
                1,
                "read-back",
                "the section was written but does not read back as posted"
                + (f"; not uploaded: {', '.join(local)}" if local else ""),
            )
        print(
            f"media: posted https://github.com/{forge.repo}/pull/{forge.pr} commit {media.head} hosting {hosting.value}"
            + (" (out of date)" if stale else "")
        )
        print(
            "media: "
            + swap_labels(
                forge,
                after["labels"],
                label(a.label_posted),
                [label(a.label_requested), label(a.label_failed)],
            )
        )
        return 0
    return 1


def cmd_stale(a: argparse.Namespace, forge: Forge) -> int:
    pr = forge.read()
    body = pr["body"]
    parts = split(body)
    shown = next(
        (m[1] for line in _lines(parts.block or "") if (m := _POSTED.match(line))), None
    )
    if shown in (None, a.head or pr["headRefOid"]):
        return 0
    forge.write_body(join(parts, as_stale(parts.block or "", newline_of(body)), body))
    print(f"media: marked the reviewer media {STALE_PREFIX}{shown}")
    return 0


def cmd_fail(a: argparse.Namespace, forge: Forge) -> int:
    if not _REASON.match(a.reason):
        raise Refusal(
            2,
            "usage",
            "--reason must be a short code of lower-case letters, digits and hyphens",
        )
    if a.run_url and not _RUN_URL.match(a.run_url):
        raise Refusal(2, "usage", "--run-url must be a github.com Actions run URL")
    pr = forge.read()
    body = pr["body"]
    parts = split(body)
    held = status_of(parts.block).claim
    head = held[0] if held and held[1] == a.run_id else pr["headRefOid"]
    if held and held[1] == a.run_id:
        forge.write_body(
            join(parts, without_claim(parts.block or "", newline_of(body)), body)
        )
        print("media: released the claim")
    print(
        "media: "
        + swap_labels(
            forge, pr["labels"], label(a.label_failed), [label(a.label_requested)]
        )
    )
    marker = f"<!-- reviewer-media:failed {head} -->"
    listed = forge.gh(
        "api",
        "--paginate",
        f"repos/{forge.repo}/issues/{forge.pr}/comments",
        "--jq",
        ".[].body",
    ).stdout
    if marker in listed:
        print(f"media: commit {head} already has its failure comment")
        return 0
    comment = [
        marker,
        f"Reviewer media was not produced for commit {head}.",
        "",
        f"Reason: `{a.reason}`",
    ]
    comment += [f"Run: {a.run_url}"] if a.run_url else []
    comment += ["", "No further automatic run is made on this commit."]
    with tempfile.TemporaryDirectory(prefix="reviewer-media-") as tmp:
        target = Path(tmp) / "comment.md"
        target.write_text("\n".join(comment) + "\n", encoding="utf-8")
        forge.gh(
            "pr",
            "comment",
            forge.pr,
            "-R",
            forge.repo or "",
            "--body-file",
            str(target),
        )
    print(f"media: posted the failure comment for commit {head}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="media.py", description=(__doc__ or "").split("\n\n")[0]
    )
    sub = parser.add_subparsers(dest="action", required=True)
    for name, run in (
        ("claim", cmd_claim),
        ("post", cmd_post),
        ("stale", cmd_stale),
        ("fail", cmd_fail),
    ):
        p = sub.add_parser(name)
        p.set_defaults(run=run)
        p.add_argument("pr")
        p.add_argument("--repo")
        p.add_argument("--label-requested", default="reviewer-media: requested")
        p.add_argument("--label-posted", default="reviewer-media: posted")
        p.add_argument("--label-failed", default="reviewer-media: failed")
        if name != "stale":
            p.add_argument("--run-id", required=True)
        if name == "post":
            p.add_argument("--manifest", required=True)
            p.add_argument("--artifact-url", default="")
            p.add_argument("--artifact-name", default="")
            p.add_argument("--retention-days", type=int, default=30)
            p.add_argument("--no-attach", action="store_true")
        if name == "stale":
            p.add_argument("--head")
            p.add_argument("--quiet", action="store_true")
        if name == "fail":
            p.add_argument("--reason", required=True)
            p.add_argument("--run-url", default="")
    a = parser.parse_args(argv)
    try:
        if getattr(a, "run_id", None) is not None and not re.fullmatch(_RUN, a.run_id):
            raise Refusal(
                2,
                "usage",
                "--run-id must be 1 to 64 letters, digits, dots, underscores or hyphens",
            )
        if getattr(a, "head", None) and not re.fullmatch(_SHA, a.head):
            raise Refusal(2, "usage", "--head must be a full commit sha")
        if not re.fullmatch(r"[0-9]+|[A-Za-z0-9._/-]+", a.pr) or a.pr.startswith("-"):
            raise Refusal(2, "usage", "the pull request is a number or a branch name")
        return a.run(a, Forge(a.pr, a.repo))
    except Refusal as refusal:
        if getattr(a, "quiet", False):
            return 0
        print(f"media: refused {refusal.code}: {refusal.detail}", file=sys.stderr)
        return refusal.exit_code


if __name__ == "__main__":
    os.environ.setdefault("GH_PROMPT_DISABLED", "1")
    sys.exit(main(sys.argv[1:]))
