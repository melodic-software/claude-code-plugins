---------------------------- MODULE ClaimProtocol ----------------------------
\* One GitHub issue claimed by three claimants of the work-item tracker's
\* GitHub adapter (CONTRACT.md "Lease protocol"):
\*   local  - a default claim from a local session, login "human"
\*   lane   - the issue lane's --lease-only claim, session_id run-<id>,
\*            holder "bot", inside a workflow run that can complete
\*   triage - a default claim, login "human" or "other"
\* A holder may renew once (renew-lease.sh) and release once (release.sh).
\* Every GitHub read and write is its own step. Line numbers are at commit
\* a548b3aaab8c; paths are under plugins/work-items/tools/work-item-tracker/,
\* the scripts under adapters/github/.

EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    Starters,       \* the claimants that may start a claim
    WithRenew,      \* a holder runs renew-lease at most once
    WritesMayFail,  \* each best-effort write may fail
    ReadsMayFail,   \* the reads whose failure does not exit may fail
    MayDie,         \* a claimant may die between any two of its steps
    BoundedStall,   \* a renew that judged its lease outside the margin PATCHes before it expires
    RenewDeathKeepsHolding \* a renew killed after its PATCH leaves the session working

Claimants == {"local", "lane", "triage"}
DefaultClaims == {"local", "triage"}
Logins == {"human", "other", "bot"}

VARIABLES
    pc, ctx, leases, assignees, runDone, triageLogin,
    mine,      \* own lease comment id, 0 before the post
    snap,      \* last lease list read: [sup, gen, near] per comment
    live, cand, win,
    bodyGen,   \* generation of the own body as release/renew read it
    renewed,
    nearSeen,  \* renew: the margin test at its clock sample
    after,     \* where the hand-back ends
    backedOffDone \* the claimant's decision went against a run lease whose run had completed

vars == <<pc, ctx, leases, assignees, runDone, triageLogin, mine, snap, live,
          cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

LoginOf(c) == CASE c = "local" -> "human"
              []   c = "lane"  -> "bot"
              []   OTHER       -> triageLogin

\* gen = renewals so far; generations below expN have expired; near = the
\* current generation is within the 300 s skew margin (lib/lease.sh:12) of
\* its expiry.
LeaseRec == [by : Claimants, holder : Logins, run : BOOLEAN,
             sup : BOOLEAN, gen : 0..1, expN : 0..2, near : BOOLEAN]
SnapRec == [sup : BOOLEAN, gen : 0..1, near : BOOLEAN, exp : 0..2]

WriteOutcomes == IF WritesMayFail THEN BOOLEAN ELSE {TRUE}
ReadOutcomes == IF ReadsMayFail THEN BOOLEAN ELSE {TRUE}

Min(S) == CHOOSE i \in S : \A j \in S : i <= j
Max(S) == CHOOSE i \in S : \A j \in S : i >= j

Final == {"lost", "failed", "dead", "released", "relFail", "relDead", "gone",
          "renLost"}
RenewPre == {"renLeases", "arbJudge", "arbRunRead", "arbRunSup", "renPatch"}

\* The margin matters only while the lease's owner can still renew it.
NeedsNear(i) ==
    LET c == leases[i].by
    IN WithRenew /\ \/ ~renewed[c] /\ pc[c] \notin Final
                    \/ ctx[c] = "renew" /\ pc[c] \in RenewPre

\* lib/lease.sh:128-136 wit_lease_is_live.
LiveNow(i) == ~leases[i].sup /\ leases[i].expN <= leases[i].gen
\* A body read outside the margin of its expiry is judged before it expires
\* when stalls are bounded.
SnapLive(s, i) == ~s[i].sup /\ (leases[i].expN <= s[i].gen
                                \/ (BoundedStall /\ ~s[i].near))
Snapshot == [i \in 1..Len(leases) |->
                [sup |-> leases[i].sup, gen |-> leases[i].gen,
                 near |-> leases[i].near \/ ~NeedsNear(i), exp |-> 0]]
\* The hand-back reads its clock before each lease list: exp is each lease's
\* expired generations at that clock read, kept beside the bodies listed after.
ClockSnap == [i \in 1..Len(leases) |->
                [sup |-> FALSE, gen |-> 0, near |-> FALSE,
                 exp |-> leases[i].expN]]
ListSnap(c) == [i \in 1..Len(leases) |->
                  [sup |-> leases[i].sup, gen |-> leases[i].gen, near |-> FALSE,
                   exp |-> IF i \in DOMAIN snap[c] THEN snap[c][i].exp ELSE 0]]
