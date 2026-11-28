# Collaborative canvas mode

The person and the agent draw and revise one live canvas over several turns, then the agent writes
the final text diagram. Run it when the person asks for it, directly or by accepting a calling
skill's offer, and never under `--unattended`: nobody is there to revise with. It draws only where
the `excalidraw` or `tldraw` target would: such a server connected, a surface that renders it, and
`hosted_canvas` allowing it, under the canvas rule in `SKILL.md` Step 3. That rule's
committed-diagram exception does not stop this mode: the canvas is a working surface, never the
committed diagram, and the text written at Close is what a document commits. Use the server
`diagram_target` names when it is one of the two; otherwise the one connected canvas server, asking
which when both are. When none qualifies, say in one line what is missing and use `auto`.

1. **Open.** Draw the first version through the connected server's own tools, from what the
   conversation holds.
2. **Revise.** Each turn, read the canvas's current state through the server before changing it,
   so the person's own edits on the canvas survive, then apply only the change the person directs.
   When the server returns no canvas state, say so once, revise from your last drawn version, and
   ask the person to describe any edit they made by hand.
3. **Close.** When the person calls the canvas done, write the final text diagram from its last
   state: a Mermaid fence through the mermaid gate in `SKILL.md` Step 3, or the fenced form a
   calling skill asked for, which that skill writes into its own document. That text is the lasting
   record. Never save, export or link the canvas from the repository.
