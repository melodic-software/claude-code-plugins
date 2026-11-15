---------------------------- MODULE ClaimProtocol ----------------------------
(***************************************************************************)
(* One GitHub issue claimed at once by three claimants of the work-item   *)
(* tracker's GitHub adapter (CONTRACT.md "Lease protocol", claim.sh,      *)
(* release.sh):                                                           *)
(*   local  - a default claim from a local session (assigns, then leases) *)
(*   lane   - the issue lane's lease-only claim, session_id run-<id>      *)
(*   triage - a triage-phase claim, a default claim with --phase triage   *)
(* with lease expiry, release and the completed-run rule. Renew, reclaim  *)
(* and the other adapters are not modeled.                                *)
(*                                                                         *)
(* DRAFT: the invariants below wait for the owner's approval before this  *)
(* model is checked.                                                      *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

Claimants == {"local", "lane", "triage"}
DefaultClaims == {"local", "triage"}

VARIABLES
    pc,          \* each claimant's step
    leases,      \* the lease comments in id order; index = comment id
    assignees,   \* the logins assigned to the issue
    runDone,     \* the lane's workflow run has completed
    mine,        \* the index of each claimant's own lease comment, 0 before it posts
    lostTo,      \* the lease that beat a claimant in arbitration, 0 otherwise
    lostToDone,  \* whether the lane's run had completed when that claimant lost
    triageLogin  \* the triage session's login: the local session's, or another

vars == <<pc, leases, assignees, runDone, mine, lostTo, lostToDone, triageLogin>>

LoginOf(c) == CASE c = "local"  -> "human"
              []   c = "lane"   -> "bot"
              []   c = "triage" -> triageLogin

Steps == {"idle", "assigned", "checked", "posted", "won", "lost", "released"}

Lease == [by : Claimants, holder : {"human", "other", "bot"}, run : BOOLEAN,
          superseded : BOOLEAN, expired : BOOLEAN]

Live(i) == ~leases[i].superseded /\ ~leases[i].expired

Min(S) == CHOOSE i \in S : \A j \in S : i <= j
Max(S) == CHOOSE i \in S : \A j \in S : i >= j

\* The newest lease with no superseded_at (lib/lease.sh wit_select_active_lease).
Active == LET open == {i \in DOMAIN leases : ~leases[i].superseded}
          IN IF open = {} THEN 0 ELSE Max(open)

\* A claimant still doing the work its claim was for.
Proceeding(c) == /\ pc[c] = "won"
                 /\ Live(mine[c])
                 /\ (c = "lane" => ~runDone)

Init == /\ pc = [c \in Claimants |-> "idle"]
        /\ leases = <<>>
        /\ assignees = {}
        /\ runDone = FALSE
        /\ mine = [c \in Claimants |-> 0]
        /\ lostTo = [c \in Claimants |-> 0]
        /\ lostToDone = [c \in Claimants |-> FALSE]
        /\ triageLogin \in {"human", "other"}

\* Step 1: assign the session identity.
Assign(c) == /\ c \in DefaultClaims
             /\ pc[c] = "idle"
             /\ assignees' = assignees \cup {LoginOf(c)}
             /\ pc' = [pc EXCEPT ![c] = "assigned"]
             /\ UNCHANGED <<leases, runDone, mine, lostTo, lostToDone, triageLogin>>

\* Step 2: any other login assigned -> unassign self and back off.
CheckAssignees(c) ==
    /\ pc[c] = "assigned"
    /\ IF \E l \in assignees : l # LoginOf(c)
       THEN /\ assignees' = assignees \ {LoginOf(c)}
            /\ pc' = [pc EXCEPT ![c] = "lost"]
       ELSE /\ pc' = [pc EXCEPT ![c] = "checked"]
            /\ UNCHANGED assignees
    /\ UNCHANGED <<leases, runDone, mine, lostTo, lostToDone, triageLogin>>

\* Step 3: post the lease comment. The lane, lease-only, starts here.
Post(c) ==
    /\ \/ c \in DefaultClaims /\ pc[c] = "checked"
       \/ c = "lane" /\ pc[c] = "idle" /\ ~runDone
    /\ leases' = Append(leases, [by |-> c, holder |-> LoginOf(c), run |-> (c = "lane"),
                                 superseded |-> FALSE, expired |-> FALSE])
    /\ mine' = [mine EXCEPT ![c] = Len(leases) + 1]
    /\ pc' = [pc EXCEPT ![c] = "posted"]
    /\ UNCHANGED <<assignees, runDone, lostTo, lostToDone, triageLogin>>

\* Step 4: re-read the leases; the earliest live lease wins, except a lease
\* held by a completed run, which is superseded and passed over. The read and
\* the decision are one step here.
Arbitrate(c) ==
    /\ pc[c] = "posted"
    /\ (c = "lane" => ~runDone)
    /\ LET released(i) == i # mine[c] /\ leases[i].run /\ runDone
           cands == {i \in DOMAIN leases : Live(i) /\ ~released(i)}
           winner == IF cands = {} THEN 0 ELSE Min(cands)
           swept == {i \in DOMAIN leases :
                        Live(i) /\ released(i) /\ (winner = 0 \/ i < winner)}
           sweep == [i \in DOMAIN leases |->
                        IF i \in swept THEN [leases[i] EXCEPT !.superseded = TRUE]
                                       ELSE leases[i]]
       IN IF winner = 0 \/ winner = mine[c]
          THEN /\ pc' = [pc EXCEPT ![c] = "won"]
               /\ leases' = sweep
               /\ UNCHANGED <<assignees, lostTo, lostToDone>>
          ELSE /\ pc' = [pc EXCEPT ![c] = "lost"]
               /\ leases' = [sweep EXCEPT ![mine[c]].superseded = TRUE]
               /\ assignees' =
                    IF c \in DefaultClaims /\ leases[winner].holder # LoginOf(c)
                    THEN assignees \ {LoginOf(c)}
                    ELSE assignees
               /\ lostTo' = [lostTo EXCEPT ![c] = winner]
               /\ lostToDone' = [lostToDone EXCEPT ![c] = runDone]
    /\ UNCHANGED <<runDone, mine, triageLogin>>

\* The claimant is done: a default claimant clears its own assignee, then
\* release supersedes its lease only when it is the active lease and live.
Release(c) ==
    /\ pc[c] = "won"
    /\ (c = "lane" => ~runDone)
    /\ pc' = [pc EXCEPT ![c] = "released"]
    /\ assignees' = IF c \in DefaultClaims THEN assignees \ {LoginOf(c)} ELSE assignees
    /\ leases' = IF Active = mine[c] /\ Live(mine[c])
                 THEN [leases EXCEPT ![mine[c]].superseded = TRUE]
                 ELSE leases
    /\ UNCHANGED <<runDone, mine, lostTo, lostToDone, triageLogin>>

\* The lane's run ends after its lease is posted (completed, cancelled or
\* timed out) without releasing.
RunCompletes ==
    /\ pc["lane"] \in {"posted", "won", "lost", "released"}
    /\ ~runDone
    /\ runDone' = TRUE
    /\ UNCHANGED <<pc, leases, assignees, mine, lostTo, lostToDone, triageLogin>>

