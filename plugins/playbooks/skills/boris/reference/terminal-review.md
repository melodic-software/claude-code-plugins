# Reading Code in the Terminal: Sections 121–124

Boris's *"Just landed: /diff is now a persistent pane"* (Part 24, September 10, 2026): a terminal UI release and the replies it drew, about reading agent output without leaving the session and about who maintains the terminal itself.

## 121. The Diff Pane

`/diff` went from a one-shot list (open, pick a file, read, close) to a persistent pane beside the conversation that you scroll and click into, and that updates live as Claude writes. Boris's use for it: seeing the code without switching windows. Claude Desktop already had a diff viewer; this brought the terminal in line.

`/focus` does the other half of the job. Asked how to switch off the inline file-write diffs that fill the transcript, Boris answered `/focus`: one gives you a place to read changes, the other stops them appearing inline. For what each command currently does, see the [commands reference](https://code.claude.com/docs/en/commands#all-commands) (as of 2026-10-13; recheck when `/diff`, `/focus` or `/tui` change there).

## 122. Read the Diffs That Matter

Asked why anyone reads code if coding is solved: *"I read diffs when it's touching critical code, or code that's important to get right. I don't write the code."* Reading is triage, not proofreading. The agent writes the code; choosing which of its changes to read stays your job, and which code meets the bar is your call. Pairs with Section 120 (review throughput is the bottleneck).

## 123. Fix a Misbehaving Terminal

A TUI that jumps around or flickers is a bug, not something to live with. Boris's fix, in his order: run `claude update`, and if that doesn't work, run `/tui`. He gave no more detail than that.

## 124. Claude Maintains the Renderer

Claude has rewritten Ink, the React-for-terminals library that draws Claude Code's interface, several times. Boris: *"I don't actually know how this impl works -- we treat it as a black box with a ton of property-based tests and benchmarks. Claude maintains it for us."* You can hand a component over once its tests specify it well enough that you never need to read it; writing those tests is the part that stays with you. The same move as Part 23 (Sections 116–120) and Section 109, at component scale.
