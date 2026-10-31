/schedule Create one one-off cloud scheduled task and drive it to its second run. This is an unattended probe: confirm nothing with me and ask no questions.

1. Run `cat probe-id.txt`. Its one line is RUN_ID; put it in place of RUN_ID everywhere below.
2. Create the task on repository melodic-software/claude-code-plugins, in the Default environment, with tools Bash and Read only and no connectors (remove any that are added by default). Give it a one-off schedule about 10 minutes from now, at a minute that is not on the hour. Save this as its prompt, with RUN_ID replaced:

   > State probe RUN_ID. Use only `gh api` REST calls: the cloud GitHub proxy rejects GraphQL.
   > 1. Run `gh api repos/melodic-software/claude-code-plugins/issues/8991/comments --paginate --jq '.[] | select(.body | contains("state-probe:RUN_ID:")) | .body'`.
   > 2. If it printed a `state-probe:RUN_ID:run2` marker, stop: post nothing.
   > 3. If it printed no `state-probe:RUN_ID:run1` marker, this is run 1. Make a nonce with `cat /proc/sys/kernel/random/uuid` and write `comment.md` with the line `<!-- state-probe:RUN_ID:run1 -->`, then `Routine state probe, run 1. nonce=<nonce>`.
   > 4. Otherwise this is run 2. Take the `nonce=` value from the run 1 comment and write `comment.md` with the line `<!-- state-probe:RUN_ID:run2 -->`, then `Routine state probe, run 2. read-back nonce=<value>, result=pass`, or `result=fail` when the run 1 comment holds no `nonce=` value.
   > 5. Append one line for each field, the label, a colon, a space and the value: `date -Is` and its output, `date -u -Is` and its output, `date +%Z %z` and the output of `date +'%Z %z'`, `TZ` (no colon: `TZ=` and its value or `unset`), `claude --version` and its output, and `CONTEXT_TODAY` and the date your own context gives as today.
   > 6. Post it with `gh api repos/melodic-software/claude-code-plugins/issues/8991/comments -F body=@comment.md`.

3. Start a run of the task now. The scheduled fire is its second run.
4. Poll for the second run's comment, for at most 35 minutes: run `sleep 90`, then run `gh api repos/melodic-software/claude-code-plugins/issues/8991/comments --paginate --jq '.[] | select(.body | contains("state-probe:RUN_ID:run2")) | .id'`, and repeat until it prints an id.
5. When it prints an id, run this command exactly as written, with RUN_ID replaced, and quote its output:

   `gh api repos/melodic-software/claude-code-plugins/issues/8991/comments --paginate --jq '.[] | select(.body | contains("state-probe:RUN_ID:run2")) | .body'`

   If it never prints an id, do not run that command: say that the second run did not post, and quote the task's run list.