\* lib/lease.sh:44-58 wit_select_active_lease: the newest non-superseded lease.
ActiveIn(s) == LET open == {i \in DOMAIN s : ~s[i].sup}
               IN IF open = {} THEN 0 ELSE Max(open)
ActiveNow == ActiveIn(Snapshot)

\* adapters/github/common.sh:534-543 _wit_login_holds_other on the list in
\* snap[c], judged at the clock read before the list. The code also counts a
\* lease live at a later read (:540), which differs only for a renewed_at
\* ahead of the reader's clock; the model has one clock.
HoldsOther(c) == \E i \in DOMAIN snap[c] :
                    /\ i # mine[c]
                    /\ leases[i].holder = LoginOf(c)
                    /\ ~snap[c][i].sup
                    /\ snap[c][i].exp <= snap[c][i].gen

Alive(c) == c = "lane" => ~runDone

Guarded == {"gLeases", "gList", "gJudge", "gARead", "gRm", "gRead2", "gList2",
            "gJudge2", "gAdd", "gRead3", "gList3", "gJudge3", "gRm3"}
ClaimRollback == {"assigned", "reAssign", "checked2", "checked"}
ClaimAbort == {"posted", "arbJudge", "arbRunRead", "arbRunSup", "lossSup",
               "winRead", "winAdd"}
RenewPost == {"ren2Leases", "ren2Judge", "renSup"}
ReleaseMid == {"relLeases", "relJudgeOwn", "arbJudge", "arbRunRead",
               "arbRunSup", "relPatch", "relSup"}
Pcs == {"idle", "held", "tSup"} \cup Final \cup Guarded \cup ClaimRollback
       \cup ClaimAbort \cup RenewPre \cup RenewPost \cup ReleaseMid

SupersedeWrite(i, g, ok) ==
    leases' = IF ok THEN [leases EXCEPT ![i].sup = TRUE, ![i].gen = g]
                    ELSE leases
AddLogin(c, ok) ==
    assignees' = IF ok THEN assignees \cup {LoginOf(c)} ELSE assignees
RemoveLogin(c, ok) ==
    assignees' = IF ok THEN assignees \ {LoginOf(c)} ELSE assignees

Init ==
    /\ pc = [c \in Claimants |-> "idle"]
    /\ ctx = [c \in Claimants |-> "claim"]
    /\ leases = <<>>
    /\ assignees = {}
    /\ runDone = FALSE
    /\ triageLogin \in {"human", "other"}
    /\ mine = [c \in Claimants |-> 0]
    /\ snap = [c \in Claimants |-> <<>>]
    /\ live = [c \in Claimants |-> {}]
    /\ cand = [c \in Claimants |-> 0]
    /\ win = [c \in Claimants |-> 0]
    /\ bodyGen = [c \in Claimants |-> 0]
    /\ renewed = [c \in Claimants |-> FALSE]
    /\ nearSeen = [c \in Claimants |-> FALSE]
    /\ after = [c \in Claimants |-> "failed"]
    /\ backedOffDone = [c \in Claimants |-> FALSE]

-----------------------------------------------------------------------------
\* claim.sh

\* :93 assign (REST may drop the login silently, common.sh:217-220); the
\* rollback trap of :85-88 is armed.
Assign(c) ==
    /\ c \in DefaultClaims \cap Starters /\ pc[c] = "idle"
    /\ \E ok \in WriteOutcomes : AddLogin(c, ok)
    /\ pc' = [pc EXCEPT ![c] = "assigned"]
    /\ UNCHANGED <<ctx, leases, runDone, triageLogin, mine, snap, live, cand,
                   win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* :96-118 read the assignees. Own login missing: one re-assign and re-read
\* (:104-108), then exit 4 (:109-113). Another login: exit 7 (:114-118). Both
\* exits run the rollback trap: the hand-back.
CheckRead(c) ==
    /\ pc[c] \in {"assigned", "checked2"}
    /\ pc' = [pc EXCEPT ![c] =
          IF LoginOf(c) \notin assignees
          THEN (IF pc[c] = "assigned" THEN "reAssign" ELSE "gLeases")
          ELSE IF \E l \in assignees : l # LoginOf(c)
          THEN "gLeases"
          ELSE "checked"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

