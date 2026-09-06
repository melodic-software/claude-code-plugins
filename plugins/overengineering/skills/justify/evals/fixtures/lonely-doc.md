# Rollout notes for the queue migration

These notes were written while moving the job queue from the old broker to the new one.

## Before you start

Drain the old broker and confirm the consumer count is zero. A consumer left attached will keep
pulling from a queue nobody is filling any more.

## The cutover

Flip the writer first, then the readers. The reverse order loses whatever is written in between.

## If it goes wrong

Point the writer back at the old broker. The old queues are retained for thirty days after cutover,
so a rollback inside that window loses nothing.

## Afterwards

Delete the old broker's credentials. They are still valid until someone does.
