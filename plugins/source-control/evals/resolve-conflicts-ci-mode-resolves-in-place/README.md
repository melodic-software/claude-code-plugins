# resolve-conflicts-ci-mode-resolves-in-place

CI mode has no shell: the scaffold writes the merge context the lane's runner writes
(`.lane/merge/`, each conflicted path's three versions and both sides' logs), and the run resolves
the conflicted files in place. The content graders (`no-markers-*`, `both-sides-*`) read the
working tree, which is what the runner turns into the patch. The lane's run has no Bash tool;
the case lists Bash so `no-shell` can fail: it checks the skill runs no command even when one is
available, as its CI mode says.
