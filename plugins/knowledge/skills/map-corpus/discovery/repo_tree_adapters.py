"""Forge adapters for the repo-tree discovery rung.

Each adapter turns one forge's tree listing into the blob paths it holds, and
builds the two URLs the link map needs: the repository seed URL and the raw URL
a file is fetched from. parse_discovery.py names only the registry, so a second
forge is a new entry here plus its fetch reference under
reference/providers/<forge>/repo-tree.md.

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

from urllib.parse import quote


class ListingError(ValueError):
    """The listing is unusable: wrong shape, or incomplete."""


class GitHubTreeAdapter:
    """GitHub's recursive trees listing: GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=1."""

    name = "github"

    @staticmethod
    def blob_paths(listing) -> list:
        if not isinstance(listing, dict) or not isinstance(listing.get("tree"), list):
            raise ListingError("not a GitHub tree listing: no top-level 'tree' array.")
        if listing.get("truncated") is not False:
            raise ListingError(
                "the listing's 'truncated' is not false: GitHub cut the tree "
                "array short, so it is not a complete denominator. Stop and "
                "ask the user to narrow the corpus."
            )
        paths = []
        for index, entry in enumerate(listing["tree"]):
            if not isinstance(entry, dict):
                raise ListingError(f"tree[{index}] is not an object.")
            path, kind = entry.get("path"), entry.get("type")
            if not isinstance(path, str) or not path or not isinstance(kind, str):
                raise ListingError(f"tree[{index}] has no string 'path' and 'type'.")
            if kind == "blob":  # 'tree' is a directory, 'commit' a submodule
                paths.append(path)
        return paths

    @staticmethod
    def seed_url(owner: str, repo: str, ref: str) -> str:
        return f"https://github.com/{owner}/{repo}/tree/{ref}"

    @staticmethod
    def base_url(owner: str, repo: str, ref: str) -> str:
        return f"https://raw.githubusercontent.com/{owner}/{repo}/{ref}/"

    @classmethod
    def resource_url(cls, owner: str, repo: str, ref: str, path: str) -> str:
        return cls.base_url(owner, repo, ref) + quote(path, safe="/")


ADAPTERS = {GitHubTreeAdapter.name: GitHubTreeAdapter}
