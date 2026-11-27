# render-report.jq: the fixed-section sync and audit report, as a pure function
# of sync-run.sh's digest. fixtures/render/ holds a golden of each shape.
#
#   jq -r -f render-report.jq <run_dir>/digest.json
#
# sync-run.sh runs this once per invocation, writes the result to
# <run_dir>/report.txt, and prints it after the digest under `--render`. The
# same command reproduces the report from a run directory later.
#
# Every section, row, annotation and `Action needed` bullet is derived from a
# digest field; nothing here is judgment, so the report cannot misstate a
# number, an id, or a scope the digest carries. In audit mode every call sync
# would make is a predicted row, printed as `would run:` and the row's label,
# the command as sync-run.sh records it. A remedy sync never runs itself (the
# `git -C … pull`, a project-scope enable) is the operator's in both modes and
# carries no prefix, since sync would not run it either; a pull the user agreed
# to, which the script ran, renders as a `fast-forwarded:` row instead.
#
# Layout, for a pasted monospace block with no color: the `Result:` verdict,
# then `Action needed`, then what the run changed (in audit, would change),
# then each marketplace's state, then what it leaves as it is, then the `Run`
# footer, then the reload lines. Sections are separated by one blank line and
# headed by a line with their item count; a section's `label:` values share
# one column. Each line carries one fact, and a remedy gets its own `remedy:`
# line under the fact it fixes. No line is wrapped by hand, and every
# character is ASCII except text the digest carries. A path under the
# digest's `home` prints as `~/...`; a command never does, since a quoted `~`
# does not expand.
#
# verdict.jq classifies the digest (status, pending and changed, the install and
# enable outcomes, every `Action needed` item); this program lays those facts
# and the digest's rows out as lines.
#
# It formats only the digest shape of digest-contract.json's `digest_version`;
# a digest of any other version gets one line pointing at the report.txt its
# own run wrote.

include "verdict" {search: "./"};
import "digest-contract" as $contract {search: "./"};

# Rows past this count print as one `+N more` line naming the file that holds
# them all.
def list_cap: 3;

def secs: if . == null then "n/a" else "\(.)s" end;
def pair: "\(.old) -> \(.new)" + (if .direction == "unknown" then " (direction unknown)" else "" end);
def auto_update_slot:
  if . == true then "on" elif . == false then "off" else "unreadable" end;