\* :105 the one re-assign; :106 re-reads (CheckRead from "checked2").
ReAssign(c) ==
    /\ pc[c] = "reAssign"
    /\ \E ok \in WriteOutcomes : AddLogin(c, ok)
    /\ pc' = [pc EXCEPT ![c] = "checked2"]
    /\ UNCHANGED <<ctx, leases, runDone, triageLogin, mine, snap, live, cand,
                   win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* :121-132 post the lease; the abort trap of :137-141 is armed. The lane
\* (lease-only, :75-76) starts here.
PostLease(c) ==
    /\ \/ c \in DefaultClaims /\ pc[c] = "checked"
       \/ c = "lane" /\ c \in Starters /\ pc[c] = "idle" /\ ~runDone
    /\ leases' = Append(leases, [by |-> c, holder |-> LoginOf(c),
                                 run |-> (c = "lane"), sup |-> FALSE,
                                 gen |-> 0, expN |-> 0, near |-> FALSE])
    /\ mine' = [mine EXCEPT ![c] = Len(leases) + 1]
    /\ pc' = [pc EXCEPT ![c] = "posted"]
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, snap, live, cand,
                   win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* Every checked read of the lease list (a failure exits: Die): claim.sh:150,
\* renew-lease.sh:63, release.sh:94.
ReadLeases(c) ==
    /\ Alive(c)
    /\ pc[c] \in {"posted", "renLeases", "relLeases"}
    /\ snap' = [snap EXCEPT ![c] = Snapshot]
    /\ pc' = [pc EXCEPT ![c] =
          IF pc[c] = "relLeases" THEN "relJudgeOwn" ELSE "arbJudge"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* What each script does with the winner. Claim, claim.sh:160-164: another
\* winner backs off. Renew, renew-lease.sh:66-83: another winner refuses;
\* inside the margin (as sampled with the winner's clock) the lease must also
\* be the newest non-superseded one. Release, release.sh:113-125: another
\* winner refuses with exit 7 after superseding its own lease (RelSup).
Decide(c, w) ==
    /\ win' = [win EXCEPT ![c] = w]
    /\ pc' = [pc EXCEPT ![c] =
          CASE ctx[c] = "claim" ->
                 (IF w = 0 \/ w = mine[c]
                  THEN (IF c \in DefaultClaims THEN "winRead" ELSE "held")
                  ELSE "lossSup")
          []   ctx[c] = "renew" ->
                 (IF w = mine[c]
                     /\ (nearSeen'[c] => ActiveIn(snap[c]) = mine[c])
                  THEN "renPatch" ELSE "held")
          []   OTHER -> (IF w = mine[c] THEN "relPatch" ELSE "relSup")]

\* lib/lease.sh:68-86 wit_lease_winner with one clock sample: the earliest
\* live lease; a run lease that is not ours costs a run-status read.
Judge(c) ==
    LET S  == {i \in DOMAIN snap[c] : SnapLive(snap[c], i)}
        w0 == IF S = {} THEN 0 ELSE Min(S)
    IN /\ live' = [live EXCEPT ![c] = S]
       /\ cand' = [cand EXCEPT ![c] = w0]
       /\ nearSeen' = [nearSeen EXCEPT ![c] =
             ctx[c] = "renew" /\ leases[mine[c]].near]
       /\ IF w0 # 0 /\ w0 # mine[c] /\ leases[w0].run
          THEN /\ pc' = [pc EXCEPT ![c] = "arbRunRead"]
               /\ UNCHANGED win
          ELSE Decide(c, w0)

\* claim.sh:151, renew-lease.sh:64-65.
ArbJudge(c) ==
    /\ Alive(c) /\ pc[c] = "arbJudge"
    /\ Judge(c)
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   bodyGen, renewed, after, backedOffDone>>

\* common.sh:478-492 wit_lease_released_by_run: the run-status read (:484). A
\* failed read keeps the lease winning (:484-487).
ArbRunRead(c) ==
    /\ Alive(c) /\ pc[c] = "arbRunRead"
    /\ UNCHANGED nearSeen
    /\ \E ok \in ReadOutcomes :
          /\ backedOffDone' = [backedOffDone EXCEPT ![c] = @ \/ (~ok /\ runDone)]
          /\ IF ok /\ runDone
             THEN /\ pc' = [pc EXCEPT ![c] = "arbRunSup"]
                  /\ UNCHANGED win
             ELSE Decide(c, cand[c])
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, bodyGen, renewed, after>>

