"""Question-shape rules both interview servers apply: one definition each, read by round.py, the
page server and the shared session, which ship the results to their pages as flags."""

import re

WITHHELD = re.compile(r"\s*Withheld:")
MARKER = re.compile(r"\(recommended\)", re.IGNORECASE)


def withheld(rec):
    """True when a recommendation is the `Withheld:` text: the question is asked open, with no
    recommendation to accept and none on a card."""
    return bool(WITHHELD.match(str(rec or "")))


def _norm(s):
    return re.sub(r"\s+", " ", MARKER.sub(" ", str(s or ""))).strip().casefold().rstrip(".,;:!?").strip()


def _within(needle, hay):
    """Whole-word containment, so the alternative `no` does not match `now`."""
    return re.search(rf"(?<!\w){re.escape(needle)}(?!\w)", hay) is not None


def restates(alt_text, rec):
    """True when an alternative restates the recommendation: either text contains the other as
    whole words, after case, spacing, trailing punctuation and a (recommended) marker are folded.
    A withheld recommendation has nothing to restate."""
    if withheld(rec):
        return False
    r, a = _norm(rec), _norm(alt_text)
    return bool(r and a and (_within(r, a) or _within(a, r)))
