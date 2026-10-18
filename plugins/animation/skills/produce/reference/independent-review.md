# Independent film review

The agent that built the film does not judge it. After the pack check and your own 1:1 read,
dispatch a fresh-context subagent (the general-purpose agent, not a fork, with a model at least as
capable as yours) and give it only the artifacts and the rules. Withhold your reasoning, your own
review and any claim that a row or a mark is fixed: the reviewer judges the frames, not the story.

Brief to send, filled in:

```text
Review a short film before it is delivered. You did not make it; judge only what the frames show.

Film: <dir>/frames.<fmt> and its frames in <dir>/frames/ (fNNNN.png, frame i is at t = i / <fps>)
Brief: <dir>/brief.md
Approved boards: <dir>/boards/ (storyboard.json and its panels, model and element sheets)
Style: <dir>/boards/style-guide.md and the pack's STYLE.md at <pack dir>/STYLE.md
Shot list: <dir>/shots.json (cuts at each t0)
Pack check output: <the inkstats.py output> (machine rows; confirm or refute them from frames, do not trust them)

Read frames at 1:1 (crop regions with ffmpeg or an image tool) and around every cut. Report, with
timestamps and frame files:
1. Marks that do not read as the pack at 1:1: name the mark and what STYLE.md says it should be.
2. Marks that look added only to move a check row (stray specks, uniform roughness, repeated
   patterns) rather than drawn for the picture.
3. Continuity at each cut: a subject that jumps position, changes speed, or appears or vanishes
   without the boards showing it.
4. Anything the brief or the boards ask for that the film does not show, or shows differently.
5. Frozen or empty stretches the shot list does not call for.
Verdict: SHIP, SHIP AFTER FIXES (list them, severity first) or NOT READY.
```

The verdict is the reviewer's. Open one named frame to confirm each finding is located correctly,
fix it in the shot or board modules (a board change needs the user's approval again), then
render, run the pack check and send a new fresh-context reviewer until its verdict is SHIP.
