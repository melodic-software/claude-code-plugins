# render-report.jq: the fixed-section sync and audit report, as a pure function
# of sync-run.sh's digest. fixtures/render/ holds a golden of each shape.
#
#   jq -r -f render-report.jq <run_dir>/digest.json
#
# sync-run.sh runs this once per invocation, writes the result to
# <run_dir>/report.txt, and prints it after the digest under `--render`. The
# same command reproduces the report from a run directory at any later time.
#
# Every section, conditional row, annotation and `Action needed` bullet is
# derived from a digest field; nothing here is judgment, so the report cannot
# misstate a number, an id, or a scope the digest carries. In audit mode every
# call sync would make is a predicted row, printed as `would run:` and the
# row's label, the command as sync-run.sh records it. A remedy sync never runs
# itself (the `git -C … pull`, a project-scope enable) is the operator's in both
# modes and carries no prefix, since sync would not run it either; a pull the
# user agreed to, which the script ran, renders on the source row instead. The
# `Would withhold` row appears beside `Would update` whether or not a downgrade
# was found. Errors in a block's `errors[]` render under that block's
# `Action needed`; the run's own `errors[]` render under the trailing one.
#
# Layout: the report opens with a one-line `Result:` verdict. Each line carries
# one fact; a part of a multi-part row gets its own indented line under it, and
# a remedy gets its own `remedy:` line under the fact it fixes. No line is
# wrapped by hand, and every character is ASCII except text the digest carries.
#
# The one report line this program does not carry is the reload guidance,
# which the caller appends after the render.
#
# verdict.jq classifies the digest (status, pending and changed, the install and
# enable outcomes, every `Action needed` item); this program lays those facts
# and the digest's rows out as lines.

include "verdict" {search: "./"};

def secs: if . == null then "n/a" else "\(.)s" end;
def pair: "\(.old) -> \(.new)" + (if .direction == "unknown" then " (direction unknown)" else "" end);
# An `Action needed` item, an array of lines: the first is the bullet, the rest
# sit under it.
def bullet: "  - \(.[0])", (.[1:][] | "    \(.)");
def auto_update_slot:
  if . == true then "on" elif . == false then "off" else "unreadable" end;
