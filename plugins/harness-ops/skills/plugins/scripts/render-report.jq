# render-report.jq: the fixed-section report SKILL.md's Report section fixes,
# as a pure function of sync-run.sh's digest.
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
# call sync would make carries the `would run:` prefix. A remedy sync never runs
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

def secs: if . == null then "n/a" else "\(.)s" end;
# The first line of a journaled CLI output that is the CLI's own, not the
# `$ <command>` echo the journal opens with.
def first_line: (. // "") | split("\n") | map(select(startswith("$ ") | not)) | (.[0] // "");
# Capture-time classification lives in .reason. This fallback is the same rule
# as sync-run.sh's cli_outcome_line for a row that has no reason yet: CRs
# dropped, `$` and empty lines skipped, then the first ✘ / Failed / Error line,
# else the first line left. Not the last line, which can be a userConfig note.
def outcome_line:
  (. // "") | gsub("\r"; "") | split("\n")
  | map(select((startswith("$ ") | not) and . != "")) as $lines
  | ([$lines[] | select(startswith("✘") or contains("Failed") or contains("Error"))][0])
    // $lines[0] // "";
def reported:
  if (.reason | type) == "string" and .reason != "" then .reason
  else (.output | outcome_line) end;
def pair: "\(.old) -> \(.new)" + (if .direction == "unknown" then " (direction unknown)" else "" end);
def scoped: "\(.id) (\(.scope))";
# A labeled list as lines: inline up to three entries, past that one `- `
# entry per line under the label. The caller indents the entry lines.
def listed($head; $items):
  if ($items | length) <= 3 then ["\($head): \($items | join(", "))"]
  else ["\($head):"] + ($items | map("- \(.)")) end;
# An `Action needed` item, an array of lines: the first is the bullet, the rest
# sit under it.
def bullet: "  - \(.[0])", (.[1:][] | "    \(.)");
def auto_update_slot:
  if . == true then "on" elif . == false then "off" else "unreadable" end;
def short_sha: (. // "?") | .[0:12];
def key_count: (capture("keys=(?<k>[0-9]+)") // {k: "?"}) | .k;
# The normalizer's `moved=K`, or null from a digest written before it carried one.
def moved_count: (capture("moved=(?<m>[0-9]+)") // {m: null}) | .m;

# The slowest timed step of a block's timings object, or null.
def slowest_step:
  [to_entries[]
   | select(.key != "total" and .key != "resolution" and .key != "unattributed" and .value != null)]
  | if length == 0 then null else max_by(.value) end;

# One marketplace block: its lines, its `Action needed` item count, and whether
# the run changed (in audit, would change) anything in it.
def block($d):
  ($d.mode == "audit") as $audit
  | (.in_repo.updated + .user_sweep.updated) as $updated
  | (.in_repo.would_update + (.user_sweep.would_update | map(. + {scope: "user"}))) as $would
  | (.in_repo.failed + (.user_sweep.failed | map(. + {scope: "user"}))) as $failed
  | .user_sweep.withheld_downgrades as $withheld
  | (.other_paths // {}) as $op
  | ([.installed[] | select(.rc == 0)]) as $installed_ok
  | ([.installed[] | select(.rc != 0)]) as $installed_failed
  | (.install_gap - ($installed_ok | map(.id))) as $install_left
  | ([.enabled[] | select(.predicted == true)]) as $would_enable
  | ([.enabled[] | select(.predicted != true and .rc == 0)]) as $enabled_ok
  | ([.enabled[] | select(.predicted != true and .rc != 0)]) as $enabled_failed
  | (.normalize.output // "") as $norm
  | (.normalize.project_report.output // "") as $pnorm
  | (.enable_gap - ($enabled_ok | map(.id)) - ($would_enable | map(.id))
     - (.project_enable_rows | map(.id))) as $enable_unfilled
  | (.install_enable_deferred == true and (.install_gap | length) > 0
     and .stopped_before_install != true) as $install_deferred
  | (.install_enable_deferred == true and (.enable_gap | length) > 0) as $enable_deferred
  # The `Action needed` items for pending actions: work this run left to a person
  # (an install declined, skipped by policy or held for the ask prompt, an unfilled
  # enable, a withheld downgrade, a delisted plugin). The header counts them; a gap
  # deferred by a failed refresh is refresh state instead, so it is not among them.
  | [if .stopped_before_install == true then
       listed("\(.install_gap | length) catalog plugin(s) not installed at user scope (policy ask, stopped before Step 4 pending the batched prompt)"; .install_gap)
     elif $install_deferred then empty
     elif ($audit | not) and $d.install_new == "ask" and ($install_left | length) > 0 then
       listed("\($install_left | length) catalog plugin(s) offered and not installed (policy ask)"; $install_left)
       + ["remedy: disable any you never want with enabledPlugins: false, or ask offers it again on every sync"]
     elif ($d.install_new == "none" or ($audit and $d.install_new == "ask")) and (.install_gap | length) > 0 then
       listed("\(.install_gap | length) catalog plugin(s) not installed at user scope (policy \($d.install_new))"; .install_gap)
     else empty end] as $install_pending
  | [if ($enable_deferred | not) and ($enable_unfilled | length) > 0 then
       listed("missing_from_enabled, not enabled this run"; $enable_unfilled)
     else empty end,
     (.project_enable_rows[]
      | ["project-scope enable gap: \(.id) in \(.project_path)",
         "remedy: (cd \"\(.project_path)\" && claude plugin enable \(.id) -s project)",
         "that writes the repo's committed .claude/settings.json, so review the diff before committing"])] as $enable_pending
  | [(.installed_disabled // [])[]
     | ["\(.): installed but not enabled", "remedy: claude plugin enable \(.) -s user"]] as $disabled_pending
  | [(if ((.delisted // []) | length) == 0 then empty
      elif $audit then
        listed("delisted, absent from the unrefreshed catalog (audit prediction)"; .delisted)
        + ["sync names any still absent after its refresh, with the remedy"]
      else
        listed("delisted, absent from the catalog"; .delisted)
        + ["remedy: uninstall each with `claude plugin uninstall <id> -s user`"]
      end),
     (if ((.delisted_project // []) | length) == 0 then empty
      elif $audit then
        listed("delisted in this repo, absent from the unrefreshed catalog (audit prediction)"; .delisted_project | map(scoped))
        + ["sync names any still absent after its refresh, with the remedy"]
      else
        (.project_root // "?") as $root
        | (.delisted_project[]
           | ["delisted in this repo, absent from the catalog: \(scoped)",
              "remedy: (cd \"\($root)\" && claude plugin uninstall \(.id) -s \(.scope))"])
      end),
     (if ((.delisted_settings_only // []) | length) == 0 then empty
      elif $audit then
        listed("enabled in settings, not installed, and absent from the unrefreshed catalog (audit prediction)"; .delisted_settings_only)
        + ["sync names any still absent after its refresh, with the remedy"]
      else
        listed("enabled in settings, not installed, and absent from the catalog"; .delisted_settings_only)
        + ["remedy: remove each key from enabledPlugins in the settings file that sets it"]
      end)] as $delisted_pending
  | [if ($audit | not) and ($withheld | length) > 0 then
       ["downgrade withheld: \($withheld | length) plugin(s)"]
       + ($withheld | map("- \(scoped): \(.installed) -> \(.catalog)"))
       + ["likely cause: marketplace source moved backward (\(.catalog_source // "source unknown"))",
          "remedy: rerun with --allow-downgrade only if the rollback is intended"]
     else empty end] as $withheld_pending
  # Audit predicts a withheld downgrade as its `Would withhold` row, not a bullet;
  # it counts as one pending action.
  | (($install_pending + $enable_pending + $disabled_pending + $delisted_pending + $withheld_pending | length)
     + (if $audit and ($withheld | length) > 0 then 1 else 0 end)) as $pending
  # `needs update`: refresh, update and failure state only. Audit predicts what sync
  # would update, install or enable itself.
  | (if $audit then
       (($would | length) > 0 or ($would_enable | length) > 0 or (($op.would_update // []) | length) > 0
        or ($d.install_new == "all" and (.install_gap | length) > 0 and .install_enable_deferred != true))
     else
       (($failed | length) > 0 or .install_enable_deferred == true or (($op.failed // []) | length) > 0
        or ($installed_failed | length) > 0 or ($enabled_failed | length) > 0
        or (.errors | length) > 0)
     end) as $needs
  | .timings as $t
  | .source_checkout as $src
  | (.source_pull // null) as $pull
  | (($src.behind // 0) > 0) as $behind
  | (.name as $n | any(($d.quiet_auto_update // [])[]; . == $n)) as $quiet
  # What the verdict calls a change: something this run moved, or in audit
  # something sync would move or withhold.
  | (if $audit then ($needs or ($norm | test("^would-normalize")) or ($withheld | length) > 0)
     else
       (($updated | length) > 0 or (.downgraded | length) > 0 or ($installed_ok | length) > 0
        or (($op.updated // []) | length) > 0
        or ($enabled_ok | length) > 0 or ($norm | test("^normalized ")) or $pull.status == "pulled")
     end) as $changed
  # Action needed: omitted entirely when nothing needs action.
  | [
      (if $behind then
         ["source checkout \($src.path) is \($src.behind) commit(s) behind \($src.upstream), and the catalog is read from it as it is",
          "remedy: run `git -C \($src.path | @sh) pull --ff-only`, then rerun `/harness-ops:plugins sync \(.name)`"]
         + (if $src.ahead > 0 then ["it also carries \($src.ahead) local commit(s), so --ff-only refuses until they are reconciled"] else [] end)
         + (if $src.dirty then ["tracked files are modified, and the pull refuses if it would overwrite them"] else [] end)
       else empty end),
      # A requested fast-forward that did not happen. HEAD and the work tree are
      # as they were, so the behind item above, when there is one, still stands.
      (if $pull.status == "refused" then
         ["requested fast-forward of \($src.path // "the source checkout") refused, nothing changed: \($pull.reason)"]
       elif $pull.status == "failed" then
         ["requested fast-forward of \($src.path // "the source checkout") failed (exit \($pull.rc)): \($pull.reason)"]
       else empty end),
      (if $install_deferred then
         listed("install gap deferred (marketplace refresh failed)"; .install_gap)
       else empty end),
      $install_pending[],
      (if $enable_deferred then
         listed("enable gap deferred (marketplace refresh failed)"; .enable_gap)
       else empty end),
      $enable_pending[],
      ($failed[] | if .stopped == true then ["update stopped in \(.path): \(.id) -s \(.scope): \(.reason)"]
                   else ["update failed (exit \(.rc)): \(.id) -s \(.scope): \(reported)"] end),
      (($op.failed // [])[]
       | ["update \(if .stopped then "stopped" else "failed" end) in \(.path): \(.id) -s \(.scope): \(.reason)"]),
      ($installed_failed[] | ["install failed (exit \(.rc)): \(.id): \(reported)"]),
      ($enabled_failed[] | ["enable failed (exit \(.rc)): \(.id) -s \(.scope): \(reported)"]),
      $disabled_pending[],
      $delisted_pending[],
      (if (.user_scope_orphans | length) > 0 then
         listed("user-scope orphan(s), a project/local record with no user-scope install"; .user_scope_orphans)
       else empty end),
      (.installed_with_unset_user_config[]
       | ["\(.id): \(.options_unset) userConfig option(s) not yet set"
          + (if .required != null then " (\(.required) required)" else "" end),
          "remedy: run /plugin configure \(.id) in Claude Code, or pass --config KEY=VALUE"]),
      (if (.updated_with_monitors | length) > 0 then
         listed("monitor(s) declared by updated plugin(s)"; .updated_with_monitors | map("\(.id) (\(.monitors))"))
         + ["remedy: restart the session to run the updated monitors, /reload-plugins does not switch them"]
       else empty end),
      (if ($norm | test("^refused:")) then
         ["user-scope enabledPlugins reorder refused: \($norm | first_line)"]
       else empty end),
      (if ($pnorm | test("^project-unsorted")) then
         ["project-scope enabledPlugins map is unsorted (\(.project_root // "?")/.claude/settings.json)",
          "remedy: run converge, the only action that may rewrite it"]
       else empty end),
      $withheld_pending[],
      (.errors[] | ["error: \(.)"])
    ] as $actions
  | [
      "Marketplace: \(.name): \(if $needs then "needs update" elif $behind then "source checkout behind \($src.upstream)" else "current" end)"
      + (if $pending > 0 then ", \($pending) action(s) pending" else "" end)
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
         "  would run: claude plugin marketplace update \(.name)",
         "    predicted against the unrefreshed catalog (lastUpdated \(.catalog_last_updated // "unknown")), a lower bound on what sync would update"
       elif .refresh.rc != null and .refresh.rc != 0 then
         "  refresh failed (exit \(.refresh.rc)): \(.refresh | reported)"
       else empty end),

      # In-repo: a fixed row with three variants, picked by two digest fields.
      (if .project_root == null then
         "In-repo: skipped: no project context resolved from \($d.cwd // "the current directory")"
       elif .in_repo_records == null then
         "In-repo: unknown: no fleet-state snapshot was read for this marketplace"
       elif .in_repo_records == 0 then
         "In-repo: 0: \(.project_root) has no project/local installs"
       elif $audit then
         "In-repo: \(.in_repo.would_update | length) project/local install(s) would be updated in \(.project_root)"
       else
         "In-repo: \(.in_repo.updated | length) project/local install(s) updated in \(.project_root)"
       end),

      ((.in_repo.live_read // [])[] |
         "  \(.id) (\(.scope)): read live from \(.path)",
         "    project record pinned at \(.installed), which the CLI will not update",
         "    remedy: remove and re-add the project record if the pin matters"),

      (if $audit then
         "Would update: \($would | length) plugin(s)",
         ($would[] | "  would run: claude plugin update \(.id) -s \(.scope) (installed \(.installed))"),
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
      (if $audit then
         (if (($op.would_update // []) | length) > 0 then
            "Would update in other paths: \($op.would_update | length) record(s)",
            ($op.would_update[] | "  would run: (cd \"\(.path)\" && claude plugin update \(.id) -s \(.scope)) (installed \(.old))")
          else empty end)
       else
         (if (($op.updated // []) | length) > 0 then
            "Updated in other paths: \($op.updated | length) record(s)",
            ($op.updated[] | "  - \(scoped) in \(.path): \(.old) -> \(.new)")
          else empty end),
         (if (($op.not_moved // []) | length) > 0 then
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
      ((.moved_during_run // []) as $moved
       | if ($moved | length) > 0 then
           "Moved during this run: \($moved | length) plugin(s), by something other than this run's update calls",
           ($moved[] | "  - \(scoped): \(pair)"
             + (if .direction == "backward" then " (backward, also under Downgraded)" else "" end))
         else empty end),
      (if (.noop_unverified // 0) > 0 then
         "Not verified: \(.noop_unverified) plugin(s) the CLI called already current could not be checked against a snapshot version"
       else empty end),

      (if .catalog_regression != null then
         "Catalog regression: \(.catalog_regression.interval)",
         (.catalog_regression.rows[] | split(" ") | "  - \(.[0]): \(.[1]) -> \(.[2])")
       else empty end),

      (if $audit then
         (if $d.install_new == "all" and (.install_gap | length) > 0 and .install_enable_deferred != true then
            "Would install: \(.install_gap | length) new catalog plugin(s) (policy install_new: all)",
            (.install_gap[] | "  would run: claude plugin install \(.) -s user"),
            "  once installed, a later sync would reinstall any of these you uninstall",
            "    remedy: to keep one out, disable it instead of uninstalling"
          else empty end)
       elif ($installed_ok | length) > 0 then
         (listed("Installed: \($installed_ok | length) new catalog plugin(s)"; $installed_ok | map(.id))
          | .[0], (.[1:][] | "  \(.)")),
         (if $d.install_new != "all" then empty
          else
            "  policy install_new: all, so the next sync reinstalls any of these you uninstall",
            (if (($installed_ok | map(.id)) - (.installed_disabled // []) | length) == 0 then
               "  leaving them installed and not enabled keeps them off unless a project or local setting enables them"
             else
               "    remedy: to keep one out, disable it with claude plugin disable <id> -s user instead of uninstalling"
             end)
          end),
         (if ((.installed_disabled // []) | length) > 0 then
            (listed("  installed but not enabled"; .installed_disabled) | .[0], (.[1:][] | "    \(.)"))
          else empty end)
       else empty end),

      (($norm | moved_count) as $moved
       | if ($norm | test("^normalized ")) then
           "Normalized: user enabledPlugins key order ("
           + (if $moved == null then "\($norm | key_count) keys reordered"
              else "\($moved) of \($norm | key_count) keys moved" end) + ")"
         elif ($norm | test("^would-normalize")) then
           "Would normalize: user enabledPlugins key order (would run: normalize-enabled-plugins.sh, "
           + (if $moved == null then "\($norm | key_count) keys"
              else "\($moved) of \($norm | key_count) keys would move" end) + ")"
         elif ($norm | test("^missing-file")) then
           "\(if $audit then "Would normalize" else "Normalized" end): skipped, no user settings file"
         else empty end),

      (if ($would_enable | length) > 0 then
         "Would enable: \($would_enable | length) plugin(s)",
         ($would_enable[] | "  would run: claude plugin enable \(.id) -s \(.scope)")
       elif ($enabled_ok | length) > 0 then
         (listed("Enabled: \($enabled_ok | length) plugin(s)"; $enabled_ok | map(scoped))
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
      # count lines alone.
      ((.divergences.by_path // []) as $paths
       | if ($paths | length) == 0 then empty
         else
           "  by project path:",
           ($paths[]
            | "    - \(.path)"
              + (if .class == "blocked" then " (not present)"
                 elif .class == "worktree" then " (linked worktree)" else "" end)
              + ": \(.count) diverging record(s): \(.ids | join(", "))"
              + (if (.more // 0) > 0 then ", +\(.more) more" else "" end))
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
      (if (.stale_project_records.total // 0) > 0 then
         # The records come from this marketplace's install records only, so the label names it.
         .name as $name | .stale_project_records as $s
         # A digest written before 3.8.1 carries only `by_path`; render it the way it was rendered then.
         | if $s.by_parent == null then
             "Stale project records (\($name)): \($s.total) record(s) across \($s.by_path | length) path(s) not present on this machine",
             ($s.by_path[] | "  - \(.path): \(.count) record(s)")
           else
             "Stale project records (\($name)): \($s.total) record(s) across \($s.paths) path(s) not present on this machine",
             ($s.by_parent[] | "  - \(.parent): \(.count) record(s) across \(.paths) path(s)"),
             (if ($s.more_parents // 0) > 0 then "  +\($s.more_parents) more parent director(ies)" else empty end),
             (if $audit then "  Full per-path list: not kept, the audit scratch directory is removed on exit"
              elif $s.list_file == null then "  Full per-path list: not written this run"
              else "  Full per-path list: \($s.list_file)" end)
           end,
         # Only project-scope records under the source-control worktree root are that audit's to
         # classify, so the pointer needs a project-scope record and says which of them it covers.
         (if ($s.project // 0) > 0 then
            "  \($s.project) project-scope record(s)",
            "    remedy: /source-control:worktree audit (if installed) classifies those left by worktrees removed under the source-control worktree root, and gives the gated reap"
          else empty end),
         (if ($s["local"] // 0) > 0 then
            "  \($s["local"]) local-scope record(s), which nothing reaps yet"
          else empty end)
       else empty end),

      # Why converge blocks these rows is context/scope-semantics.md's, not the render's.
      (if (.user_home_records.total // 0) > 0 then
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

      (if ($actions | length) == 0 then empty
       else "Action needed:", ($actions[] | bullet) end)
    ]
  | {lines: ., actions: ($actions | length), changed: $changed};

. as $d
| ($d.mode == "audit") as $audit
| [$d.marketplaces[] | block($d)] as $blocks
| [
    (if $d.install_new_invalid != null then
       ["install_new value \"\($d.install_new_invalid)\" is not all, none, or ask", "this run used ask"]
     else empty end),
    (if ($d.source_pull_invalid // null) != null then
       ["directory_source_pull value \"\($d.source_pull_invalid)\" is not ask or never", "this run used \($d.source_pull // "ask")"]
     else empty end),
    ($d.errors[] | ["error: \(.)"])
  ] as $run_actions
| (([$blocks[].actions] | add // 0) + ($run_actions | length)) as $action_count
| [
    # The verdict counts every `Action needed` item, the blocks' and the run's. A
    # remedy on a row outside that section (converge, autoUpdate) is not one of them.
    (if $action_count > 0 then "Result: \($action_count) item(s) under Action needed"
     elif $audit then
       (if any($blocks[]; .changed) then "Result: see the predictions below, nothing under Action needed"
        else "Result: no change predicted, a lower bound against the unrefreshed catalog" end)
     elif any($blocks[]; .changed) then "Result: changes applied, nothing under Action needed"
     else "Result: clean, nothing changed and nothing under Action needed" end),
    (if $audit then "Audit (read-only): every call sync would make is a prediction, prefixed would run:" else empty end),
    ($blocks[].lines[]),
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
    (if ($run_actions | length) == 0 then empty
     else "Action needed:", ($run_actions[] | bullet) end)
  ]
| join("\n")
