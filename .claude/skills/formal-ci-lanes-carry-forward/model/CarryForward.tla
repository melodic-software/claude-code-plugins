--------------------------- MODULE CarryForward ---------------------------
\* The `ci-lanes` commit status on one pull request head SHA, written by full
\* runs of PR Require Checks and read by one contract-only run (a label flip or
\* body edit) whose `CI Status` job carries the recorded verdict forward.
\*
\* Line numbers: WF is .github/workflows/pr-require-checks.yml in this
\* repository; REPORT is .github/actions/pr-require-checks/report-ci-status/action.yml,
\* RUN is .github/actions/pr-require-checks/aggregate-results/run.sh and ACTION
\* its action.yml, in melodic-software/ci-workflows at
\* 9c5bedfbfdbdfe733b9ce4cd7ca80c1574bd4cb8, the commit WF:7018 pins. REPORT
\* calls aggregate-results through `$/`, so at that same commit (REPORT:119-123).
\* Its contract and draft steps are continue-on-error (REPORT:94-105), so the
\* step WF:7015-7049 concludes on the lanes alone, as the model's gate does.

EXTENDS Naturals, FiniteSets

CONSTANTS
    FullRuns,       \* the full runs that may start on the SHA
    MaxAttempts,    \* attempts per full run (a re-run is attempt 2)
    Rerunnable,     \* the full runs a person may re-run
    Yield,          \* REPORT:128 yield-to-full-run
    Hold,           \* WF:7045 yield-wait-seconds above 0 (REPORT:134-140)
    MarkMayFail     \* mark-lanes may fail after its three tries (WF:761-772)

NoRun == "none"
States == {"pending", "success", "failure"}
Gates == {"none", "running", "success", "failure", "cancelled"}
Marks == {"todo", "done", "failed", "kept"}
Entry == [state : States, run : FullRuns, att : 1..MaxAttempts, t : Nat]
NoEntry == [state |-> "none", run |-> NoRun, att |-> 0, t |-> 0]
SnapRec == [created : BOOLEAN, live : BOOLEAN, att : 0..MaxAttempts, start : Nat]
Final == {"pass", "fail"}
CPcs == {"idle", "list", "read", "verify", "decide", "hold",
         "sRead", "sList", "sReRead"} \cup Final

VARIABLES
    att,      \* attempt number of each full run, 0 before it is created
    live,     \* the run is incomplete (queued or in progress)
    start,    \* run_started_at of the run's latest attempt
    mark,     \* the mark-lanes job of the latest attempt
    gate,     \* the Aggregate lane results step of the latest attempt
    newest,   \* the newest ci-lanes status the Actions bot wrote
    clock,    \* orders every start and every status write
    cpc,      \* where the contract-only run is
    snap,     \* its last run listing (runs.json)
    entry,    \* the newest status as it last read it
    carried,  \* carried_state after the read and the writer check
    wRunning, \* carried_writer_running
    held,     \* yield_held_ids
    heldStarts, \* start of each attempt it held for, when it held
    waiting,  \* the runs the current hold waits on
    holdEntry, \* the newest status when the hold began
    timedOut, \* the yield ceiling has passed
    liveAtPass, \* <<run, attempt, start>> in flight at the step that passed
    listClock \* the clock at its last run listing

vars == <<att, live, start, mark, gate, newest, clock, cpc, snap, entry,
          carried, wRunning, held, heldStarts, waiting, holdEntry, timedOut,
          liveAtPass, listClock>>
cvars == <<cpc, snap, entry, carried, wRunning, held, heldStarts, waiting,
           holdEntry, timedOut, liveAtPass, listClock>>
rvars == <<att, live, start, mark, gate, newest, clock>>

\* Readers take the newest entry by id (RUN:367-386), so the model keeps only
\* that one.
Write(s, r) == /\ newest' = [state |-> s, run |-> r, att |-> att[r], t |-> clock + 1]
               /\ clock' = clock + 1
Listing == [r \in FullRuns |-> [created |-> att[r] > 0, live |-> live[r],
                                att |-> att[r], start |-> start[r]]]
InFlightSnap == {r \in FullRuns : snap[r].live}

