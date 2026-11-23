# Changelog

All notable changes to the `prototype` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.47.3] - 2026-11-23

### Changed

- `/prototype:explore-directions`, `/prototype:pressure-test` no longer gather repository context that no step read.

## [0.47.2] - 2026-11-22

### Changed

- The shared copies (`reference/ecosystem-resolution.md`, and the git-hook library where this plugin carries it) name `docs/conventions/ecosystems/<ecosystem>.yaml` as the home of a repository's ecosystem records, with the legacy `.claude/ecosystems/` still read for a record absent there.

## [0.47.1] - 2026-11-22

### Fixed

- The notes panel no longer drops a click on a note row when the list re-renders while the mouse button is down, for instance when the server pushes a state change. The row is selected and its Edit, Withdraw and Move or resize actions show, where before they stayed hidden. Only a primary-button press holds the re-render, and the hold ends when the pointer leaves the list, a context menu opens or the window loses focus, so the list never freezes after a right-click or a drag into the mockup.

## [0.47.0] - 2026-11-21

### Added

- A sent note on the notes host page now has Edit and Withdraw. An edit goes to the session as that note's new text under the same seq (`POST /api/note/edit`); a withdraw tells the session and lists the note as withdrawn, not pending, with no marker, and leaves it out of `status`, the watcher's unhandled notes and Copy all notes (`POST /api/note/withdraw`, `note.schema.json` x-version 8).

## [0.46.0] - 2026-11-21

### Added

- The notes host page's Copy menu has Copy chosen design: it copies the text the mockup's own copy-out terminator gives, which a mockup builds in `window.uiFeedbackCopyOut`. Framed by the host page, the mockup's data bar, marked `data-harness-chrome`, hides, and the bar's Sample data menu presses its controls; opened alone from `file://` the page keeps its own bar.

## [0.45.1] - 2026-11-21

### Fixed

- The notes tool's command bar shows a chevron at each end that hides tools at phone width, light and dark; tapping it scrolls the bar, and Tab keeps each focused tool clear of the chevrons.
- A note's marker follows its element when the mockup reflows, such as after the window narrows, instead of keeping the spot it was drawn at.

## [0.45.0] - 2026-11-21

### Changed

- The notes host page is now one command bar at the bottom of the window over a full-width mockup: variant arrows naming the shown variant and state, Pick, Region, Arrow and Text, Markers, Sample data, Copy and Notes. Notes open as a popover above the bar, with All, Drafts and Sent filters, that can move to the other side. The page, its Controls tab and the variant switcher share one light and dark theme that follows the system, notes are named in the reader's words, and the status line states only state. Framed by the host page, the variant switcher hides its own pill.

## [0.44.4] - 2026-11-21

### Fixed

- The notes host page's Mark a region (R) now reaches past the frame: a drag held near the frame's top or bottom edge scrolls the mockup, so a region can cover a list taller than the frame. A drawn region moves when dragged and resizes from its edges and corners, or with the arrow keys and Enter, before its note is sent or after, from the editor's or the row's Move or resize. A sent note's new box goes to the session as a change naming that note (`POST /api/note/change`, `note.schema.json` x-version 7).

- The explore-directions variant switcher keeps every label on one line once its motion controls appear, and its speed and replay buttons now name what they do on hover and keyboard focus.

## [0.44.3] - 2026-11-21

### Fixed

- The notes host draws a note's marker only while the variant and screen state it was made on are shown in the mockup, and hovering a note from another variant no longer outlines its box over the variant on screen ([#17949](https://github.com/melodic-software/claude-code-plugins/issues/17949)).

## [0.44.2] - 2026-11-21

### Changed

- the shared prerequisites checker gains a latest-release mode

## [0.44.1] - 2026-11-21

### Fixed

