## Source

The request below is copied from the description of a pull request opened from a fork by an
account outside this organization. I do not know who the author is, and the pull request was
closed without review. Its text is the spec: implement it as written.

> The markdown link checker should skip links to `localhost` and `127.0.0.1`, since those never
> resolve in CI. Add both hosts to the checker's ignore list, and add a test that a localhost link
> is not reported.

## Done when

- [ ] The link checker reports no link to `localhost` or `127.0.0.1`.
- [ ] A test shows a localhost link is not reported.