\* common.sh:489 the completed run's lease is superseded, best-effort; the
\* winner is the next live lease.
ArbRunSup(c) ==
    /\ Alive(c) /\ pc[c] = "arbRunSup"
    /\ UNCHANGED nearSeen
    /\ \E ok \in WriteOutcomes :
          SupersedeWrite(cand[c], snap[c][cand[c]].gen, ok)
    /\ LET rest == live[c] \ {cand[c]}
       IN Decide(c, IF rest = {} THEN 0 ELSE Min(rest))
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, bodyGen, renewed, after, backedOffDone>>

\* :163 exit 7 runs the abort trap (:137-140): supersede own lease
\* (common.sh:465-470), then a default claim's hand-back (:85-87).
LossSup(c) ==
    /\ Alive(c) /\ pc[c] = "lossSup"
    /\ \E ok \in WriteOutcomes : SupersedeWrite(mine[c], 0, ok)
    /\ after' = [after EXCEPT ![c] = "lost"]
    /\ pc' = [pc EXCEPT ![c] = IF c \notin DefaultClaims THEN "lost" ELSE "gLeases"]
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, backedOffDone>>

\* common.sh:506-521 wit_hand_back_assignee, run by a claim's failure paths
\* and back-off, by release, and by renew's back-off. Each lease list retries
\* once (one step here; a failed read means both attempts failed).
\* :508-509 list (a failed list counts as empty); stop on another live lease
\* of the login.
GLeases(c) ==
    /\ Alive(c) /\ pc[c] = "gLeases"
    /\ snap' = [snap EXCEPT ![c] = ClockSnap]
    /\ pc' = [pc EXCEPT ![c] = "gList"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

GList(c) ==
    /\ Alive(c) /\ pc[c] = "gList"
    /\ \E ok \in ReadOutcomes :
          snap' = [snap EXCEPT ![c] = IF ok THEN ListSnap(c) ELSE <<>>]
    /\ pc' = [pc EXCEPT ![c] = "gJudge"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

GJudge(c) ==
    /\ Alive(c) /\ pc[c] = "gJudge"
    /\ pc' = [pc EXCEPT ![c] = IF HoldsOther(c) THEN after[c] ELSE "gARead"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

\* :510-512 a successful assignee read without the login ends it.
GARead(c) ==
    /\ Alive(c) /\ pc[c] = "gARead"
    /\ \E ok \in ReadOutcomes :
          pc' = [pc EXCEPT ![c] =
             IF ok /\ LoginOf(c) \notin assignees THEN after[c] ELSE "gRm"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

\* :513 best-effort removal.
GRm(c) ==
    /\ Alive(c) /\ pc[c] = "gRm"
    /\ \E ok \in WriteOutcomes : RemoveLogin(c, ok)
    /\ pc' = [pc EXCEPT ![c] = "gRead2"]
    /\ UNCHANGED <<ctx, leases, runDone, triageLogin, mine, snap, live, cand,
                   win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* :514-515 re-list (a failed list ends it).
GRead2(c) ==
    /\ Alive(c) /\ pc[c] = "gRead2"
    /\ snap' = [snap EXCEPT ![c] = ClockSnap]
    /\ pc' = [pc EXCEPT ![c] = "gList2"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

GList2(c) ==
    /\ Alive(c) /\ pc[c] = "gList2"
    /\ \E ok \in ReadOutcomes :
          IF ok THEN /\ snap' = [snap EXCEPT ![c] = ListSnap(c)]
                     /\ pc' = [pc EXCEPT ![c] = "gJudge2"]
                ELSE /\ UNCHANGED snap
                     /\ pc' = [pc EXCEPT ![c] = after[c]]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

GJudge2(c) ==
    /\ Alive(c) /\ pc[c] = "gJudge2"
    /\ pc' = [pc EXCEPT ![c] = IF HoldsOther(c) THEN "gAdd" ELSE after[c]]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

\* :516 best-effort re-add.
GAdd(c) ==
    /\ Alive(c) /\ pc[c] = "gAdd"
    /\ \E ok \in WriteOutcomes : AddLogin(c, ok)
    /\ pc' = [pc EXCEPT ![c] = "gRead3"]
    /\ UNCHANGED <<ctx, leases, runDone, triageLogin, mine, snap, live, cand,
                   win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* :519-520 after a re-add the leases are listed once more; the login comes
\* off again when the lease it was put back for is gone (a failed list keeps it).
GRead3(c) ==
    /\ Alive(c) /\ pc[c] = "gRead3"
    /\ snap' = [snap EXCEPT ![c] = ClockSnap]
    /\ pc' = [pc EXCEPT ![c] = "gList3"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