Init ==
    /\ att = [r \in FullRuns |-> 0]
    /\ live = [r \in FullRuns |-> FALSE]
    /\ start = [r \in FullRuns |-> 0]
    /\ mark = [r \in FullRuns |-> "todo"]
    /\ gate = [r \in FullRuns |-> "none"]
    /\ newest = NoEntry
    /\ clock = 0
    /\ cpc = "idle"
    /\ snap = [r \in FullRuns |-> [created |-> FALSE, live |-> FALSE,
                                   att |-> 0, start |-> 0]]
    /\ entry = NoEntry
    /\ carried = "none"
    /\ wRunning = FALSE
    /\ held = {}
    /\ heldStarts = {}
    /\ waiting = {}
    /\ holdEntry = NoEntry
    /\ timedOut = FALSE
    /\ liveAtPass = {}
    /\ listClock = 0

\* ------------------------------------------------------------------------
\* Full runs. Every same-repository pull_request event but a label flip or a
\* body edit starts one (WF:42-56, the contract-only predicate at WF:234). The
\* rules read nothing after the contract-only run's verdict, so full runs stop
\* moving then.

Moving == cpc \notin Final

\* The event creates the run: it is queued and in flight from here.
Start(r) ==
    /\ Moving /\ att[r] = 0
    /\ att' = [att EXCEPT ![r] = 1]
    /\ live' = [live EXCEPT ![r] = TRUE]
    /\ start' = [start EXCEPT ![r] = clock + 1]
    /\ clock' = clock + 1
    /\ UNCHANGED <<mark, gate, newest>> /\ UNCHANGED cvars

\* mark-lanes POSTs ci-lanes=pending on the head (WF:761-767). It runs beside
\* the lanes; ci-status needs it (WF:4109-4110), so it lands before the verdict.
Mark(r) ==
    /\ Moving /\ live[r] /\ mark[r] = "todo"
    /\ Write("pending", r)
    /\ mark' = [mark EXCEPT ![r] = "done"]
    /\ UNCHANGED <<att, live, start, gate>> /\ UNCHANGED cvars

\* Three failed POSTs fail the job (WF:769-772); ci-status still runs on
\* !cancelled() (WF:4132) and aggregates that failure.
MarkFails(r) ==
    /\ Moving /\ MarkMayFail /\ live[r] /\ mark[r] = "todo"
    /\ mark' = [mark EXCEPT ![r] = "failed"]
    /\ UNCHANGED <<att, live, start, gate, newest, clock>> /\ UNCHANGED cvars

\* ci-status's Aggregate lane results step (WF:7015-7049) records the lanes
\* verdict (RUN:1554-1559, write_status at RUN:236-257). A failure exits 1
\* (RUN:1561-1563); a success keeps the step running while it re-runs failed
\* contract-only siblings (RUN:1702-1705).
Aggregate(r) ==
    /\ Moving /\ live[r] /\ mark[r] # "todo" /\ gate[r] = "none"
    /\ \E v \in (IF mark[r] = "failed" THEN {"failure"} ELSE {"success", "failure"}) :
          /\ Write(v, r)
          /\ gate' = [gate EXCEPT ![r] = IF v = "success" THEN "running" ELSE "failure"]
    /\ UNCHANGED <<att, live, start, mark>> /\ UNCHANGED cvars

\* The aggregate step ends; the sibling re-run cannot fail it (RUN:1600-1601).
StepEnds(r) ==
    /\ Moving /\ live[r] /\ gate[r] = "running"
    /\ gate' = [gate EXCEPT ![r] = "success"]
    /\ UNCHANGED <<att, live, start, mark, newest, clock>> /\ UNCHANGED cvars

\* The run completes after its ci-status job.
Complete(r) ==
    /\ Moving /\ live[r] /\ gate[r] \in {"success", "failure"}
    /\ live' = [live EXCEPT ![r] = FALSE]
    /\ UNCHANGED <<att, start, mark, gate, newest, clock>> /\ UNCHANGED cvars

\* A newer event on the pull request cancels it (WF:106-115), or a person
\* does. A step that was running ends cancelled; ci-status never starts in a
\* cancelled run (WF:4132).
Cancel(r) ==
    /\ Moving /\ live[r]
    /\ live' = [live EXCEPT ![r] = FALSE]
    /\ gate' = [gate EXCEPT ![r] = IF @ = "running" THEN "cancelled" ELSE @]
    /\ UNCHANGED <<att, start, mark, newest, clock>> /\ UNCHANGED cvars

