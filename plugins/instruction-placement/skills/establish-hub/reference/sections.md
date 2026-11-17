# The hub instruction file's sections

The catalog `/instruction-placement:establish-hub` reports against and writes from. Each section of
the hub's `AGENTS.md` below says what it must state, where its content comes from, and how `plan`
grades it. Inputs: the hub repository's root, its remote, and the answers to the skill's one
question round. Write each section in the estate's own names; this file carries none.

A section is `present` when the hub's `AGENTS.md` states everything its "Must state" line asks,
under any heading. It is `drifted` when it states something the estate contradicts (a listing
command that no longer answers, an owner that moved, a scratch directory that is not ignored). It
is `missing` otherwise. Quote the line behind each verdict.

## 1. Start here

- **Must state:** this repository is the hub; every agent session starts here; it holds the
  session start, the tracker for work that spans repositories, and ignored working material, and
  nothing else: no code, no skills, no clones.
- **Filled from:** the pattern itself, plus the owners discovery and the question round found.
- **Why:** a session that does not know it is in the hub treats the hub as a code repository and
  starts building there.

## 2. What belongs where

- **Must state:** three scopes. A fact true of one repository lives in that repository. A fact
  true of every repository on a machine lives in the person's machine-wide instructions (name
  where, when the person keeps them). Work between repositories is the hub's.
- **Filled from:** the question round's answer on machine-wide instructions; skip that clause
  when there are none.
- **Why:** without the split, a hub fills up with each repository's exceptions and drifts from
  them.

## 3. Where work is filed

- **Must state:** an item goes in the hub's tracker only when no single repository owns it;
  otherwise it is filed in the owning repository, and the two link to each other.
- **Filled from:** the hub's own forge tracker. No tracker binding is written.
- **Why:** an item filed in the hub that one repository owns is invisible to the sessions and
  lanes working in that repository.

## 4. The repositories

- **Must state:** the command that lists the estate's repositories and their purpose, for each
  owner the hub spans; the rule for where a repository's local checkout lives, and the command
  that prints that root; what to do when a checkout is absent (clone it to the rule's path).
- **Filled from:** discovery's listing command and checkout root. A listing that did not resolve
  leaves the section `missing` with the reason `unresolved`, and nothing is written for it.
- **Never:** a list of repositories, or a machine-specific path. A list drifts the day a
  repository is added; a path holds only on the machine that wrote it.

## 5. Dispatching work

- **Must state:** work reaches a target repository through a worktree of that repository, never
  its main checkout; a small task goes to a subagent in that worktree, and a task that needs the
  target's own hooks and settings to load goes to a session started in the target's worktree;
  read the target's `AGENTS.md` from its default branch before working there; name the
  repository explicitly in every forge command, since the session's directory is the hub.
- **Filled from:** the pattern. Write the routes as rules; do not restate what a session started
  elsewhere loads. Point at the harness docs for that instead:
  [Additional directories grant file access, not configuration](https://code.claude.com/docs/en/permissions#additional-directories-grant-file-access-not-configuration).
- **Why:** a forge command run without the repository named acts on the hub, and a write to a
  target's main checkout collides with whoever else works there.

## 6. Working material

- **Must state:** the scratch directory's name, that it is ignored, and that it lives in the
  hub's main checkout only.
- **Filled from:** the ignored scratch directory discovery found, else the question round's
  answer. `apply` appends its line to `.gitignore` when absent.
- **Drifted when:** the named directory is not ignored.

## 7. Where cross-repository decisions live

- **Must state:** where a decision that spans repositories is recorded, as a pointer to its owner.
- **Filled from:** the decision-record convention discovery or the question round found. When the
  convention lives in the hub, the hub's own adoption record is written there; otherwise it is
  proposed, not written.
- **Never:** copy decisions into the hub. A shared glossary or standards file with no owner is
  reported as unowned, not adopted here.

## Writing the text

New sections are written in the imperative, one rule per bullet, each with its reason where the
rule's wording does not already show it. Keep the file short: it loads in every hub session. A
pointer names the file or command and the condition that sends a reader to it; it is not a
summary of what it points at.