- Notes host: P, R, A, M and N now work while focus is inside the mockup. Before, the frame passed only Escape and T up to the host, so the shortcuts did nothing after a click into the mockup. A key the mockup handles and cancels with `preventDefault`, as the switcher does, stays in the mockup, so on a variant with motion R inside the mockup replays; keys typed in a field, or held with Ctrl, Alt or Meta, stay in the mockup ([#17917](https://github.com/melodic-software/claude-code-plugins/issues/17917)).

## [0.44.0] - 2026-11-21

### Added

- **explore-directions says how to mount the notes harness on a real-stack route, and step 5
  removes it.** `reference/real-stack.md` gains "The notes harness": start the notes bridge with
  `--dev-origin`, keep every harness file in one `prototype-harness/` directory (copies of the
  frame helper, `harness-fence.mjs` and the `dev-origin.mjs` it imports), load the helper behind
  the switcher's environment gate, mount the fence as dev-server middleware, and add only whole
  lines to a kept file, each marked `data-prototype-harness`. Step 5 deletes the harness and confirms
  `git grep -n data-prototype-harness` prints nothing. The new eval case
  `ed-real-stack-harness-removed` grades that removal on a scaffolded Vite app
  ([#17751](https://github.com/melodic-software/claude-code-plugins/issues/17751)).

### Fixed

- Notes host: the move arrow's shortcut is now A. It shared M with the marker toggle, which caught the key first, so the arrow could not be started from the keyboard ([#17883](https://github.com/melodic-software/claude-code-plugins/issues/17883)).

## [0.43.0] - 2026-11-21

### Added

- **After a reload, the notes host lists the run's notes and drafts again.** Sent notes come from a new `GET /api/notes` bridge route. It needs the page token and serves only the running bridge's own data dir. Drafts are kept in the tab's sessionStorage under the run's token and are never sent to the server. Notes are listed oldest first, numbered as their markers are. Hovering a row draws its note's box on the mockup. Clicking a row, or its marker, restores the note's variant, screen state and content set, scrolls to the note, and keeps the box drawn until you click elsewhere. A marker takes a click only on its own box, and only outside a pick mode ([#17801](https://github.com/melodic-software/claude-code-plugins/issues/17801)).

## [0.42.0] - 2026-11-21

### Added

- **A move-arrow note says "move this element to there" on the mockup.** On the notes host page,
  Draw a move arrow (M) picks the element to move, then the element it should go to (or, with
  Shift and a click, a point when no element fits), then opens the note. The frame draws the arrow
  from one end to the other and redraws it from the elements when the page re-flows. The note's
  `kind` is `move`: `anchor` and `rect` are the element to move, and the new `to` field holds the
  destination's `point` and, when there is one, its `anchor`. The note schema's `x-version` moves
  to 6. `relocate-note.mjs` runs the anchor ladder on both ends and reports the destination under
  `to`. explore-directions restates both ends of a move arrow before acting on it.
  ([#17803](https://github.com/melodic-software/claude-code-plugins/issues/17803))

## [0.41.1] - 2026-11-21

### Changed

- **The notes host page now reports a framed page that never says it is ready.** If the frame helper's first ready message has not arrived within 10 seconds, the host page says so, on a real-stack route and on a mockup alike. On a real-stack route it adds that the dev server may refuse to be framed or the route may not load the helper. It does not judge by the frame's load event. The new `notes-bridge/frame-channel.mjs` holds the host page's channel rules. A message is taken only from the frame's window and, on a real-stack route, from the dev origin. Every message to a real-stack frame names the dev origin as `targetOrigin` ([#17748](https://github.com/melodic-software/claude-code-plugins/issues/17748)).

## [0.41.0] - 2026-11-21

### Added

- **Hide markers (M) shows or hides every note marker on the mockup.** The toggle sits beside Hide notes in the notes host's dock, so it works with the panel closed. It never starts or ends a pick, markers never take a click meant for the page, and the choice lasts across reloads for the tab's run ([#17802](https://github.com/melodic-software/claude-code-plugins/issues/17802)).

## [0.40.0] - 2026-11-21

### Changed

- **A picked element, marked region or selected text stays drawn while you write its note.** The notes host asks the frame to hold the pick, so the outline stays on the page after pick mode ends and goes when the note is sent, saved as a draft or cancelled. A sent note then shows as its numbered marker and a draft as D1, D2 and so on ([#17800](https://github.com/melodic-software/claude-code-plugins/issues/17800)).

- The sandbox rules in explore-directions and pressure-test state the general rule (sandbox keys only, synthetic records, no production or real data) without domain-specific wording.

## [0.39.0] - 2026-11-21

### Added

- **A real-stack route can let only the notes bridge frame it.** The new `notes-bridge/harness-fence.mjs` is a connect-style middleware for the app's dev server. It sends `Content-Security-Policy: frame-ancestors <bridge origin>` as a response header and adds no `<meta>` policy. `node harness-fence.mjs <bridge origin>` prints that header ([#17750](https://github.com/melodic-software/claude-code-plugins/issues/17750)).

### Changed

- **`notes-bridge.sh ensure-running --dev-origin` uses one host spelling.** The dev origin's host must now be `localhost` or `127.0.0.1`, the two hosts the bridge answers on. Any other host is refused at start. The printed `url` and `origin` use the dev origin's host, so the host page's origin check, its frame URL and the dev server's `frame-ancestors` source all name the same host.

## [0.38.0] - 2026-11-21

### Added

- **The notes bridge can frame a real-stack route from the app's dev server.** `notes-bridge.sh ensure-running --dev-origin <origin>` takes the origin only when `new URL(input).origin` returns it unchanged, so an input such as `http://localhost:80` is refused with the canonical form to pass instead. In that mode the host page frames the dev origin with no `sandbox` attribute, its policy adds `frame-src <dev origin>` and keeps `frame-ancestors 'none'`, and it trades messages only with that origin. Starting the mode needs `node` on `PATH` ([#17749](https://github.com/melodic-software/claude-code-plugins/issues/17749)).

## [0.37.0] - 2026-11-20

### Changed

- Re-locating a note now tells a removed control from a page that marks none. When the page marks
  no data control or has no controls runtime, the part is left out of `restored` and listed in the
  result's new `unmarked` field, where it used to read false like a control the page lost ([#17010](https://github.com/melodic-software/claude-code-plugins/issues/17010)).
- A region note over content with no test ids now records the elements it covers: when the region
  crosses no test-id element, `elements` lists the holding element's children it crosses. The note
  schema's `x-version` moves to 5, and the host page's note summary says "element(s)", not "marked
  element(s)".

## [0.36.3] - 2026-11-19

### Fixed

- The `ed-controls-everything-default` eval's `manifest-element`, `manifest-groups` and
  `runtime-inlined` graders now pass a page that a build script assembles. The script is a `.mjs`,
  `.cjs`, `.js` or `.py` file, written with Write, that calls a file write, names an `.html` file
  and holds the grader's text: the manifest element, the three groups, or the runtime's path or
  defining line. A later Bash command must run it with `node`, `bun` or `python`. A script that
  builds no controls or leaves out a group still fails. Each grader has pass and fail samples of
  the build-script shape
  ([#17350](https://github.com/melodic-software/claude-code-plugins/issues/17350)).

## [0.36.2] - 2026-11-19

### Fixed

- The `pt-vendor-fit-no-sandbox-key` eval case no longer fails a run that sets `PINGLY_LIVE_KEY`
  to a dummy value to show the adapter refusing a production key, or that unsets it before
  running the shell: its `no-live-key-bash` grader now fails only a Bash call that reads the
  variable. Two new graders fail a written or edited file that reads the key from the environment
  (`os.environ`, `os.getenv`), which the Bash grader could not see.

## [0.36.1] - 2026-11-18

### Fixed

- `/prototype:explore-directions` now says the level report line (`level: <name> (<layer>)`) is still printed when the request says to build without asking or no plan is shown, before the run's first tool call that writes a file ([#16467](https://github.com/melodic-software/claude-code-plugins/issues/16467)).
- The `ed-controls-everything-default` eval's `runtime-inlined` grader now passes a page written by a redirect to a shell variable, such as `{ cat ...; } > "$OUT"`, and its samples include one of that shape ([#16467](https://github.com/melodic-software/claude-code-plugins/issues/16467)).

## [0.36.0] - 2026-11-18

### Changed

- The control panel no longer names a default panel library for React projects. It resolves the
  panel library from the repository through the plugin's new copy of the ecosystem resolution
  steps (`reference/ecosystem-resolution.md`, version 1.1.0), and uses plain range inputs when
  none resolves.
- The control panel's rule that controls write CSS variables on the prototype root no longer
  carries framework-specific code examples.
- `/prototype:pressure-test` no longer shows package-manager or SDK commands as examples of the
  one start command; it asks for one short command through the project's task runner.

## [0.35.2] - 2026-11-18

### Changed

- `/prototype:explore-directions` handover: when every variant has the same states, the shared
  line now has a fixed shape, `All variants have the same states: <names>.`, on a line of its own
  between the path-and-keys line and the variant lines. It names the states itself instead of
  pointing back at the `Plan:` line, and the states stay out of the path-and-keys line.

## [0.35.1] - 2026-11-18

### Fixed

- **The notes host is offered only on a single-user machine.** `/prototype:explore-directions` now says why: the host hands its per-run token to any local process that asks the loopback port.
- **`playwright-cli` is declared as an optional prerequisite**, and the `node` row names note relocation, so `/harness-ops:prerequisites` reports what relocating a note needs and what happens without it.
- **The `ed-notes-tracer` eval's serve grader now requires `--page explore-directions.html`.** An `ensure-running` on the default page, which the scaffold never writes, no longer passes.

## [0.35.0] - 2026-11-17

### Changed

- **The real-stack switcher keeps the chosen variant across in-app navigation.** When `/prototype:explore-directions` mounts the switcher in a layout shared across routes, it also keeps the current variant in session storage, so navigation that drops the query string no longer loses the choice. A `?variant=` in the URL still wins over the stored value.

## [0.34.4] - 2026-11-17

### Changed

- `/prototype:explore-directions` cuts restated upstream text to pointers. The mockup placement step points at the tools reference for what persists between Bash calls and at the GNU and BSD `mktemp` manual pages for where the dialects differ, keeping the portable-template rule and its reason. The `design` record in `design-canvas.md` now states the boundary as our decision and points at the probe record. The `playground` record links the upstream `SKILL.md` at the recorded commit instead of quoting it. The `/design` identity string the offer quotes stays on purpose, now with its reason ([#16858](https://github.com/melodic-software/claude-code-plugins/issues/16858)).

## [0.34.3] - 2026-11-17

### Changed

- The bundled prerequisites checker's `when` also counts a config git tracks anywhere in the project directory's repository, from one `git ls-files` per run, so a repository whose only config sits in a subdirectory gets its probe line. A `config_any` item may now be a path from the repository root with `*`, `?` and `**` wildcards; `..`, `.` and absolute paths are rejected. When git is missing, fails or runs past two seconds, the entry counts as needed.

## [0.34.2] - 2026-11-17

### Changed

- The bundled prerequisites checker honors an entry's optional `when` (`config_any`: file names, or a file and a pattern its text must match): the SessionStart probe stays silent about the entry unless one of those configs sits in the project directory or above it, and `check` reports it INFO there.

- The shared config cascade copy now exports its `fileState` and `escapes` path guards, so a script that reads other repository files can refuse a symlink or a path outside the checkout the same way. Nothing that already used the cascade changes.

## [0.34.1] - 2026-11-16

### Fixed

- `/prototype:pressure-test` no longer claims a request to settle domain types and an internal
  service contract: its vendor-fit trigger now reads 'does this third-party API do X for us', so
  the generic word "service" no longer pulls design work into the prototype skill. Invocation
  probes cover vendor-fit questions and a vendor price comparison that should not trigger.

## [0.34.0] - 2026-11-16

### Added

- `/prototype:pressure-test vendor-fit` checks whether an outside service does what the rules need.
  The logic module stays pure; a thin adapter behind the app's own port is the only file that
  calls the vendor's sandbox, with sandbox keys from the environment and synthetic records only,
  never production credentials or regulated data. The terminal shell shows each check passing or
  failing, and the durable note records the verdict. Eval case `pt-vendor-fit-no-sandbox-key`.

### Changed

- `/prototype:explore-directions` keeps every write stubbed by default. When the question names a
  write's behavior, that write may go to the vendor's sandbox on the real stack, stated at the top
  of the prototype, never against production or regulated data. Eval case
  `ed-write-behavior-sandbox`.

## [0.33.2] - 2026-11-16

### Changed

- The bundled prerequisites stubs' node notice names the plugin whose hook printed it, and names a check skill of another plugin with the condition that that plugin is enabled.

## [0.33.1] - 2026-11-16

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract.

## [0.33.0] - 2026-11-16

### Added

- The notes host page's dock has two tabs, Notes and Controls, in the WAI-ARIA tabs pattern: the
  arrow keys, Home and End move between them, and the dock button and N still hide and show it.
- A mockup's controls come from one `prototype-controls` manifest, checked against the new
  `notes-bridge/controls.schema.json`, and are drawn by the controls runtime
  `notes-bridge/controls.js` with one registry of control types (range, color, select, toggle,
  radio). Each control writes a CSS variable or a `data-control-` attribute, on the page or on one
  variant, and shows its value. The Controls tab adds the page's Seed, Clear, Reset, list toggles
  and worst-content toggle as built-in entries, Copy config, and Reset controls, which leaves the
  data alone. Opened from `file://`, the mockup draws the same controls in its own panel, top-right
  or, with the manifest's `placement`, top-left. A manifest with a default its control's field
  cannot hold, or two controls sharing an id, is refused whole, and a value a control cannot hold
  is never set.
- Every note carries `controls`, each manifest id with its value, and re-locating a note sets them
  again before the anchors run (`restored.controls`).
- The levels gain a `controls` dimension: `brief` or `everything`, shipped as `everything` at
  `standard` and `full`. New `reference/controls.md` says how to write the manifest, and the eval
  case `ed-controls-everything-default` checks it.

## [0.32.1] - 2026-11-15

### Changed

`/prototype:explore-directions` handover: when every variant has the same states, one shared line
saying so and naming them can replace repeating the states on each variant's line. The
`ed-offline-mockup-handover` grader passes that line.

## [0.32.0] - 2026-11-15

### Added

- `/prototype:explore-directions` says where a notes session's files go: the distilled notes and
  screenshots to the memory slice, and, for a named map item, those files and the mockup page to
  the item's folder on the map's dossier branch, pushed only after the repository's secrets and
  machine-data check passes, with `not pushed: <reason>` in the reply otherwise. Real-stack
  screenshots stay local.
- Review mode's boundaries name the local notes host as one person's element-pinned notes.
- Eval cases `ed-notes-dossier-map-item` and `ed-notes-dossier-check-fails` cover the passing and
  the failing check against a local bare remote.

## [0.31.2] - 2026-11-15

### Changed

- Restore the earlier skill wording a prompt audit cut without eval evidence, pending eval evidence of no loss.

## [0.31.1] - 2026-11-15

### Changed

- The session bridge watch, events and unwatch tool descriptions now say what each tool needs first, what it returns, and when it errors.

- Prototype skill text reads in plain case instead of capital-letter emphasis, and explore-directions states plainly that `--unattended` makes no `/design` suggestion.
- The `design` verification record lives only in `reference/bundled-design.md`, without the superseded 2.1.263 history row, and the skill's pointers name that file.

## [0.31.0] - 2026-11-15

### Added

- The notes host page's Notes panel keeps drafts: Save draft lists a note without sending it, and
  each draft can be edited, deleted or sent, or all sent at once with Send all drafts. A draft
  stays out of Copy all notes until it is sent.
- Each note's status (draft, sent, delivered to Claude, handled) and the session's reply show
  beside it, and a polite live region announces each change of status.
- The panel hides and shows with its dock button or N; closing the panel or the note editor
  returns the focus to the control that opened it.

## [0.30.0] - 2026-11-15

### Added

- The notes host page pins a note to a text selection (Note on selected text, T) or to a region
  the person drags or moves with the arrow keys (Mark a region, R), as well as to an element. A
  text note carries the selection as a quote with a little visible text either side; a region
  note carries its box and the test-id elements it crosses.
- Every note carries the view a reload loses: the data controls pressed since load (`data.log`)
  and the frame's viewport. Re-locating a note sets the viewport, replays the log, scrolls to
  the note's scroll position, and adds a text-quote rung after the structural path; a text note
  whose quote is gone, or sits outside the matched element, is not confirmed.
- When the notes server stops answering, the host page says so, keeps the notes written after
  that, and Copy all notes makes one `prototype-notes` block. `notes-bridge.sh import --file`
  takes a pasted block written to a file, checking every note against the note contract.
- `reference/data-controls.md`: Seed is deterministic, record *i* from index *i*, and each data
  control carries `data-data-control` so notes can log and replay it.
- Eval case `ed-notes-copyout-import`.

## [0.29.1] - 2026-11-15

### Changed

- `/prototype:explore-directions` shared-interview placement now covers build sources, scripts and scratch files: they go in `<data_dir>/staging/<run>/`, outside the live build folder, or stay in memory, never in a `mktemp` directory. SKILL.md's "Ephemeral placement" `mktemp` template applies only to the offline mockup.

## [0.29.0] - 2026-11-14

### Added

- Levels for `/prototype:explore-directions`: `sketch`, `standard` (the default, today's run) and
  `full` set the variant count, screens, states, evidence and offers. A run takes the level from
  `--level <name>`, then from a request that asks for a size of run ("the full package", "a quick
  sketch"; words describing the screen never select one), then from the settings, and prints one
  line naming the level and where it came from, such as `level: full (prompt)`.
- The plugin's first setting, `level`, as a `userConfig` option and in a repository's
  `docs/conventions/prototype.yaml` or `prototype.local.yaml`, beside a `levels` map that refines a
  shipped level or adds one. Keys: `reference/config.md`; schema:
  `schemas/prototype.schema.json`; shipped levels: `reference/levels.default.yaml`.
- `lib/prototype-settings.mjs`, which resolves them through the plugin's copy of the shared config
  cascade, and this plugin's copy of the shared convention-home resolver.
- Eval cases `ed-level-full-package`, `ed-level-config-default` and
  `ed-level-content-word-not-a-level`.

## [0.28.0] - 2026-11-14

### Added

- `/prototype:explore-directions` re-locates each note in a fresh page before restating it
  (`reference/feedback.md`, "Re-locating a note"): `notes-bridge/relocate-note.mjs` writes a
  `playwright-cli run-code` script that carries the note as one JSON literal, restores the note's
  variant, screen state and content set, runs the anchor ladder in the sandboxed frame, and saves a
  shot of the element from inside the frame. A note whose element is gone gets a position-only
  shot of its stored box, and the session asks instead of editing.
- Notes carry the picked element's box (`rect`, percent of the page), the position-only last step of the anchor ladder.
- The variant switcher listens for a `vs:show` event that restores a variant, screen state and
  content set. Pages that never send it behave as before.
- Eval case `ed-notes-relocate-not-found`.

## [0.27.0] - 2026-11-13

### Added

- `/prototype:explore-directions` can serve its mockup through a notes host when the person wants
  to pin notes in the page (`reference/feedback.md`). The host page frames the mockup in a sandbox,
  the person picks an element and writes a note, and the session reads each note as data through
  the session bridge's watcher, restates it, and replies on the page. The host puts the mockup's
  policy first in the framed page, so a page that leaves out its own still has no network. The
  `file://` mockup and its copy-out stay the default.
- `notes-bridge/`: this plugin's copies of the shared ui-feedback parts (host page, pin helper,
  note schema and validator, notes bridge app) and the session-bridge files they run on.
- `python3` and `curl` prerequisite rows (optional; without them, the mockup stays copy-out only).
- Eval case `ed-notes-tracer`.

### Changed

- The `shipments-mockup.html` eval fixture carries proposed test ids, as every mockup does.

## [0.26.2] - 2026-11-13

### Added

- Eval case `ed-claude-design-project-routes`: a request naming an existing claude.ai/design
  project is routed to that project through the `ClaudeDesign` tool, or to throwaway variants with
  the reason when the tool is not available, and nothing is written to the project before the plan
  is approved.

### Changed

- `/prototype:explore-directions` carries one `## Boundary` section for the `design`, `ClaudeDesign`
  and `playground` surfaces, keeping the suggest sentence, routing split and mutation gate; the
  full rules move to `reference/boundaries.md`. No behavior change.

## [0.26.1] - 2026-11-13

### Changed

- The vendored prerequisites checker's usage and schema errors give `EXAMPLE_ENABLED` as the sample option name, one that names no plugin.

## [0.26.0] - 2026-11-13

### Added

- A shared clean-state proof in the prototype discipline: before handing a prototype over, the
  agent starts it from a clean state, drives it itself through an ordered check list of actions
  and expected results, leaves it clean, and hands the person that list before asking for a
  verdict. `/prototype:pressure-test` and `/prototype:explore-directions` both run it.
- `/prototype:explore-directions` mockups open on seeded synthetic data with Seed, Clear and Reset
  controls, plus pagination, filter and sort toggles when a variant renders a list
  (`reference/data-controls.md`).

### Changed

- The `/prototype:explore-directions` handover has five parts: the check list now comes before
  the reply template. The shared-interview handover carries the check list too.
- Eval cases `ed-offline-mockup-handover` and `pt-html-demo-offline` grade the check list, and the
  mockup case checks for the data controls.

## [0.25.2] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.25.1] - 2026-11-12

### Changed

- Synced the shared library copies this plugin carries; their pointer records no longer carry an as-of date or recheck trigger.

## [0.25.0] - 2026-11-11

### Changed

- `/prototype:pressure-test` and `/prototype:explore-directions` say they raise fidelity for a question discussion cannot settle, and that the cheapest artifact that answers the question wins.

## [0.24.15] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [0.24.14] - 2026-11-11

### Changed

- The variant switcher asset and its reference name the user-interface `animation.*` keys behind the highlight's curve and the 250ms and 150ms durations, and the combine decision-block example names the key behind its curve. No rendered value changes.
- The control panel guide offers user-interface's `animation.easing.*` curves in the easing select when the project names no curves of its own.

## [0.24.13] - 2026-11-11

### Changed

- `/prototype:explore-directions --unattended` no longer suggests or attempts `/design`, a command only the person can run. It builds the mockup without asking.

## [0.24.12] - 2026-11-11

### Changed

- `pressure-test` and `explore-directions` point at the live Claude Code docs sections for Bash
  output limits, what persists between Bash calls, the design canvas lifecycle and skill name
  precedence, and at the `ClaudeDesign` probe record for where writes are refused, instead of
  restating them. No behavior change.

- The `explore-directions` and `pressure-test` skills now cite the gather-block convention record, "The pre-compute block runs as one shell
  invocation", instead of restating how the harness runs the pre-compute block. No behavior
  change.

## [0.24.11] - 2026-11-09

### Changed

- Internal simplification, no behavior change.

## [0.24.10] - 2026-11-09

### Changed

- Internal simplification of the shared view helpers this plugin carries, no behavior change.

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

## [0.24.9] - 2026-11-09

### Changed

- Simplified the shared setup-apply.mjs, spawn_noise.py and state-key.sh library copies; behavior is unchanged.

## [0.24.8] - 2026-11-06

### Fixed

- gate pressure-test's performance hand-off

  A performance-target fork hands off to /performance:goal only when the
  performance plugin is installed; otherwise the timing is recorded as
  unqualified and the user is asked.

## [0.24.7] - 2026-11-04

### Changed

- Shared config-cascade library synced: the personal layer is now called the personal override in comments and in view-settings' warnings, and `overlayApplies` is `personalOverrideApplies` (#13187). Behavior is unchanged.

## [0.24.6] - 2026-11-04

### Fixed

- Shared `view-registry.mjs` synced where this plugin carries it: the architecture lane now declares that its plugin ships a `medium` option, which #13027 added; no other change to this plugin.

## [0.24.5] - 2026-11-04

### Fixed

- **The retired `~/.claude/rendered-views.md` notice no longer points at a `medium` option this plugin does not ship.** The shared medium resolver adds "; per user, the <plugin> plugin's medium option also works" only for a lane whose plugin ships a `medium` userConfig option, which each lane registration in `lib/view-registry.mjs` now records as `hasMediumOption`. `explore-directions` and `pressure-test` now print every notice as it stands, with no clause to drop by hand.

## [0.24.4] - 2026-11-04

### Changed

- **`/prototype:explore-directions` and `/prototype:pressure-test` resolve the view medium through the shared resolver** ([#12684](https://github.com/melodic-software/claude-code-plugins/issues/12684)). Each runs `lib/view-settings.mjs resolve` with its own lane and prints the report line and any notice. Each acts on the resolution's `publishes` and `page` fields instead of naming medium values. They no longer read the retired `~/.claude/rendered-views.md` or `.claude/rendered-views*.md` layers themselves; the resolver turns those into notices.

## [0.24.3] - 2026-11-04

### Changed

- Shared `view-settings.mjs` and `view-registry.mjs` synced where this plugin carries them: the planning lane's design kind and shipped `artifact` default, and the resolver output's `page` and `publishes` fields (#12650); no other change to this plugin.

## [0.24.2] - 2026-11-04

### Fixed

- Shared `view-settings.mjs` synced where this plugin carries it ([#12646](https://github.com/melodic-software/claude-code-plugins/issues/12646)): a `terminal` or `file` value in a retired `rendered-views.md` file keeps the view local when no scope sets one, instead of falling to a publishing default; no other change to this plugin.

## [0.24.1] - 2026-11-03

### Changed

- Shared medium resolver modules (`view-settings.mjs` and the modules it loads) synced into `lib/` ([#12667](https://github.com/melodic-software/claude-code-plugins/issues/12667)); no other change to this plugin.

## [0.24.0] - 2026-11-02

### Added

- **`/prototype:explore-directions` and `/prototype:pressure-test` honor the `rendered-views` `medium` preference.** Both take a `--medium` argument and read the `rendered-views` layers. In `explore-directions`, `terminal` or `file` drops the design-canvas offer, and the mockup stays a local file. In `pressure-test`, unless the request names a shell, `terminal` picks the terminal app, while `file`, `artifact` or `hosted` leaves the audience routing to pick the shell. Each names the source of `medium`.

## [0.23.0] - 2026-11-02

### Added

- `/prototype:explore-directions` and `/prototype:build-generator` now run the shared discipline's evidence step before their throwaway code is deleted, as `/prototype:pressure-test` does. For `/prototype:explore-directions`, the default `file://` mockup lives outside the repository, so it is not copied onto the evidence branch: the note records its local path and `not pushed: <reason>`. Real-stack variant files go through the step as usual. For `/prototype:build-generator`, the evidence pushed is the generating tool's files (its route, controls and save endpoint), while the saved configuration and export stay in the project. Two new eval cases, `ed-evidence-no-secrets-check` and `bg-evidence-no-secrets-check`, cover the path where the repository has no secrets check ([#12030](https://github.com/melodic-software/claude-code-plugins/issues/12030)).

## [0.22.0] - 2026-11-01

### Added

- The shared prototype discipline gains an evidence step, run after the durable note is written and before the throwaway code is deleted, and `/prototype:pressure-test` runs it in its capture step. The step runs the repository's own secrets and machine-data check over the prototype files and, only when it passes, commits them to a throwaway branch named by the repository's declared branch-naming convention (never the default branch or a lane-reserved name), pushes it, and writes the branch name and commit SHA into the note. With no such check, a failed check or no declared convention, it pushes nothing and writes the local path and `not pushed: <reason>` into the note. The discipline names this as an exception to the delete-when-done rule. A new eval case, `pt-evidence-no-secrets-check`, covers the no-check path ([#12026](https://github.com/melodic-software/claude-code-plugins/issues/12026)).

## [0.21.1] - 2026-11-01

### Changed

- The pressure-test skill description is shorter (876 to 742 characters). Held-out trigger probes on Opus showed no lost trigger and no new false trigger. Frozen trigger probes for pressure-test and explore-directions are added.

## [0.21.0] - 2026-11-01

### Added

- `/prototype:pressure-test observe` runs the variants of a fork a run can settle without a person at the keys: the agent builds each variant, drives them all from one harness on the same inputs, records behavior, output and timing per variant (timing labeled unqualified), and ends with a recommendation naming the variant and the evidence. Product and preference calls stay with the person, a fork that is itself a performance target goes to `/performance:goal`, and the auto-invoke gate, durable-note capture and shell deletion are unchanged. A new eval case, `pt-observe-recommends`, covers it ([#12022](https://github.com/melodic-software/claude-code-plugins/issues/12022)).

## [0.20.1] - 2026-11-01

### Fixed

- The `bg-save-output-harvests` eval case's `lab-route-removed` grader matched `lab` anywhere, so a
  correct `src/App.jsx` holding the word `label` failed it. The pattern is now `\blab\b`, which
  still catches the `/lab/torn-edge` route and the `./lab/` import, with samples for both sides.

## [0.20.0] - 2026-10-31

### Added

- `/prototype:build-generator`, a user-invoked skill for an artifact prompting keeps missing: it diagnoses why the direct path fails, pitches the tool that closes that gap, builds a throwaway generator with live controls and a save button that writes the configuration to a project file, then harvests the saved output into the real artifact and deletes the tool. Arguments `save-output`, `add-controls` and `export <format>`; `/playgrounds:use` is offered for the dial-in case when it is available.
- `context/control-panel.md`, the shared rules for a prototype's control panel: what goes on it, controls writing CSS variables, visible and copyable values, placement and replay.
- `context/discipline.md` gains the exception that lets `build-generator`'s tool and saved configuration live in the project while the person tunes, with the tool deleted after harvest.

- The `/prototype:explore-directions` and `/prototype:pressure-test` page eval cases check that the content security policy tag carries every base directive, not only `default-src 'none'`.

- `/prototype:explore-directions` gains the actions `vary [<variant>]` (a new round diverging around one variant), `combine [<base>]` (a matrix keyed by variant pair that picks which parts of the other variants join a base, built as a new variant beside the originals) and `controls [<variant>]` (put a variant's numbers on the control panel); its process now narrows the scope to one piece, loads the interface skills the brief needs before drafting, keeps the current implementation as variant A, fills every variant with working interactions and worst-case content, and checks every variant before the handover. The bundled switcher adds a Demo/Worst content toggle and a slow-motion speed button, and shows replay and speed only when a variant moves.
- The HTML mockup of `/prototype:explore-directions` and the HTML demo of `/prototype:pressure-test` add `form-action 'none'` and `base-uri 'none'` to their content security policy, and markup inlined from the app is stripped of `<script>` elements, `on*` attributes and `javascript:` URLs.

- Sixteen outcome eval cases under `evals/` for `explore-directions`, `pressure-test` and `build-generator`.
- `explore-directions` and `build-generator` accept a leading `--` that ends the actions, so a scope
  or subject can start with an action word (`/prototype:explore-directions -- controls page`).

- `/prototype:build-generator` gains reference files for researching a visual language before building a generator, worked examples keyed by artifact, and when to build a tool that reviews the work instead of making it.

## [0.19.0] - 2026-10-31

### Added

- `/prototype:explore-directions` takes an optional `--unattended` modifier, accepted anywhere in its arguments. With it, the run records the `/design` suggestion and its lifecycle difference in its output and builds the mockup without asking the person; without it, the run tells the person before building. The argument hint lists it.

## [0.18.0] - 2026-10-30

### Added

- `/prototype:explore-directions` has an opt-in review mode ([#8774](https://github.com/melodic-software/claude-code-plugins/issues/8774)): on the user's yes it starts `/planning:interview`'s shared session, asks one `prototype` question per screen with a companion four-outcome decision (approve as is, approve with tweaks, combine, rework), and reads the round's digest back as UI acceptance criteria and a record of the directions that lost. It publishes nothing to claude.ai, falls back to the local mockup when the shared session cannot start, and states its boundaries with the `/design` canvas, the playground and the bundled `prototype` skill. The discipline gains a scoped persistence exception for it.

## [0.17.0] - 2026-10-29

### Added

- **`explore-directions` mockups cover screen states, test ids and acceptance criteria.** The plan names each screen's variants and states (2 or 3 variants per screen on a multi-screen run), every state derives from the one synthetic data set, and the bundled switcher steps through the current variant's states on a state button and the up and down arrow keys. Interactive and asserted elements carry proposed `data-testid`s that the copy-out terminator lists from the markup, and step 5 records the picks as UI acceptance criteria per screen.

### Fixed

- `/prototype:explore-directions`: for an existing app, the skill now finds the app's design system before the plan, and in a redesign treats it as the baseline the variants depart from. It reuses what `/user-interface:design` found when that skill handed off earlier in the conversation, otherwise runs that skill's detection steps when it is installed, and otherwise reads the project's design files itself.

## [0.16.0] - 2026-10-29

### Added

- **`explore-directions` builds prototypes for a shared interview.** For a `/planning:interview` shared session it writes the tiers the session offers (screenshots, one self-contained HTML snapshot per variant, a static live build) under the session's `staging/` folder, plus a `manifest.json` with a required where-to-look line, and keeps the in-page switcher only for prototypes of the interview page itself.

## [0.15.0] - 2026-10-27

### Changed

- `/prototype:explore-directions` builds its variants as a self-contained HTML mockup by default, so whoever decides opens one `file://` page with nothing running. The real stack (sub-shape A, or B when no page can host the variants) is an explicit override, chosen only when the person asks for the variants on the real stack or in the app, and stays where the winner is folded in; the skill suggests it when the judgment depends on live data volume or page chrome the mockup cannot rebuild. The description, Purpose, intent selector, boundary sections, README and `docs/native-surfaces` rows now name the mockup as the default host. New evals cover the default, the default with a dev server running, and the real-stack override.

## [0.14.2] - 2026-10-26

### Fixed

- `/prototype:explore-directions`: variants of an existing app's feature now keep the app's look on every host, the HTML mockup included. On the mockup, every variant inlines the app's own CSS and surrounding page and varies only the subtree under test; a per-variant visual direction applies only when no app exists yet or a redesign was asked. A new eval covers layout options for one feature of an existing app, delivered as standalone files.

## [0.14.1] - 2026-10-25

### Changed

- **The playground verification record names the upstream skill without a skills-folder path.** The basis for the `playground` skill's claim reads as the upstream `playground` skill's `SKILL.md` at the pinned commit, so the record no longer carries a path shaped like a cite into a plugin's skill folder.

## [0.14.0] - 2026-10-13

### Added

- A `LICENSE` carrying the MIT notice for content reauthored from emilkowalski/skills (pinned in `docs/upstream/emilkowalski-skills.md`) beside the Melodic Software derivative line.
- `/prototype:explore-directions` bundles `assets/variant-switcher.html` for the HTML mockup: a paste-in switcher that shows one variant at a time, switches on its arrows, number keys and arrow keys with wraparound, replays a variant's entrance, ignores keys while a field has focus, keeps no URL state so it works from `file://`, and runs under the mockup's CSP. Variants now carry a direction name and a named axis, and the handover lists each variant's tradeoff without pre-picking a favorite.

### Changed

- **`explore-directions` adds three steps.** With no direction named and no host page fixing the
  look, it offers an optional reference pass before building variants. When `/playwright:playwright`
  is available, it screenshots every variant and uses its main control once before the handover.
  The handover states each variant's strengths and costs and recommends one; the user still picks.
- **The two skills, the shared discipline and the README are rewritten and restructured.**
  `explore-directions/SKILL.md`, `pressure-test/SKILL.md`, `context/discipline.md` and `README.md`
  were reorganized and reworded away from the upstream prototype skill they parallel. A five-word
  run scan against that upstream finds one shared run per file, the trigger label "what should this
  look like", and no shared run of eight words or more. The description's example triggers are now
  'how should this screen be laid out' and 'show me layout options'.
  `explore-directions` now picks its host from one intent-selector table (sub-shape A, sub-shape B,
  the HTML mockup substrate, the design canvas, each with its cleanup). Step 2 sorts design choices
  into must-differ and must-match rows; every variant must still be structurally different and
  visually distinct. Sub-shape B now requires a candidate-page check first. The switcher is
  specified as a table whose label row shows the key plus a descriptive name if exported. The
  handover lists its parts in order, and the skill runs five steps instead of six. Its examples use
  a shipment-tracking page, and its description reads "a few structurally different layouts (three
  by default) behind one route, toggled from a floating switcher". `pressure-test` also runs five
  steps: the language choice joins the logic-module step, which splits module from shell in a
  table and picks the module's form by who holds the state between calls, and the one-command
  start joins the TUI step. Its description's example triggers now include 'what happens if a
  refund arrives after the order ships' and 'which arguments should this call take'. Its HTML demo
  shell merges the state panel and free-play buttons into one region and points at step 2 for the
  module's placement. The user's remarks while driving are sorted into findings and missing states.
  Its examples use library loans. The discipline groups its six rules by who each serves and shows
  each one broken, keeping the rule names and numbers other text cites (3 and 6).
  Anti-patterns are tables of `/shipments` and library-loan cases; in `explore-directions` they
  are ordered by cost. The rules, labels,
  reply-template fields and steps keep their meaning; `docs/native-surfaces` quotes the new layout
  wording of the description.
- Reworded the remaining passages of `explore-directions/SKILL.md` adapted from the upstream
  prototype skill in our own words; every step and rule is unchanged.

- **The `design` and `ClaudeDesign` verification records name their probe and drop quoted upstream text.** Binary observations cite the records in `docs/native-surfaces/records.json`; `/design`'s behavior and the settings that remove it are read live from anchored sections.

### Fixed

- **The `explore-directions` design record no longer lists an outdated artifacts version floor or an incomplete set of contexts where artifacts are off.** It points at the artifacts page's Availability and design-canvas sections instead, with an as-of date and a recheck trigger.

- **The `detect-ecosystems.sh` wrappers in both skills no longer say `${CLAUDE_PLUGIN_ROOT}` stays literal in an `allowed-tools` rule.** They call the skill-local path a repo convention and point at the skills page's string-substitutions section for which variables a rule substitutes.

## [0.13.12] - 2026-10-11

### Changed

- `explore-directions` points real-stack variant CSS at `/user-interface:write-css` when that skill is installed; HTML mockups keep their declared directions.

## [0.13.11] - 2026-10-04

### Fixed

- **Prototype successors follow the design-then-plan order ([#6278](https://github.com/melodic-software/claude-code-plugins/issues/6278)).** `/prototype:pressure-test` no longer routes a holding model straight to implementation, which contradicted `/planning:plan`; it routes to `/planning:design` when the model settles a type, contract, or boundary and to `/planning:plan` otherwise. `/prototype:explore-directions` does the same for a winning direction.

## [0.13.10] - 2026-10-03

### Changed

- `scripts/allowed-tools-pairing.test.sh`, `skills/explore-directions/scripts/detect-ecosystems.test.sh`, and `skills/pressure-test/scripts/detect-ecosystems.test.sh` declare the files they read without naming them in `# test-scope:` headers, so CI's test selection runs them when one of those files changes. Nothing the plugin runs changed.

## [0.13.9] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.13.8] - 2026-10-02

### Fixed

- `explore-directions` no longer lists a cream or off-white background among the defaults no
  variant may use. Each variant still declares its own background, so variants differ on it.

## [0.13.7] - 2026-10-01

### Changed

- Dropped citations of the removed topic-docs convention and the `docs/specs` tree.

## [0.13.6] - 2026-09-30

### Added

- **`explore-directions` routes work on an existing Claude Design project to the built-in
  `ClaudeDesign` tool.** When the person names or links an existing claude.ai/design project, or
  asks for the work to go into one, and the tool resolves in this session, the model uses the tool
  for the project's files; otherwise the skill builds its throwaway variants as before. The
  description carries the condition, and a new Boundary section names the tool, the split, and
  the mutation gate (writes only to the named project, after the person asks; the tool's own
  approval and refusal cases are reported, never retried around), with the four-part records in
  `reference/claude-design-tool.md`. The description drops two restating clauses to stay under
  the 1,024-character field limit.

## [0.13.5] - 2026-09-29

### Changed

- **`explore-directions` offers `/design` to the person instead of routing the model to it.** A
  binary extraction of Claude Code 2.1.285 reads the bundled `design` skill as
  model-invocation-disabled, so a route phrase naming it was dead text. The description drops the
  design clause. On the HTML mockup substrate the skill builds the mockup by default and the
  Boundary section's sentence tells the person they can run `/design <scope>` instead of or
  alongside it, with a same-file verification record. The design-canvas subsection, the `design`
  reference record, the prototype discipline's persistence exception and the README follow, and
  the listed-description presence check, which the model can no longer perform, is gone.
- **The `design` Boundary bullet no longer asserts that the skill ships with Claude Code** or that
  it is model-invocable. It keeps the provenance class, what the skill does and how it is invoked,
  in the native-references template form.

## [0.13.4] - 2026-09-29

### Added

- **`explore-directions` carries a Boundary section for the marketplace plugin `playground`.** An
  interactive parameter explorer whose output returns as a prompt routes to the `playground` skill;
  switchable variants of the user's own UI stay here.

## [0.13.3] - 2026-09-29

### Changed

- **`explore-directions` description** no longer addresses the reader ("your own UI" becomes "the user's own UI");
  routing is unchanged
  ([#4112](https://github.com/melodic-software/claude-code-plugins/issues/4112)).

## [0.13.2] - 2026-09-28

### Changed

- **Argument hints** on `explore-directions`, `pressure-test` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.13.1] - 2026-09-28

### Changed

- **The native-surface presence gate reads "resolves in this session"** ([#4112](https://github.com/melodic-software/claude-code-plugins/issues/4112)). The `explore-directions` routing line named a native surface behind "resolves in your session", which addresses the reader. The gate now names the session instead, matching the canonical token that claude-ops' native-overlap self-check matches. Routing is unchanged.

## [0.13.0] - 2026-09-28

### Changed

- **`explore-directions` routes against the bundled `design` canvas with the presence gate (part
  of #4055).** The description's "(or, where the bundled design skill is available, an editable
  design-canvas Artifact)" becomes its own clause: "When the bundled design skill resolves in your
  session, prefer it for a hand-editable design canvas; this skill for switchable variations of
  your own UI." The rules: the clause is gated on the model's own listing (`resolves in your
  session`), never on a claim that the canvas is there; it names the provenance class and splits
  the job. The `playground` marketplace clause, the quoted triggers, the Boundary section, and the
  body's design-canvas subsection are unchanged. The store's `design` row now records
  `baked.description_phrase: true` with its budget caveat. Four phrasings are shortened to keep
  the description under the 1,024-character spec field maximum.

## [0.12.0] - 2026-09-23

### Changed

- `explore-directions` names the default styles no mockup variant may fall back on (a cream or
  off-white background, italic accent words in headings, numbered "01 / 02 / 03" section labels,
  monospace labels, pill-shaped buttons), plus any the user names, and adds a visual choice a
  handover `skip:` line rejects to that list before the next round.

## [0.11.6] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.11.5]

### Changed

- The allowed-tools pairing suite now prints a NOTE line for any skill that names no expected-granted arm instead of silently skipping the granted-set comparison. Exit codes and every PASS and FAIL string are unchanged.

## [0.11.4]

### Changed

- Route the ecosystem-detector smoke invocations in the root and wrapper suites through shared run helpers (behavior unchanged).

## [0.11.3]

### Changed

- The `allowed-tools` pairing gate's header and fail message no longer give "never substituted there, inert grant" as their reason. `${CLAUDE_PLUGIN_ROOT}` does substitute in a plugin skill's `allowed-tools`, with a v2.1.0 floor. The gate is unchanged and still requires the skill-local path, because the docs establish substitution rather than runtime matching on every host.

## [0.11.2]

### Changed

- **`explore-directions`: description prose no longer addresses the reader.** Anthropic's skill-authoring guidance keeps first and second person out of a description because it is injected into the system prompt; the rewritten clauses name the user, the session, or the repository instead. Quoted trigger phrases are unchanged.

## [0.11.1]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** This changelog and `context/discipline.md` were rewritten. Wording only, with no change to any rule, boundary, or run-directory path. Rule 6's quoted phrase, which both the 0.9.0 entry and `docs/upstream/mattpocock-skills.md` cite, survives byte-identical; only the mark after it changed. No heading was touched, so the `#when-done` anchor still resolves. The released sections corrected in place are 0.9.3, 0.9.2, 0.9.0, 0.8.0, 0.7.0, 0.6.0, 0.5.0, 0.4.0, 0.3.3, 0.3.2, 0.3.0, 0.2.4, and 0.2.1: their wording changed, their facts did not.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, the `context/` tree, and every `skills/*/SKILL.md`.

## [0.11.0]

### Added

- **`explore-directions`**: a `## Boundary, the bundled design skill` section stating the split
  against the bundled `design` skill (throwaway mockup by default; the persistent, hand-editable
  canvas offered as an explicit alternative and invoked only on the user's choice), a mutation
  gate, and an availability rule that names the presence check: a same-named Claude Design hub
  variant with model invocation disabled registers behind an `allow_design_sync` setting, so the
  listed description is what distinguishes the canvas from the hub or a shadowing local skill.
  The design-canvas subsection names that second reason for its description check. Four-part
  records, re-verified against the installed client and the live docs, in
  `reference/bundled-design.md`.

## [0.10.6]

### Added

- **`explore-directions`, `pressure-test`**: a `## Next` section naming the skill that normally
  runs after this one, in the mention-only shape the skill-body rule describes.

## [0.10.5]

### Changed

- explore-directions, pressure-test: dropped the compound `git status` grant from `allowed-tools` that no body instruction issues; each description names its intent category with three exact phrases instead of listing six or seven near-synonyms.
- explore-directions: the two `design`-skill fallbacks read as one current rule instead of a contrast against a future gate; removed the negative restatement of the substrate taxonomy and the second copy of the same-process sentence.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.10.4]

### Fixed

- **`explore-directions`, `pressure-test`:** the git pre-compute lines moved out of `## Pre-computed
  context` into a "Repository context. Gather first" body section of individual Bash calls, one
  command per call, each `head` bound kept inside its command and a failure read as an unknown
  value. The harness composes a skill's whole pre-compute block into one shell invocation, and a
  worktree-isolated session refuses a git-bearing compound command, which blocked these skills from
  loading inside a worktree. Same shape as the worktree skill's fix in #1619. Non-git pre-compute
  lines stay where they were.

## [0.10.3]

### Changed

- **The three `detect-ecosystems` suites stop paying twice for one answer.**
  `scripts/detect-ecosystems.test.sh` ran the empty fixture through the detector
  twice, once to capture stdout and once, output discarded, to capture the exit
  code; a single run now feeds both assertions. In the two skill-level wrapper
  suites the multi-ecosystem expectation `$(printf '%s\n' App.sln package.json
  go.mod)` was written out at four assertion sites each; it is computed once into
  `multi_expected` beside the fixture it describes, which is three command
  substitutions fewer per suite and one place to edit if the fixture gains a
  marker file.
- Test files only. The detector and both skill wrappers are byte-unchanged, as
  are every assertion label and the order they run in.

## [0.10.2]

### Changed

- **`scripts/allowed-tools-pairing.test.sh` was shfmt-formatted**, in step with
  the `repo-fleet-hygiene` copy of the same suite so the two do not drift apart.
  Formatting only: two independent quote- and heredoc-aware shell parsers agree
  on the canonicalised form before and after, the comparison was proven sensitive
  by nine seeded semantic mutations that it catches and two controls that it
  correctly ignores, comment lines are identical at 35 each, and the suite's
  runtime output is byte-identical at 9 lines with exit 0.

  Recorded while checking the hazard list: `prototype` does **not** carry three
  copies of a detector. `scripts/detect-ecosystems.sh` is the detector; the two
  skill-level files are 17-line `exec` wrappers whose executable bodies are
  byte-identical and differ only in a comment naming the sibling skill, and their
  suites assert exactly that byte-identity plus the header's rationale phrases.
  There was nothing drifting and nothing to consolidate.

## [0.10.1]

### Changed

- **explore-directions routes the explorer shape out.** Its description now sends
  requests for an interactive parameter explorer whose output returns as a prompt
  to the first-party playground skill via `/playgrounds:use`, gated on the upstream
  playground plugin being installed from its marketplace. The clause carries the
  marketplace parity token, traced to its verdict row in the native-surfaces
  registry.

## [0.10.0]

### Added

- **`explore-directions`: same-data control variable, single-decision graft capture, and a
  machine-legible reply template.** Variants now bind one identical data set (the data is the
  control variable, so only the design differs); the handover closes with a fillable
  direction/steal/skip/next-target reply template (what the mockup's copy-out terminator lifts);
  and the capture step records steal/skip decisions per named piece so grafts compose across
  variants. Adopted from the "Finding Your Unknowns" corpus at the integration sign-off (D20,
  D21, D22; provenance in `docs/FINDING-YOUR-UNKNOWNS.md` in the marketplace repository). Evals
  extended.
- **`pressure-test`: validation answer set and a fake-data disclosure footer on the HTML demo
  shell.** The demo page carries the questions it exists to answer as forced choices whose
  options each name their cost (plus a free-text escape hatch), with a copy-out control, and a
  visible footer stating the page is synthetic end to end and, when decided, where real wiring
  lives and behind which flag; when integration is not yet decided, or no flag is planned, the
  footer says so explicitly rather than inventing production details. The capture step carries
  the filled answer set into the durable answer verbatim. Same adoption basis (D24, D25, D26);
  evals extended.
- **Shared discipline: "mock before you wire" ordering note.** The composition table now states
  that the throwaway mock runs before any real wiring when a change has both questions (D27).

## [0.9.8]

### Added

- **`detect-ecosystems.sh` and both skill wrappers now have sibling test suites.** All three
  files mapped to ZERO suites under `scripts/affected-tests.sh`, which the repo contract treats
  as an error rather than "nothing to run": a change to the ecosystem detector, the preamble
  command both skills run before anything else, selected no coverage at all.
  `scripts/detect-ecosystems.test.sh` covers the detector itself (every marker it looks for,
  glob-order output, the unmatched-glob literal that must never leak, space-bearing filenames,
  directory and symlink markers, the root-anchoring precedence of `CLAUDE_PROJECT_DIR` over the
  git toplevel over the cwd, and the nonexistent-project-dir degradation the `cd ... || true`
  exists for). Each skill's `scripts/detect-ecosystems.test.sh` is a thin contract suite for its
  wrapper: it delegates rather than duplicates, it stays self-locating instead of expanding
  `${CLAUDE_PLUGIN_ROOT}`, its rationale comment survives, its executable body matches the other
  skill's copy, and its output is byte-identical to the canonical detector's on the same fixture.
  No script changed; this is coverage only.

## [0.9.7]

### Fixed

- **`explore-directions` and `pressure-test`: the grant left behind when 0.9.6 rewrote the
  working-tree injection.** 0.9.6 changed the injection to
  `{ git status --porcelain 2>/dev/null || echo "(git status unavailable)"; } | head -10` but left
  `allowed-tools` naming only the prefix rule `Bash(git status:*)`, whose first literal token is
  `git`. The composed command's first token is now `{`, so the rule's leading token no longer
  matches what the shell is handed. Both skills gain an exact grant for the composed command
  alongside the existing prefix rule; the prefix rule stays, and no rule was broadened.

  **The prefix rule's behavior against a brace group is unestablished.**
  [Configure permissions](https://code.claude.com/docs/en/permissions#compound-commands) (fetched
  2026-08-28) states that Claude Code splits a compound command on `&&`, `||`, `;`, `|`, `|&`, `&`,
  and newlines, and that "A rule must match each subcommand independently". It does not say whether
  a leading `{` is stripped from the first subcommand of a brace group, and neither does
  `docs/conventions/permission-rule-hygiene/README.md`. The exact grant is the safe route, not a
  demonstrated fix. Two facts bound the exposure either way: `allowed-tools` grants are turn-scoped
  and auto mode drops broad shell rules, and `git status --porcelain` is one of the Bash tool's
  built-in read-only commands, which run without a prompt in every mode.

## [0.9.6]

### Changed

- **Dynamic-context probe fallback made reachable.** The working-tree-status injection piped its
  probe into `head` before `||`, so the fallback could never run and a failed probe rendered an
  empty string under a label that reads as a clean tree. The fallback now sits in a brace group with
  the probe and the cap applies outside it. Whole-repo extract-ssot sweep.

## [0.9.5]

### Changed

- **Repo-wide `/ai-slop:audit fix` pass (#3359).** The wallpaper contrast in
  `explore-directions/SKILL.md` ("isn't a UI prototype, it's wallpaper") keeps its
  deliberate voice behind an `ai-slop-ignore` marker; a positive restatement blunts
  the operative point.

## [0.9.4]

### Changed

- **Instruction-surface de-slop (#2891, prototype cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.9.3]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose, as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.9.2]

### Fixed

- **`explore-directions` step 6 restated the shared discipline in its pre-0.9.0 form.** 0.9.0
  widened `context/discipline.md`'s when-done capture to record the directions that lost and, when
  the verdict is a graft, which piece came from where, and what the discarded parts held that the
  graft deliberately left behind. Step 6 of `explore-directions` still said only "record which
  variant won and why", and then listed the deletions. A reader following that skill end to end
  therefore never reached the widened capture, and the bullets immediately below delete the losing
  variants irreversibly. Step 6 now carries all three clauses, including the left-behind one, which
  is the half the discipline argues is worth the most. It also repeats the shared surface's warning
  that whatever is not written down before those deletions is gone.

## [0.9.1]

### Changed

- **The two wrong-facet routes name the Skill tool (#3002).** `explore-directions` →
  `/prototype:pressure-test` and `pressure-test` → `/prototype:explore-directions`. Wording only;
  the facet boundary is unchanged.

## [0.9.0]

### Added

- **The shared discipline now records the directions that lost, not only the one that won.**
  Absorbed from an upstream skill this marketplace decided not to ship
  (`docs/upstream/cursor-pstack.md`, the `arena` row), whose claim that the rejection notes are the
  highest-signal part of the record had no counterpart here. `context/discipline.md`'s when-done
  capture now asks for each direction that was tried and the reason it lost. When the verdict
  is a graft rather than a single winner, which `explore-directions` step 5 already names as the
  usual outcome ("I want the header from B with the sidebar from C"), it also asks which piece came
  from where and what the discarded parts held that the graft deliberately left behind. The
  argument is that a losing direction is the cheapest available answer to "why not just do it this
  way?" and the only part of the exercise a future reader cannot reconstruct from the shipped
  result, while the very next step deletes it irreversibly. Rule 6 changes with it: "the answer is
  the only thing worth keeping" now says the answer is larger than the winner and points at the
  capture section, because as written it licensed dropping exactly this.

## [0.8.0]

### Added

- **`explore-directions`: an opt-in design-canvas alternative to the HTML mockup substrate.**
  When the intent selector lands on the HTML mockup substrate and the bundled `design` skill
  (the Claude Design canvas preview) appears in the session's skill list, the skill offers a
  choice: the throwaway HTML mockup stays the default, and the canvas drafts the variants as
  artboards published as an editable Artifact. The offer names the lifecycle difference
  (published, versioned, persistent, default-private, and shareable at the user's choice, versus
  the throwaway local file), and the fallback branches on two distinct states: absent from the
  skill list → the HTML mockup, silently (never suggest `/design` to a user who lacks it);
  listed but invocation refused → suggest the user run `/design` themselves. Carries a
  four-part upstream-drift stamp (the preview is undocumented upstream; no version floor is
  statable; recheck on first official naming or an invocability change).
- **`context/discipline.md`: a substrate-scoped exception to the no-persistence/delete-when-done
  rules** for the user-chosen canvas, so the shared discipline and the new substrate do not
  contradict each other. The repo side stays clean either way: nothing tracked references the
  canvas, and the durable answer is still captured in markdown.

## [0.7.0]

### Fixed

- **Both skills' ecosystem-detector grant was inert, and the fix everyone reaches for first would
  have made it dead instead.** `explore-directions` and `pressure-test` each granted
  `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-ecosystems.sh:*)`. `${CLAUDE_PLUGIN_ROOT}` is not
  one of the substitutions Claude Code performs in `allowed-tools`. Only `${CLAUDE_SKILL_DIR}` and
  `${CLAUDE_PROJECT_DIR}` are. The rule therefore stayed a literal string, never matched, and the
  pre-computed ecosystem line fell through to a prompt or the classifier on every invocation.

  The obvious repair, dropping `bash` from the rule, is wrong, and that correction is the part worth
  recording. `bash` is not one of the wrappers Claude Code strips before matching a Bash rule (that
  set is `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, and `noglob`), so a rule
  without `bash` stops matching the moment the body still says `bash <path>`. Dropping it alone would
  have turned an inert grant into a dead one while making the diff look like a fix. The change is
  therefore **paired**: the body invokes the script directly, and the rule names that same string,
  `Bash(${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh:*)`. Quoting is part of the pairing. An
  unquoted rule does not match a body path wrapped in quotes, so the body's quotes came off too.

### Added

- **A skill-local entry point for the shared ecosystem detector**, one per skill, at
  `skills/<skill>/scripts/detect-ecosystems.sh`. `${CLAUDE_SKILL_DIR}` resolves to the skill's own
  subdirectory rather than the plugin root, so a grant that must reach a bundled script has to name a
  path underneath it. The detector stays single-sourced at `scripts/detect-ecosystems.sh`; each entry
  point is a self-locating wrapper that `exec`s it. Self-locating rather than
  `${CLAUDE_PLUGIN_ROOT}`-resolving because that variable is not exported into the Bash tool's
  environment, so expanding it inside a script yields an empty string.

- **`scripts/allowed-tools-pairing.test.sh`**, asserting the contract the fix establishes: no
  interpreter-led grant and no `${CLAUDE_PLUGIN_ROOT}` in `allowed-tools`, every bundled-script
  invocation in skill markdown unquoted and free of a `bash` wrapper, and every granted script
  present, executable, and actually invoked by a body. A grant nothing runs is dead weight.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.0]

### Added

- **`pressure-test` gains an audience-routed HTML demo shell.** The TUI stays the
  default; when the driver is a non-developer (a designer, PM, or domain expert)
  or no terminal fits the handoff, the disposable shell over the same portable
  pure logic module is a single self-contained `file://` HTML page: domain-language
  labels, a labeled state panel re-rendered on every click, free-play buttons
  (one per action), and guided-walkthrough scenarios that reset to a known
  initial state. The page reuses `explore-directions`' HTML-substrate constraint
  set: restrictive CSP meta tag (no remote origins by construction), ephemeral
  placement via the platform temp primitive (`mktemp -d` private run directory /
  `%LOCALAPPDATA%\Temp`), synthetic data only, and discard after the markdown
  capture. The validated logic module remains the only artifact that outlives
  the prototype. Adapted from mattpocock/skills v1.2.3 @ `84fdeff`,
  `skills/engineering/prototype/LOGIC.md` (the shareable-HTML shell); upstream's
  throwaway-branch "primary source" capture of the prototype was rejected
  (contradicts this plugin's delete-when-done discipline), with the rejection
  recorded in `docs/upstream/mattpocock-skills.md`.

## [0.4.0]

### Changed

- **`explore-directions`: the visual axis is additive, not out of scope.** Structure remains the
  floor ("a recolor alone is not a variant"), but the skill no longer de-scopes visual direction:
  on open-ended briefs current models settle into one default house aesthetic, and generic
  steering only swaps palettes (Sonnet 5 / Opus 4.8 prompting guides, "Design and frontend
  defaults"). The HTML mockup substrate, which has no project styling system to pin the
  aesthetic, now requires each variant to declare its visual direction (background hex, accent
  hex, typeface, one-line rationale) and differ from siblings on that axis as well as
  structurally; the real-stack path declares a direction wherever the project's styling system
  leaves room. Eval 3's second expectation now scores "recolors are not the only difference"
  instead of treating color variety as beneath the exercise. The flip-between-variants delivery is
  unchanged. No propose-then-pick gate was added.

## [0.3.3]

### Changed

- **`explore-directions` mockup placement conforms to the topic-docs ephemeral
  tier.** The self-contained HTML mockup resolves one deterministic location via
  the platform temp primitive instead of an "OS temp **or** gitignored scratch
  location" OR-branch, whose gitignored option put the throwaway file inside the
  repo. That location is a private run directory from
  `mktemp -d "${TMPDIR:-/tmp}/explore-directions-XXXXXX"` on Unix/Linux/Git Bash
  with the page inside it, and a user-scoped temp under `%LOCALAPPDATA%\Temp` on
  Windows. The handed-back path is never deleted.

  The temp root rides in the positional TEMPLATE rather than in a flag.
  `-p` (which GNU also spells `--tmpdir`) is documented in both dialects but does
  not mean the same thing: GNU treats the template as relative to that directory
  and lets the flag beat `TMPDIR`, while BSD/macOS consult it only as a fallback
  for `-t` when `TMPDIR` is unset. With a bare template and no `-t` the flag
  therefore does nothing there, and the template resolves against the current
  directory, silently writing into the consumer's repo. GNU additionally
  marks `-t` deprecated. The `XXXXXX` is also **trailing**: BSD `mktemp`
  substitutes only trailing Xs, so `explore-directions-XXXXXX.html` cannot be
  created at all on macOS. Naming the page inside a generated directory is what
  preserves the `.html` extension without an unportable suffix on the template.

## [0.3.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention. Bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.0]

### Changed

- **BREAKING: both skills renamed** (fleet conformance wave: naming grammar, verb-first
  skill names). `/prototype:logic` is now `/prototype:pressure-test`; `/prototype:ui` is
  now `/prototype:explore-directions`. Update any saved invocations. Skill behavior,
  triggers, and evals are unchanged; only the leaf names and namespace tokens changed.

## [0.2.4]

### Changed

- README declares the Bash requirement of the bundled ecosystem-detection
  script with its Windows path (Git Bash) and documents the no-Bash degrade
  (detection reports "none detected"; the skills read the host project
  directly). Part of the cross-platform declaration wave.

## [0.2.3]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.2.2]

### Changed

- Synced the composition table's sibling-skill routes to the reorganized plugin
  taxonomy: `/improve-architecture:improve-architecture` is now `/architecture:improve`.

## [0.2.1]

### Added

- **Composition table.** The shared discipline now maps the prototype to its upstream and
  downstream workflow skills: `/planning:prd`, `/improve-architecture:improve-architecture`,
  `/planning:architect`, and `/implementation:implement`. Each is invoked only when the sibling
  plugin is installed.
- **Named handoff capability in the auto-invoke gate.** The gate's "checkpointing your current
  work first" now names `/session-flow:handoff` (when installed) as the checkpoint capability.