\* A person re-runs a completed run: a new attempt with a new run_started_at.
\* "Re-run all jobs" runs mark-lanes again; "re-run failed jobs" keeps a
\* mark-lanes that succeeded, so that attempt writes no marker.
Rerun(r) ==
    /\ Moving /\ r \in Rerunnable /\ ~live[r] /\ att[r] \in 1..(MaxAttempts - 1)
    /\ att' = [att EXCEPT ![r] = @ + 1]
    /\ live' = [live EXCEPT ![r] = TRUE]
    /\ start' = [start EXCEPT ![r] = clock + 1]
    /\ clock' = clock + 1
    /\ gate' = [gate EXCEPT ![r] = "none"]
    /\ \E m \in (IF mark[r] = "done" THEN {"todo", "kept"} ELSE {"todo"}) :
          mark' = [mark EXCEPT ![r] = m]
    /\ UNCHANGED <<newest>> /\ UNCHANGED cvars

\* ------------------------------------------------------------------------
\* The contract-only run's CI Status job, Aggregate lane results step. It may
\* start at any point; a re-run of it (RUN:1602-1705) is a later start.

CStart ==
    /\ cpc = "idle"
    /\ cpc' = IF Yield THEN "list" ELSE "sRead"
    /\ UNCHANGED <<snap, entry, carried, wRunning, held, heldStarts, waiting,
                   holdEntry, timedOut, liveAtPass, listClock>> /\ UNCHANGED rvars

\* Yield, step 1: list this workflow's runs on the SHA (list_in_flight_full_runs,
\* RUN:1216-1245, called at RUN:1413). Every full run reads full by its jobs:
\* mark-lanes runs in every full run (WF:234).
CList ==
    /\ cpc = "list"
    /\ snap' = Listing
    /\ listClock' = clock
    /\ cpc' = "read"
    /\ UNCHANGED <<entry, carried, wRunning, held, heldStarts, waiting,
                   holdEntry, timedOut, liveAtPass>> /\ UNCHANGED rvars

\* Yield, step 2: read the newest bot-written ci-lanes status
\* (read_newest_entry RUN:353-387, from read_carried_state at RUN:1418).
CRead ==
    /\ cpc = "read"
    /\ entry' = newest
    /\ carried' = newest.state
    /\ wRunning' = FALSE
    /\ cpc' = IF newest.state = "success" THEN "verify" ELSE "decide"
    /\ UNCHANGED <<snap, held, heldStarts, waiting, holdEntry, timedOut,
                   liveAtPass, listClock>> /\ UNCHANGED rvars

\* The writer check of a success (verify_carried_writer RUN:401-472,
\* verify_writer_step RUN:695-733, gate_step_outcome RUN:749-758,
\* verify_no_newer_verdict RUN:825-866). The writer's row comes from the
\* listing, else from a live read (RUN:446-457); its gate step and each rival's
\* are read live, as one step.
WriterStart == IF snap[entry.run].created THEN snap[entry.run].start
               ELSE start[entry.run]
NewerVerdictFailed ==
    \E r \in FullRuns :
        /\ r # entry.run
        /\ snap[r].created /\ ~snap[r].live
        /\ snap[r].start >= WriterStart
        /\ gate[r] \in {"failure", "cancelled"}
CVerify ==
    /\ cpc = "verify"
    /\ LET g == gate[entry.run] IN
         \/ /\ g \in {"none", "running"}
            /\ carried' = "pending" /\ wRunning' = TRUE
         \/ /\ g = "success"
            /\ carried' = IF NewerVerdictFailed THEN "none" ELSE "success"
            /\ wRunning' = FALSE
         \/ /\ g \in {"failure", "cancelled"}
            /\ carried' = "none" /\ wRunning' = FALSE
    /\ cpc' = "decide"
    /\ UNCHANGED <<snap, entry, held, heldStarts, waiting, holdEntry, timedOut,
                   liveAtPass, listClock>> /\ UNCHANGED rvars

