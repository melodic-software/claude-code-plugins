# Snapshot map: prototype names the page reads, and their contract names

The page (`web/app.js`) reads the prototype's state names. `web/core.js` is the only file that talks
to the server: it reads the contract snapshot (`GET /api/state?since=<rev>`) and builds the
prototype-shaped view in `toView()`, which is the complete mapping. Each row below is one name the
page reads, the contract field it comes from, and how. `tests/test_server.py`
`TestSnapshotContract` pins the contract side of these rows against `tests/fixtures/state-v1.json`.

Views: G = every person, M = owner and leaders, O = owner only.

## Top level

| Prototype name | Contract source | Mapping |
|---|---|---|
| `title`, `goal`, `serverTime` | `title`, `goal`, `serverTime` | same |
| `ended` (`{ts}` or null) | `ended` (bool) | same truthiness |
| `v` (protocol level, 8 or 10) | none | dropped: the page has one server, so `v8()` is always true |
| `settings.voting`, `signoff`, `chat`, `follow`, `digestNames`, `uploads`, `theme` | `settings.*` | same |
| `settings.showNames` | `settings.names` | `names === "full"`; the server already masks names for guests |
| `settings.hideClaude` | `settings.claudeTake` | `claudeTake === "answerFirst"` |
| `round.current` | `round.n` (last of `rounds`) | same |
| `round.status` (`open`, `sent`, `working`, `preparing`) | `round.status` (`open`, `sent`, `working`, `closed`) | same; `preparing` is never sent |
| `round.ready.by` (a name), `round.ready.ts` | `rounds[-1].status.ready.by` (pid), `.at` | pid to name |
| `round.sentAt` | `rounds[-1].status.sentAt` | same |
| (none) | `rounds[n-1].status.kind` | `isSent(q)` reads the question's own round, so late answers on a `closed` round stay open |
| `questions` | `questions` | see Question |
| `answers[qid]` | `cards[qid]` (+ `cardDetails` O) | see Answer |
| `locks[qid]` | `locks[qid]` | see Lock |
| `suggestions[qid]` | `suggestions[qid]` | see Suggestion |
| `ideas` | `proposals` (G own, M all) | see Idea |
| `research[qid]` | `results[qid]` (G published, O all) | see Research |
| `chat` | `chat` | see Chat |
| `presence` | `presence` + `people` | `{cid: pid, name, q, typing, chatTyping, owner: pid === "host", leader, trusted}` |
| `people` (`{pid: {name, ts, color, seen?}}`) | `people` (list), `removed` (O), `lastSeen` | keyed by pid; `ts` from `joinedAt`; `seen` from `lastSeen[pid]` |
| `leaders`, `trusted` | `people[].role`, `people[].trusted` | derived lists |
| `ownerPid` | none | `"host"` |
| `removed` (pids) | `removed` (O, person records) | pids |
| `youRemoved` | 403 `removed` on the poll | set when the poll answers `removed` |
| `shareUrl` | `share.url` (M) | same |
| `shareChanged` | `share.changedAt` (M) | present |
| `guestKey` | `guestKey` (M) | same |
| `requestCounts` | `requestCounts` | same |
| `requests` (O) | `requests` (O, runner host) | see Request |
| `myRequests` | `myRequests` | see Request |
| `mergeRequests` (O) | `mergeRequests` (O) | `{id, from, to, fromName, toName, ts, status: kind}` |
| `myMergeRequests` | `myMergeRequests` | `{id, status: kind, toName}` |
| `me.pid`, `me.prefs`, `me.unread` | `me.pid`, `me.prefs`, `me.unread` | same |
| `me.notifications` | `me.notifications` | `ts` from `at`; `byCid` from `by` (a pid); `by` becomes the name |
| `myUploads`, `uploads` (O) | `myUploads`, `uploads` (O) | `cid` from `pid`, `ts` from `at`, `status` from `status.kind`; no path reaches the page |
| `files` | `files` | same, merged over the files the page already holds |
| `behind`, `aboutYou` (O), `myAbout` | `behind` (M), `aboutYou` (O), `me.aboutYou` | same |
| (none) | `schemaVersion`, `rev`, `build` | read by `core.js` only: a version or build change reloads the page; `rev` feeds `?since=` |
| (none) | `me.reactions`, `cards[].reactions` | Gather reactions |

## Question

