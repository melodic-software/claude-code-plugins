#!/usr/bin/env bash
# A blog package with a shared slugify helper, and a draft plan for permalinks that writes its own.
set -euo pipefail

mkdir -p .work/post-permalink/design blog tests
cat >README.md <<'EOF'
# blog

Posts, listings and shared text helpers (blog/text.py).
EOF
: >blog/__init__.py
cat >blog/text.py <<'EOF'
"""Text helpers shared by the blog modules."""
import re
import unicodedata


def slugify(title):
    """Lowercase ASCII words joined by hyphens: 'Café Notes!' -> 'cafe-notes'."""
    ascii_title = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    return "-".join(re.findall(r"[a-z0-9]+", ascii_title.lower()))
EOF
cat >blog/models.py <<'EOF'
from dataclasses import dataclass
from datetime import date


@dataclass
class Post:
    title: str
    body: str
    published_on: date
EOF
cat >blog/posts.py <<'EOF'
"""Post listing helpers."""


def recent(posts, limit=10):
    return sorted(posts, key=lambda post: post.published_on, reverse=True)[:limit]
EOF
cat >tests/test_posts.py <<'EOF'
import unittest
from datetime import date

from blog.models import Post
from blog.posts import recent


class RecentTest(unittest.TestCase):
    def test_newest_first(self):
        old = Post("a", "", date(2026, 1, 1))
        new = Post("b", "", date(2026, 2, 1))
        self.assertEqual(recent([old, new]), [new, old])


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/post-permalink/PLAN.md <<'EOF'
# Post permalinks

## Brief

### Problem
Posts have no stable address: the site links to them by list position, so links break when a post is added.

### Goal
Each post has a permalink built from its publication date and title.

### Acceptance criteria
- AC1: `permalink(post)` returns `/YYYY/MM/<slug>/`, with the month zero-padded.
- AC2: The slug is lowercase ASCII words joined by hyphens, accents folded: `Café Notes!` becomes `cafe-notes`.
- AC3: Two posts with the same title in different months get different permalinks.

### Out-of-scope
- Redirects from the old list-position links.
- Custom slugs chosen per post.

## Design

Early exit (tier C): One new function over an existing dataclass; no new types.

## Plan

### Behavior
- B1: A post's permalink is its publication year and zero-padded month followed by its slug (AC1, AC3). Delivered by Phase 1.
- B2: Edit `blog/posts.py` to add `_make_slug` (AC2). Delivered by Phase 1.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Every post has `published_on` set | plan | Phase 1 Sanity Check | Minor: proceed and note |

### Phase 1: Add permalink [STATUS]
**Satisfies:** AC1, AC2, AC3
**Delivers:** B1, B2

- In `blog/posts.py`, add `_make_slug(title)`: lowercase it, replace spaces with hyphens, and drop every character outside `[a-z0-9-]`.
- Add `permalink(post)` returning `f"/{post.published_on:%Y}/{post.published_on:%m}/{_make_slug(post.title)}/"`.
- In `tests/test_posts.py`, add one case per criterion.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `blog/posts.py` | modify |
| `tests/test_posts.py` | modify |
EOF
cat >.work/post-permalink/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One new function over an existing dataclass; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/post-permalink
