/playbooks:skill-authoring. Rewrite this reference file of my skill so it meets our skill criteria. Print only the rewritten file in your reply; do not write any file.

`reference/branch-names.md`:

```markdown
# Branch names

Now take the `$KEY` you looked up in step 2 and build the branch name from it:
`<type>/<KEY>-<three-word-slug>`, all lowercase, where `<type>` is `feat`, `fix` or `docs`.
Then continue with step 4.
```

Author's note, not part of the file: the skill's SKILL.md runs five steps, and step 2 looks up the ticket key. This file is only ever read during step 3, so it can rely on step 2 having run. Our release skill also wants to name branches the same way.