\* writer_attempt_wrote (RUN:1381-1386): the run is the writer and its attempt
\* in the listing started at or before the status was created.
Wrote(r) == r = entry.run /\ snap[r].created /\ snap[r].start <= entry.t
\* RUN:1423-1431: a run whose attempt wrote the carried success (or, under a
\* hold, failure) does not supersede.
Skips(r) == (carried = "success" \/ (Hold /\ carried = "failure")) /\ Wrote(r)
Superseding == {r \in InFlightSnap : ~Skips(r)}
\* carried_postdates (RUN:1335-1341) over the held runs, held_success_carries
\* (RUN:1346-1360): each held run in the listing started at or before the success.
Postdates == \A r \in held : snap[r].created /\ snap[r].start <= entry.t

\* Yield, steps 3-6 (RUN:1422-1468). The single read passes a success once its
\* writer is verified (RUN:1481-1488).
CDecide ==
    /\ cpc = "decide"
    /\ IF ~Yield
         THEN /\ cpc' = IF carried = "success" THEN "pass" ELSE "fail"
              /\ UNCHANGED <<held, heldStarts, waiting, holdEntry>>
         ELSE CASE Superseding = {} ->
                     /\ cpc' = IF carried = "success" /\ (held = {} \/ Postdates)
                               THEN "pass" ELSE "fail"
                     /\ UNCHANGED <<held, heldStarts, waiting, holdEntry>>
                [] wRunning /\ Superseding = {entry.run} /\ Wrote(entry.run)
                     /\ ~timedOut ->
                     \* The writer's step is finishing (RUN:1436-1454): list again.
                     /\ cpc' = "list"
                     /\ UNCHANGED <<held, heldStarts, waiting, holdEntry>>
                [] Hold /\ ~timedOut ->
                     \* yield_hold (RUN:1457-1459, RUN:1294-1331).
                     /\ cpc' = "hold"
                     /\ waiting' = Superseding
                     /\ held' = held \cup Superseding
                     /\ heldStarts' = heldStarts \cup {snap[r].start : r \in Superseding}
                     /\ holdEntry' = entry
                [] OTHER ->
                     \* fail_superseded (RUN:1364-1376).
                     /\ cpc' = "fail"
                     /\ UNCHANGED <<held, heldStarts, waiting, holdEntry>>
    /\ UNCHANGED <<snap, entry, carried, wRunning, timedOut, listClock>>
    /\ liveAtPass' = IF cpc' = "pass"
                     THEN {<<r, att[r], start[r]>> : r \in {q \in FullRuns : live[q]}}
                     ELSE liveAtPass
    /\ UNCHANGED rvars

\* The hold ends when the runs it waits on complete, the newest status changes,
\* or the ceiling passes (RUN:1301-1330); the loop then lists again (RUN:1459).
CHoldEnds ==
    /\ cpc = "hold"
    /\ \/ \A r \in waiting : ~live[r]
       \/ newest # holdEntry
       \/ timedOut
    /\ cpc' = "list"
    /\ waiting' = {}
    /\ UNCHANGED <<snap, entry, carried, wRunning, held, heldStarts, holdEntry,
                   timedOut, liveAtPass, listClock>> /\ UNCHANGED rvars

\* yield-wait-seconds (600 at WF:7045) or the writer wait's 30 s passes.
CTimeout ==
    /\ Yield /\ cpc \in {"list", "read", "verify", "decide", "hold"} /\ ~timedOut
    /\ timedOut' = TRUE
    /\ UNCHANGED <<cpc, snap, entry, carried, wRunning, held, heldStarts,
                   waiting, holdEntry, liveAtPass, listClock>> /\ UNCHANGED rvars

\* Single read (carry-forward-wait-seconds '0', REPORT:129, without yield): read
\* the status (RUN:1481-1487), then verify_carried_writer lists the runs
\* (RUN:424-429) and reads the status again (RUN:436-440).
SRead ==
    /\ cpc = "sRead"
    /\ entry' = newest
    /\ carried' = newest.state
    /\ cpc' = IF newest.state = "success" THEN "sList" ELSE "fail"
    /\ UNCHANGED <<snap, wRunning, held, heldStarts, waiting, holdEntry,
                   timedOut, liveAtPass, listClock>> /\ UNCHANGED rvars
SList ==
    /\ cpc = "sList"
    /\ snap' = Listing
    /\ listClock' = clock
    /\ cpc' = "sReRead"
    /\ UNCHANGED <<entry, carried, wRunning, held, heldStarts, waiting,
                   holdEntry, timedOut, liveAtPass>> /\ UNCHANGED rvars