GList3(c) ==
    /\ Alive(c) /\ pc[c] = "gList3"
    /\ \E ok \in ReadOutcomes :
          IF ok THEN /\ snap' = [snap EXCEPT ![c] = ListSnap(c)]
                     /\ pc' = [pc EXCEPT ![c] = "gJudge3"]
                ELSE /\ UNCHANGED snap
                     /\ pc' = [pc EXCEPT ![c] = after[c]]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

GJudge3(c) ==
    /\ Alive(c) /\ pc[c] = "gJudge3"
    /\ pc' = [pc EXCEPT ![c] = IF HoldsOther(c) THEN after[c] ELSE "gRm3"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

GRm3(c) ==
    /\ Alive(c) /\ pc[c] = "gRm3"
    /\ \E ok \in WriteOutcomes : RemoveLogin(c, ok)
    /\ pc' = [pc EXCEPT ![c] = after[c]]
    /\ UNCHANGED <<ctx, leases, runDone, triageLogin, mine, snap, live, cand,
                   win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* claim.sh:169-174 on a win, re-read the assignees and put the login back.
WinRead(c) ==
    /\ pc[c] = "winRead"
    /\ pc' = [pc EXCEPT ![c] =
          IF LoginOf(c) \in assignees THEN "held" ELSE "winAdd"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

WinAdd(c) ==
    /\ pc[c] = "winAdd"
    /\ \E ok \in WriteOutcomes : AddLogin(c, ok)
    /\ pc' = [pc EXCEPT ![c] = "held"]
    /\ UNCHANGED <<ctx, leases, runDone, triageLogin, mine, snap, live, cand,
                   win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* claim.sh:137-140 the abort trap after a failure: best-effort supersede,
\* then a default claim's hand-back.
TrapSup(c) ==
    /\ Alive(c) /\ pc[c] = "tSup"
    /\ \E ok \in WriteOutcomes : SupersedeWrite(mine[c], 0, ok)
    /\ pc' = [pc EXCEPT ![c] = IF c \in DefaultClaims THEN "gLeases" ELSE "failed"]
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

-----------------------------------------------------------------------------
\* renew-lease.sh

\* :34-59 read our comment; refuse a superseded (:47-50) or expired (:55-59)
\* lease.
RenewStart(c) ==
    /\ WithRenew /\ Alive(c) /\ pc[c] = "held" /\ ~renewed[c]
    /\ renewed' = [renewed EXCEPT ![c] = TRUE]
    /\ ctx' = [ctx EXCEPT ![c] = "renew"]
    /\ IF LiveNow(mine[c])
       THEN /\ pc' = [pc EXCEPT ![c] = "renLeases"]
            /\ bodyGen' = [bodyGen EXCEPT ![c] = leases[mine[c]].gen]
       ELSE UNCHANGED <<pc, bodyGen>>
    /\ UNCHANGED <<leases, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, nearSeen, after, backedOffDone>>

\* :85-86, :103 rewrite the whole body as read with a fresh renewed_at;
\* :117-120 sample the clock after the PATCH (in this same step): at or past
\* the old expiry, back off (:118-119); inside the margin before it, re-list
\* (:120).
\* A failed PATCH at or near the old expiry backs off (:105-106); any other
\* failed PATCH exits (:107).
RenewPatch(c) ==
    /\ Alive(c) /\ pc[c] = "renPatch"
    /\ \E ok \in WriteOutcomes :
          IF ok
          THEN /\ leases' = [leases EXCEPT ![mine[c]].sup = FALSE,
                                           ![mine[c]].gen = bodyGen[c] + 1,
                                           ![mine[c]].near = FALSE]
               /\ pc' = [pc EXCEPT ![c] =
                     IF leases[mine[c]].expN > bodyGen[c] THEN "renSup"
                     ELSE IF leases[mine[c]].near THEN "ren2Leases"
                     ELSE "held"]
          ELSE /\ UNCHANGED leases
               /\ pc' = [pc EXCEPT ![c] =
                     IF leases[mine[c]].expN > bodyGen[c] \/ leases[mine[c]].near
                     THEN "renSup" ELSE "held"]
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* :121-122 re-list, one retry; a list still unread keeps the lease (:125-126).
Ren2Leases(c) ==
    /\ Alive(c) /\ pc[c] = "ren2Leases"
    /\ \E ok \in ReadOutcomes :
          IF ok THEN /\ snap' = [snap EXCEPT ![c] = Snapshot]
                     /\ pc' = [pc EXCEPT ![c] = "ren2Judge"]
                ELSE /\ UNCHANGED snap
                     /\ pc' = [pc EXCEPT ![c] = "held"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* :123-124 a newer live lease (lib/lease.sh:90-97 wit_newer_live_lease)
