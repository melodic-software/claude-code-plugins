---
bump: patch
---

### Security

- `/source-control:pull-request view` asks for the repository's visibility only on github.com or a host the forge CLI holds a stored login for; any other host gets no request and the visibility reads `UNKNOWN`, so an unknown server cannot report a private repository as public to the explain-change publish gate. An enterprise token in the environment does not count as a login for this lookup ([#6951](https://github.com/melodic-software/claude-code-plugins/issues/6951)).