SReRead ==
    /\ cpc = "sReRead"
    /\ cpc' = IF newest = entry THEN "verify" ELSE "fail"
    /\ UNCHANGED <<snap, entry, carried, wRunning, held, heldStarts, waiting,
                   holdEntry, timedOut, liveAtPass, listClock>> /\ UNCHANGED rvars

\* The contract-only run has its verdict; nothing after it is read.
Done ==
    /\ cpc \in Final
    /\ UNCHANGED vars

Next ==
    \/ \E r \in FullRuns :
         Start(r) \/ Mark(r) \/ MarkFails(r) \/ Aggregate(r) \/ StepEnds(r)
         \/ Complete(r) \/ Cancel(r) \/ Rerun(r)
    \/ CStart \/ CList \/ CRead \/ CVerify \/ CDecide \/ CHoldEnds \/ CTimeout
    \/ SRead \/ SList \/ SReRead
    \/ Done

Spec == Init /\ [][Next]_vars

\* Ticks are only compared with each other, and every new tick is above every
\* old one, so two states whose ticks are in the same order behave alike. The
\* view replaces each tick by its rank among the ticks the state holds.
Ticks == {0, clock, listClock, newest.t, entry.t, holdEntry.t}
         \cup {start[r] : r \in FullRuns} \cup {snap[r].start : r \in FullRuns}
         \cup heldStarts \cup {x[3] : x \in liveAtPass}
Rank(t) == Cardinality({u \in Ticks : u < t})
RankE(e) == [e EXCEPT !.t = Rank(@)]
View == <<att, live, [r \in FullRuns |-> Rank(start[r])], mark, gate,
          RankE(newest), Rank(clock), cpc,
          [r \in FullRuns |-> [snap[r] EXCEPT !.start = Rank(@)]],
          RankE(entry), carried, wRunning, held,
          {Rank(s) : s \in heldStarts}, waiting, RankE(holdEntry), timedOut,
          {<<x[1], x[2], Rank(x[3])>> : x \in liveAtPass}, Rank(listClock)>>

\* ------------------------------------------------------------------------
\* Rules.

TypeOK ==
    /\ att \in [FullRuns -> 0..MaxAttempts]
    /\ live \in [FullRuns -> BOOLEAN]
    /\ start \in [FullRuns -> Nat]
    /\ mark \in [FullRuns -> Marks]
    /\ gate \in [FullRuns -> Gates]
    /\ newest \in Entry \cup {NoEntry}
    /\ clock \in Nat
    /\ cpc \in CPcs
    /\ snap \in [FullRuns -> SnapRec]
    /\ entry \in Entry \cup {NoEntry}
    /\ carried \in States \cup {"none"}
    /\ wRunning \in BOOLEAN
    /\ held \subseteq FullRuns
    /\ heldStarts \subseteq Nat
    /\ waiting \subseteq FullRuns
    /\ holdEntry \in Entry \cup {NoEntry}
    /\ timedOut \in BOOLEAN
    /\ liveAtPass \subseteq (FullRuns \X (1..MaxAttempts) \X Nat)
    /\ listClock \in Nat

Writer(x) == x[1] = entry.run /\ x[2] = entry.att

\* The promise: a contract-only run that passes carries no success a full run
\* in flight is about to replace. Every full-run attempt in flight at the step
\* that passes wrote the success it carries, or started after the run's last
\* listing of the runs.
NoStaleCarry ==
    cpc = "pass" => \A x \in liveAtPass : Writer(x) \/ x[3] > listClock

\* A run that held for full runs passes only on a success created at or after
\* each of them started (ACTION:206-227, yield-wait-seconds).
HeldPassIsNewer ==
    cpc = "pass" => \A s \in heldStarts : entry.t >= s

\* It passes only on a success whose writer it verified.
PassCarriesSuccess ==
    cpc = "pass" => (entry.state = "success" /\ carried = "success")

\* Not a shipped rule: NoStaleCarry without its exception for an attempt that
\* started after the last listing. See the skill's "Reading a result".
NoStaleCarryAtPass ==
    cpc = "pass" => \A x \in liveAtPass : Writer(x)
=============================================================================