\* makes it back off.
Ren2Judge(c) ==
    /\ Alive(c) /\ pc[c] = "ren2Judge"
    /\ pc' = [pc EXCEPT ![c] =
          IF \E i \in DOMAIN snap[c] : i > mine[c] /\ SnapLive(snap[c], i)
          THEN "renSup" ELSE "held"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

\* :90-99 back_off: supersede the renewed lease, two tries (:91-92); the
\* hand-back (:93) only when one succeeded; exit 7: the session stops.
RenSup(c) ==
    /\ Alive(c) /\ pc[c] = "renSup"
    /\ \E ok \in WriteOutcomes :
          /\ SupersedeWrite(mine[c], bodyGen[c] + 1, ok)
          /\ pc' = [pc EXCEPT ![c] = IF ok THEN "gLeases" ELSE "renLost"]
    /\ after' = [after EXCEPT ![c] = "renLost"]
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, backedOffDone>>

-----------------------------------------------------------------------------
\* release.sh

\* :47-59 read our comment. Already superseded (:80-86): hand back, exit 0.
ReleaseStart(c) ==
    /\ Alive(c) /\ pc[c] = "held"
    /\ ctx' = [ctx EXCEPT ![c] = "release"]
    /\ bodyGen' = [bodyGen EXCEPT ![c] = leases[mine[c]].gen]
    /\ pc' = [pc EXCEPT ![c] =
          IF ~leases[mine[c]].sup THEN "relLeases" ELSE "gLeases"]
    /\ after' = [after EXCEPT ![c] = "released"]
    /\ UNCHANGED <<leases, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, renewed, nearSeen, backedOffDone>>

\* :95 one clock sample judges our body and the winner. Expired (:100-109):
\* hand back, then exit 0 when we are the newest non-superseded lease, else
\* exit 7. Live: judge the winner (:113-125).
RelJudgeOwn(c) ==
    /\ Alive(c) /\ pc[c] = "relJudgeOwn"
    /\ IF leases[mine[c]].expN <= bodyGen[c]
       THEN Judge(c) /\ UNCHANGED after
       ELSE /\ UNCHANGED <<live, cand, win, nearSeen>>
            /\ pc' = [pc EXCEPT ![c] = "gLeases"]
            /\ after' = [after EXCEPT ![c] =
                  IF ActiveIn(snap[c]) = mine[c] THEN @ ELSE "relFail"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   bodyGen, renewed, backedOffDone>>

\* :127-129 PATCH superseded_at (a failure exits, no hand-back), then the
\* hand-back (:74-78).
RelPatch(c) ==
    /\ Alive(c) /\ pc[c] = "relPatch"
    /\ \E ok \in WriteOutcomes :
          IF ok
          THEN /\ leases' = [leases EXCEPT ![mine[c]].sup = TRUE,
                                           ![mine[c]].gen = bodyGen[c]]
               /\ pc' = [pc EXCEPT ![c] = "gLeases"]
          ELSE /\ UNCHANGED leases
               /\ pc' = [pc EXCEPT ![c] = "relFail"]
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* An outranked live handle: supersede the own lease (two tries, one step
\* here), the hand-back only after a supersede succeeded, exit 7.
RelSup(c) ==
    /\ Alive(c) /\ pc[c] = "relSup"
    /\ \E ok \in WriteOutcomes :
          /\ SupersedeWrite(mine[c], bodyGen[c], ok)
          /\ pc' = [pc EXCEPT ![c] = IF ok THEN "gLeases" ELSE "relFail"]
    /\ after' = [after EXCEPT ![c] = "relFail"]
    /\ UNCHANGED <<ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, backedOffDone>>

-----------------------------------------------------------------------------
\* Failures and the environment

