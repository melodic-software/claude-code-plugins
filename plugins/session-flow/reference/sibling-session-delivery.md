# Sibling-session delivery (desktop app only)

Read this file only when this session has a tool that starts another session, which the Claude
desktop app's Code tab provides. Without one (the terminal CLI, the VS Code extension, `claude -p`,
a CI lane), skip it: the citing skill's `/clear`-then-paste delivery applies unchanged.

The delivery hands the rails resume prompt, already produced and redacted by the save-point engine
([save-point.md](save-point.md)), to a new session started beside this one with a fresh context,
instead of asking the user to `/clear` and paste. The user gets a session they can open, steer and
archive, and this session's conversation stays intact.

- **Pointer**: what the started session is and where it runs,
  <https://code.claude.com/docs/en/desktop#start-a-task-that-claude-suggests>; which sessions this
  one can then list and message, <https://code.claude.com/docs/en/desktop#work-across-sessions>.

## The user starts it

Offer the session as a card the user starts. Never start it on your own: the citing skill's gates
(handoff stops for a resume the user chooses, `continue-in-background` launches only on the user's
explicit request, the workflow router suggests by default) all hold on this delivery. Start it at
once only when the user's own words asked for a new session for this work.

## The brief is the rails prompt

The brief is the rails block, byte for byte, as `save_point.py emit` printed it (full path) or as
the prompt-only path emitted it, plus these lines below it:

- the absolute path of the checkout and the branch the work continues on;
- "commit only the files this task changes; never stash, reset or switch branches";
- on a worktree claim this session holds, the claim handover the citing skill prepared (handoff,
  "Hand worktree claims to the resuming session"), so the new session takes the claim first.

Start it with a fresh context, never a fork of this conversation: a fresh session that loads only
the save-point is the point of a handoff.

## Where it runs decides which path

The handoff file lives in the gitignored memory tier of this checkout, so only a session in this
checkout can read it.

- **Full path**: start the session in this checkout, with no new worktree.
- **A new worktree, another checkout, or a cloud session**: take the prompt-only path, or promote
  the file's substance into an artifact that session can read (a pushed commit, the PR body, the
  claimed item) before starting it. A rails prompt whose `Read @` line names a file the session
  cannot read is a resume that fails on its first step.

## After the start

- **Main task handed off**: this session stops the task, as the citing skill's STOP gate says.
  No `/clear` is needed; the user may archive this session or keep it for `/resume`.
- **Side task**: this session keeps working its own task and never does the side task.
- **This session ran under `/loop`**: nothing was cleared, so the loop stays armed here and the
  new session does not re-arm it, as with a background launch (save-point.md, the `/loop` re-arm
  note).
- Follow-ups for the started session go to it as a message, not a new session.

## Background continuation (`continue-in-background`)

The user asked in words for the work to continue now, so that request is the user's own words
asking for a new session: start it at once, with no card to click. That skill's explicit-intent
gate still decides whether there is a request at all.

- **Brief**: the `/goal` payload that skill's completion condition gate produced, verbatim, the
  same text a `claude --bg` agent would receive, plus the lines under "The brief is the rails
  prompt". Those lines become part of the `/goal` argument, so count the whole brief as that skill
  counts its payload (`wc -m`, less the 6 characters of `/goal` and its space) against the limit
  [save-point.md](save-point.md) states; over it, start nothing and take the fallback below.
- **Where**: this checkout, as for a full-path handoff. The session edits it in place, so the
  `claude --bg` dirty-tree gate does not apply; say in the report that the started session and
  the user may touch the same files.
- **Permissions**: when the start offers a permission mode, choose auto, as that skill does for
  `claude --bg`.
- **Report**: the started session's name and that it shows under this session in the sidebar,
  in place of the `claude agents` hint, then stop as that skill's step 5 says. Whether a
  desktop-started session arms a `/goal` from its brief has not been probed, so the report says so
  and tells the user to confirm `◎ /goal active` when they open the session.

## Fallback

The card is not available, the start is refused or fails, or the user chooses to keep the work in
this session: print the citing skill's own delivery instruction (`/clear`, then copy everything
between the dashed lines) with the same rails prompt, and say which of the three applied. For
`continue-in-background` the fallback is its own `claude --bg` launch, which falls back in turn.