def short_sha: (. // "?") | .[0:12];
def tilde($home):
  if ($home | type) != "string" or $home == "" or $home == "/" or (type) != "string" then .
  elif . == $home then "~"
  elif startswith($home + "/") then "~" + .[($home | length):]
  else . end;
def pad($n): . + (" " * ([$n - length, 0] | max));
def lpad($n): (" " * ([$n - length, 0] | max)) + .;

# A row: `label:` and its value, `cont` lines aligned under the value, then
# `sub` lines (remedies, member rows) indented under the label.
def row($label; $value): {label: $label, value: $value, cont: [], sub: []};
def subs($lines): .sub += $lines;
def conts($lines): .cont += $lines;

def rows_lines:
  ([.[] | .label | length + 1] | max // 0) as $w
  | .[]
  | "  " + ("\(.label):" | pad($w)) + "  " + .value,
    (.cont[] | "  " + ("" | pad($w)) + "  " + .),
    (.sub[] | "    " + .);
def section($heading; $rows):
  if ($rows | length) == 0 then empty
  else ["\($heading) (\($rows | length))"] + [$rows | rows_lines] end;

# Columns: every cell but the last is padded to its column's widest; a cell
# array's `right` positions are right-aligned.
def columns($right):
  (.[0] | length) as $n
  | [range($n - 1) as $i | [.[][$i] | length] | max] as $w
  | .[]
  | [range($n) as $i | .[$i] as $c
     | if $i == $n - 1 then $c
       elif ($right | index($i)) != null then $c | lpad($w[$i])
       else $c | pad($w[$i]) end]
  | join("  ");

def bullet($prefix): "  - \($prefix)\(.[0])", (.[1:][] | "    \(.)");

# The slowest timed step of a block's timings object, or null.
def slowest_step:
  [to_entries[]
   | select(.key != "total" and .key != "resolution" and .key != "unattributed" and .value != null)]
  | if length == 0 then null else max_by(.value) end;

# One marketplace block as {changed, state, left} row lists, from the block and
# its classified facts $v.
def block_rows($d; $v):
  . as $b
  | ($d.mode == "audit") as $audit
  | ($d.home // "") as $home
  | (.in_repo.updated + .user_sweep.updated) as $updated
  | (.in_repo.would_update + (.user_sweep.would_update | map(. + {scope: "user"}))) as $would
  | .user_sweep.withheld_downgrades as $withheld
  | .other_paths as $op
  | (.normalize // {}) as $norm
  | .source_checkout as $src
  | .source_pull as $pull
  | .divergences as $div
  | (.name as $n | any($d.quiet_auto_update[]; . == $n)) as $quiet
  | ($withheld | length) as $nw
  | "would withhold" as $wh_label
  | (("\($nw) downgrade(s)"
      + (if $audit and $d.allow_downgrade then " (--allow-downgrade ignored: audit issues no update either way)" else "" end))) as $wh_value
  | (if ($norm.moved) == null then "\($norm.keys // "?") keys" else "\($norm.moved) of \($norm.keys // "?") keys" end) as $norm_count

  # Divergence lines: the split by what can be done, the split by origin, then
  # one aligned row per project path holding a skewed record.
  | (($div.actionable_here // 0) + ($div.actionable_elsewhere // 0)) as $actionable
  | ((.divergences.by_path // []) as $paths
     | .divergences.blocked_paths as $absent
     | if ($paths | length) == 0 and ($absent.paths // 0) == 0 then []
       else
         ["by project path (diverging records, first ids):"]
         + ($paths[:list_cap]
            | map([(.path | tilde($home)) + (if .class == "worktree" then " (linked worktree)" else "" end),
                   "\(.count)",
                   (.ids | join(", ")) + (if (.more // 0) > 0 then ", +\(.more) more" else "" end)])
            | if length == 0 then [] else [columns([1])] | map("  " + .) end)
         + (if ($paths | length) > list_cap then
              ["  +\(($paths | length) - list_cap) more path(s): "
               + (if .divergences.records_file == null then "in the digest's divergences.by_path"
                  else .divergences.records_file | tilde($home) end)]
            else [] end)
         + (if ($absent.paths // 0) > 0 then
              ["  \($absent.paths) path(s) not present: \($absent.records) diverging record(s), counted under stale project records"]
            else [] end)
       end) as $by_path
  | (["by origin:", "  \($div.pre_existing) pre-existing", "  \($div.new_total) newly created by this run"]
     + (if ($div.new_total // 0) > 0 then
          ["    \($div.new_by_interval.in_repo) by the in-repo update",
           "    \($div.new_by_interval.user_sweep) by the user-scope sweep"]
          + (if ($div.new_by_interval.concurrent // 0) > 0
             then ["    \($div.new_by_interval.concurrent) moved during this run, cause unattributed"] else [] end)
        else [] end)) as $origin

  | (.cache_content as $c | ("\($c.scope // "user")-scope install(s)")) as $installs

  | {
      changed: [
        (if $pull.status == "pulled" then
           row("fast-forwarded"; "\($src.path | tilde($home)) from \($pull.from | short_sha) to \($pull.to | short_sha) with git pull --ff-only, before the refresh")
         else empty end),
        (if $audit then
           (if ($would | length) > 0 then
              row("would update"; "\($would | length) plugin(s)")
              | subs([$would[] | "would run: \(.label) (installed \(.installed))"])
            else empty end),
           (if $nw > 0 then
              row($wh_label; $wh_value)
              | subs([$withheld[] | "- \(scoped): \(.installed) -> \(.catalog) (catalog moved backward)"])
            else empty end),
           (if ($op.would_update | length) > 0 then
              row("would update in other paths"; "\($op.would_update | length) record(s)")
              | subs([$op.would_update[] | "would run: \(.label) (installed \(.old))"])
            else empty end),
           (if ($v.installed.predicted | length) > 0 then
              row("would install"; "\($v.installed.predicted | length) new catalog plugin(s) (policy install_new: all)")
              | subs([$v.installed.predicted[] | "would run: \(.label)"]
                     + ["once installed, a later sync would reinstall any of these you uninstall",
                        "  remedy: to keep one out, disable it instead of uninstalling"])
            else empty end),
           (if $norm.status == "would-normalize" then
              row("would normalize"; "user enabledPlugins key order, \($norm_count) would move")
              | subs(["would run: normalize-enabled-plugins.sh"])
            else empty end),
           (if ($v.enabled.predicted | length) > 0 then
              row("would enable"; "\($v.enabled.predicted | length) plugin(s)")
              | subs([$v.enabled.predicted[] | "would run: \(.label)"])
            else empty end)
         else
           (if ($updated | length) > 0 then
              row("updated"; "\($updated | length) plugin(s)") | subs([$updated[] | "- \(scoped): \(pair)"])
            else empty end),
           (if ($op.updated | length) > 0 then
              row("updated in other paths"; "\($op.updated | length) record(s)")
              | subs([$op.updated[] | "- \(scoped) in \(.path | tilde($home)): \(.old) -> \(.new)"])
            else empty end),
           (if (.downgraded | length) > 0 then
              row("downgraded"; "\(.downgraded | length) plugin(s)")
              | subs([$b.downgraded[] | "- \(scoped): \(.old) -> \(.new)"
                      + (if .concurrent == true then " (moved during this run)" else "" end)])
            else empty end),
           (if ($v.installed.ok | length) > 0 then
              listed("\($v.installed.ok | length) new catalog plugin(s)"; $v.installed.ok) as $l
              | row("installed"; $l[0])
              | subs($l[1:]
                     + (if $d.install_new != "all" then []
                        else
                          ["policy install_new: all, so the next sync reinstalls any of these you uninstall"]
                          + (if ($v.installed.ok - $v.installed_disabled | length) == 0 then
                               ["leaving them installed and not enabled keeps them off unless a project or local setting enables them"]
                             else
                               ["  remedy: to keep one out, disable it with claude plugin disable <id> -s user instead of uninstalling"]
                             end)
                        end)
                     + (if ($v.installed_disabled | length) > 0 then
                          listed("installed but not enabled"; $v.installed_disabled) | .[0:1] + (.[1:] | map("  " + .))
                        else [] end))
            else empty end),
           (if $norm.status == "normalized" then
              row("normalized"; "user enabledPlugins key order, "
                  + (if $norm.moved == null then "\($norm.keys // "?") keys reordered" else "\($norm_count) moved" end))
            else empty end),
           (if ($v.enabled.ok | length) > 0 then
              listed("\($v.enabled.ok | length) plugin(s)"; $v.enabled.ok | map(scoped)) as $l
              | row("enabled"; $l[0]) | subs($l[1:])
            else empty end)
         end)
      ],

      state: [
        row("status"; {needs_update: "needs update", source_behind: "source checkout behind \($src.upstream)"}[$v.status] // "current"),
        # `$quiet`: the user silenced the enable-it suggestion for this marketplace.
        (row("autoUpdate"; .auto_update | auto_update_slot)
         | if .value == "off" and ($quiet | not) then
             subs(["remedy: enable autoUpdate so the catalog refreshes automatically"])
           else . end),
        (if $v.pending > 0 then row("pending"; "\($v.pending) action(s)") else empty end),
        # A directory source is read as it is on disk; these lines say how fresh that is.
        (if $src == null then empty
         elif $src.state == "not_a_repo" then
           row("source"; "directory \($src.path | tilde($home))") | subs(["not a git work tree, freshness not checked"])
         else
           row("source"; "directory \($src.path | tilde($home))")
           | subs([if $src.state == "detached" then "a git checkout at a detached HEAD, freshness not checked"
                   elif $src.state == "no_upstream" then "a git checkout on \($src.branch) with no upstream, freshness not checked"
                   else "on \($src.branch), \($src.behind) behind and \($src.ahead) ahead of \($src.upstream) as of its last fetch" end]
                  + (if $src.dirty then ["tracked files modified"] else [] end)
                  + (if $pull.status == "pulled" then []
                     elif $pull.status == "failed" then ["a requested git pull --ff-only failed, see Action needed"]
                     else ["this run does not fetch or pull it"] end))
         end),
        (if $audit then
           row("refresh"; "would run: \(.refresh.label)")
           | subs(["predicted against the unrefreshed catalog (lastUpdated \($b.catalog_last_updated // "unknown")), a lower bound on what sync would update"])
         elif .refresh.rc != null and .refresh.rc != 0 then
           row("refresh"; "failed (exit \(.refresh.rc)): \(.refresh | reported)")
         elif .refresh.skipped != null then
           row("refresh"; "skipped, the clone is at \(.refresh.skipped.head | short_sha), where origin \(.refresh.skipped.ref) points")
         else empty end),
        # The in-repo row: four variants, picked by two digest fields and the mode.
        row("in-repo";
          if .project_root == null then "skipped, no project context resolved from \($d.cwd | tilde($home))"
          elif .in_repo_records == null then "unknown, no fleet-state snapshot was read for this marketplace"
          elif .in_repo_records == 0 then "0, \(.project_root | tilde($home)) has no project/local installs"
          elif $audit then "\(.in_repo.would_update | length) project/local install(s) would be updated in \(.project_root | tilde($home))"
          else "\(.in_repo.updated | length) project/local install(s) updated in \(.project_root | tilde($home))" end),
        (if $audit and ($would | length) == 0 then row("would update"; "0 plugin(s)") else empty end),
        # The `would withhold` row prints beside `would update` whether or not a downgrade was found.
        (if $audit and $nw == 0 then row($wh_label; $wh_value) else empty end),
        # An id whose update call the CLI answered "already at the latest version" while
        # the run's snapshots show its version differing from the pre-mutation one. Nothing
        # here says what moved it. A backward one is listed under downgraded too.
        (.moved_during_run as $moved
         | if ($moved | length) > 0 then
             row("moved during this run"; "\($moved | length) plugin(s), by something other than this run's update calls")
             | subs([$moved[] | "- \(scoped): \(pair)"
                     + (if .direction == "backward" then " (backward, also under downgraded)" else "" end)])
           else empty end),
        (if .noop_unverified > 0 then
           row("not verified"; "\(.noop_unverified) plugin(s) the CLI called already current could not be checked against a snapshot version")
         else empty end),
        (if .catalog_regression != null then
           row("catalog regression"; .catalog_regression.interval)
           | subs([$b.catalog_regression.rows[] | split(" ") | "- \(.[0]): \(.[1]) -> \(.[2])"])
         else empty end),
        (if .self_updated == true then
           row("self-update"; "\(.self_update.id | split("@")[0]) (\(.self_update.old // "?") -> \(.self_update.new // "?")) moved during this run")
           | subs(["the algorithm that ran is the pre-update one: ${CLAUDE_PLUGIN_ROOT} still resolves to the version loaded at session start",
                   "remedy: /reload-plugins before relying on the new version"])
         else empty end),
        (if $norm.status == "missing-file" then row("normalize"; "skipped, no user settings file") else empty end),
        (if $div.post == null then row("divergences"; "not computed (\($div.note // "a snapshot was missing"))") | subs($by_path)
         elif $div.post == 0 then row("divergences"; "0 actionable") | subs($by_path)
         else empty end),
        (.cache_content as $c
         | if $c == null or ($c.stale_content // 0) > 0 then empty
           elif ($c.unverifiable // 0) > 0 or ($c.not_checked // 0) > 0 then
             row("cache content"; "\($c.match) of \($c.checked) \($installs) compared, no disagreement found")
             | conts([if ($c.not_checked // 0) > 0 then "\($c.not_checked) not checked (recorded at an older commit)" else empty end,
                      if ($c.unverifiable // 0) > 0 then "\($c.unverifiable) unverifiable, which is not a pass" else empty end])
           else empty end)
      ],

      left: [
        (.in_repo.live_read[] as $r
         | $r | row("read live"; "\(.id) (\(.scope)) from \(.path | tilde($home))")
         | subs(["project record pinned at \($r.installed), which the CLI will not update",
                 "remedy: remove and re-add the project record if the pin matters"])),
        # The records of every other present path, updated from that path.
        (if $op.skipped.records > 0 then
           row("behind in other paths"; "\($op.skipped.records) record(s) in \($op.skipped.paths) path(s), not updated")
           | subs(["remedy: /harness-ops:plugins sync --update-other-paths"])
         else empty end),
        (if $op.catalog_moved > 0 then
           row("catalog moved during this run"; "\($op.catalog_moved) plugin(s), records updated before the move lag it")
         else empty end),
        (if ($audit | not) and ($op.not_moved | length) > 0 then
           row("not moved in other paths"; "\($op.not_moved | length) record(s)")
           | subs([$op.not_moved[] | "- \(scoped) in \(.path | tilde($home)): did not move from \(.version) (\(.label))"])
         else empty end),
        # The divergences row counts version-skewed rows only (versionsMatch false). The count is split
        # by what can be done about each row, so only the actionable part points at
        # converge, and again by interval, so the run-caused share is visible.
        (if ($div.post // 0) > 0 then
           row("divergences"; "\($div.post) in all")
           | subs((if $actionable > 0 then
                     ["\($actionable) actionable"]
                     + (if ($div.actionable_here // 0) > 0 then ["  \($div.actionable_here) here"] else [] end)
                     + (if ($div.actionable_elsewhere // 0) > 0 then ["  \($div.actionable_elsewhere) elsewhere on this machine"] else [] end)
                     + ["  remedy: run `/harness-ops:plugins converge`"]
                   else [] end)
                  + (if ($div.in_worktrees // 0) > 0 then
                       ["\($div.in_worktrees) in linked worktrees",
                        "  remedy: remove the worktree",
                        "  remedy: /source-control:worktree audit (if installed) classifies them"]
                     else [] end)
                  + (if ($div.blocked // 0) > 0 then
                       ["\($div.blocked) blocked, path not present",
                        "  remedy: see stale project records below"]
                     else [] end)
                  + $origin + $by_path)
         else empty end),
        # Why these records are not divergences, and why an absent path is not proof
        # the directory is gone, is context/stale-records-cache-content.md's, not the render's.
        (if .stale_project_records.total > 0 then
           .stale_project_records as $s
           | (if $audit then "not kept, the audit scratch directory is removed on exit"
              elif $s.list_file == null then "not written this run"
              else $s.list_file | tilde($home) end) as $list
           | row("stale project records"; "\($s.total) record(s) across \($s.paths) path(s) not present on this machine")
           | ([$s.by_parent[].count | tostring | length] | max // 0) as $cw
           | subs(($s.by_parent | map([(.parent | tilde($home)), "\(.count | tostring | lpad($cw)) record(s) across \(.paths) path(s)"])
                   | if length == 0 then [] else [columns([])] end)
                  + (if $s.more_parents > 0 then ["+\($s.more_parents) more parent director(ies): \($list)"]
                     else ["full per-path list: \($list)"] end)
                  # Only project-scope records under the source-control worktree root are that
                  # audit's to classify, so the pointer needs a project-scope record and says
                  # which of them it covers.
                  + (if $s.project > 0 then
                       ["\($s.project) project-scope record(s)",
                        "  remedy: /source-control:worktree audit (if installed) classifies those left by worktrees removed under the source-control worktree root, and gives the gated reap"]
                     else [] end)
                  + (if $s["local"] > 0 then ["\($s["local"]) local-scope record(s), which nothing reaps yet"] else [] end))
         else empty end),
        # Why converge blocks these rows is context/scope-semantics.md's, not the render's.
        (if .user_home_records.total > 0 then
           row("user-home project records"; "\(.user_home_records.total) record(s) keyed to a user home directory")
           | subs([$b.user_home_records.paths[] | "- \(tilde($home))"])
         else empty end),
        (.cache_content as $c
         | if $c == null or ($c.stale_content // 0) == 0 then empty
           else
             row("cache content"; "\($c.stale_content) \($installs) whose cache files disagree with their recorded gitCommitSha")
             | subs([$c.stale[] | (if .files_differ == null then "- \(.id)" else "- \(.id) \(.version): \(.files_differ) file(s) differ" end)
                                  + (if .unreleased_changes == true then " (unreleased changes pending)" else "" end)]
                    + (if ($c.unverifiable // 0) > 0 or ($c.not_checked // 0) > 0 then
                         ["\($c.checked) \($installs) checked", "  \($c.match) match"]
                         + (if ($c.unverifiable // 0) > 0 then ["  \($c.unverifiable) unverifiable, which is not a pass"] else [] end)
                         + (if ($c.not_checked // 0) > 0 then ["  \($c.not_checked) not checked (recorded at an older commit)"] else [] end)
                       else [] end)
                    + (if any($c.stale[]; .unreleased_changes == true) then
                         ["unreleased changes pending: the marketplace holds changelog fragments for that plugin, so its files changed without a version bump",
                          "  remedy: leave its cache alone, its next release brings the cache up to date"]
                       else [] end)
                    + (if any($c.stale[]; .unreleased_changes != true) then
                         ["remedy\(if any($c.stale[]; .unreleased_changes == true) then ", for the rows not marked unreleased" else "" end): remove that version's directory under the plugin cache, then re-run `claude plugin update <id>@<marketplace>`, which recreates it from the clone"]
                       else [] end))
           end)
      ]
    };

# The footer's timing rows for one block; `$pre` names the marketplace when the
# run has more than one.
def block_timing_rows($pre; $resolution):
  .timings as $t
  | (if $pre == "" then "marketplace block" else "\($pre)block" end) as $block
  | if $t == null then row($block; "n/a")
    else
      ($t | slowest_step) as $slow
      | row($block; $t.total | secs),
        (if $slow == null then empty else row("\($pre)slowest step"; "\($slow.key) \($slow.value)s") end),
        (if $t.unattributed == null then empty else row("\($pre)outside the steps"; "\($t.unattributed)s") end),
        (if $t.resolution == $resolution then empty else row("\($pre)clock resolution"; $t.resolution) end)
    end;

def format_run:
. as $d
| ($d.mode == "audit") as $audit
| ($d.home // "") as $home
| classify as $v
| ($d.marketplaces | length) as $n
| [range($n) as $i | $d.marketplaces[$i] | block_rows($d; $v.blocks[$i])] as $parts
| (if $n > 1 then [$d.marketplaces[] | "\(.name): "] else [""] end) as $prefix
| ($d.timings.passes // null) as $passes
| [
    [({action_needed: "Result: \($v.run.action_count) item(s) under Action needed",
       predicted: "Result: see the predictions below, nothing under Action needed",
       no_change_predicted: "Result: no change predicted, a lower bound against the unrefreshed catalog",
       changed: "Result: changes applied, nothing under Action needed",
       clean: "Result: clean, nothing changed and nothing under Action needed"}[$v.run.result]),
     (if $audit then "Audit (read-only): every call sync would make is a prediction, prefixed would run:" else empty end)],

    (if $v.run.action_count == 0 then empty
     else
       ["Action needed (\($v.run.action_count))"]
       + [range($n) as $i | $v.blocks[$i].actions[].lines | bullet($prefix[$i])]
       + [$v.run.actions[].lines | bullet("")]
     end),

    (range($n) as $i
     | section((if $audit then "Would change" else "Changed by this run" end)
               + (if $n > 1 then ": \($d.marketplaces[$i].name)" else "" end);
               $parts[$i].changed)),

    (range($n) as $i
     | ["Marketplace: \($d.marketplaces[$i].name)"] + [$parts[$i].state | rows_lines]),
    # A marketplace whose block could not be assembled did resolve; its error
    # under Action needed names it. The text matched is the run_error wording in
    # sync-run.sh's emit_marketplace_block: change both together.
    (if $n == 0 and ([$d.errors[] | select(test("its report block could not be assembled"))] | length) == 0
     then ["Marketplace: none resolved for this run"] else empty end),

    (range($n) as $i
     | section("Left as they are" + (if $n > 1 then ": \($d.marketplaces[$i].name)" else "" end);
               $parts[$i].left)),

    # A re-entry digest times both passes; the block rows time the re-entry alone.
    (["Run"]
     + ([row("journal"; if $audit then "audit scratch directory, removed on exit" else $d.run_dir | tilde($home) end),
         row("total"; ($d.timings.total | secs)
                      + (if $passes == null then "" else " over both passes (the wait between them is not counted)" end)),
         (if $passes == null then empty
          else row("first pass"; $passes[0].total | secs), row("re-entry"; $passes[1].total | secs) end),
         ($d.marketplaces[] | block_timing_rows(if $n > 1 then "\(.name) " else "" end; $d.timings.resolution)),
         (if $d.timings.outside_marketplaces == null then empty
          else row("outside the blocks"; "\($d.timings.outside_marketplaces)s") end),
         row("clock resolution"; $d.timings.resolution)]
        | [rows_lines])),

    # A two-step, not a guess at which change makes the bare reload warn.
    (if $v.run.reload | not then empty
     else
       [(if $audit then "Reload: after sync applies these, run /reload-plugins"
         else "Reload: run /reload-plugins to load these changes into this session" end),
        "  if it warns, rerun it as /reload-plugins --force"]
     end)
  ]
| map(join("\n"))
| join("\n\n");

$contract::contract[0].run.digest_version as $current
| if .digest_version == $current then format_run
  else "This digest predates this renderer (digest_version \(.digest_version // "none"), renderer \($current)): read report.txt in the same run directory, or re-run /harness-ops:plugins sync"
  end
