# Scratch notes

Working notes kept beside the code. Not a decision log, not indexed, and
regularly rewritten in place.

- The retry helper wraps three call sites; the fourth still retries inline.
- The queue consumer's prefetch is set in two places and they disagree.
- Nobody remembers why the scheduler runs in its own process.
