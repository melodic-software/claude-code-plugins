# Independent frame review

The agent that produced the video does not judge it. After `qc.py` passes, dispatch a fresh
subagent (the general-purpose agent, with a model at least as capable as the producer's) and hand
it only the artifacts and the rules. Withhold the producer's reasoning, its own QC summary and any
"this is fixed" claim; the reviewer audits the frames, not the story.

Brief to send, filled in:

```text
Review a demo video for a pull request. You did not make it; judge only what the frames show.

Video: <work>/demo.mp4 (30 fps; frame N is at t = (N - 1) / 30)
QC sheets: <work>/qc/sheet-key-moments.png, <work>/qc/sheet-failures.png if present
QC report: <work>/qc/qc.json (machine checks; confirm or refute them from frames, do not trust them)
What the demo should show: <one line per step, from script.json>

Extract frames yourself (ffmpeg -ss T -i VIDEO -frames:v 1 OUT.png, or a dense range around each
cut and zoom peak) and look at them. Report, with timestamps and frame files:
1. Text or content cut by a frame edge at a zoom peak (all four edges).
2. Any frame mixing two page states (ghosting), a white or black flash, or a frozen stretch.
3. The camera moving across a page cut, or a jerky move.
4. Captions: correct wording, readable, never over content or the click target.
5. Whether each step's outcome is visible on screen long enough to read.
6. With narration: a line that starts before the state it describes, or overlapping lines.
Verdict: SHIP, SHIP AFTER FIXES (list them, severity first) or NOT READY.
```

Read the verdict, spot-check at least one of its findings yourself on the named frame, fix through
the replay, the script or the edit plan, and repeat render, QC and review until the verdict is
SHIP.