| Prototype name | Contract source | Mapping |
|---|---|---|
| `id`, `text`, `round`, `dependsOn`, `references`, `lockedText` | same | same |
| `format` (`"choice"`, `"confirm"`, absent) | `format.kind` | `text` becomes absent |
| `options[{id, label, image}]` | `format.options` (choice), `format.variants` (prototype) | same ids |
| confirm option ids `opt-yes`, `opt-no` | option ids `yes`, `no` | renamed both ways in `core.js` |
| `image`, `rect` (confirm) | `format.image`, `format.rect` | same |
| `needsReview` (`{because, ts}` or absent) | `needsReview` (list) | newest flag, `ts` from `at` |
| `from` (suggested by, a name) | `origin.kind === "proposal"` | the proposal author's name when visible |
| `addedBy`, `byHost` | `origin.kind === "host"`, `origin.by` | name of `by`; `byHost` when `by === "host"` |
| `proposal` | `origin.proposal` | same |
| (none) | `purpose`, `scope`, `short`, `context`, `basis`, `answerScope` | passed through; `purpose` drives votes, reactions and the poll |

## Answer (`answers[qid][]`)

| Prototype name | Contract source | Mapping |
|---|---|---|
| `cid` | person: `pid`; Claude: `key`; option: `option` | person cards keep the pid; Claude's become `claude` (rec) and `claude-a`..`claude-c`; options keep their id (`yes`/`no` become `opt-yes`/`opt-no`) |
| (none) | card `ref` | `ref` (`p:<pid>[:<device>]`, `c:<key>`, `o:<id>`): the list key, and what votes, locks and go-with send; a device-scoped question gives one person several cards, told apart by it |
| `name` | `people[pid].name` | Claude cards `Claude`, option cards the label |
| `text` | person `text`; Claude from `recommendation` or `alternatives[key].text`; option the label | |
| `ts` | `at` | option cards 0 |
| `votes` | card `votes` | same (masked to `""` when names are not full) |
| `claude`, `rec`, `option` | card `kind`, `key === "rec"` | flags |
| `basis` | `question.basis` | on the rec card |
| `pick` | card `pick` | `yes`/`no` become `opt-yes`/`opt-no` |
| `cites` | card `cites` | same |
| `editedAfter` | `editedAfterVotes` | same |
| `ctx` (O: `{view, device, browser, vw, vh}`) | `cardDetails[qid][ref]` (O: `view`, `deviceInfo`) | `device` from `deviceInfo.kind`, `vw`/`vh` from `deviceInfo.screen` |
| `late` | `late` | passed through |
| `att` | `attachments` (upload ids) | `[{kind: "file", upload: id}]`; the same on picks, suggestions, ideas, chat, comments and requests |

## Lock

| Prototype name | Contract source | Mapping |
|---|---|---|
| `text` | `source.text` | same |
| `answerCid` | `source.card` (card), suggestion author (suggestion), `source.from` (edited) | ref to the answer `cid` above |
| `name` | the source's author | `Claude`, `Option`, or a person's name |
| `by` | `by` (pid) | name |
| `ts` | `at` | same |
| `edited` | `source.kind === "edited"` | flag |

## Suggestion, idea, chat, research, request

| Prototype name | Contract source | Mapping |
|---|---|---|
| suggestion `id`, `text`, `note`, `votes` | same | same |
| suggestion `cid`, `name`, `ts`, `status` | `pid`, name, `at`, `status.kind` | |
| idea `id`, `text`, `cid`, `name`, `ts` | proposal `id`, `text`, `pid`, name, `at` | |
| idea `status` (`notplaced`) | `status.kind` (`not-placed`) | renamed |
| idea `qid`, `reason` | `status.question`, `status.reason` | |
| idea `via` (a name) | `via.kind === "chat"`, `via.by` | name |
| chat `id`, `text` | same | |
| chat `cid`, `name`, `ts` | `pid`, name, `at` | |
| chat `replyTo{id, cid, name, text}` | `replyTo{id, pid, excerpt}` | `text` from `excerpt` |
| chat `forwarded` | `proposed` | |
| research `id`, `kind`, `summary`, `sources`, `report`, `ts` | result `id`, `kind`, `summary`, `sources`, `report`, `at` | |
| research `skill` | `used[].name` | joined; `why` passed through |
| research `requestId`, `ask`, `by`, `byCid` | `request`; the request's text and author when this viewer may see them | others' request text is never sent |
| (none) | result `published` | the owner's Publish and Discard |
| request `id`, `qid`, `kind`, `text`, `edited` | same | |
| request `cid`, `name`, `ts` | `pid`, name, `at` | |
| request `status`, `reason` | `status.kind`, `status.reason` | |

## Gaps

- `POST /api/asset` (the owner's image reference) has no contract route; image references come from
  Claude's `add-asset`. The page offers link and quote references only.
