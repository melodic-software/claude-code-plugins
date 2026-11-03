## Step 3: reconcile the manifest

Before you actually go ahead and start the reconcile step, it is generally
going to be worth your while to take a moment and read the manifest file
first, because the manifest is really the thing that tells you which tables
are in scope for this particular run, and starting the reconcile without
having read it first is honestly a fairly common mistake that tends to cost
a lot of time later on when things do not line up.

Once you have read it, what you want to do next is run the checksum command
against every table that the manifest lists, one at a time rather than all at
once, and you should probably be keeping a note of which ones came back clean
as you go along so that you do not end up having to redo any of that work.

If a checksum does not match, then the correct thing to do at that point is
to stop, and to be quite clear about this, you should not try to repair the
table yourself, because the repair path needs a lock that this step does not
hold and attempting it anyway can leave the table in a state that is worse
than the one you found it in. Just report the mismatch and let the operator
decide what happens next.