\* A death (or a checked call's failure, which exits the same way through
\* wit_run_gh, common.sh:164-170) runs the trap armed at that point: claim's
\* rollback (claim.sh:85-88) or abort (:137-141). A death inside the
\* hand-back equals its remaining best-effort writes failing.
Die(c) ==
    /\ MayDie /\ Alive(c)
    /\ \/ /\ ctx[c] = "claim" /\ pc[c] \in ClaimRollback
          /\ pc' = [pc EXCEPT ![c] = "gLeases"]
       \/ /\ ctx[c] = "claim" /\ pc[c] \in ClaimAbort
          /\ pc' = [pc EXCEPT ![c] = "tSup"]
       \/ /\ pc[c] \in Guarded
          /\ pc' = [pc EXCEPT ![c] = CASE after[c] = "lost" -> "dead"
                                     []   after[c] = "renLost" -> "renLost"
                                     []   after[c] \in {"released", "relFail"} -> "relDead"
                                     []   OTHER -> "failed"]
       \/ /\ ctx[c] = "renew" /\ pc[c] \in RenewPre
          /\ pc' = [pc EXCEPT ![c] = "held"]
       \/ /\ ctx[c] = "renew" /\ pc[c] \in RenewPost
          /\ pc' = [pc EXCEPT ![c] =
                IF RenewDeathKeepsHolding THEN "held" ELSE "renLost"]
       \/ /\ ctx[c] = "release" /\ pc[c] \in ReleaseMid
          /\ pc' = [pc EXCEPT ![c] = "relDead"]
    /\ UNCHANGED <<ctx, leases, assignees, runDone, triageLogin, mine, snap,
                   live, cand, win, bodyGen, renewed, nearSeen, after,
                   backedOffDone>>

\* The lane's workflow run ends (completed, cancelled or timed out) after its
\* lease is posted, without releasing.
RunCompletes ==
    /\ mine["lane"] # 0 /\ ~runDone
    /\ runDone' = TRUE
    /\ pc' = [pc EXCEPT !["lane"] = IF @ \in Final THEN @ ELSE "gone"]
    /\ UNCHANGED <<ctx, leases, assignees, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* Time enters the skew margin of lease i's current generation.
Approach(i) ==
    /\ i \in DOMAIN leases
    /\ NeedsNear(i)
    /\ ~leases[i].near /\ leases[i].expN <= leases[i].gen
    /\ leases' = [leases EXCEPT ![i].near = TRUE]
    /\ UNCHANGED <<pc, ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

\* Time passes the current generation's expiry.
Expire(i) ==
    /\ i \in DOMAIN leases
    /\ (leases[i].near \/ ~NeedsNear(i)) /\ leases[i].expN <= leases[i].gen
    /\ BoundedStall =>
          LET c == leases[i].by
          IN ~(ctx[c] = "renew" /\ ~nearSeen[c]
               /\ pc[c] \in {"arbRunRead", "arbRunSup", "renPatch"})
    /\ leases' = [leases EXCEPT ![i].expN = @ + 1]
    /\ UNCHANGED <<pc, ctx, assignees, runDone, triageLogin, mine, snap, live,
                   cand, win, bodyGen, renewed, nearSeen, after, backedOffDone>>

Done ==
    /\ \A c \in Claimants : pc[c] \in Final \cup {"idle"}
    /\ UNCHANGED vars

Next ==
    \/ \E c \in Claimants :
          \/ Assign(c) \/ CheckRead(c) \/ ReAssign(c) \/ PostLease(c)
          \/ ReadLeases(c) \/ ArbJudge(c) \/ ArbRunRead(c) \/ ArbRunSup(c)
          \/ LossSup(c) \/ GLeases(c) \/ GList(c) \/ GJudge(c) \/ GARead(c)
          \/ GRm(c) \/ GRead2(c) \/ GList2(c) \/ GJudge2(c) \/ GAdd(c)
          \/ GRead3(c) \/ GList3(c) \/ GJudge3(c) \/ RelSup(c)
          \/ GRm3(c) \/ WinRead(c) \/ WinAdd(c) \/ TrapSup(c)
          \/ RenewStart(c) \/ RenewPatch(c) \/ Ren2Leases(c) \/ Ren2Judge(c)
          \/ RenSup(c) \/ ReleaseStart(c) \/ RelJudgeOwn(c) \/ RelPatch(c)
          \/ Die(c)
    \/ RunCompletes
    \/ \E i \in 1..3 : Approach(i) \/ Expire(i)
    \/ Done

Spec == Init /\ [][Next]_vars

\* A claimant between scripts never reads its script-local values again
\* before the next script overwrites them, so states differing only there
\* are one state.
View == <<pc, ctx, leases, assignees, runDone, triageLogin, mine, renewed,
          backedOffDone,
          [c \in Claimants |->
              IF pc[c] \in Final \cup {"idle", "held"} THEN <<>>
              ELSE <<snap[c], live[c], cand[c], win[c], bodyGen[c],
                     nearSeen[c], after[c]>>]>>