\* A lease's TTL elapses.
Expire(i) ==
    /\ Live(i)
    /\ leases' = [leases EXCEPT ![i].expired = TRUE]
    /\ UNCHANGED <<pc, assignees, runDone, mine, lostTo, lostToDone, triageLogin>>

\* Every claimant has finished; nothing changes.
Finished ==
    /\ \A c \in Claimants : pc[c] \in {"lost", "released"} \/ (c = "lane" /\ runDone)
    /\ UNCHANGED vars

Next ==
    \/ \E c \in Claimants : Assign(c) \/ CheckAssignees(c) \/ Post(c)
                            \/ Arbitrate(c) \/ Release(c)
    \/ RunCompletes
    \/ \E i \in DOMAIN leases : Expire(i)
    \/ Finished

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* DRAFT invariants. Each quotes the contract or code line it encodes.    *)

TypeOK ==
    /\ pc \in [Claimants -> Steps]
    /\ \A i \in DOMAIN leases : leases[i] \in Lease
    /\ assignees \subseteq {"human", "other", "bot"}
    /\ runDone \in BOOLEAN
    /\ mine \in [Claimants -> 0..3]
    /\ lostTo \in [Claimants -> 0..3]

\* CONTRACT.md: "If an earlier live lease exists that is not our own comment,
\* the foreign lease wins -> supersede own comment, exit `7`." (arrow in ASCII)
\* claim.sh: "# Earliest LIVE lease wins."
OneHolder == Cardinality({c \in Claimants : Proceeding(c)}) <= 1

\* CONTRACT.md: "Lease-only (`--lease-only`): the claim posts the lease
\* comment and assigns no one."
LaneAssignsNoOne == "bot" \notin assignees

\* CONTRACT.md: "Claim = **assignee (authenticated human user) + lease record**."
HolderAssigned ==
    \A c \in DefaultClaims : Proceeding(c) => LoginOf(c) \in assignees

\* claim.sh: "any failure between this successful assignment and a successful
\* lease-comment write (step 3) would otherwise strand the issue assigned with
\* no lease record"
NoStrandedAssignee ==
    \A l \in assignees : \E c \in DefaultClaims :
        LoginOf(c) = l /\ pc[c] \in {"assigned", "checked", "posted", "won"}

\* CONTRACT.md: "the foreign lease wins -> supersede own comment, exit `7`." (arrow in ASCII)
LoserSupersedesOwn ==
    \A c \in Claimants : (pc[c] = "lost" /\ mine[c] # 0) => leases[mine[c]].superseded

\* CONTRACT.md: "A run whose `status` is `completed`, whatever its conclusion,
\* holds nothing, so its lease is superseded in place"
CompletedRunHoldsNothing ==
    \A c \in Claimants : lostTo[c] # 0 => ~(leases[lostTo[c]].run /\ lostToDone[c])

\* CONTRACT.md: "a session that has finished with an item hands it back at once
\* instead of blocking every later claim"
ReleaseFreesItem ==
    \A c \in Claimants : pc[c] = "released" => ~Live(mine[c])

=============================================================================
