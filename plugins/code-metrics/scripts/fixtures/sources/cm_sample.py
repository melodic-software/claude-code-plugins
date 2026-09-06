"""Fixture source for the code-metrics suites.

One function with two branches and a nested helper, a comment, and blank
lines, so every collector has something to report. Never imported by the
plugin; kept lint-clean on purpose.
"""


def classify(value: int) -> str:
    """Return a coarse label for value."""

    def inner(flag: bool) -> str:
        # a nested function, so the range join has a nested range to subtract
        return "positive" if flag else "non-positive"

    if value > 0:
        return inner(True)
    if value == 0:
        return "zero"
    return inner(False)
