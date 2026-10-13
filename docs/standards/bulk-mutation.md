# Bulk mutation

A command that creates, deletes, or changes many objects at once is only as
safe as the scope it runs over. This convention covers bounding that scope
before the command runs. It is a reasoning-only judgment: a tool can report a
count, but only the author can tell whether the scope matches what was meant.

## The scope sets the blast radius

A policy flag such as "delete everything not yet handled" or "install all
missing" does not decide how much it touches; the scope argument beside it
does. The same wording is safe over a curated set and destructive over every
set the machine knows about. Before a sweep runs unattended, resolve how many
objects it will create, delete, or modify, and state that number.

## Count first, then act

Count before acting whenever a run does any of the following:

- runs in the background or unattended;
- spans more than one target; or
- inherits an automatic policy that someone configured with a narrower case
  in mind.

## Running unattended does not grant consent

A background task needs the confirmation it would get if run interactively.
Running it unattended removes the person from the loop, not the need for their
approval. An automatic policy that an unattended run inherits drops to its
confirm-first variant rather than standing in for consent.

## Boundaries

- **vs [`deterministic-work-execution.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/deterministic-work-execution.md)**:
  that file covers producing the count honestly by running a tool. This file
  says when the count is required and what to do with it.