def short_sha: (. // "?") | .[0:12];

# The slowest timed step of a block's timings object, or null.
def slowest_step:
  [to_entries[]
   | select(.key != "total" and .key != "resolution" and .key != "unattributed" and .value != null)]
  | if length == 0 then null else max_by(.value) end;

# One marketplace block's lines, from the block and its classified facts $v.
def format_block($d; $v):
  ($d.mode == "audit") as $audit
  | (.in_repo.updated + .user_sweep.updated) as $updated
  | (.in_repo.would_update + (.user_sweep.would_update | map(. + {scope: "user"}))) as $would
  | .user_sweep.withheld_downgrades as $withheld
  | .other_paths as $op
  | (.normalize | norm_fields) as $norm
  | .timings as $t
  | .source_checkout as $src
  | .source_pull as $pull
  | (.name as $n | any($d.quiet_auto_update[]; . == $n)) as $quiet
  | [
      "Marketplace: \(.name): \({needs_update: "needs update", source_behind: "source checkout behind \($src.upstream)"}[$v.status] // "current")"
      + (if $v.pending > 0 then ", \($v.pending) action(s) pending" else "" end)
      + " (autoUpdate: \(.auto_update | auto_update_slot))",
      # `$quiet`: the user silenced the enable-it suggestion for this marketplace.
      (if .auto_update == false and ($quiet | not) then
         "  remedy: enable autoUpdate so the catalog refreshes automatically"
       else empty end),
      # A directory source is read as it is on disk; these rows say how fresh that is.
      (if $src == null then empty
       elif $src.state == "not_a_repo" then
         "  source: directory \($src.path)",
         "    not a git work tree, freshness not checked"
       else
         "  source: directory \($src.path)",
         (if $src.state == "detached" then "    a git checkout at a detached HEAD, freshness not checked"
          elif $src.state == "no_upstream" then "    a git checkout on \($src.branch) with no upstream, freshness not checked"
          else "    on \($src.branch), \($src.behind) behind and \($src.ahead) ahead of \($src.upstream) as of its last fetch" end),
         (if $src.dirty then "    tracked files modified" else empty end),
         (if $pull.status == "pulled" then
            "    fast-forwarded by this run from \($pull.from | short_sha) to \($pull.to | short_sha) with git pull --ff-only, before the refresh"
          elif $pull.status == "failed" then
            "    a requested git pull --ff-only failed, see Action needed"
          else "    this run does not fetch or pull it" end)
       end),
      (if $audit then
         "  would run: \(.refresh.label)",
         "    predicted against the unrefreshed catalog (lastUpdated \(.catalog_last_updated // "unknown")), a lower bound on what sync would update"
       elif .refresh.rc != null and .refresh.rc != 0 then
         "  refresh failed (exit \(.refresh.rc)): \(.refresh | reported)"
       elif .refresh.skipped != null then
         "  refresh skipped: the clone is at \(.refresh.skipped.head | short_sha), where origin \(.refresh.skipped.ref) points"
       else empty end),

      # In-repo: a fixed row with three variants, picked by two digest fields.
      (if .project_root == null then
         "In-repo: skipped: no project context resolved from \($d.cwd)"
       elif .in_repo_records == null then
         "In-repo: unknown: no fleet-state snapshot was read for this marketplace"
       elif .in_repo_records == 0 then
         "In-repo: 0: \(.project_root) has no project/local installs"
       elif $audit then
         "In-repo: \(.in_repo.would_update | length) project/local install(s) would be updated in \(.project_root)"
       else
         "In-repo: \(.in_repo.updated | length) project/local install(s) updated in \(.project_root)"
       end),

      (.in_repo.live_read[] |
         "  \(.id) (\(.scope)): read live from \(.path)",
         "    project record pinned at \(.installed), which the CLI will not update",
         "    remedy: remove and re-add the project record if the pin matters"),

      (if $audit then
         "Would update: \($would | length) plugin(s)",
         ($would[] | "  would run: \(.label) (installed \(.installed))"),
         ("Would withhold: \($withheld | length) downgrade(s)"
          + (if $d.allow_downgrade then " (--allow-downgrade ignored: audit issues no update either way)" else "" end)),
         ($withheld[] | "  - \(scoped): \(.installed) -> \(.catalog) (catalog moved backward)")
       else
         (if ($updated | length) > 0 then
            "Updated: \($updated | length) plugin(s)",
            ($updated[] | "  - \(scoped): \(pair)")
          else empty end)
       end),

      # The records of every other present path, updated from that path.
      (if $op.skipped.records > 0 then
         "Behind in other paths: \($op.skipped.records) record(s) in \($op.skipped.paths) path(s), not updated",
         "  remedy: /harness-ops:plugins sync --update-other-paths"
       else empty end),
      (if $op.catalog_moved > 0 then
         "Catalog moved during this run: \($op.catalog_moved) plugin(s), records updated before the move lag it"
       else empty end),
      (if $audit then
         (if ($op.would_update | length) > 0 then
            "Would update in other paths: \($op.would_update | length) record(s)",
            ($op.would_update[] | "  would run: \(.label) (installed \(.old))")
          else empty end)
       else
         (if ($op.updated | length) > 0 then
            "Updated in other paths: \($op.updated | length) record(s)",
            ($op.updated[] | "  - \(scoped) in \(.path): \(.old) -> \(.new)")
          else empty end),
         (if ($op.not_moved | length) > 0 then
            "Not moved in other paths: \($op.not_moved | length) record(s)",
            ($op.not_moved[] | "  - \(scoped) in \(.path): did not move from \(.version) (\(.label))")
          else empty end)
       end),

      (if (.downgraded | length) > 0 then
         "Downgraded: \(.downgraded | length) plugin(s)",
         (.downgraded[] | "  - \(scoped): \(.old) -> \(.new)"
           + (if .concurrent == true then " (moved during this run)" else "" end))
       else empty end),

      # An id whose update call the CLI answered "already at the latest version" while
      # the run's snapshots show its version differing from the pre-mutation one. Nothing
      # here says what moved it. A backward one is listed under Downgraded: too.
      (.moved_during_run as $moved
       | if ($moved | length) > 0 then
           "Moved during this run: \($moved | length) plugin(s), by something other than this run's update calls",
           ($moved[] | "  - \(scoped): \(pair)"
             + (if .direction == "backward" then " (backward, also under Downgraded)" else "" end))
         else empty end),
      (if .noop_unverified > 0 then
         "Not verified: \(.noop_unverified) plugin(s) the CLI called already current could not be checked against a snapshot version"
       else empty end),

      (if .catalog_regression != null then
         "Catalog regression: \(.catalog_regression.interval)",
         (.catalog_regression.rows[] | split(" ") | "  - \(.[0]): \(.[1]) -> \(.[2])")
       else empty end),

      (if $audit then
         (if ($v.installed.predicted | length) > 0 then
            "Would install: \($v.installed.predicted | length) new catalog plugin(s) (policy install_new: all)",
            ($v.installed.predicted[] | "  would run: \(.label)"),
            "  once installed, a later sync would reinstall any of these you uninstall",
            "    remedy: to keep one out, disable it instead of uninstalling"
          else empty end)
       elif ($v.installed.ok | length) > 0 then
         (listed("Installed: \($v.installed.ok | length) new catalog plugin(s)"; $v.installed.ok)
          | .[0], (.[1:][] | "  \(.)")),
         (if $d.install_new != "all" then empty
          else
            "  policy install_new: all, so the next sync reinstalls any of these you uninstall",
            (if ($v.installed.ok - $v.installed_disabled | length) == 0 then
               "  leaving them installed and not enabled keeps them off unless a project or local setting enables them"
             else
               "    remedy: to keep one out, disable it with claude plugin disable <id> -s user instead of uninstalling"
             end)
          end),
         (if ($v.installed_disabled | length) > 0 then
            (listed("  installed but not enabled"; $v.installed_disabled) | .[0], (.[1:][] | "    \(.)"))
          else empty end)
       else empty end),

      ($norm.moved as $moved | ($norm.keys // "?") as $keys
       | if $norm.status == "normalized" then
           "Normalized: user enabledPlugins key order ("
           + (if $moved == null then "\($keys) keys reordered"
              else "\($moved) of \($keys) keys moved" end) + ")"
         elif $norm.status == "would-normalize" then
           "Would normalize: user enabledPlugins key order (would run: normalize-enabled-plugins.sh, "
           + (if $moved == null then "\($keys) keys"
              else "\($moved) of \($keys) keys would move" end) + ")"
         elif $norm.status == "missing-file" then
           "\(if $audit then "Would normalize" else "Normalized" end): skipped, no user settings file"
         else empty end),

      (if ($v.enabled.predicted | length) > 0 then
         "Would enable: \($v.enabled.predicted | length) plugin(s)",
         ($v.enabled.predicted[] | "  would run: \(.label)")
       elif ($v.enabled.ok | length) > 0 then
         (listed("Enabled: \($v.enabled.ok | length) plugin(s)"; $v.enabled.ok | map(scoped))
          | .[0], (.[1:][] | "  \(.)"))
       else empty end),

      # Divergences: version-skewed rows only (versionsMatch false), split by interval.
      # The interval lines follow the machine-wide count they sum to, and the per-step
      # lines follow the newly created count, shown only when it is above zero.
      # A digest from this version also splits the count by what can be done about each
      # row: only the actionable parts point at converge. A digest written before that
      # split carries no `blocked` field and renders its count with one converge remedy.
      (.divergences as $v
       | (["  \($v.pre_existing) pre-existing",
           "  \($v.new_total) newly created by this run"]
          + (if ($v.new_total // 0) > 0 then
               ["    \($v.new_by_interval.in_repo) by the in-repo update",
                "    \($v.new_by_interval.user_sweep) by the user-scope sweep"]
               + (if ($v.new_by_interval.concurrent // 0) > 0
                  then ["    \($v.new_by_interval.concurrent) moved during this run, cause unattributed"] else [] end)
             else [] end)) as $intervals
       | if $v.post == null then
           "Divergences: not computed (\($v.note // "a snapshot was missing"))"
         elif $v.post == 0 then "Divergences: 0 actionable"
         elif $v.blocked == null then
           (if .project_root != null and .divergences_here != null then
              "Divergences: \($v.post) actionable on this whole machine",
              "  \(.divergences_here) behind here"
            else
              "Divergences: \($v.post) actionable"
            end),
           $intervals[],
           "  remedy: run `/harness-ops:plugins converge`"
         else
           (($v.actionable_here // 0) + ($v.actionable_elsewhere // 0)) as $actionable
           | "Divergences: \($v.post) in all",
           (if $actionable > 0 then
              "  \($actionable) actionable",
              (if ($v.actionable_here // 0) > 0 then "    \($v.actionable_here) here" else empty end),
              (if ($v.actionable_elsewhere // 0) > 0 then "    \($v.actionable_elsewhere) elsewhere on this machine" else empty end),
              "    remedy: run `/harness-ops:plugins converge`"
            else empty end),
           (if ($v.in_worktrees // 0) > 0 then
              "  \($v.in_worktrees) in linked worktrees",
              "    remedy: remove the worktree",
              "    remedy: /source-control:worktree audit (if installed) classifies them"
            else empty end),
           (if ($v.blocked // 0) > 0 then
              "  \($v.blocked) blocked, path not present",
              "    remedy: see Stale project records below"
            else empty end),
           # The same total split a second way, so the lines go under a heading of their own.
           "  by origin:",
           ($intervals[] | "  \(.)")
         end),
      # One sub-line per project path holding a skewed record, so the count names where
      # the work is. A path converge cannot act on says why; a digest written before
      # `class` renders every path bare. A digest written before `by_path` renders the
      # count lines alone. The paths that are not present get one count line, since
      # the stale project records section counts each of them; a digest written before
      # `blocked_paths` carries them in `by_path`, and the count is taken from there.
      ((.divergences.by_path // []) as $all
       | [$all[] | select(.class != "blocked")] as $paths
       | (.divergences.blocked_paths
          // ([$all[] | select(.class == "blocked")] | {paths: length, records: (map(.count) | add // 0)})) as $absent
       | if ($paths | length) == 0 and ($absent.paths // 0) == 0 then empty
         else
           "  by project path:",
           ($paths[]
            | "    - \(.path)"
              + (if .class == "worktree" then " (linked worktree)" else "" end)
              + ": \(.count) diverging record(s): \(.ids | join(", "))"
              + (if (.more // 0) > 0 then ", +\(.more) more" else "" end)),
           (if ($absent.paths // 0) > 0 then
              "    - \($absent.paths) path(s) not present: \($absent.records) diverging record(s), counted under Stale project records"
            else empty end)
         end),

      # The digest names this plugin's own row; a digest written before it did
      # carries no row, so the note names no plugin rather than guess one.
      (if .self_updated == true then
         (if .self_update == null then "this plugin"
          else "\(.self_update.id | split("@")[0]) (\(.self_update.old // "?") -> \(.self_update.new // "?"))" end) as $what
         | "Note: \($what) moved during this run",
           "  the algorithm that ran is the pre-update one: ${CLAUDE_PLUGIN_ROOT} still resolves to the version loaded at session start",
           "  remedy: /reload-plugins before relying on the new version"
       else empty end),

      # Why these records are not divergences, and why an absent path is not proof
      # the directory is gone, is context/stale-records-cache-content.md's, not the render's.
      (if .stale_project_records.total > 0 then
         # The records come from this marketplace's install records only, so the label names it.
         .name as $name | .stale_project_records as $s
         # A digest written before 3.8.1 carries only `by_path`; render it the way it was rendered then.
         | if $s.by_parent == null then
             "Stale project records (\($name)): \($s.total) record(s) across \($s.by_path | length) path(s) not present on this machine",
             ($s.by_path[] | "  - \(.path): \(.count) record(s)")
           else
             "Stale project records (\($name)): \($s.total) record(s) across \($s.paths) path(s) not present on this machine",
             ($s.by_parent[] | "  - \(.parent): \(.count) record(s) across \(.paths) path(s)"),
             (if $s.more_parents > 0 then "  +\($s.more_parents) more parent director(ies)" else empty end),
             (if $audit then "  Full per-path list: not kept, the audit scratch directory is removed on exit"
              elif $s.list_file == null then "  Full per-path list: not written this run"
              else "  Full per-path list: \($s.list_file)" end)
           end,
         # Only project-scope records under the source-control worktree root are that audit's to
         # classify, so the pointer needs a project-scope record and says which of them it covers.
         (if $s.project > 0 then
            "  \($s.project) project-scope record(s)",
            "    remedy: /source-control:worktree audit (if installed) classifies those left by worktrees removed under the source-control worktree root, and gives the gated reap"
          else empty end),
         (if $s["local"] > 0 then
            "  \($s["local"]) local-scope record(s), which nothing reaps yet"
          else empty end)
       else empty end),

      # Why converge blocks these rows is context/scope-semantics.md's, not the render's.
      (if .user_home_records.total > 0 then
         .user_home_records as $h
         | "User-home project records: \($h.total) record(s) keyed to a user home directory",
           ($h.paths[] | "  - \(.)")
       else empty end),

      (.cache_content as $c
       | ("\($c.scope // "user")-scope install(s)") as $installs
       | if $c == null then empty
         elif ($c.stale_content // 0) > 0 then
           "Cache content: \($c.stale_content) \($installs) whose cache files disagree with their recorded gitCommitSha",
           ($c.stale[] | (if .files_differ == null then "  - \(.id)" else "  - \(.id) \(.version): \(.files_differ) file(s) differ" end)
                         + (if .unreleased_changes == true then " (unreleased changes pending)" else "" end)),
           (if ($c.unverifiable // 0) > 0 or ($c.not_checked // 0) > 0 then
              "  \($c.checked) \($installs) checked",
              "    \($c.match) match",
              (if ($c.unverifiable // 0) > 0 then "    \($c.unverifiable) unverifiable, which is not a pass" else empty end),
              (if ($c.not_checked // 0) > 0 then "    \($c.not_checked) not checked (recorded at an older commit)" else empty end)
            else empty end),
           (if any($c.stale[]; .unreleased_changes == true) then
              "  Unreleased changes pending: the marketplace holds changelog fragments for that plugin, so its files changed without a version bump",
              "    remedy: leave its cache alone, its next release brings the cache up to date"
            else empty end),
           (if any($c.stale[]; .unreleased_changes != true) then
              "  remedy\(if any($c.stale[]; .unreleased_changes == true) then ", for the rows not marked unreleased" else "" end): remove that version's directory under the plugin cache, then re-run `claude plugin update <id>@<marketplace>`, which recreates it from the clone"
            else empty end)
         elif ($c.unverifiable // 0) > 0 or ($c.not_checked // 0) > 0 then
           "Cache content: \($c.match) of \($c.checked) \($installs) compared, no disagreement found",
           (if ($c.not_checked // 0) > 0 then "  \($c.not_checked) not checked (recorded at an older commit)" else empty end),
           (if ($c.unverifiable // 0) > 0 then "  \($c.unverifiable) unverifiable, which is not a pass" else empty end)
         else empty end),

      (if $t == null then "Timing: n/a"
       else
         ($t | slowest_step) as $slow
         | "Timing: \($t.total | secs) this marketplace",
           (if $slow == null then empty else "  slowest step: \($slow.key) \($slow.value)s" end),
           (if $t.unattributed == null then empty else "  outside the named steps: \($t.unattributed)s" end),
           "  clock resolution: \($t.resolution)"
       end),

      (if ($v.actions | length) == 0 then empty
       else "Action needed:", ($v.actions[].lines | bullet) end)
    ];

. as $d
| ($d.mode == "audit") as $audit
| classify as $v
| [
    ({action_needed: "Result: \($v.run.action_count) item(s) under Action needed",
      predicted: "Result: see the predictions below, nothing under Action needed",
      no_change_predicted: "Result: no change predicted, a lower bound against the unrefreshed catalog",
      changed: "Result: changes applied, nothing under Action needed",
      clean: "Result: clean, nothing changed and nothing under Action needed"}[$v.run.result]),
    (if $audit then "Audit (read-only): every call sync would make is a prediction, prefixed would run:" else empty end),
    (range($d.marketplaces | length) as $i | $d.marketplaces[$i] | format_block($d; $v.blocks[$i])[]),
    # A marketplace whose block could not be assembled did resolve; its error
    # under Action needed names it. The text matched is the run_error wording in
    # sync-run.sh's emit_marketplace_block: change both together.
    (if ($d.marketplaces | length) == 0
        and ([$d.errors[] | select(test("its report block could not be assembled"))] | length) == 0
     then "Marketplace: none resolved for this run" else empty end),
    "",
    (if $audit then "Run: audit scratch directory, removed on exit"
     else "Run journal: \($d.run_dir)" end),
    # A re-entry digest times both passes; the marketplace rows above time the
    # re-entry alone.
    "Timing: \($d.timings.total | secs) run total"
    + (if ($d.timings.passes // null) == null then "" else " over both passes" end),
    (if ($d.timings.passes // null) == null then empty
     else
       "  first pass: \($d.timings.passes[0].total | secs)",
       "  --only-install re-entry: \($d.timings.passes[1].total | secs)",
       "  the wait between the passes is not counted"
     end),
    (if $d.timings.outside_marketplaces == null then empty
     else "  outside the marketplace blocks: \($d.timings.outside_marketplaces)s" end),
    "  clock resolution: \($d.timings.resolution)",
    (if ($v.run.actions | length) == 0 then empty
     else "Action needed:", ($v.run.actions[].lines | bullet) end)
  ]
| join("\n")