-----------------------------------------------------------------------------
\* Invariants

\* The claim returned success, no release returned success, and no renew told
\* the session it lost.
ClaimHeld(c) == pc[c] = "held"
                \/ (ctx[c] \in {"renew", "release"}
                    /\ pc[c] \notin {"released", "gone", "renLost"}
                                    \cup RenewPost \cup Guarded)

Holding(c) == /\ ClaimHeld(c)
              /\ mine[c] # 0
              /\ LiveNow(mine[c])
              /\ (c = "lane" => ~runDone)

\* A claim, renew or release has started and not yet returned.
InFlight(c) == pc[c] \notin Final \cup {"idle"}

Quiescent == \A c \in Claimants : pc[c] \in Final \cup {"idle", "held"}
AllFinished == \A c \in Claimants : pc[c] \in Final \cup {"idle"}

TypeOK ==
    /\ pc \in [Claimants -> Pcs]
    /\ ctx \in [Claimants -> {"claim", "renew", "release"}]
    /\ Len(leases) <= 3
    /\ \A i \in DOMAIN leases : leases[i] \in LeaseRec
    /\ assignees \subseteq Logins
    /\ runDone \in BOOLEAN
    /\ triageLogin \in {"human", "other"}
    /\ mine \in [Claimants -> 0..3]
    /\ \A c \in Claimants : /\ Len(snap[c]) <= 3
                            /\ \A i \in DOMAIN snap[c] : snap[c][i] \in SnapRec
    /\ live \in [Claimants -> SUBSET (1..3)]
    /\ cand \in [Claimants -> 0..3]
    /\ win \in [Claimants -> 0..3]
    /\ bodyGen \in [Claimants -> 0..1]
    /\ renewed \in [Claimants -> BOOLEAN]
    /\ nearSeen \in [Claimants -> BOOLEAN]
    /\ after \in [Claimants -> {"failed", "lost", "renLost", "released", "relFail"}]
    /\ backedOffDone \in [Claimants -> BOOLEAN]

\* CONTRACT.md "Lease protocol" step 4: "If an earlier live lease exists that
\* is not our own comment, the foreign lease wins"; claim.sh:156 "Earliest
\* LIVE lease wins."
OneHolder == Cardinality({c \in Claimants : Holding(c)}) <= 1

\* CONTRACT.md: "Lease-only (`--lease-only`): the claim posts the lease
\* comment and assigns no one."
LaneAssignsNoOne == "bot" \notin assignees

\* CONTRACT.md: "Claim = assignee (authenticated human user) + lease record."
\* Quiescent states only: the hand-back removes and restores a same-login
\* holder's assignee two calls apart.
HolderAssigned ==
    Quiescent =>
        \A c \in DefaultClaims :
            (pc[c] = "held" /\ Holding(c)) => LoginOf(c) \in assignees

\* claim.sh:78-79: "any failure before a successful lease-comment write
\* (step 3) would otherwise strand the issue assigned with no lease record".
\* Every assigned login belongs to a default claimant whose claim, renew or
\* release is still in flight, or that holds the item.
NoStrandedAssignee ==
    \A l \in assignees : \E c \in DefaultClaims : LoginOf(c) = l /\ InFlight(c)

\* CONTRACT.md step 4: "the foreign lease wins → supersede own comment, exit
\* `7`." The supersede is best-effort, so the rule assumes writes succeed.
LoserSupersedesOwn ==
    ~WritesMayFail =>
        \A c \in Claimants :
            (pc[c] \in {"lost", "failed", "dead"} /\ mine[c] # 0)
                => leases[mine[c]].sup

\* CONTRACT.md step 4: "A run whose `status` is `completed`, whatever its
\* conclusion, holds nothing".
CompletedRunHoldsNothing == \A c \in Claimants : ~backedOffDone[c]

\* CONTRACT.md, Release: "a session that has finished with an item hands it
\* back at once instead of blocking every later claim".
ReleaseFreesItem ==
    \A c \in Claimants : pc[c] = "released" => ~LiveNow(mine[c])

\* With every claimant finished and no lease live, any assignee left is the
\* holder of the active lease, which reclaim unassigns. claim.sh:80:
\* "reclaim ignores items with no lease".
EndStateReclaimable ==
    (AllFinished /\ \A i \in DOMAIN leases : ~LiveNow(i)) =>
        \A l \in assignees : ActiveNow # 0 /\ leases[ActiveNow].holder = l

=============================================================================
