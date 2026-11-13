# What `necessary` keeps above the floor

The shipped keep list. A repository replaces it through the `comment_keep_list` setting
([SKILL.md](../SKILL.md#settings)); the floor is kept under every list.

- public-API doc comments in the language's structured doc-comment form (a docstring, an XML doc,
  JSDoc or TSDoc, a GoDoc sentence) on a public declaration;
- a **comment on behavior an outside party forces**: the code does something only because a
  dependency, platform, vendor service or protocol this repository cannot change requires it, and
  the comment names that party and its limit (`# The gateway closes idle sockets at 60s, so the
  keepalive is 45s`). Keep it only when verified: the adjacent code depends on the named party and
  nothing in this repository could remove the reason. The outside fact itself need not be provable
  from here; a comment the code contradicts is class A;
- an **issue or RFC link that explains a constraint** the code cannot state (`# Header order is
  fixed by RFC 9110 section 5.3`).

A comment naming a workaround is never one of the two outside-constraint keeps, link or not: it is
deleted and listed as open root-cause work, unless it is a `TODO(#issue)` marker.
