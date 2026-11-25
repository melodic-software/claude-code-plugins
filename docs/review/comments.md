# Code comments

- A comment a change adds to code is one the `necessary` posture keeps: the
  [floor](../../plugins/code-tidying/skills/remove-comments/SKILL.md#postures) or an entry on the
  [keep list](../../plugins/code-tidying/skills/remove-comments/reference/keep-list.md).
- The comment lint (`comment_lint` in `docs/conventions/code-tidying.yaml`) judges each comment line
  a change adds by shape. A note about an outside party's limit passes it only with its link or
  `remove-comments-ignore` on the line.
- A comment the change moved in from another file counts as added; one it only re-indented or moved
  within its own file does not.
- A changed line whose trailing comment text is byte-identical to the base line's is not judged as
  an added comment; a comment whose text changed is.
- A lint finding in a workflow file or a hook manager's config is fixed by hand:
  `/code-tidying:remove-comments` skips those paths unless given its `override` argument.
- `remove-comments-ignore` on a comment is judged at review like any other added comment.
